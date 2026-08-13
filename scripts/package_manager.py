#!/usr/bin/env python3
"""Create, update, remove, version, and validate indexed packages."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from nevermore_packages.manager import KINDS, PackageManager


def _print_result(result) -> int:
    stream = sys.stdout if result.ok else sys.stderr
    print(result.summary, file=stream)
    for diagnostic in result.diagnostics:
        print(f"error: {diagnostic}", file=stream)
    for log in result.logs:
        if log:
            print(log, file=stream)
    if result.changed_paths:
        print("Changed:", file=stream)
        for path in result.changed_paths:
            print(f"  {path.relative_to(ROOT)}", file=stream)
    return 0 if result.ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    create = subparsers.add_parser("create", help="Create and scaffold an indexed package")
    create.add_argument("name")
    create.add_argument("--version", default="0.0.1")
    create.add_argument("--kind", choices=sorted(KINDS), default="empty")
    create.add_argument("--export-name")
    create.add_argument("--purpose", default="")
    create.add_argument("--description", default="")
    create.add_argument("--tag", action="append", default=[])

    remove = subparsers.add_parser("remove", help="Remove an unused indexed package")
    remove.add_argument("name")
    remove.add_argument("--yes", action="store_true")

    version = subparsers.add_parser("set-version", help="Set a package's semantic version")
    version.add_argument("name")
    version.add_argument("version")

    edit = subparsers.add_parser("edit", help="Update catalog metadata and exports")
    edit.add_argument("name")
    edit.add_argument("--purpose", required=True)
    edit.add_argument("--description", required=True)
    edit.add_argument("--tags", default="")
    edit.add_argument("--exports", required=True, help="JSON object mapping aliases to targets")

    subparsers.add_parser("migrate-catalog", help="Create sidecars from the existing PKGINFO cards")
    sync = subparsers.add_parser("sync", help="Regenerate manifests, wrappers, and PKGINFO")
    sync.add_argument("--check", action="store_true")
    normalize = subparsers.add_parser("normalize", help="Normalize package-local requires")
    normalize.add_argument("--check", action="store_true")
    subparsers.add_parser("validate", help="Run all package and Luau validation")
    subparsers.add_parser("tui", help="Open the interactive package manager")

    args = parser.parse_args()
    manager = PackageManager(ROOT)
    if args.command == "create":
        result = manager.create_package(
            args.name,
            args.version,
            args.kind,
            args.export_name,
            args.purpose,
            args.description,
            args.tag,
        )
    elif args.command == "remove":
        result = manager.remove_package(args.name, confirmed=args.yes)
    elif args.command == "set-version":
        result = manager.set_version(args.name, args.version)
    elif args.command == "edit":
        try:
            exports = json.loads(args.exports)
            if not isinstance(exports, dict):
                raise ValueError("--exports must contain a JSON object")
        except (json.JSONDecodeError, ValueError) as error:
            print(f"error: {error}", file=sys.stderr)
            return 1
        result = manager.update_package(
            args.name,
            purpose=args.purpose,
            description=args.description,
            tags=args.tags.split(","),
            exports={str(alias): str(target) for alias, target in exports.items()},
            modules=None,
        )
    elif args.command == "migrate-catalog":
        result = manager.migrate_catalog()
    elif args.command == "sync":
        result = manager.sync(check=args.check)
    elif args.command == "normalize":
        result = manager.normalize(check=args.check)
    elif args.command == "validate":
        result = manager.validate()
    else:
        from nevermore_packages.tui import run

        run(manager)
        return 0
    return _print_result(result)


if __name__ == "__main__":
    sys.exit(main())
