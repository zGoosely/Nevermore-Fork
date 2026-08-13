from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

from nevermore_packages.catalog import parse_legacy_catalog, render_catalog, validate_catalog
from nevermore_packages.manager import PackageManager


@pytest.fixture()
def repository(tmp_path: Path) -> Path:
    root = tmp_path / "repo"
    (root / "src" / "_Index").mkdir(parents=True)
    (root / "scripts").mkdir()
    (root / "PKGINFO.md").write_text("# Nevermore Package Information\n", encoding="utf-8")
    shutil.copy(Path("scripts/normalize_package_requires.py"), root / "scripts")
    shutil.copy(Path("scripts/sync_packages.py"), root / "scripts")
    shutil.copytree(Path("nevermore_packages"), root / "nevermore_packages")
    return root


def test_create_version_and_remove_package(repository: Path) -> None:
    manager = PackageManager(repository)

    created = manager.create_package(
        "example-utils",
        kind="utility",
        export_name="ExampleUtils",
        purpose="Normalizes examples.",
        description="Stateless example helpers.",
        tags=("utility", "data"),
    )
    assert created.ok, created.diagnostics
    record = manager.get_package("example-utils")
    assert record.exports == {"ExampleUtils": "ExampleUtils"}
    assert not validate_catalog(record)

    versioned = manager.set_version("example-utils", "0.1.0")
    assert versioned.ok, versioned.diagnostics
    assert manager.get_package("example-utils").version == "0.1.0"

    removed = manager.remove_package("example-utils", confirmed=True)
    assert removed.ok, removed.diagnostics
    assert manager.list_packages() == []


def test_remove_reports_reverse_dependencies(repository: Path) -> None:
    manager = PackageManager(repository)
    assert manager.create_package("base", purpose="Base.", description="Base.").ok
    assert manager.create_package("consumer", purpose="Consumer.", description="Consumer.").ok
    consumer = manager.get_package("consumer")
    manifest_path = consumer.root / "package.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["dependencies"] = ["quenty/base@0.0.1"]
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    result = manager.remove_package("base", confirmed=True)
    assert not result.ok
    assert "quenty/consumer" in result.diagnostics[0]


def test_failed_sync_rolls_back_creation(repository: Path) -> None:
    manager = PackageManager(repository)
    (repository / "scripts" / "sync_packages.py").write_text("raise SystemExit(1)\n", encoding="utf-8")

    result = manager.create_package("rollback", purpose="Rollback.", description="Rollback.")
    assert not result.ok
    assert not list((repository / "src" / "_Index").glob("quenty_rollback@*"))


def test_catalog_rendering_is_deterministic(repository: Path) -> None:
    manager = PackageManager(repository)
    assert manager.create_package(
        "ordered", kind="types", purpose="Types.", description="Shared types.", tags=("z", "a")
    ).ok
    records = manager.list_packages()
    assert render_catalog(records) == render_catalog(reversed(records))


def test_legacy_catalog_parser() -> None:
    markdown = """# Nevermore Package Information

# example

- **Purpose:** Example purpose
- **Path:** [`src/_Index/quenty_example@0.0.1/`](src/_Index/quenty_example@0.0.1/)
- **Short Description:** Example description
- **Tags:** `utility`, `data`

### Submodules

| Module | Realm | Kind | Responsibility and public surface |
| --- | --- | --- | --- |
| [`Example.luau`](src/_Index/quenty_example@0.0.1/Example.luau) | shared | Utility | Example helper. |
"""
    entry = parse_legacy_catalog(markdown)["example"]
    assert entry.purpose == "Example purpose"
    assert entry.tags == ("data", "utility")
    assert entry.modules[0].path == "Example.luau"


def test_project_mounts_surfaces_at_replicated_storage_packages() -> None:
    project = json.loads(Path("default.project.json").read_text(encoding="utf-8"))
    tree = project["tree"]
    assert tree["$className"] == "DataModel"
    assert tree["ReplicatedStorage"]["Packages"]["$path"] == "src"
