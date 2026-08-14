#!/usr/bin/env python3
"""Normalize package-local and cross-package requires for the split package roots."""

from __future__ import annotations

import argparse
import json
import posixpath
import re
import sys
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
SHARED_INDEX = ROOT / "src" / "shared" / "_Index"
SERVER_INDEX = ROOT / "src" / "server" / "_Index"
LOCAL_REQUIRE = re.compile(
    r"(?P<prefix>(?:\brequire|\(require\s*::\s*any\))\s*\(\s*)"
    r"(?P<quote>[\"'])(?P<target>(?:@self/|\.\.?/)[^\"']+)(?P=quote)"
)
PACKAGE_REQUIRE = re.compile(
    r"(?P<prefix>(?:\brequire|\(require\s*::\s*any\))\s*\(\s*)(?:"
    r"(?P<quote>[\"'])@game/(?:ReplicatedStorage/Packages|ServerStorage/ServerPackages)/"
    r"(?P<path_alias>[A-Za-z_][A-Za-z0-9_]*)(?P=quote)"
    r"|(?P<root>Packages|ServerPackages)\.(?P<property_alias>[A-Za-z_][A-Za-z0-9_]*))"
)
ROOT_BINDING = re.compile(
    r"^const (?:Packages|ServerPackages) = "
    r"(?:ReplicatedStorage\.Packages|ServerStorage\.ServerPackages)\n?",
    re.MULTILINE,
)
VALID_REALMS = {"shared", "client", "server"}


def runtime_path(package_root: Path, source_path: Path) -> PurePosixPath:
    relative = PurePosixPath(source_path.relative_to(package_root).as_posix())
    if relative.name in {"init.lua", "init.luau"}:
        return relative.parent
    return relative.with_suffix("")


def source_paths(package_roots: tuple[Path, ...]) -> tuple[Path, ...]:
    return tuple(
        sorted(
            path
            for package_root in package_roots
            for path in package_root.rglob("*")
            if path.is_file() and path.suffix in {".lua", ".luau"}
        )
    )


def owning_root(package_roots: tuple[Path, ...], source_path: Path) -> Path:
    return next(root for root in package_roots if source_path.is_relative_to(root))


def filesystem_target(
    package_roots: tuple[Path, ...],
    package_root: Path,
    source_path: Path,
    target: str,
) -> PurePosixPath | None:
    if target.startswith("@self/"):
        relative = PurePosixPath(target.removeprefix("@self/"))
    else:
        relative = PurePosixPath(
            posixpath.normpath(
                (PurePosixPath(source_path.relative_to(package_root).parent.as_posix()) / target).as_posix()
            )
        )

    for root in package_roots:
        candidates = (
            root / f"{relative}.lua",
            root / f"{relative}.luau",
            root / relative / "init.lua",
            root / relative / "init.luau",
        )
        for candidate in candidates:
            if candidate.is_file():
                return runtime_path(root, candidate)
    return None


def resolve_runtime(source_runtime: PurePosixPath, target: str) -> PurePosixPath:
    if target.startswith("@self/"):
        base = source_runtime
        suffix = target.removeprefix("@self/")
    else:
        base = source_runtime.parent
        suffix = target
    return PurePosixPath(posixpath.normpath((base / suffix).as_posix()))


def render_require(source_path: Path, source_runtime: PurePosixPath, target_runtime: PurePosixPath) -> str:
    if source_path.name in {"init.lua", "init.luau"}:
        try:
            child = target_runtime.relative_to(source_runtime)
        except ValueError:
            pass
        else:
            if child.parts:
                return f"@self/{child.as_posix()}"

    relative = posixpath.relpath(target_runtime.as_posix(), source_runtime.parent.as_posix())
    return relative if relative.startswith("../") else f"./{relative}"


def normalize_local_requires(
    package_roots: tuple[Path, ...],
    source_path: Path,
    source: str,
    runtime_modules: set[PurePosixPath],
) -> tuple[str, list[str]]:
    package_root = owning_root(package_roots, source_path)
    source_runtime = runtime_path(package_root, source_path)
    unresolved: list[str] = []

    def replace(match: re.Match[str]) -> str:
        target = match.group("target")
        target_runtime = resolve_runtime(source_runtime, target)
        if target_runtime not in runtime_modules:
            legacy_target = filesystem_target(package_roots, package_root, source_path, target)
            if legacy_target is None:
                unresolved.append(target)
                return match.group(0)
            target_runtime = legacy_target

        canonical = render_require(source_path, source_runtime, target_runtime)
        return f'{match.group("prefix")}{match.group("quote")}{canonical}{match.group("quote")}'

    return LOCAL_REQUIRE.sub(replace, source), unresolved


