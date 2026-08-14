from __future__ import annotations

from pathlib import Path

import pytest

textual = pytest.importorskip("textual")

from nevermore_packages.manager import PackageManager
from nevermore_packages.tui import CreatePackageScreen, PackageManagerApp
from textual.widgets import DataTable, Input, Select


@pytest.mark.asyncio
async def test_tui_search_filters_packages(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    root = tmp_path / "repo"
    package = root / "src" / "_Index" / "quenty_example@0.0.1"
    package.mkdir(parents=True)
    (package / "package.json").write_text(
        '{"name":"quenty/example","version":"0.0.1","exports":{"Maid":"Maid"},'
        '"dependencies":[],"externals":[]}\n',
        encoding="utf-8",
    )
    (package / "catalog.json").write_text(
        '{"purpose":"Example","description":"Reactive helper","tags":["reactive"],'
        '"modules":{"Internal.luau":{"realm":"shared","kind":"Utility","description":"Internal module"},'
        '"Maid.luau":{"realm":"shared","kind":"Utility","description":"Test module"}}}\n',
        encoding="utf-8",
    )
    (package / "Maid.luau").write_text("--!strict\n\nreturn {}\n", encoding="utf-8")
    (package / "Internal.luau").write_text("--!strict\n\nreturn {}\n", encoding="utf-8")
    second_package = root / "src" / "_Index" / "quenty_second@0.0.1"
    second_package.mkdir(parents=True)
    (second_package / "package.json").write_text(
        '{"name":"quenty/second","version":"0.0.1","exports":{"Second":"Second"},'
        '"dependencies":[],"externals":[]}\n',
        encoding="utf-8",
    )
    (second_package / "catalog.json").write_text(
        '{"purpose":"Second","description":"Another helper","tags":[],'
        '"modules":{"Second.luau":{"realm":"shared","kind":"Utility","description":"Second module"}}}\n',
        encoding="utf-8",
    )
    (second_package / "Second.luau").write_text("--!strict\n\nreturn {}\n", encoding="utf-8")
    (root / "PKGINFO.md").write_text("", encoding="utf-8")
    snippet_path = root / "luau.code-snippets"
    snippet_path.write_text(
        """{
            "Define a new Library": {
                "body": ["--!strict", "const ${1} = {}", "return ${1}"],
                "description": "Define a library",
                "prefix": "lib"
            },
            "Define a new service": {
                "body": ["--!strict", "const ${1:Service} = {}", "return ${1}"],
                "description": "Define a service",
                "prefix": "service"
            }
        }
        """,
        encoding="utf-8",
    )

    manager = PackageManager(root, snippet_path=snippet_path)
    exposure_calls: list[tuple[object, ...]] = []
    monkeypatch.setattr(
        manager,
        "set_module_exposed",
        lambda *arguments: exposure_calls.append(arguments),
    )
    app = PackageManagerApp(manager)
    async with app.run_test(size=(120, 42)) as pilot:
        app.show_record(manager.get_package("second"))
        app.refresh_packages()
        await pilot.pause()
        assert app.selected_name == "quenty/second"
        module_table = app.query_one("#modules-table", DataTable)
        assert module_table.row_count == 1
        assert "1 module · 1 exposed" in str(app.query_one("#module-summary").render())
        await pilot.click("#modules-table", offset=(3, 1))
        await pilot.pause()
        assert exposure_calls == []
        await pilot.click("#search")
        await pilot.press(*"missing")
        assert app.query_one("#packages").row_count == 0
        app.query_one("#search", Input).value = "reactive"
        await pilot.pause()
        assert app.query_one("#packages").row_count == 1
        assert module_table.row_count == 2
        module_table.move_cursor(row=1, column=0)
        await pilot.pause()
        assert app.selected_module_target == "Maid"
        app.show_record(manager.get_package("example"))
        await pilot.pause()
        assert app.selected_module_target == "Maid"
        assert module_table.cursor_row == 1

        app.action_create()
        await pilot.pause()
        assert isinstance(app.screen, CreatePackageScreen)
        assert app.screen.query_one("#template", Select).value == "Define a new Library"
        await pilot.click("#dependencies")
        await pilot.press("m", "a")
        await pilot.pause()
        await pilot.press("tab")
        assert app.screen.query_one("#dependencies", Input).value == "Maid"
        app.screen.query_one("#template", Select).value = "Define a new service"
        await pilot.pause()
        assert app.screen.query_one("#service-options").styles.display == "block"
        await pilot.press("escape")
