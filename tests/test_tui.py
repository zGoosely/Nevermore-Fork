from __future__ import annotations

from pathlib import Path

import pytest

textual = pytest.importorskip("textual")

from nevermore_packages.manager import PackageManager
from nevermore_packages.tui import CreatePackageScreen, PackageManagerApp
from textual.widgets import Input, Select


@pytest.mark.asyncio
async def test_tui_search_filters_packages(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    package = root / "src" / "_Index" / "quenty_example@0.0.1"
    package.mkdir(parents=True)
    (package / "package.json").write_text(
        '{"name":"quenty/example","version":"0.0.1","exports":{"Maid":"Maid"},'
        '"dependencies":[],"externals":[]}\n',
        encoding="utf-8",
    )
    (package / "catalog.json").write_text(
        '{"purpose":"Example","description":"Reactive helper","tags":["reactive"],"modules":{}}\n',
        encoding="utf-8",
    )
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

    app = PackageManagerApp(PackageManager(root, snippet_path=snippet_path))
    async with app.run_test(size=(120, 42)) as pilot:
        await pilot.click("#search")
        await pilot.press(*"missing")
        assert app.query_one("#packages").row_count == 0
        app.query_one("#search", Input).value = "reactive"
        await pilot.pause()
        assert app.query_one("#packages").row_count == 1

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
