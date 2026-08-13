#!/usr/bin/env python3
"""Normalize and validate package-local string requires against the Rojo module shape."""

from __future__ import annotations

import argparse
import posixpath
import re
import sys
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
INDEX = ROOT / "src" / "_Index"
LOCAL_REQUIRE = re.compile(
    r"(?P<prefix>(?:\brequire|\(require\s*::\s*any\))\s*\(\s*)"
    r"(?P<quote>[\"'])(?P<target>(?:@self/|\.\.?/)[^\"']+)(?P=quote)"
)


def runtime_path(package_root: Path, source_path: Path) -> PurePosixPath:
    relative = PurePosixPath(source_path.relative_to(package_root).as_posix())
    if relative.name in {"init.lua", "init.luau"}:
        return relative.parent
    return relative.with_suffix("")


def filesystem_target(package_root: Path, source_path: Path, target: str) -> PurePosixPath | None:
    if target.startswith("@self/"):
        relative = PurePosixPath(target.removeprefix("@self/"))
    else:
        relative = PurePosixPath(posixpath.normpath((PurePosixPath(source_path.relative_to(package_root).parent) / target).as_posix()))

    candidates = (
        package_root / f"{relative}.lua",
        package_root / f"{relative}.luau",
        package_root / relative / "init.lua",
        package_root / relative / "init.luau",
    )
    for candidate in candidates:
        if candidate.is_file():
            return runtime_path(package_root, candidate)
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


def normalize_source(
    package_root: Path,
    source_path: Path,
    source: str,
    runtime_modules: set[PurePosixPath],
) -> tuple[str, list[str]]:
    source_runtime = runtime_path(package_root, source_path)
    unresolved: list[str] = []

    def replace(match: re.Match[str]) -> str:
        target = match.group("target")
        target_runtime = resolve_runtime(source_runtime, target)
        if target_runtime not in runtime_modules:
            legacy_target = filesystem_target(package_root, source_path, target)
            if legacy_target is None:
                unresolved.append(target)
                return match.group(0)
            target_runtime = legacy_target

        canonical = render_require(source_path, source_runtime, target_runtime)
        quote = match.group("quote")
        return f'{match.group("prefix")}{quote}{canonical}{quote}'

    return LOCAL_REQUIRE.sub(replace, source), unresolved


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Report noncanonical or unresolved package-local requires")
    args = parser.parse_args()

    changed: list[Path] = []
    unresolved: list[tuple[Path, str]] = []
    for package_root in sorted(path for path in INDEX.glob("quenty_*@*") if path.is_dir()):
        source_paths = sorted(
            path for path in package_root.rglob("*") if path.is_file() and path.suffix in {".lua", ".luau"}
        )
        runtime_modules = {runtime_path(package_root, path) for path in source_paths}
        for source_path in source_paths:
            source = source_path.read_text(encoding="utf-8", errors="replace")
            normalized, source_unresolved = normalize_source(package_root, source_path, source, runtime_modules)
            unresolved.extend((source_path, target) for target in source_unresolved)
            if normalized == source:
                continue

            changed.append(source_path)
            if not args.check:
                source_path.write_text(normalized, encoding="utf-8")

    if unresolved:
        print(f"Unresolved package-local requires found: {len(unresolved)}", file=sys.stderr)
        for path, target in unresolved[:25]:
            print(f"{path.relative_to(ROOT)}: {target}", file=sys.stderr)
        if len(unresolved) > 25:
            print(f"... and {len(unresolved) - 25} more", file=sys.stderr)
        return 1

    if changed:
        action = "require normalization needed" if args.check else "normalized package requires"
        print(f"{action} in {len(changed)} files:")
        for path in changed[:25]:
            print(path.relative_to(ROOT))
        if len(changed) > 25:
            print(f"... and {len(changed) - 25} more")
        return 1 if args.check else 0

    print("Package-local requires match the Rojo module hierarchy")
    return 0


if __name__ == "__main__":
    sys.exit(main())
