#!/usr/bin/env python3
"""Generate a loader-free, flat package folder from a Nevermore checkout."""

from __future__ import annotations

import argparse
import re
import shutil
import sys
import tomllib
from collections import defaultdict, deque
from pathlib import Path


LOADER_LINE = re.compile(
    r"^\s*(?:const|local)\s+require\s*=\s*require\([^\n]*[Ll]oader[^\n]*\)\.load(?:\([^\n]*\))?\s*\r?\n",
    re.MULTILINE,
)
STRING_REQUIRE = re.compile(r'require\(("[^"\n]+"|\'[^\'\n]+\')\)')
SCRIPT_REQUIRE = re.compile(r"require\(script[^\n\)]*(?:\([^\n\)]*\))?\)")


def code_only(source: str) -> str:
    """Remove documentation blocks before inspecting dependency imports."""
    source = re.sub(r"--\[(=*)\[.*?\]\1\]", "", source, flags=re.DOTALL)
    return "\n".join(line.split("--", 1)[0] for line in source.splitlines())


def module_name(path: Path) -> str:
    return path.parent.name if path.stem == "init" else path.stem


def package_name(path: Path, source: Path) -> str:
    relative = path.relative_to(source)
    return relative.parts[0]


def read_config(path: Path) -> tuple[Path, Path, list[str], set[str]]:
    data = tomllib.loads(path.read_text())
    settings = data.get("nevermore", {})
    source = Path(settings.get("source", "lib"))
    output = Path(settings.get("output", "roblox_packages"))

    requested: list[str] = []
    packages = data.get("packages", settings.get("packages", []))
    if isinstance(packages, list):
        requested.extend(str(value) for value in packages)
    elif isinstance(packages, dict):
        requested.extend(str(name) for name, enabled in packages.items() if enabled is not False)

    package_table = data.get("package", {})
    if isinstance(package_table, dict):
        requested.extend(str(name) for name in package_table)

    external = {str(name) for name in data.get("external", settings.get("external", []))}
    return source, output, requested, external


def resolve_key(name: str, current: Path, module_keys: dict[str, list[Path]], keys: dict[Path, str]) -> Path | None:
    if name.startswith("."):
        name = Path(name).name
    candidates = module_keys.get(name, [])
    if not candidates:
        return None
    current_package = current.parts[0]
    local = [candidate for candidate in candidates if candidate.parts[0] == current_package]
    return local[0] if len(local) == 1 else candidates[0] if len(candidates) == 1 else None


def rewrite(source: str, current: Path, module_keys: dict[str, list[Path]], keys: dict[Path, str]) -> str:
    source = LOADER_LINE.sub("", source)

    def script_replace(match: re.Match[str]) -> str:
        expression = match.group(0)
        wait_for_child = re.search(r"WaitForChild\((\"[^\"]+\"|'[^']+')\)", expression)
        if wait_for_child:
            name = wait_for_child.group(1)[1:-1]
        else:
            identifiers = re.findall(r"\.([A-Za-z_][A-Za-z0-9_]*)", expression)
            if not identifiers:
                return expression
            name = identifiers[-1]
        target = resolve_key(name, current, module_keys, keys)
        return f"require(Packages.{keys[target]})" if target else expression

    source = SCRIPT_REQUIRE.sub(script_replace, source)

    def string_replace(match: re.Match[str]) -> str:
        name = match.group(1)[1:-1]
        if name.lower().endswith("loader") or name == "Loader":
            return match.group(0)
        target = resolve_key(name, current, module_keys, keys)
        key = keys[target] if target else name
        return f"require(Packages.{key})"

    source = STRING_REQUIRE.sub(string_replace, source)
    if "require(Packages." in source and "Packages =" not in source:
        lines = source.splitlines(keepends=True)
        index = 1 if lines and lines[0].startswith("--!") else 0
        if index < len(lines) and lines[index].lstrip().startswith("--[="):
            while index < len(lines):
                if "]=]" in lines[index]:
                    index += 1
                    break
                index += 1
        lines.insert(index, 'const Packages = game:GetService("ReplicatedStorage").Packages\n\n')
        source = "".join(lines)
    return source


def generate(config_path: Path) -> None:
    source, output, requested, external = read_config(config_path)
    if not requested:
        raise SystemExit("No packages selected in .nevermore.toml")
    if not source.exists():
        raise SystemExit(f"Source directory does not exist: {source}")

    files = sorted(
        path
        for path in source.rglob("*")
        if path.is_file() and path.suffix in {".luau", ".lua"} and not path.name.endswith(".spec.luau") and path.name != "Loader.luau"
    )
    module_keys: dict[str, list[Path]] = defaultdict(list)
    for path in files:
        relative = path.relative_to(source)
        module_keys[module_name(path)].append(relative)

    roots = {path.name.lower(): path.name for path in source.iterdir() if path.is_dir()}
    selected: set[str] = set()
    for name in requested:
        root = roots.get(name.lower())
        if root:
            selected.add(root)
            continue
        candidates = module_keys.get(name, [])
        if len(candidates) == 1:
            selected.add(candidates[0].parts[0])
            continue
        raise SystemExit(f"Unknown or ambiguous package: {name}")

    package_files = {root: [path for path in files if package_name(path, source) == root] for root in roots.values()}
    queue = deque(selected)
    missing: dict[str, set[str]] = defaultdict(set)
    while queue:
        root = queue.popleft()
        for path in package_files[root]:
            relative = path.relative_to(source)
            text = code_only(path.read_text())
            dependencies = [match.group(0) for match in SCRIPT_REQUIRE.finditer(text)]
            for match in STRING_REQUIRE.finditer(text):
                name = match.group(1)[1:-1]
                if name.startswith(".") or name.lower().endswith("loader") or name == "Loader":
                    continue
                target = resolve_key(name, relative, module_keys, {})
                if target is None:
                    if name not in external:
                        missing[root].add(name)
                elif target.parts[0] not in selected:
                    selected.add(target.parts[0])
                    queue.append(target.parts[0])
            for expression in dependencies:
                identifiers = re.findall(r"\.([A-Za-z_][A-Za-z0-9_]*)", expression)
                wait_for_child = re.search(r"WaitForChild\((\"[^\"]+\"|'[^']+')\)", expression)
                name = wait_for_child.group(1)[1:-1] if wait_for_child else identifiers[-1] if identifiers else ""
                target = resolve_key(name, relative, module_keys, {})
                if target is not None and target.parts[0] not in selected:
                    selected.add(target.parts[0])
                    queue.append(target.parts[0])

    if missing:
        details = "; ".join(f"{root}: {', '.join(sorted(names))}" for root, names in missing.items())
        raise SystemExit(f"Missing dependencies (add them to lib or [external]): {details}")

    selected_files = [path for root in sorted(selected) for path in package_files[root]]
    keys: dict[Path, str] = {}
    used: set[str] = set()
    for path in selected_files:
        path = path.relative_to(source)
        base = module_name(path)
        key = base if base not in used else f"{path.parts[0]}_{base}"
        while key in used:
            key = f"{path.parts[0]}_{key}"
        used.add(key)
        keys[path] = key

    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    for path in selected_files:
        relative = path.relative_to(source)
        destination = output / f"{keys[relative]}{path.suffix}"
        destination.write_text(rewrite(path.read_text(), relative, module_keys, keys))
    print(f"Generated {len(selected_files)} modules from {len(selected)} packages in {output}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", nargs="?", default=".nevermore.toml")
    args = parser.parse_args()
    try:
        generate(Path(args.config))
    except (OSError, tomllib.TOMLDecodeError) as error:
        print(f"nevermore-package-gen: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
