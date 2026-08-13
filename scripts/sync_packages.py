#!/usr/bin/env python3
"""Synchronize checked-in package surfaces, manifests, and the Rojo index map."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from nevermore_packages.catalog import read_catalog, render_catalog, validate_catalog
from nevermore_packages.models import PackageRecord


SRC = ROOT / "src"
INDEX = SRC / "_Index"
CATALOG = ROOT / "PKGINFO.md"
DOCUMENTATION_NAMES = {"MyClass"}
ABSOLUTE_REQUIRE = re.compile(
    r'(?:\brequire|\(require\s*::\s*any\))\s*\(\s*["\']'
    r'@game/ReplicatedStorage/Packages/(?P<alias>[A-Za-z_][A-Za-z0-9_]*)["\']\s*\)'
)
TYPE_DECLARATION = re.compile(
    r"^export type\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?P<generics><[^=\n]+>)?\s*=",
    re.MULTILINE,
)
CATALOG_PACKAGE = re.compile(r"^# (?P<name>[a-z0-9][a-z0-9-]*)$", re.MULTILINE)
CATALOG_COVERAGE = re.compile(r"^\*\*Coverage:\*\* .+$", re.MULTILINE)


def resolve_module(package_root: Path, target: str) -> Path:
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
    raise ValueError(f"Cannot resolve export target {target!r} in {package_root}")


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
    return "\n".join(
        ["--!strict", "", require_binding, "", *declarations, "", "return Implementation", ""]
    )


def write_or_check(path: Path, expected: str, check: bool, differences: list[Path]) -> None:
    actual = path.read_text(encoding="utf-8") if path.exists() else None
    if actual == expected:
        return
    differences.append(path)
    if not check:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(expected, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Report drift without writing files")
    args = parser.parse_args()

    manifests: dict[str, tuple[Path, dict[str, object]]] = {}
    alias_owners: dict[str, str] = {}
    alias_targets: dict[str, tuple[Path, str]] = {}

    for manifest_path in sorted(INDEX.glob("quenty_*@*/package.json")):
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        package_name = str(manifest["name"])
        if package_name in manifests:
            raise ValueError(f"Duplicate indexed package: {package_name}")
        manifests[package_name] = (manifest_path, manifest)
        for alias, target in dict(manifest["exports"]).items():
            if alias in alias_owners:
                raise ValueError(f"Duplicate surface export: {alias}")
            alias_owners[alias] = package_name
            alias_targets[alias] = (manifest_path.parent, str(target))

    package_versions = {name: str(manifest["version"]) for name, (_, manifest) in manifests.items()}
    dependencies: dict[str, set[str]] = defaultdict(set)
    externals: dict[str, set[str]] = defaultdict(set)
    for package_name, (manifest_path, _) in manifests.items():
        for source_path in manifest_path.parent.rglob("*"):
            if not source_path.is_file() or source_path.suffix not in {".lua", ".luau"}:
                continue
            source = source_path.read_text(encoding="utf-8", errors="replace")
            for match in ABSOLUTE_REQUIRE.finditer(source):
                alias = match.group("alias")
                dependency = alias_owners.get(alias)
                if dependency and dependency != package_name:
                    dependencies[package_name].add(dependency)
                elif not dependency and alias not in DOCUMENTATION_NAMES:
                    externals[package_name].add(alias)

    differences: list[Path] = []
    index_tree: dict[str, object] = {"$className": "Folder"}
    records: list[PackageRecord] = []

    for package_name, (manifest_path, manifest) in sorted(manifests.items()):
        version = str(manifest["version"])
        scoped_version = f"{package_name}@{version}"
        index_tree[scoped_version] = {"$path": manifest_path.parent.name}
        normalized_manifest = {
            "name": package_name,
            "version": version,
            "exports": dict(sorted(dict(manifest["exports"]).items())),
            "dependencies": [
                f"{dependency}@{package_versions[dependency]}" for dependency in sorted(dependencies[package_name])
            ],
            "externals": sorted(externals[package_name]),
        }
        write_or_check(
            manifest_path,
            json.dumps(normalized_manifest, indent=2) + "\n",
            args.check,
            differences,
        )

        catalog_path = manifest_path.parent / "catalog.json"
        catalog = read_catalog(catalog_path)
        record = PackageRecord(
            root=manifest_path.parent,
            name=package_name,
            version=version,
            exports={str(alias): str(target) for alias, target in normalized_manifest["exports"].items()},
            dependencies=tuple(str(item) for item in normalized_manifest["dependencies"]),
            externals=tuple(str(item) for item in normalized_manifest["externals"]),
            catalog=catalog,
        )
        records.append(record)

        for alias, target in normalized_manifest["exports"].items():
            implementation = resolve_module(manifest_path.parent, target)
            wrapper = render_wrapper(scoped_version, implementation, target)
            write_or_check(SRC / f"{alias}.luau", wrapper, args.check, differences)

    index_project = json.dumps({"name": "_Index", "tree": index_tree}, indent=2) + "\n"
    write_or_check(INDEX / "default.project.json", index_project, args.check, differences)

    rendered_catalog = render_catalog(records)
    write_or_check(CATALOG, rendered_catalog, args.check, differences)

    expected_wrappers = {f"{alias}.luau" for alias in alias_owners}
    unexpected_wrappers = [path for path in SRC.glob("*.luau") if path.name not in expected_wrappers]
    differences.extend(unexpected_wrappers)
    if not args.check:
        for wrapper in unexpected_wrappers:
            wrapper.unlink()

    if args.check:
        for record in records:
            if validate_catalog(record) and record.root / "catalog.json" not in differences:
                differences.append(record.root / "catalog.json")

    if differences:
        action = "would update" if args.check else "updated"
        print(f"Package surfaces {action} {len(differences)} files:")
        for path in differences[:25]:
            print(path.relative_to(ROOT))
        if len(differences) > 25:
            print(f"... and {len(differences) - 25} more")
        return 1 if args.check else 0

    print(f"Package surfaces are synchronized ({len(manifests)} packages, {len(alias_owners)} exports)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