def read_packages() -> tuple[dict[str, tuple[Path, ...]], dict[str, str], dict[tuple[str, str], str]]:
    package_roots: dict[str, list[Path]] = {}
    alias_realms: dict[str, str] = {}
    module_realms: dict[tuple[str, str], str] = {}

    for partition, index in (("shared", SHARED_INDEX), ("server", SERVER_INDEX)):
        for manifest_path in sorted(index.glob("quenty_*@*/package.json")):
            root = manifest_path.parent
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            name = str(manifest["name"])
            package_roots.setdefault(name, []).append(root)
            catalog = json.loads((root / "catalog.json").read_text(encoding="utf-8"))
            targets = {}
            for relative_path, metadata in dict(catalog.get("modules", {})).items():
                realm = str(metadata.get("realm", "shared"))
                if realm not in VALID_REALMS:
                    raise ValueError(f"Invalid realm {realm!r} in {root / 'catalog.json'}")
                target = module_target(str(relative_path))
                targets[target] = realm
                module_realms[(name, str(relative_path))] = realm
            for alias, target_value in dict(manifest.get("exports", {})).items():
                target = str(target_value)
                realm = targets.get(target)
                if realm is None:
                    raise ValueError(f"Export {alias} has no catalog module in {name}")
                expected_partition = "server" if realm == "server" else "shared"
                if partition != expected_partition:
                    raise ValueError(f"Export {alias} is in the wrong package partition")
                if str(alias) in alias_realms:
                    raise ValueError(f"Duplicate public alias: {alias}")
                alias_realms[str(alias)] = realm

    return (
        {name: tuple(sorted(roots, key=lambda path: "server" not in path.parts)) for name, roots in package_roots.items()},
        alias_realms,
        module_realms,
    )


def module_target(relative_path: str) -> str:
    path = PurePosixPath(relative_path)
    if path.name in {"init.lua", "init.luau"}:
        return "." if path.parent.as_posix() == "." else path.parent.as_posix()
    return path.with_suffix("").as_posix()


def infer_source_realm(
    name: str,
    package_root: Path,
    source_path: Path,
    module_realms: dict[tuple[str, str], str],
) -> str:
    relative = source_path.relative_to(package_root).as_posix()
    realm = module_realms.get((name, relative))
    if realm is not None:
        return realm
    parts = {part.casefold() for part in PurePosixPath(relative).parts[:-1]}
    if "server" in package_root.parts or "server" in parts:
        return "server"
    if "client" in parts:
        return "client"
    return "shared"


def normalize_package_requires(
    source: str,
    source_realm: str,
    alias_realms: dict[str, str],
) -> tuple[str, list[str]]:
    invalid: list[str] = []

    def replace(match: re.Match[str]) -> str:
        alias = match.group("path_alias") or match.group("property_alias")
        target_realm = alias_realms.get(alias)
        if target_realm is None:
            target_realm = "server" if match.group("root") == "ServerPackages" else "shared"
        allowed = (
            target_realm == "shared"
            or source_realm == "server" and target_realm == "server"
            or source_realm == "client" and target_realm == "client"
        )
        if not allowed:
            invalid.append(f"{source_realm} module cannot require {target_realm} export {alias}")
        runtime_root = (
            "@game/ServerStorage/ServerPackages"
            if target_realm == "server"
            else "@game/ReplicatedStorage/Packages"
        )
        return f'{match.group("prefix")}"{runtime_root}/{alias}"'

    normalized = PACKAGE_REQUIRE.sub(replace, source)
    normalized = ROOT_BINDING.sub("", normalized)
    return normalized, invalid


def normalize_document_requires(source: str, alias_realms: dict[str, str]) -> str:
    def replace(match: re.Match[str]) -> str:
        alias = match.group("path_alias") or match.group("property_alias")
        target_realm = alias_realms.get(alias, "shared")
        runtime_root = (
            "@game/ServerStorage/ServerPackages"
            if target_realm == "server"
            else "@game/ReplicatedStorage/Packages"
        )
        return f'{match.group("prefix")}"{runtime_root}/{alias}"'

    return PACKAGE_REQUIRE.sub(replace, source)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Report noncanonical or unresolved requires")
    args = parser.parse_args()

    package_roots, alias_realms, module_realms = read_packages()
    changed: list[Path] = []
    diagnostics: list[tuple[Path, str]] = []
    for name, roots in sorted(package_roots.items()):
        paths = source_paths(roots)
        runtime_modules = {runtime_path(owning_root(roots, path), path) for path in paths}
        for source_path in paths:
            source = source_path.read_text(encoding="utf-8", errors="replace")
            normalized, local_unresolved = normalize_local_requires(roots, source_path, source, runtime_modules)
            source_realm = infer_source_realm(name, owning_root(roots, source_path), source_path, module_realms)
            normalized, package_diagnostics = normalize_package_requires(normalized, source_realm, alias_realms)
            diagnostics.extend((source_path, target) for target in (*local_unresolved, *package_diagnostics))
            if normalized == source:
                continue
            changed.append(source_path)
            if not args.check:
                source_path.write_text(normalized, encoding="utf-8")

    for readme_path in sorted((ROOT / "src").rglob("README.md")):
        source = readme_path.read_text(encoding="utf-8", errors="replace")
        normalized = normalize_document_requires(source, alias_realms)
        if normalized == source:
            continue
        changed.append(readme_path)
        if not args.check:
            readme_path.write_text(normalized, encoding="utf-8")

    if diagnostics:
        print(f"Invalid or unresolved package requires found: {len(diagnostics)}", file=sys.stderr)
        for path, diagnostic in diagnostics[:25]:
            print(f"{path.relative_to(ROOT)}: {diagnostic}", file=sys.stderr)
        if len(diagnostics) > 25:
            print(f"... and {len(diagnostics) - 25} more", file=sys.stderr)
        return 1

    if changed:
        action = "require normalization needed" if args.check else "normalized package requires"
        print(f"{action} in {len(changed)} files:")
        for path in changed[:25]:
            print(path.relative_to(ROOT))
        if len(changed) > 25:
            print(f"... and {len(changed) - 25} more")
        return 1 if args.check else 0

    print("Package requires match the split runtime hierarchy")
    return 0


if __name__ == "__main__":
    sys.exit(main())
