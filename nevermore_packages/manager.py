"""Transactional package-management backend shared by the CLI and TUI."""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Sequence

from .catalog import parse_legacy_catalog, read_catalog, validate_catalog, write_catalog
from .models import (
    CatalogEntry,
    CommandResult,
    ModuleEntry,
    OperationResult,
    PackageModule,
    PackageRecord,
    SnippetTemplate,
)
from .snippets import inject_package_requires, load_snippet_templates, render_snippet_template


PACKAGE_NAME = re.compile(r"^[a-z0-9][a-z0-9-]*$")
SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
EXPORT_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
KINDS = {"utility", "class", "service", "types", "empty"}
SERVICE_REALMS = {"server", "client", "both"}


def _pascal_case(name: str) -> str:
    return "".join(part[:1].upper() + part[1:] for part in re.split(r"[-_\s]+", name) if part)


def _file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


class PackageManager:
    """Owns package discovery, validation, and safe local mutations."""

    def __init__(self, root: Path | None = None, snippet_path: Path | None = None) -> None:
        self.root = (root or Path(__file__).resolve().parents[1]).resolve()
        self.src = self.root / "src"
        self.shared = self.src / "shared"
        self.server = self.src / "server"
        self.shared_index = self.shared / "_Index"
        self.server_index = self.server / "_Index"
        self.catalog_path = self.root / "PKGINFO.md"
        self.scripts = self.root / "scripts"
        self.snippet_path = snippet_path or self._find_snippet_path()

    def list_snippet_templates(self) -> tuple[SnippetTemplate, ...]:
        """Return complete module templates imported from Untitled Knife Game."""

        return load_snippet_templates(self.snippet_path)

    def list_dependency_aliases(self) -> tuple[str, ...]:
        """Return public exports that a newly created package can require."""

        return tuple(sorted({alias for record in self.list_packages() for alias in record.exports}, key=str.casefold))

    def dependency_alias_realms(self) -> dict[str, str]:
        """Return each public alias and the realm that owns it."""

        return {
            alias: module.realm
            for record in self.list_packages()
            for module in self._list_record_modules(record)
            for alias in module.aliases
        }

    def list_packages(self) -> list[PackageRecord]:
        names = {
            str(self._read_json(path)["name"])
            for index in (self.shared_index, self.server_index)
            for path in index.glob("quenty_*@*/package.json")
        }
        return [self._record_pair(name) for name in sorted(names)]

    def get_package(self, name: str) -> PackageRecord:
        short_name = self._validate_name(name.removeprefix("quenty/"))
        matches = {
            path.parent.name
            for index in (self.shared_index, self.server_index)
            for path in index.glob(f"quenty_{short_name}@*/package.json")
        }
        if not matches:
            raise ValueError(f"Unknown package: quenty/{short_name}")
        if len(matches) != 1:
            raise ValueError(f"Multiple installed versions found for quenty/{short_name}")
        return self._record_pair(f"quenty/{short_name}")

    def list_package_modules(self, name: str) -> tuple[PackageModule, ...]:
        """Discover every production Luau module and its public exposure state."""

        return self._list_record_modules(self.get_package(name))

    def _list_record_modules(self, record: PackageRecord) -> tuple[PackageModule, ...]:
        metadata = {module.path: module for module in record.catalog.modules}
        target_paths: dict[str, list[str]] = {}
        roots = self._record_roots(record)
        for path in self._source_module_paths(record):
            root = next(candidate for candidate in roots if path.is_relative_to(candidate))
            relative = path.relative_to(root).as_posix()
            target_paths.setdefault(self._module_target(relative), []).append(relative)

        modules = []
        for target, paths in sorted(target_paths.items()):
            path = sorted(paths, key=lambda item: (not item.endswith(".luau"), item))[0]
            entry = metadata.get(path)
            aliases = tuple(sorted(alias for alias, export_target in record.exports.items() if export_target == target))
            modules.append(
                PackageModule(
                    path=path,
                    target=target,
                    realm=entry.realm if entry else self._infer_module_realm(path),
                    kind=entry.kind if entry else "Uncatalogued",
                    description=entry.description if entry else "",
                    aliases=aliases,
                )
            )
        return tuple(modules)

    def set_module_exposed(self, name: str, target: str, exposed: bool) -> OperationResult:
        """Expose or hide one package module through the flat public package surface."""

        try:
            record = self.get_package(name)
            module = next((module for module in self.list_package_modules(name) if module.target == target), None)
            if module is None:
                raise ValueError(f"Unknown package module target: {target}")
            exports = dict(record.exports)
            if exposed:
                self._add_module_export(record, module, exports, self._public_alias_owners(record.name))
            else:
                exports = {alias: value for alias, value in exports.items() if value != target}
        except (OSError, ValueError) as error:
            return OperationResult(False, "Module exposure could not be changed", diagnostics=(str(error),))

        state = "Exposed" if exposed else "Hidden"
        return self._write_exports(record, exports, f"{state} {module.path}")

    def set_all_modules_exposed(self, name: str, exposed: bool) -> OperationResult:
        """Expose or hide every production module in one package."""

        try:
            record = self.get_package(name)
            modules = self.list_package_modules(name)
            exports = dict(record.exports) if exposed else {}
            if exposed:
                alias_owners = self._public_alias_owners(record.name)
                for module in modules:
                    self._add_module_export(record, module, exports, alias_owners)
        except (OSError, ValueError) as error:
            return OperationResult(False, "Module exposure could not be changed", diagnostics=(str(error),))

        state = "Exposed" if exposed else "Hidden"
        return self._write_exports(record, exports, f"{state} all modules in {record.name}")

    def set_module_realm(self, name: str, target: str, realm: str) -> OperationResult:
        """Move one module between authoring partitions and update its runtime realm."""

        try:
            record = self.get_package(name)
            if realm not in {"shared", "client", "server"}:
                raise ValueError(f"Unknown module realm: {realm}")
            module = next((item for item in self._list_record_modules(record) if item.target == target), None)
            if module is None:
                raise ValueError(f"Unknown package module target: {target}")
            if module.realm == realm:
                return OperationResult(True, f"{module.path} is already {realm}")
        except (OSError, ValueError) as error:
            return OperationResult(False, "Module realm could not be changed", diagnostics=(str(error),))

        before = self._snapshot()
        try:
            source_partition = "server" if module.realm == "server" else "shared"
            destination_partition = "server" if realm == "server" else "shared"
            source_root = self._partition_roots(record)[source_partition]
            destination_root = self._partition_roots(record).get(destination_partition)
            if destination_root is None:
                destination_index = self.server_index if destination_partition == "server" else self.shared_index
                destination_root = destination_index / source_root.name
                destination_root.mkdir(parents=True)
                self._write_json(
                    destination_root / "package.json",
                    {
                        "name": record.name,
                        "version": record.version,
                        "exports": {},
                        "dependencies": [],
                        "externals": [],
                    },
                )

            if source_partition != destination_partition:
                self._move_module_sources(source_root, destination_root, target)

            modules = tuple(
                sorted(
                    (
                        ModuleEntry(item.path, realm, item.kind, item.description)
                        if self._module_target(item.path) == target
                        else item
                        for item in record.catalog.modules
                    ),
                    key=lambda item: item.path,
                )
            )
            roots = {**self._partition_roots(record), destination_partition: destination_root}
            exports_by_partition = {"shared": {}, "server": {}}
            realms_by_target = {self._module_target(item.path): item.realm for item in modules}
            for alias, export_target in record.exports.items():
                partition = "server" if realms_by_target[export_target] == "server" else "shared"
                exports_by_partition[partition][alias] = export_target

            for partition, root in tuple(roots.items()):
                partition_modules = tuple(
                    item for item in modules if (item.realm == "server") == (partition == "server")
                )
                if not partition_modules:
                    other_root = roots[destination_partition]
                    if root != other_root:
                        self._move_remaining_package_files(root, other_root)
                        shutil.rmtree(root)
                    continue
                manifest_path = root / "package.json"
                manifest = self._read_json(manifest_path)
                manifest["exports"] = dict(sorted(exports_by_partition[partition].items()))
                self._write_json(manifest_path, manifest)
                write_catalog(
                    root / "catalog.json",
                    CatalogEntry(
                        record.catalog.purpose,
                        record.catalog.description,
                        record.catalog.tags,
                        partition_modules,
                    ),
                )

            sync_result = self._fast_sync()
            if not sync_result.ok:
                raise RuntimeError(sync_result.output)
            return self._success(f"Moved {module.path} to {realm}", before, (sync_result,))
        except Exception as error:
            self._restore(before)
            return OperationResult(False, "Module realm change failed and was rolled back", diagnostics=(str(error),))

    def reverse_dependencies(self, name: str) -> tuple[str, ...]:
        target = self.get_package(name).name
        dependents = []
        for record in self.list_packages():
            dependency_names = {dependency.rsplit("@", 1)[0] for dependency in record.dependencies}
            if target in dependency_names:
                dependents.append(record.name)
        return tuple(sorted(dependents))

    def migrate_catalog(self) -> OperationResult:
        before = self._snapshot()
        try:
            legacy = parse_legacy_catalog(self.catalog_path.read_text(encoding="utf-8"))
            missing = []
            for record in self.list_packages():
                entry = legacy.get(record.short_name)
                if entry is None:
                    missing.append(record.short_name)
                    continue
                for partition, root in self._partition_roots(record).items():
                    partition_modules = tuple(
                        module
                        for module in entry.modules
                        if (module.realm == "server") == (partition == "server")
                    )
                    write_catalog(
                        root / "catalog.json",
                        CatalogEntry(entry.purpose, entry.description, entry.tags, partition_modules),
                    )
            if missing:
                raise ValueError(f"PKGINFO.md has no package cards for: {', '.join(missing)}")
            sync_result = self._fast_sync()
            if not sync_result.ok:
                raise RuntimeError(sync_result.output)
            return self._success("Migrated package catalog metadata", before, (sync_result,))
        except Exception as error:
            self._restore(before)
            return OperationResult(False, "Catalog migration failed", diagnostics=(str(error),))

    def create_package(
        self,
        name: str,
        version: str = "0.0.1",
        kind: str = "empty",
        export_name: str | None = None,
        purpose: str = "",
        description: str = "",
        tags: Sequence[str] = (),
        template_name: str | None = None,
        service_realm: str | None = None,
        dependencies: Sequence[str] = (),
    ) -> OperationResult:
        try:
            short_name = self._validate_name(name.removeprefix("quenty/"))
            version = self._validate_version(version)
            normalized_kind = kind.lower()
            if normalized_kind not in KINDS:
                raise ValueError(f"Unknown package kind: {kind}")
            if template_name and normalized_kind == "empty":
                raise ValueError("A snippet template must create a non-empty package")
            normalized_realm = (service_realm or "server").lower()
            if normalized_kind == "service" and normalized_realm not in SERVICE_REALMS:
                raise ValueError(f"Unknown service realm: {service_realm}")
            if normalized_kind != "service" and service_realm is not None:
                raise ValueError("Service realm options only apply to service templates")
            dependency_aliases = tuple(dict.fromkeys(alias.strip() for alias in dependencies if alias.strip()))
            if normalized_kind == "empty" and dependency_aliases:
                raise ValueError("An empty package cannot require dependencies")
            alias_realms = self.dependency_alias_realms()
            available_aliases = set(alias_realms)
            unknown_aliases = sorted(set(dependency_aliases) - available_aliases)
            if unknown_aliases:
                raise ValueError(f"Unknown package exports: {', '.join(unknown_aliases)}")
            if any(
                list(index.glob(f"quenty_{short_name}@*")) for index in (self.shared_index, self.server_index)
            ):
                raise ValueError(f"Package already exists: quenty/{short_name}")
            public_name = _pascal_case(export_name or short_name)
            module_specs = self._module_specs(normalized_kind, public_name, normalized_realm)
            if any(not EXPORT_NAME.fullmatch(module_name) for module_name, _realm in module_specs):
                raise ValueError("Export names must be valid Luau identifiers")
        except ValueError as error:
            return OperationResult(False, "Invalid package configuration", diagnostics=(str(error),))

        before = self._snapshot()
        try:
            identifier = f"quenty_{short_name}@{version}"
            roots = {
                realm: (self.server_index if realm == "server" else self.shared_index) / identifier
                for _module_name, realm in module_specs
            }
            if not roots:
                roots["shared"] = self.shared_index / identifier
            modules_by_partition: dict[str, list[ModuleEntry]] = {realm: [] for realm in roots}
            exports_by_partition: dict[str, dict[str, str]] = {realm: {} for realm in roots}
            for module_name, realm in module_specs:
                package_root = roots[realm]
                package_root.mkdir(parents=True, exist_ok=True)
                module_path = f"{module_name}.luau"
                source = self._render_template(normalized_kind, module_name, template_name)
                source = inject_package_requires(source, dependency_aliases, alias_realms, realm)
                (package_root / module_path).write_text(source, encoding="utf-8")
                exports_by_partition[realm][module_name] = module_name
                modules_by_partition[realm].append(
                    ModuleEntry(
                        module_path,
                        realm,
                        {
                            "utility": "Utility",
                            "class": "Class/model",
                            "service": "Service",
                            "types": "Types",
                        }[normalized_kind],
                        description or purpose or f"Provides {module_name}.",
                    )
                )
            if normalized_kind == "empty":
                package_root = roots["shared"]
                package_root.mkdir(parents=True, exist_ok=True)
                placeholder = package_root / "README.md"
                placeholder.write_text(
                    f"# {public_name}\n\nAdd strict Luau modules and exports through `nevermore-packages`.\n",
                    encoding="utf-8",
                )
            package_purpose = purpose or f"Provides the {public_name} package."
            package_description = description or purpose or f"Provides the {public_name} package."
            package_tags = tuple(sorted({tag.strip() for tag in tags if tag.strip()}))
            for realm, package_root in roots.items():
                self._write_json(
                    package_root / "package.json",
                    {
                        "name": f"quenty/{short_name}",
                        "version": version,
                        "exports": exports_by_partition[realm],
                        "dependencies": [],
                        "externals": [],
                    },
                )
                write_catalog(
                    package_root / "catalog.json",
                    CatalogEntry(
                        purpose=package_purpose,
                        description=package_description,
                        tags=package_tags,
                        modules=tuple(modules_by_partition[realm]),
                    ),
                )
            sync_result = self._fast_sync()
            if not sync_result.ok:
                raise RuntimeError(sync_result.output)
            return self._success(f"Created quenty/{short_name}@{version}", before, (sync_result,))
        except Exception as error:
            self._restore(before)
            return OperationResult(False, "Package creation failed and was rolled back", diagnostics=(str(error),))

    def update_package(
        self,
        name: str,
        *,
        purpose: str,
        description: str,
        tags: Sequence[str],
        exports: dict[str, str],
        modules: Sequence[ModuleEntry] | None = None,
    ) -> OperationResult:
        try:
            record = self.get_package(name)
            for alias, target in exports.items():
                if not EXPORT_NAME.fullmatch(alias):
                    raise ValueError(f"Invalid export name: {alias}")
                if not target.strip():
                    raise ValueError(f"Export target is empty: {alias}")
                self._resolve_module(record, target)
            if not purpose.strip():
                raise ValueError("Purpose cannot be empty")
            if not description.strip():
                raise ValueError("Description cannot be empty")
            if modules is not None:
                roots = self._record_roots(record)
                actual_modules = {
                    path.relative_to(next(root for root in roots if path.is_relative_to(root))).as_posix()
                    for path in self._source_module_paths(record)
                    if path.is_file()
                    and path.suffix in {".lua", ".luau"}
                    and not path.name.endswith((".spec.lua", ".spec.luau"))
                    and path.name not in {"jest.config.lua", "jest.config.luau"}
                }
                described_modules = {module.path for module in modules}
                if actual_modules != described_modules:
                    missing = sorted(actual_modules - described_modules)
                    stale = sorted(described_modules - actual_modules)
                    details = []
                    if missing:
                        details.append(f"missing module metadata: {', '.join(missing)}")
                    if stale:
                        details.append(f"stale module metadata: {', '.join(stale)}")
                    raise ValueError("; ".join(details))
        except (OSError, ValueError) as error:
            return OperationResult(False, "Invalid package metadata", diagnostics=(str(error),))

        before = self._snapshot()
        try:
            updated_modules = (
                tuple(sorted(modules, key=lambda module: module.path)) if modules is not None else record.catalog.modules
            )
            module_realms = {self._module_target(module.path): module.realm for module in updated_modules}
            exports_by_partition = {"shared": {}, "server": {}}
            for alias, target in exports.items():
                realm = module_realms.get(target)
                if realm is None:
                    raise ValueError(f"Export {alias} has no module metadata")
                exports_by_partition["server" if realm == "server" else "shared"][alias] = target
            for partition, root in self._partition_roots(record).items():
                manifest = self._read_json(root / "package.json")
                manifest["exports"] = dict(sorted(exports_by_partition[partition].items()))
                self._write_json(root / "package.json", manifest)
                write_catalog(
                    root / "catalog.json",
                    CatalogEntry(
                        purpose=purpose.strip(),
                        description=description.strip(),
                        tags=tuple(sorted({tag.strip() for tag in tags if tag.strip()})),
                        modules=tuple(
                            module
                            for module in updated_modules
                            if (module.realm == "server") == (partition == "server")
                        ),
                    ),
                )
            sync_result = self._fast_sync()
            if not sync_result.ok:
                raise RuntimeError(sync_result.output)
            return self._success(f"Updated {record.name}", before, (sync_result,))
        except Exception as error:
            self._restore(before)
            return OperationResult(False, "Package update failed and was rolled back", diagnostics=(str(error),))

    def set_version(self, name: str, version: str) -> OperationResult:
        try:
            record = self.get_package(name)
            version = self._validate_version(version)
            if record.version == version:
                raise ValueError(f"{record.name} is already at {version}")
            destinations = {
                partition: root.parent / f"quenty_{record.short_name}@{version}"
                for partition, root in self._partition_roots(record).items()
            }
            if any(destination.exists() for destination in destinations.values()):
                raise ValueError(f"Version destination already exists for {record.name}@{version}")
        except (OSError, ValueError) as error:
            return OperationResult(False, "Invalid version change", diagnostics=(str(error),))

        before = self._snapshot()
        try:
            for partition, root in self._partition_roots(record).items():
                destination = destinations[partition]
                root.rename(destination)
                manifest = self._read_json(destination / "package.json")
                manifest["version"] = version
                self._write_json(destination / "package.json", manifest)
            sync_result = self._fast_sync()
            if not sync_result.ok:
                raise RuntimeError(sync_result.output)
            return self._success(
                f"Updated {record.name} from {record.version} to {version}", before, (sync_result,)
            )
        except Exception as error:
            self._restore(before)
            return OperationResult(False, "Version update failed and was rolled back", diagnostics=(str(error),))

    def remove_package(self, name: str, *, confirmed: bool = False) -> OperationResult:
        try:
            record = self.get_package(name)
            if not confirmed:
                raise ValueError("Removal requires explicit confirmation")
            dependents = self.reverse_dependencies(name)
            if dependents:
                raise ValueError(f"Package is still required by: {', '.join(dependents)}")
        except (OSError, ValueError) as error:
            return OperationResult(False, "Package cannot be removed", diagnostics=(str(error),))

        before = self._snapshot()
        try:
            for root in self._record_roots(record):
                shutil.rmtree(root)
            sync_result = self._fast_sync()
            if not sync_result.ok:
                raise RuntimeError(sync_result.output)
            return self._success(f"Removed {record.name}", before, (sync_result,))
        except Exception as error:
            self._restore(before)
            return OperationResult(False, "Package removal failed and was rolled back", diagnostics=(str(error),))

    def sync(self, *, check: bool = False) -> OperationResult:
        before = self._snapshot()
        command = [sys.executable, str(self.scripts / "sync_packages.py")]
        if check:
            command.append("--check")
        result = self._run(command)
        if not result.ok and not check:
            self._restore(before)
        return self._command_operation("Package synchronization", result, before)

    def normalize(self, *, check: bool = False) -> OperationResult:
        before = self._snapshot()
        command = [sys.executable, str(self.scripts / "normalize_package_requires.py")]
        if check:
            command.append("--check")
        result = self._run(command)
        if not result.ok and not check:
            self._restore(before)
        return self._command_operation("Require normalization", result, before)

    def validate(self) -> OperationResult:
        diagnostics = []
        try:
            records = self.list_packages()
            for record in records:
                diagnostics.extend(validate_catalog(record))
        except (OSError, ValueError, json.JSONDecodeError) as error:
            diagnostics.append(str(error))

        commands = (
            self._run([sys.executable, str(self.scripts / "normalize_package_requires.py"), "--check"]),
            self._run([sys.executable, str(self.scripts / "sync_packages.py"), "--check"]),
            self._run(["stylua", "--check", "src"]),
            self._run(["selene", "src"]),
        )
        diagnostics.extend(result.output for result in commands if not result.ok and result.output)
        return OperationResult(
            ok=not diagnostics,
            summary="Validation passed" if not diagnostics else "Validation failed",
            diagnostics=tuple(diagnostics),
            logs=tuple(result.output for result in commands if result.output),
        )

    def _record_pair(self, name: str) -> PackageRecord:
        short_name = name.removeprefix("quenty/")
        partition_roots: dict[str, Path] = {}
        manifests: list[dict[str, object]] = []
        catalogs = []
        for partition, index in (("shared", self.shared_index), ("server", self.server_index)):
            matches = sorted(index.glob(f"quenty_{short_name}@*/package.json"))
            if len(matches) > 1:
                raise ValueError(f"Multiple installed {partition} versions found for {name}")
            if not matches:
                continue
            partition_roots[partition] = matches[0].parent
            manifests.append(self._read_json(matches[0]))
            catalogs.append(read_catalog(matches[0].parent / "catalog.json"))
        if not manifests:
            raise ValueError(f"Unknown package: {name}")
        versions = {str(manifest["version"]) for manifest in manifests}
        if len(versions) != 1:
            raise ValueError(f"Paired package versions differ for {name}")
        first_catalog = catalogs[0]
        if any(
            (catalog.purpose, catalog.description, catalog.tags)
            != (first_catalog.purpose, first_catalog.description, first_catalog.tags)
            for catalog in catalogs[1:]
        ):
            raise ValueError(f"Paired catalog metadata differs for {name}")
        modules = tuple(sorted((module for catalog in catalogs for module in catalog.modules), key=lambda item: item.path))
        if len({module.path for module in modules}) != len(modules):
            raise ValueError(f"Module appears in both package partitions: {name}")
        exports = {
            str(alias): str(target)
            for manifest in manifests
            for alias, target in dict(manifest.get("exports", {})).items()
        }
        if sum(len(dict(manifest.get("exports", {}))) for manifest in manifests) != len(exports):
            raise ValueError(f"Duplicate public alias across package partitions: {name}")
        return PackageRecord(
            root=partition_roots.get("shared") or partition_roots["server"],
            name=name,
            version=versions.pop(),
            exports=exports,
            dependencies=tuple(
                sorted({str(item) for manifest in manifests for item in manifest.get("dependencies", [])})
            ),
            externals=tuple(sorted({str(item) for manifest in manifests for item in manifest.get("externals", [])})),
            catalog=CatalogEntry(first_catalog.purpose, first_catalog.description, first_catalog.tags, modules),
            shared_root=partition_roots.get("shared"),
            server_root=partition_roots.get("server"),
        )

    def _partition_roots(self, record: PackageRecord) -> dict[str, Path]:
        return {
            partition: root
            for partition, root in (("shared", record.shared_root), ("server", record.server_root))
            if root is not None
        }

    def _record_roots(self, record: PackageRecord) -> tuple[Path, ...]:
        return tuple(self._partition_roots(record).values())

    def _source_module_paths(self, record: PackageRecord) -> tuple[Path, ...]:
        return tuple(
            sorted(
                path
                for root in self._record_roots(record)
                for path in root.rglob("*")
                if path.is_file()
                and path.suffix in {".lua", ".luau"}
                and not path.name.endswith((".spec.lua", ".spec.luau"))
                and path.name not in {"jest.config.lua", "jest.config.luau"}
            )
        )

    def _module_target(self, relative_path: str) -> str:
        path = Path(relative_path)
        if path.name in {"init.lua", "init.luau"}:
            parent = path.parent.as_posix()
            return "." if parent == "." else parent
        return path.with_suffix("").as_posix()

    def _infer_module_realm(self, relative_path: str) -> str:
        parts = {part.casefold() for part in Path(relative_path).parts[:-1]}
        if "server" in parts:
            return "server"
        if "client" in parts:
            return "client"
        return "shared"

    def _add_module_export(
        self,
        record: PackageRecord,
        module: PackageModule,
        exports: dict[str, str],
        alias_owners: dict[str, str],
    ) -> None:
        if module.target in exports.values():
            return

        target_parts = [record.short_name] if module.target == "." else module.target.split("/")
        candidates = [
            _pascal_case("-".join(target_parts[index:]))
            for index in range(len(target_parts) - 1, -1, -1)
        ]
        candidates.append(_pascal_case("-".join((record.short_name, *target_parts))))
        for alias in dict.fromkeys(candidates):
            if EXPORT_NAME.fullmatch(alias) and alias not in exports and alias not in alias_owners:
                exports[alias] = module.target
                return

        raise ValueError(f"Cannot derive an unused public alias for {module.path}")

    def _public_alias_owners(self, excluded_package: str) -> dict[str, str]:
        return {
            alias: package.name
            for package in self.list_packages()
            if package.name != excluded_package
            for alias in package.exports
        }

    def _write_exports(self, record: PackageRecord, exports: dict[str, str], summary: str) -> OperationResult:
        if exports == record.exports:
            return OperationResult(True, f"No exposure changes needed for {record.name}")

        before = self._snapshot()
        try:
            module_realms = {
                self._module_target(module.path): module.realm for module in record.catalog.modules
            }
            for partition, root in self._partition_roots(record).items():
                manifest = self._read_json(root / "package.json")
                manifest["exports"] = dict(
                    sorted(
                        (alias, target)
                        for alias, target in exports.items()
                        if (module_realms[target] == "server") == (partition == "server")
                    )
                )
                self._write_json(root / "package.json", manifest)
            sync_result = self._fast_sync()
            if not sync_result.ok:
                raise RuntimeError(sync_result.output)
            return self._success(summary, before, (sync_result,))
        except Exception as error:
            self._restore(before)
            return OperationResult(False, "Module exposure failed and was rolled back", diagnostics=(str(error),))

    def _fast_sync(self) -> CommandResult:
        normalization = self._run([sys.executable, str(self.scripts / "normalize_package_requires.py")])
        if not normalization.ok:
            return normalization
        synchronization = self._run([sys.executable, str(self.scripts / "sync_packages.py")])
        return CommandResult(
            synchronization.command,
            synchronization.returncode,
            "\n".join(filter(None, (normalization.output, synchronization.output))),
        )

    def _run(self, command: Sequence[str]) -> CommandResult:
        completed = subprocess.run(
            command,
            cwd=self.root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        return CommandResult(tuple(command), completed.returncode, completed.stdout.strip())

    def _snapshot(self) -> dict[str, bytes]:
        paths = [self.catalog_path]
        if self.src.exists():
            paths.extend(path for path in self.src.rglob("*") if path.is_file())
        return {path.relative_to(self.root).as_posix(): path.read_bytes() for path in paths if path.exists()}

    def _restore(self, snapshot: dict[str, bytes]) -> None:
        current_paths = [self.catalog_path]
        if self.src.exists():
            current_paths.extend(path for path in self.src.rglob("*") if path.is_file())
        for path in current_paths:
            relative = path.relative_to(self.root).as_posix()
            if relative not in snapshot:
                path.unlink()
        for relative, contents in snapshot.items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(contents)
        for directory in sorted((path for path in self.src.rglob("*") if path.is_dir()), reverse=True):
            if not any(directory.iterdir()):
                directory.rmdir()

    def _success(
        self, summary: str, before: dict[str, bytes], commands: Sequence[CommandResult] = ()
    ) -> OperationResult:
        changed = self._changed_paths(before)
        return OperationResult(
            True,
            summary,
            tuple(changed),
            logs=tuple(command.output for command in commands if command.output),
        )

    def _command_operation(self, label: str, result: CommandResult, before: dict[str, bytes]) -> OperationResult:
        return OperationResult(
            result.ok,
            f"{label} {'passed' if result.ok else 'failed'}",
            tuple(self._changed_paths(before)),
            diagnostics=() if result.ok else (result.output,),
            logs=(result.output,) if result.output else (),
        )

    def _changed_paths(self, before: dict[str, bytes]) -> list[Path]:
        current = self._snapshot()
        return [
            self.root / relative
            for relative in sorted(set(before) | set(current))
            if before.get(relative) != current.get(relative)
        ]

    def _validate_name(self, name: str) -> str:
        if not PACKAGE_NAME.fullmatch(name):
            raise ValueError("Package names must contain lowercase letters, numbers, and hyphens")
        return name

    def _validate_version(self, version: str) -> str:
        if not SEMVER.fullmatch(version):
            raise ValueError("Versions must use numeric semantic versioning, for example 0.1.0")
        return version

    def _read_json(self, path: Path) -> dict[str, object]:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise ValueError(f"Expected a JSON object: {path}")
        return data

    def _write_json(self, path: Path, data: dict[str, object]) -> None:
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    def _resolve_module(self, record: PackageRecord, target: str) -> Path:
        for package_root in self._record_roots(record):
            base = package_root if target == "." else package_root / target
            candidates = [base / "init.luau", base / "init.lua"] if base.is_dir() else []
            candidates.extend((Path(f"{base}.luau"), Path(f"{base}.lua")))
            for candidate in candidates:
                if candidate.is_file():
                    return candidate
        raise ValueError(f"Cannot resolve export target {target!r}")

    def _move_module_sources(self, source_root: Path, destination_root: Path, target: str) -> None:
        relative = Path() if target == "." else Path(target)
        candidates = (
            source_root / relative / "init.luau",
            source_root / relative / "init.lua",
            Path(f"{source_root / relative}.luau"),
            Path(f"{source_root / relative}.lua"),
        )
        moved = False
        for source in candidates:
            if not source.is_file():
                continue
            destination = destination_root / source.relative_to(source_root)
            if destination.exists():
                raise ValueError(f"Module destination already exists: {destination}")
            destination.parent.mkdir(parents=True, exist_ok=True)
            source.rename(destination)
            moved = True

            spec_candidates = (
                source.with_name(f"{source.stem}.spec{source.suffix}"),
                source.with_name(f"{source.stem}.spec.lua"),
                source.with_name(f"{source.stem}.spec.luau"),
            )
            for spec in dict.fromkeys(spec_candidates):
                if spec.is_file():
                    spec_destination = destination_root / spec.relative_to(source_root)
                    spec_destination.parent.mkdir(parents=True, exist_ok=True)
                    spec.rename(spec_destination)
        if not moved:
            raise ValueError(f"Cannot resolve module target {target!r}")

    def _move_remaining_package_files(self, source_root: Path, destination_root: Path) -> None:
        for source in sorted(source_root.rglob("*")):
            if not source.is_file() or source.name in {"package.json", "catalog.json"}:
                continue
            destination = destination_root / source.relative_to(source_root)
            if destination.exists():
                if destination.read_bytes() != source.read_bytes():
                    raise ValueError(f"Package file destination already exists: {destination}")
                source.unlink()
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            source.rename(destination)

    def _render_template(self, kind: str, public_name: str, template_name: str | None = None) -> str:
        if template_name:
            return render_snippet_template(self.snippet_path, template_name, public_name)
        if kind == "utility":
            return (
                f'--!strict\n--[=[\n\tProvides stateless {public_name} helpers.\n\n\t@util {public_name}\n]=]\n\n'
                f"const {public_name} = {{}}\n\nreturn {public_name}\n"
            )
        if kind == "types":
            return f"--!strict\n--[=[\n\tDefines shared {public_name} types.\n\n\t@types {public_name}\n]=]\n\nreturn {{}}\n"
        if kind == "class":
            return (
                f'--!strict\n--[=[\n\tRepresents one {public_name}.\n\n\t@class {public_name}\n]=]\n\n'
                'const Maid = require("@game/ReplicatedStorage/Packages/Maid")\n\n'
                f"const {public_name} = {{}}\n{public_name}.ClassName = \"{public_name}\"\n{public_name}.__index = {public_name}\n\n"
                f"export type {public_name} = typeof(setmetatable({{}} :: {{ _maid: Maid.Maid }}, "
                f"{{}} :: typeof({{ __index = {public_name} }})))\n\n"
                f"function {public_name}.new(): {public_name}\n\tconst self = setmetatable({{}}, {public_name}) :: {public_name}\n"
                "\tself._maid = Maid.new()\n\treturn self\nend\n\n"
                f"function {public_name}.Destroy(self: {public_name}): ()\n\tself._maid:DoCleaning()\n"
                "\ttable.clear(self :: any)\n\tsetmetatable(self :: any, nil)\nend\n\n"
                f"return {public_name}\n"
            )
        if kind == "service":
            return (
                f'--!strict\n--[=[\n\tCoordinates {public_name} behavior.\n\n\t@class {public_name}\n\t@server\n]=]\n\n'
                'const Maid = require("@game/ReplicatedStorage/Packages/Maid")\n'
                'const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")\n'
                'const t = require("@game/ReplicatedStorage/Packages/t")\n\n'
                f"const {public_name} = {{}}\n{public_name}.ServiceName = \"{public_name}\"\n{public_name}.ServerOnly = true\n\n"
                f"export type {public_name} = typeof(setmetatable({{}} :: {{ _serviceBag: ServiceBag.ServiceBag, "
                f"_maid: Maid.Maid }}, {{}} :: typeof({{ __index = {public_name} }})))\n\n"
                f"function {public_name}.Init(self: {public_name}, serviceBag: ServiceBag.ServiceBag): ()\n"
                '\tassert(not (self :: any)._serviceBag, "Already initialized")\n'
                '\tassert(t.table(serviceBag), "Bad serviceBag")\n\tself._serviceBag = serviceBag\n\tself._maid = Maid.new()\nend\n\n'
                f"function {public_name}.Start(_self: {public_name}): ()\nend\n\n"
                f"function {public_name}.Destroy(self: {public_name}): ()\n\tself._maid:DoCleaning()\nend\n\n"
                f"return {public_name}\n"
            )
        raise ValueError(f"No source template for {kind}")

    def _module_specs(self, kind: str, public_name: str, service_realm: str) -> tuple[tuple[str, str], ...]:
        if kind == "empty":
            return ()
        if kind != "service":
            return ((public_name, "shared"),)

        base_name = public_name
        if base_name.casefold().endswith("serviceclient"):
            base_name = f"{base_name[:-13]}Service"
        elif base_name.casefold().endswith("service"):
            base_name = f"{base_name[:-7]}Service"
        else:
            base_name += "Service"
        if service_realm == "server":
            return ((base_name, "server"),)
        if service_realm == "client":
            return ((f"{base_name}Client", "client"),)
        return ((base_name, "server"), (f"{base_name}Client", "client"))

    def _find_snippet_path(self) -> Path:
        relative = Path("Untitled Knife Game") / ".vscode" / "luau.code-snippets"
        candidates = (
            self.root.parent / relative,
            Path(__file__).resolve().parents[2] / relative,
        )
        return next((path for path in candidates if path.is_file()), candidates[0])
