#!/usr/bin/env python3
"""Synchronize paired package surfaces, manifests, catalogs, and Rojo index maps."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from nevermore_packages.catalog import read_catalog, render_catalog, validate_catalog
from nevermore_packages.models import CatalogEntry, PackageRecord


SRC = ROOT / "src"
SHARED = SRC / "shared"
SERVER = SRC / "server"
SHARED_INDEX = SHARED / "_Index"
SERVER_INDEX = SERVER / "_Index"
CATALOG = ROOT / "PKGINFO.md"
DOCUMENTATION_NAMES = {"MyClass"}
PACKAGE_REQUIRE = re.compile(
    r"(?:\brequire|\(require\s*::\s*any\))\s*\(\s*(?:"
    r"[\"']@game/(?:ReplicatedStorage/Packages|ServerStorage/ServerPackages)/"
    r"(?P<path_alias>[A-Za-z_][A-Za-z0-9_]*)[\"']"
    r"|(?:Packages|ServerPackages)\.(?P<property_alias>[A-Za-z_][A-Za-z0-9_]*))\s*\)"
)
TYPE_DECLARATION = re.compile(
    r"^export type\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?P<generics><[^=\n]+>)?\s*=",
    re.MULTILINE,
)
VALID_REALMS = {"shared", "client", "server"}


def resolve_module(roots: tuple[Path, ...], target: str) -> Path:
    for package_root in roots:
        base = package_root if target == "." else package_root / target
        if base.is_dir():
            for init_name in ("init.luau", "init.lua"):
                candidate = base / init_name
                if candidate.exists():
                    return candidate
        for extension in (".luau", ".lua"):
            candidate = Path(f"{base}{extension}")
            if candidate.exists():
                return candidate
    raise ValueError(f"Cannot resolve export target {target!r} in {', '.join(str(root) for root in roots)}")


def module_target(relative_path: str) -> str:
    path = PurePosixPath(relative_path)
    if path.name in {"init.lua", "init.luau"}:
        parent = path.parent.as_posix()
        return "." if parent == "." else parent
    return path.with_suffix("").as_posix()


def runtime_expression(scoped_version: str, target: str) -> str:
    expression = f'script.Parent._Index["{scoped_version}"]'
    if target != ".":
        for segment in target.split("/"):
            expression += f'["{segment}"]'
    return expression


def generic_arguments(generics: str | None) -> str:
    if not generics:
        return ""
    parameters = [parameter.strip() for parameter in generics[1:-1].split(",")]
    arguments = []
    for parameter in parameters:
        match = re.match(r"([A-Za-z_][A-Za-z0-9_]*)(\.\.\.)?", parameter)
        if not match:
            raise ValueError(f"Unsupported generic declaration: {generics}")
        arguments.append(f"{match.group(1)}{match.group(2) or ''}")
    return f"<{', '.join(arguments)}>"


def render_wrapper(scoped_version: str, implementation: Path, target: str) -> str:
    declarations = []
    seen = set()
    source = implementation.read_text(encoding="utf-8", errors="replace")
    for match in TYPE_DECLARATION.finditer(source):
        name = match.group("name")
        generics = match.group("generics")
        signature = f"{name}{generics or ''}"
        if signature in seen:
            continue
        seen.add(signature)
        declarations.append(f"export type {signature} = Implementation.{name}{generic_arguments(generics)}")

    expression = runtime_expression(scoped_version, target)
    if not declarations:
        return f"--!strict\n\nreturn require({expression})\n"
    require_binding = f"const Implementation = require({expression})"
    if len(require_binding) > 120:
        require_binding = f"const Implementation =\n\trequire({expression})"
    return "\n".join(["--!strict", "", require_binding, "", *declarations, "", "return Implementation", ""])


def write_or_check(path: Path, expected: str, check: bool, differences: list[Path]) -> None:
    actual = path.read_text(encoding="utf-8") if path.exists() else None
    if actual == expected:
        return
    differences.append(path)
    if not check:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(expected, encoding="utf-8")


def partition_manifests(index: Path) -> dict[str, tuple[Path, dict[str, object]]]:
    result = {}
    for manifest_path in sorted(index.glob("quenty_*@*/package.json")):
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        name = str(manifest["name"])
        if name in result:
            raise ValueError(f"Duplicate indexed package partition: {name}")
        result[name] = (manifest_path, manifest)
    return result


def merge_catalogs(shared_root: Path | None, server_root: Path | None, name: str) -> CatalogEntry:
    entries = [read_catalog(root / "catalog.json") for root in (shared_root, server_root) if root is not None]
    first = entries[0]
    for entry in entries[1:]:
        if (entry.purpose, entry.description, entry.tags) != (first.purpose, first.description, first.tags):
            raise ValueError(f"Paired catalog metadata differs for {name}")
    modules = tuple(sorted((module for entry in entries for module in entry.modules), key=lambda module: module.path))
    if len({module.path for module in modules}) != len(modules):
        raise ValueError(f"Module appears in both package partitions: {name}")
    return CatalogEntry(first.purpose, first.description, first.tags, modules)


def add_source_mapping(node: dict[str, object], relative_path: str, source_path: str) -> None:
    path = PurePosixPath(relative_path)
    parts = list(path.parts)
    filename = parts.pop()
    if filename in {"init.lua", "init.luau"}:
        if not parts:
            raise ValueError("A paired server partition cannot override a shared package root init module")
        instance_parts = parts
    else:
        instance_parts = [*parts, PurePosixPath(filename).stem]

    cursor = node
    for index, part in enumerate(instance_parts):
        is_last = index == len(instance_parts) - 1
        child = cursor.setdefault(part, {} if is_last else {"$className": "Folder"})
        if not isinstance(child, dict):
            raise ValueError(f"Conflicting Rojo mapping at {relative_path}")
        cursor = child
    cursor.pop("$className", None)
    cursor["$path"] = source_path


def project_json(name: str, tree: dict[str, object]) -> str:
    return json.dumps(
        {
            "name": name,
            "globIgnorePaths": ["**/catalog.json", "**/package.json"],
            "tree": tree,
        },
        indent=2,
    ) + "\n"


def mapped_source_path(package_root: Path, source_path: Path, prefix: str) -> str:
    relative = PurePosixPath(source_path.relative_to(package_root).as_posix())
    mapped_relative = relative.parent if relative.name in {"init.lua", "init.luau"} else relative
    return f"{prefix}/{mapped_relative.as_posix()}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Report drift without writing files")
    args = parser.parse_args()

    shared_manifests = partition_manifests(SHARED_INDEX)
    server_manifests = partition_manifests(SERVER_INDEX)
    package_names = sorted(set(shared_manifests) | set(server_manifests))

    partitions: dict[tuple[str, str], tuple[Path, dict[str, object]]] = {}
    package_versions = {}
    records = []
    alias_owners = {}
    alias_targets: dict[str, tuple[str, Path, str]] = {}
    module_realms: dict[tuple[str, str], str] = {}

    for name in package_names:
        shared_pair = shared_manifests.get(name)
        server_pair = server_manifests.get(name)
        pairs = [("shared", shared_pair), ("server", server_pair)]
        versions = {str(pair[1]["version"]) for _, pair in pairs if pair is not None}
        if len(versions) != 1:
            raise ValueError(f"Paired package versions differ for {name}")
        version = versions.pop()
        package_versions[name] = version
        shared_root = shared_pair[0].parent if shared_pair else None
        server_root = server_pair[0].parent if server_pair else None
        catalog = merge_catalogs(shared_root, server_root, name)
        metadata = {module_target(module.path): module for module in catalog.modules}
        exports = {}
        dependencies = set()
        externals = set()
        for partition_name, pair in pairs:
            if pair is None:
                continue
            manifest_path, manifest = pair
            partitions[(name, partition_name)] = pair
            for alias, target_value in dict(manifest.get("exports", {})).items():
                target = str(target_value)
                module = metadata.get(target)
                if module is None:
                    raise ValueError(f"Export {alias} has no catalog module in {name}")
                expected_partition = "server" if module.realm == "server" else "shared"
                if expected_partition != partition_name:
                    raise ValueError(f"Export {alias} is in the wrong package partition")
                if alias in alias_owners:
                    raise ValueError(f"Duplicate surface export: {alias}")
                alias_owners[str(alias)] = name
                implementation = resolve_module(tuple(root for root in (shared_root, server_root) if root), target)
                alias_targets[str(alias)] = (partition_name, implementation, target)
                exports[str(alias)] = target
                module_realms[(name, str(alias))] = module.realm
            dependencies.update(str(item) for item in manifest.get("dependencies", []))
            externals.update(str(item) for item in manifest.get("externals", []))
        records.append(
            PackageRecord(
                root=shared_root or server_root,  # type: ignore[arg-type]
                name=name,
                version=version,
                exports=exports,
                dependencies=tuple(sorted(dependencies)),
                externals=tuple(sorted(externals)),
                catalog=catalog,
                shared_root=shared_root,
                server_root=server_root,
            )
        )

    dependencies_by_partition: dict[tuple[str, str], set[str]] = defaultdict(set)
    externals_by_partition: dict[tuple[str, str], set[str]] = defaultdict(set)
    for key, (manifest_path, _) in partitions.items():
        package_name, partition_name = key
        for source_path in manifest_path.parent.rglob("*"):
            if not source_path.is_file() or source_path.suffix not in {".lua", ".luau"}:
                continue
            source = source_path.read_text(encoding="utf-8", errors="replace")
            for match in PACKAGE_REQUIRE.finditer(source):
                alias = match.group("path_alias") or match.group("property_alias")
                dependency = alias_owners.get(alias)
                if dependency and dependency != package_name:
                    dependencies_by_partition[key].add(dependency)
                elif not dependency and alias not in DOCUMENTATION_NAMES:
                    externals_by_partition[key].add(alias)

    differences: list[Path] = []
    for key, (manifest_path, manifest) in sorted(partitions.items()):
        package_name, partition_name = key
        version = package_versions[package_name]
        normalized = {
            "name": package_name,
            "version": version,
            "exports": dict(sorted(dict(manifest.get("exports", {})).items())),
            "dependencies": [
                f"{dependency}@{package_versions[dependency]}"
                for dependency in sorted(dependencies_by_partition[key])
            ],
            "externals": sorted(externals_by_partition[key]),
        }
        write_or_check(manifest_path, json.dumps(normalized, indent=2) + "\n", args.check, differences)

    for alias, (partition_name, implementation, target) in sorted(alias_targets.items()):
        owner = alias_owners[alias]
        scoped_version = f"{owner}@{package_versions[owner]}"
        wrapper = render_wrapper(scoped_version, implementation, target)
        surface = SERVER if partition_name == "server" else SHARED
        write_or_check(surface / f"{alias}.luau", wrapper, args.check, differences)

    shared_tree: dict[str, object] = {"$className": "Folder"}
    for name, (manifest_path, manifest) in sorted(shared_manifests.items()):
        shared_tree[f'{name}@{manifest["version"]}'] = {"$path": manifest_path.parent.name}

    server_tree: dict[str, object] = {"$className": "Folder"}
    for name, (manifest_path, manifest) in sorted(server_manifests.items()):
        scoped_version = f'{name}@{manifest["version"]}'
        shared_pair = shared_manifests.get(name)
        if shared_pair is None:
            server_tree[scoped_version] = {"$path": manifest_path.parent.name}
            continue
        server_root = manifest_path.parent
        shared_root = shared_pair[0].parent
        server_owns_root = any((server_root / name).is_file() for name in ("init.lua", "init.luau"))
        if server_owns_root:
            node: dict[str, object] = {"$path": server_root.name}
            source_roots = ((shared_root, f"../../shared/_Index/{shared_root.name}"),)
        else:
            node = {"$className": "Folder"}
            source_roots = (
                (shared_root, f"../../shared/_Index/{shared_root.name}"),
                (server_root, server_root.name),
            )
        for source_root, source_prefix in source_roots:
            for source_path in sorted(source_root.rglob("*")):
                if not source_path.is_file() or source_path.suffix not in {".lua", ".luau"}:
                    continue
                relative = source_path.relative_to(source_root).as_posix()
                if relative in {"init.lua", "init.luau"}:
                    raise ValueError(f"A paired package cannot override its root init module: {name}")
                mapped_path = mapped_source_path(source_root, source_path, source_prefix)
                add_source_mapping(node, relative, mapped_path)
        server_tree[scoped_version] = node

    write_or_check(SHARED_INDEX / "default.project.json", project_json("_Index", shared_tree), args.check, differences)
    write_or_check(SERVER_INDEX / "default.project.json", project_json("_Index", server_tree), args.check, differences)
    write_or_check(CATALOG, render_catalog(records), args.check, differences)

    expected_shared = {f"{alias}.luau" for alias, value in alias_targets.items() if value[0] == "shared"}
    expected_server = {f"{alias}.luau" for alias, value in alias_targets.items() if value[0] == "server"}
    for surface, expected in ((SHARED, expected_shared), (SERVER, expected_server)):
        unexpected = [path for path in surface.glob("*.luau") if path.name not in expected]
        differences.extend(unexpected)
        if not args.check:
            for path in unexpected:
                path.unlink()

    if args.check:
        for record in records:
            if validate_catalog(record):
                for root in (record.shared_root, record.server_root):
                    if root is not None and root / "catalog.json" not in differences:
                        differences.append(root / "catalog.json")

    if differences:
        action = "would update" if args.check else "updated"
        print(f"Package surfaces {action} {len(differences)} files:")
        for path in differences[:25]:
            print(path.relative_to(ROOT))
        if len(differences) > 25:
            print(f"... and {len(differences) - 25} more")
        return 1 if args.check else 0

    print(f"Package surfaces are synchronized ({len(records)} packages, {len(alias_owners)} exports)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
