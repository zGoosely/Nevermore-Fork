from __future__ import annotations

from pathlib import Path

import pytest

textual = pytest.importorskip("textual")

from nevermore_packages.manager import PackageManager
from nevermore_packages.tui import PackageManagerApp


@pytest.mark.asyncio
async def test_tui_search_filters_packages(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    package = root / "src" / "_Index" / "quenty_example@0.0.1"
    package.mkdir(parents=True)
    (package / "package.json").write_text(
        '{"name":"quenty/example","version":"0.0.1","exports":{},"dependencies":[],"externals":[]}\n',
        encoding="utf-8",
    )
    (package / "catalog.json").write_text(
        '{"purpose":"Example","description":"Reactive helper","tags":["reactive"],"modules":{}}\n',
        encoding="utf-8",
    )
    (root / "PKGINFO.md").write_text("", encoding="utf-8")

    app = PackageManagerApp(PackageManager(root))
    async with app.run_test() as pilot:
        await pilot.click("#search")
        await pilot.press(*"missing")
        assert app.query_one("#packages").row_count == 0
        await pilot.press("ctrl+a", "backspace", *"reactive")
        assert app.query_one("#packages").row_count == 1
