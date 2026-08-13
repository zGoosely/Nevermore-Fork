"""Read, migrate, validate, and render package catalog metadata."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Iterable

from .models import CatalogEntry, ModuleEntry, PackageRecord


CARD_START = re.compile(r"^# (?P<name>[a-z0-9][a-z0-9-]*)$", re.MULTILINE)
FIELD = re.compile(r"^- \*\*(?P<field>Purpose|Short Description|Tags):\*\* (?P<value>.*)$", re.MULTILINE)
MODULE_ROW = re.compile(
    r"^\| \[`(?P<label>[^`]+)`\]\((?P<path>src/_Index/[^)]+)\)\s*"
    r"\|\s*(?P<realm>[^|]+?)\s*\|\s*(?P<kind>[^|]+?)\s*\|\s*(?P<description>.*?)\s*\|$",
    re.MULTILINE,
)
TAG = re.compile(r"`([^`]+)`")


def read_catalog(path: Path) -> CatalogEntry:
    if not path.exists():
        return CatalogEntry(purpose="", description="")
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"Catalog sidecar must contain an object: {path}")
    return CatalogEntry.from_dict(data)


def write_catalog(path: Path, entry: CatalogEntry) -> None:
    path.write_text(json.dumps(entry.to_dict(), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def parse_legacy_catalog(markdown: str) -> dict[str, CatalogEntry]:
    """Parse the regular package-card section of the legacy PKGINFO document."""

    starts = list(CARD_START.finditer(markdown))
    entries: dict[str, CatalogEntry] = {}
    for index, match in enumerate(starts):
        end = starts[index + 1].start() if index + 1 < len(starts) else len(markdown)
        body = markdown[match.end() : end]
        fields = {field.group("field"): field.group("value").strip() for field in FIELD.finditer(body)}
        if "Purpose" not in fields:
            continue

        modules: list[ModuleEntry] = []
        for row in MODULE_ROW.finditer(body):
            full_path = row.group("path")
            marker = f"quenty_{match.group('name')}@"
            package_fragment = full_path.split(marker, 1)
            if len(package_fragment) != 2 or "/" not in package_fragment[1]:
                continue
            relative_path = package_fragment[1].split("/", 1)[1]
            modules.append(
                ModuleEntry(
                    path=relative_path,
                    realm=row.group("realm").strip(),
                    kind=row.group("kind").strip(),
                    description=row.group("description").strip(),
                )
            )

        entries[match.group("name")] = CatalogEntry(
            purpose=fields["Purpose"],
            description=fields.get("Short Description", fields["Purpose"]),
            tags=tuple(sorted(TAG.findall(fields.get("Tags", "")))),
            modules=tuple(sorted(modules, key=lambda module: module.path)),
        )
    return entries


def module_count(record: PackageRecord) -> int:
    return sum(
        1
        for path in record.root.rglob("*")
        if path.is_file()
        and path.suffix in {".lua", ".luau"}
        and not path.name.endswith((".spec.lua", ".spec.luau"))
        and path.name not in {"jest.config.lua", "jest.config.luau"}
    )


def _escape_cell(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def render_catalog(records: Iterable[PackageRecord]) -> str:
    packages = sorted(records, key=lambda record: record.short_name)
    total_modules = sum(module_count(record) for record in packages)
    lines = [
        "# Nevermore Package Information",
        "",
        "This file is generated from each package's `catalog.json` and `package.json`. Edit catalog metadata with",
        "`nevermore-packages` or by changing the sidecar, then run `python3 scripts/sync_packages.py`.",
        "",
        f"**Coverage:** {len(packages)} packages · {total_modules} production modules",
        "",
        "## Package directory",
        "",
        "| Package | Version | Tags | Modules |",
        "| --- | --- | --- | ---: |",
    ]
    for record in packages:
        tags = ", ".join(f"`{tag}`" for tag in record.catalog.tags)
        lines.append(
            f"| [{record.short_name}](#{record.short_name}) | `{record.version}` | {tags} | {module_count(record)} |"
        )

    for record in packages:
        entry = record.catalog
        relative_root = record.root.relative_to(record.root.parents[2]).as_posix()
        lines.extend(
            [
                "",
                f"# {record.short_name}",
                "",
                f"- **Purpose:** {entry.purpose}",
                f"- **Path:** [`{relative_root}/`]({relative_root}/)",
                f"- **Short Description:** {entry.description}",
                f"- **Tags:** {', '.join(f'`{tag}`' for tag in entry.tags)}",
            ]
        )
        if entry.modules:
            lines.extend(
                [
                    "",
                    "### Submodules",
                    "",
                    "| Module | Realm | Kind | Responsibility and public surface |",
                    "| --- | --- | --- | --- |",
                ]
            )
            for module in entry.modules:
                path = f"{relative_root}/{module.path}"
                lines.append(
                    f"| [`{module.path}`]({path}) | {_escape_cell(module.realm)} | "
                    f"{_escape_cell(module.kind)} | {_escape_cell(module.description)} |"
                )
    return "\n".join(lines) + "\n"


def discover_production_modules(package_root: Path) -> set[str]:
    return {
        path.relative_to(package_root).as_posix()
        for path in package_root.rglob("*")
        if path.is_file()
        and path.suffix in {".lua", ".luau"}
        and not path.name.endswith((".spec.lua", ".spec.luau"))
        and path.name not in {"jest.config.lua", "jest.config.luau"}
    }


def validate_catalog(record: PackageRecord) -> list[str]:
    diagnostics: list[str] = []
    if not record.catalog.purpose.strip():
        diagnostics.append(f"{record.name}: purpose is empty")
    if not record.catalog.description.strip():
        diagnostics.append(f"{record.name}: description is empty")
    if len(record.catalog.tags) != len(set(record.catalog.tags)):
        diagnostics.append(f"{record.name}: tags must be unique")

    actual = discover_production_modules(record.root)
    described = {module.path for module in record.catalog.modules}
    for missing in sorted(actual - described):
        diagnostics.append(f"{record.name}: missing module metadata for {missing}")
    for stale in sorted(described - actual):
        diagnostics.append(f"{record.name}: stale module metadata for {stale}")
    return diagnostics
