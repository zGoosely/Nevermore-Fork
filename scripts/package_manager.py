#!/usr/bin/env python3
"""Create, remove, and version packages in the checked-in package index."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INDEX = ROOT / "src" / "_Index"
SYNC_SCRIPT = ROOT / "scripts" / "sync_packages.py"
CATALOG = ROOT / "PKGINFO.md"
PACKAGE_NAME = re.compile(r"^[a-z0-9][a-z0-9-]*$")
SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")


def validate_package_name(name: str) -> str:
    if not PACKAGE_NAME.fullmatch(name):
        raise ValueError("Package names must be lowercase and contain only letters, numbers, and hyphens")
    return name


def validate_version(version: str) -> str:
    if not SEMVER.fullmatch(version):
        raise ValueError("Versions must use numeric semantic versioning, for example 0.1.0")
    return version


def find_package(name: str) -> tuple[Path, dict[str, object]]:
    matches = sorted(INDEX.glob(f"quenty_{name}@*/package.json"))
    if not matches:
        raise ValueError(f"Unknown package: quenty/{name}")
    if len(matches) > 1:
        raise ValueError(f"Multiple installed versions found for quenty/{name}; select one manually")
    manifest_path = matches[0]
    return manifest_path.parent, json.loads(manifest_path.read_text(encoding="utf-8"))


def sync() -> None:
    subprocess.run([sys.executable, str(SYNC_SCRIPT)], cwd=ROOT, check=True)


def create_package(name: str, version: str) -> None:
    validate_package_name(name)
    validate_version(version)
    existing = sorted(INDEX.glob(f"quenty_{name}@*"))
    if existing:
        raise ValueError(f"Package already exists: {existing[0].name}")

    package_root = INDEX / f"quenty_{name}@{version}"
    package_root.mkdir(parents=True)
    manifest = {
        "name": f"quenty/{name}",
        "version": version,
        "exports": {},
        "dependencies": [],
        "externals": [],
    }
    (package_root / "package.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    sync()
    print(f"Created {manifest['name']}@{version} at {package_root.relative_to(ROOT)}")


def remove_package(name: str, confirmed: bool) -> None:
    validate_package_name(name)
    if not confirmed:
        raise ValueError("Removal is destructive; pass --yes after reviewing the target")

    sync()
    package_root, manifest = find_package(name)
    logical_name = str(manifest["name"])

    catalog = CATALOG.read_text(encoding="utf-8")
    if re.search(rf"^# {re.escape(name)}$", catalog, re.MULTILINE):
        raise ValueError(f"Remove the {name} package card and directory row from PKGINFO.md first")

    dependents = []
    for other_manifest_path in INDEX.glob("quenty_*@*/package.json"):
        if other_manifest_path.parent == package_root:
            continue
        other = json.loads(other_manifest_path.read_text(encoding="utf-8"))
        dependency_names = {str(item).rsplit("@", 1)[0] for item in other.get("dependencies", [])}
        if logical_name in dependency_names:
            dependents.append(str(other["name"]))

    if dependents:
        joined = ", ".join(sorted(dependents))
        raise ValueError(f"Cannot remove {logical_name}; still required by: {joined}")

    shutil.rmtree(package_root)
    sync()
    print(f"Removed {logical_name}")


def set_version(name: str, version: str) -> None:
    validate_package_name(name)
    validate_version(version)
    sync()
    package_root, manifest = find_package(name)
    old_version = str(manifest["version"])
    if old_version == version:
        raise ValueError(f"quenty/{name} is already at {version}")

    destination = INDEX / f"quenty_{name}@{version}"
    if destination.exists():
        raise ValueError(f"Version destination already exists: {destination.name}")

    catalog = CATALOG.read_text(encoding="utf-8")
    old_catalog_path = f"src/_Index/quenty_{name}@{old_version}/"
    new_catalog_path = f"src/_Index/quenty_{name}@{version}/"
    if old_catalog_path not in catalog:
        raise ValueError(f"PKGINFO.md does not contain the current package path: {old_catalog_path}")

    package_root.rename(destination)
    manifest["version"] = version
    (destination / "package.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    CATALOG.write_text(catalog.replace(old_catalog_path, new_catalog_path), encoding="utf-8")

    sync()
    print(f"Updated quenty/{name} from {old_version} to {version}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    create_parser = subparsers.add_parser("create", help="Create an empty indexed package")
    create_parser.add_argument("name")
    create_parser.add_argument("--version", default="0.0.1")

    remove_parser = subparsers.add_parser("remove", help="Remove an unused indexed package")
    remove_parser.add_argument("name")
    remove_parser.add_argument("--yes", action="store_true")

    version_parser = subparsers.add_parser("set-version", help="Set a package's semantic version")
    version_parser.add_argument("name")
    version_parser.add_argument("version")

    args = parser.parse_args()
    try:
        if args.command == "create":
            create_package(args.name, args.version)
        elif args.command == "remove":
            remove_package(args.name, args.yes)
        elif args.command == "set-version":
            set_version(args.name, args.version)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
