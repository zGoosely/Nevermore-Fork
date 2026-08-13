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
from .models import CatalogEntry, CommandResult, ModuleEntry, OperationResult, PackageRecord, SnippetTemplate
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
        self.index = self.src / "_Index"
        self.catalog_path = self.root / "PKGINFO.md"
        self.scripts = self.root / "scripts"
        self.snippet_path = snippet_path or self._find_snippet_path()

    def list_snippet_templates(self) -> tuple[SnippetTemplate, ...]:
        """Return complete module templates imported from Untitled Knife Game."""

        return load_snippet_templates(self.snippet_path)

    def list_dependency_aliases(self) -> tuple[str, ...]:
        """Return public exports that a newly created package can require."""

        return tuple(sorted({alias for record in self.list_packages() for alias in record.exports}, key=str.casefold))

    def list_packages(self) -> list[PackageRecord]:
        records = []
        for manifest_path in sorted(self.index.glob("quenty_*@*/package.json")):
            manifest = self._read_json(manifest_path)
            records.append(self._record(manifest_path.parent, manifest))
        return records

    def get_package(self, name: str) -> PackageRecord:
        short_name = self._validate_name(name.removeprefix("quenty/"))
        matches = sorted(self.index.glob(f"quenty_{short_name}@*/package.json"))
        if not matches:
            raise ValueError(f"Unknown package: quenty/{short_name}")
        if len(matches) != 1:
            raise ValueError(f"Multiple installed versions found for quenty/{short_name}")
        return self._record(matches[0].parent, self._read_json(matches[0]))

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
                sidecar = record.root / "catalog.json"
                if sidecar.exists():
                    continue
                entry = legacy.get(record.short_name)
                if entry is None:
                    missing.append(record.short_name)
                    continue
                write_catalog(sidecar, entry)
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
            available_aliases = set(self.list_dependency_aliases())
            unknown_aliases = sorted(set(dependency_aliases) - available_aliases)
            if unknown_aliases:
                raise ValueError(f"Unknown package exports: {', '.join(unknown_aliases)}")
            if list(self.index.glob(f"quenty_{short_name}@*")):
                raise ValueError(f"Package already exists: quenty/{short_name}")
            public_name = _pascal_case(export_name or short_name)
            module_specs = self._module_specs(normalized_kind, public_name, normalized_realm)
            if any(not EXPORT_NAME.fullmatch(module_name) for module_name, _realm in module_specs):
                raise ValueError("Export names must be valid Luau identifiers")
        except ValueError as error:
            return OperationResult(False, "Invalid package configuration", diagnostics=(str(error),))

        before = self._snapshot()
        try:
            package_root = self.index / f"quenty_{short_name}@{version}"
            package_root.mkdir(parents=True)
            exports = {module_name: module_name for module_name, _realm in module_specs}
            self._write_json(
                package_root / "package.json",
                {
                    "name": f"quenty/{short_name}",
                    "version": version,
                    "exports": exports,
                    "dependencies": [],
                    "externals": [],
                },
            )
            modules = []
            for module_name, realm in module_specs:
                module_path = f"{module_name}.luau"
                source = self._render_template(normalized_kind, module_name, template_name)
                source = inject_package_requires(source, dependency_aliases)
                (package_root / module_path).write_text(source, encoding="utf-8")
                modules.append(
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
                placeholder = package_root / "README.md"
                placeholder.write_text(
                    f"# {public_name}\n\nAdd strict Luau modules and exports through `nevermore-packages`.\n",
                    encoding="utf-8",
                )
            entry = CatalogEntry(
                purpose=purpose or f"Provides the {public_name} package.",
                description=description or purpose or f"Provides the {public_name} package.",
                tags=tuple(sorted({tag.strip() for tag in tags if tag.strip()})),
                modules=tuple(modules),
            )
            write_catalog(package_root / "catalog.json", entry)
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
                self._resolve_module(record.root, target)
            if not purpose.strip():
                raise ValueError("Purpose cannot be empty")
            if not description.strip():
                raise ValueError("Description cannot be empty")
            if modules is not None:
                actual_modules = {
                    path.relative_to(record.root).as_posix()
                    for path in record.root.rglob("*")
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
            manifest = self._read_json(record.root / "package.json")
            manifest["exports"] = dict(sorted(exports.items()))
            self._write_json(record.root / "package.json", manifest)
            write_catalog(
                record.root / "catalog.json",
                CatalogEntry(
                    purpose=purpose.strip(),
                    description=description.strip(),
                    tags=tuple(sorted({tag.strip() for tag in tags if tag.strip()})),
                    modules=tuple(sorted(modules, key=lambda module: module.path))
                    if modules is not None
                    else record.catalog.modules,
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
            destination = self.index / f"quenty_{record.short_name}@{version}"
            if destination.exists():
                raise ValueError(f"Version destination already exists: {destination.name}")
        except (OSError, ValueError) as error:
            return OperationResult(False, "Invalid version change", diagnostics=(str(error),))

        before = self._snapshot()
        try:
            record.root.rename(destination)
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
            shutil.rmtree(record.root)
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

    def _record(self, root: Path, manifest: dict[str, object]) -> PackageRecord:
        return PackageRecord(
            root=root,
            name=str(manifest["name"]),
            version=str(manifest["version"]),
            exports={str(key): str(value) for key, value in dict(manifest.get("exports", {})).items()},
            dependencies=tuple(str(item) for item in manifest.get("dependencies", [])),
            externals=tuple(str(item) for item in manifest.get("externals", [])),
            catalog=read_catalog(root / "catalog.json"),
        )

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

    def _resolve_module(self, package_root: Path, target: str) -> Path:
        base = package_root if target == "." else package_root / target
        candidates = [base / "init.luau", base / "init.lua"] if base.is_dir() else []
        candidates.extend((Path(f"{base}.luau"), Path(f"{base}.lua")))
        for candidate in candidates:
            if candidate.is_file():
                return candidate
        raise ValueError(f"Cannot resolve export target {target!r}")

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
