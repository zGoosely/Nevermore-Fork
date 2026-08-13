"""Textual interface for the local Nevermore package catalog."""

from __future__ import annotations

import json
from collections.abc import Callable
from typing import Any

from textual import on, work
from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import (
    Button,
    DataTable,
    Footer,
    Header,
    Input,
    Label,
    RichLog,
    Select,
    Static,
    TabbedContent,
    TabPane,
    TextArea,
)

from .manager import KINDS, PackageManager
from .models import ModuleEntry, OperationResult, PackageRecord


class FormScreen(ModalScreen[dict[str, Any] | None]):
    """Base modal with conventional save and cancel actions."""

    BINDINGS = [("escape", "cancel", "Cancel")]

    def action_cancel(self) -> None:
        self.dismiss(None)


class CreatePackageScreen(FormScreen):
    """Collect package scaffolding and initial catalog metadata."""

    def compose(self) -> ComposeResult:
        with Vertical(id="dialog"):
            yield Label("Create package", classes="dialog-title")
            yield Input(placeholder="package-name", id="name")
            yield Input(value="0.0.1", placeholder="Version", id="version")
            yield Select(((kind.title(), kind) for kind in sorted(KINDS)), value="utility", id="kind")
            yield Input(placeholder="Public export (derived when empty)", id="export")
            yield Input(placeholder="Purpose", id="purpose")
            yield Input(placeholder="Short description", id="description")
            yield Input(placeholder="Tags, comma separated", id="tags")
            with Horizontal(classes="dialog-actions"):
                yield Button("Create", variant="primary", id="save")
                yield Button("Cancel", id="cancel")

    @on(Button.Pressed, "#save")
    def save(self) -> None:
        self.dismiss(
            {
                "name": self.query_one("#name", Input).value,
                "version": self.query_one("#version", Input).value,
                "kind": self.query_one("#kind", Select).value,
                "export_name": self.query_one("#export", Input).value or None,
                "purpose": self.query_one("#purpose", Input).value,
                "description": self.query_one("#description", Input).value,
                "tags": self.query_one("#tags", Input).value.split(","),
            }
        )

    @on(Button.Pressed, "#cancel")
    def cancel(self) -> None:
        self.dismiss(None)


class EditPackageScreen(FormScreen):
    """Edit catalog metadata, exports, and module descriptions."""

    def __init__(self, record: PackageRecord) -> None:
        super().__init__()
        self.record = record

    def compose(self) -> ComposeResult:
        modules = {module.path: module.to_dict() for module in self.record.catalog.modules}
        with Vertical(id="dialog", classes="wide-dialog"):
            yield Label(f"Edit {self.record.name}", classes="dialog-title")
            yield Input(value=self.record.catalog.purpose, placeholder="Purpose", id="purpose")
            yield Input(value=self.record.catalog.description, placeholder="Short description", id="description")
            yield Input(value=", ".join(self.record.catalog.tags), placeholder="Tags", id="tags")
            yield Label("Exports (JSON)")
            yield TextArea(json.dumps(self.record.exports, indent=2), language="json", id="exports")
            yield Label("Modules (JSON keyed by relative path)")
            yield TextArea(json.dumps(modules, indent=2), language="json", id="modules")
            yield Static("", id="form-error")
            with Horizontal(classes="dialog-actions"):
                yield Button("Save", variant="primary", id="save")
                yield Button("Cancel", id="cancel")

    @on(Button.Pressed, "#save")
    def save(self) -> None:
        try:
            exports = json.loads(self.query_one("#exports", TextArea).text)
            modules_data = json.loads(self.query_one("#modules", TextArea).text)
            if not isinstance(exports, dict) or not isinstance(modules_data, dict):
                raise ValueError("Exports and modules must be JSON objects")
            modules = [
                ModuleEntry.from_dict(str(path), data)
                for path, data in modules_data.items()
                if isinstance(data, dict)
            ]
        except (json.JSONDecodeError, ValueError) as error:
            self.query_one("#form-error", Static).update(f"[red]{error}[/red]")
            return
        self.dismiss(
            {
                "name": self.record.short_name,
                "purpose": self.query_one("#purpose", Input).value,
                "description": self.query_one("#description", Input).value,
                "tags": self.query_one("#tags", Input).value.split(","),
                "exports": {str(alias): str(target) for alias, target in exports.items()},
                "modules": modules,
            }
        )

    @on(Button.Pressed, "#cancel")
    def cancel(self) -> None:
        self.dismiss(None)


class VersionScreen(FormScreen):
    """Collect a replacement semantic version."""

    def __init__(self, record: PackageRecord) -> None:
        super().__init__()
        self.record = record

    def compose(self) -> ComposeResult:
        with Vertical(id="dialog"):
            yield Label(f"Update {self.record.name}", classes="dialog-title")
            yield Input(value=self.record.version, placeholder="Version", id="version")
            with Horizontal(classes="dialog-actions"):
                yield Button("Update", variant="primary", id="save")
                yield Button("Cancel", id="cancel")

    @on(Button.Pressed, "#save")
    def save(self) -> None:
        self.dismiss({"name": self.record.short_name, "version": self.query_one("#version", Input).value})

    @on(Button.Pressed, "#cancel")
    def cancel(self) -> None:
        self.dismiss(None)


class RemoveScreen(FormScreen):
    """Show reverse dependencies and require explicit removal confirmation."""

    def __init__(self, record: PackageRecord, dependents: tuple[str, ...]) -> None:
        super().__init__()
        self.record = record
        self.dependents = dependents

    def compose(self) -> ComposeResult:
        with Vertical(id="dialog"):
            yield Label(f"Remove {self.record.name}?", classes="dialog-title")
            if self.dependents:
                yield Static("Blocked by:\n" + "\n".join(f"• {name}" for name in self.dependents))
            else:
                yield Static("This deletes the indexed package and its generated public exports.")
            with Horizontal(classes="dialog-actions"):
                yield Button("Remove", variant="error", id="save", disabled=bool(self.dependents))
                yield Button("Cancel", id="cancel")

    @on(Button.Pressed, "#save")
    def save(self) -> None:
        self.dismiss({"name": self.record.short_name})

    @on(Button.Pressed, "#cancel")
    def cancel(self) -> None:
        self.dismiss(None)


class PackageManagerApp(App[None]):
    """Interactive package browser and local mutation interface."""

    TITLE = "Nevermore Packages"
    CSS = """
    Screen { background: $surface; }
    #toolbar { height: 3; padding: 0 1; }
    #search { width: 1fr; }
    #workspace { height: 1fr; }
    #packages { width: 44%; min-width: 48; }
    #details { width: 1fr; }
    #actions { height: 3; padding: 0 1; }
    #actions Button { margin-right: 1; }
    #status { height: 1; padding: 0 1; color: $text-muted; }
    #logs { height: 1fr; }
    TabPane { padding: 1; }
    #dialog { width: 70; height: auto; max-height: 90%; padding: 1 2; border: round $primary; background: $panel; }
    .wide-dialog { width: 100; height: 90%; }
    .wide-dialog TextArea { height: 10; }
    .dialog-title { text-style: bold; margin-bottom: 1; }
    .dialog-actions { height: 3; margin-top: 1; align-horizontal: right; }
    .dialog-actions Button { margin-left: 1; }
    FormScreen { align: center middle; background: rgba(0, 0, 0, 0.55); }
    #form-error { color: $error; height: auto; }
    """
    BINDINGS = [
        ("ctrl+n", "create", "Create"),
        ("ctrl+e", "edit", "Edit"),
        ("ctrl+u", "version", "Version"),
        ("delete", "remove", "Remove"),
        ("ctrl+s", "sync", "Sync"),
        ("ctrl+r", "validate", "Validate"),
        ("q", "quit", "Quit"),
    ]

    def __init__(self, manager: PackageManager) -> None:
        super().__init__()
        self.manager = manager
        self.records: list[PackageRecord] = []
        self.selected_name: str | None = None
        self.busy = False

    def compose(self) -> ComposeResult:
        yield Header()
        with Horizontal(id="toolbar"):
            yield Input(placeholder="Search names, descriptions, tags, or exports", id="search")
            yield Button("Create", variant="primary", id="create")
            yield Button("Sync", id="sync")
            yield Button("Validate", id="validate")
        with Horizontal(id="workspace"):
            yield DataTable(id="packages", cursor_type="row", zebra_stripes=True)
            with Vertical(id="details"):
                with TabbedContent():
                    with TabPane("Overview", id="overview-tab"):
                        yield Static("Select a package", id="overview")
                    with TabPane("Exports", id="exports-tab"):
                        yield DataTable(id="exports-table", zebra_stripes=True)
                    with TabPane("Dependencies", id="dependencies-tab"):
                        yield Static("", id="dependencies")
                    with TabPane("Modules", id="modules-tab"):
                        yield DataTable(id="modules-table", zebra_stripes=True)
                    with TabPane("Logs", id="logs-tab"):
                        yield RichLog(id="logs", wrap=True, markup=True)
        with Horizontal(id="actions"):
            yield Button("Edit", id="edit")
            yield Button("Set version", id="version")
            yield Button("Remove", variant="error", id="remove")
        yield Static("Ready", id="status")
        yield Footer()

    def on_mount(self) -> None:
        packages = self.query_one("#packages", DataTable)
        packages.add_columns("Package", "Version", "Tags", "Exports")
        self.query_one("#exports-table", DataTable).add_columns("Alias", "Target")
        self.query_one("#modules-table", DataTable).add_columns("Module", "Realm", "Kind", "Description")
        self.refresh_packages()

    def refresh_packages(self, query: str = "") -> None:
        self.records = self.manager.list_packages()
        needle = query.casefold().strip()
        filtered = [record for record in self.records if not needle or self._search_text(record).find(needle) >= 0]
        table = self.query_one("#packages", DataTable)
        table.clear()
        for record in filtered:
            table.add_row(
                record.name,
                record.version,
                ", ".join(record.catalog.tags),
                str(len(record.exports)),
                key=record.name,
            )
        if filtered:
            selected = next((record for record in filtered if record.name == self.selected_name), filtered[0])
            self.show_record(selected)
        else:
            self.selected_name = None
            self.query_one("#overview", Static).update("No packages match the current search.")

    @on(Input.Changed, "#search")
    def search_changed(self, event: Input.Changed) -> None:
        self.refresh_packages(event.value)

    @on(DataTable.RowHighlighted, "#packages")
    def row_highlighted(self, event: DataTable.RowHighlighted) -> None:
        if event.row_key.value is None:
            return
        record = self._find_record(str(event.row_key.value))
        if record:
            self.show_record(record)

    def show_record(self, record: PackageRecord) -> None:
        self.selected_name = record.name
        self.query_one("#overview", Static).update(
            f"[b]{record.name}[/b]\n\nVersion: [cyan]{record.version}[/cyan]\n\n"
            f"Purpose: {record.catalog.purpose}\n\n{record.catalog.description}\n\n"
            f"Path: {record.root.relative_to(self.manager.root)}"
        )
        exports = self.query_one("#exports-table", DataTable)
        exports.clear()
        for alias, target in sorted(record.exports.items()):
            exports.add_row(alias, target)
        dependencies = [f"- `{dependency}`" for dependency in record.dependencies]
        externals = [f"- `{external}` (external)" for external in record.externals]
        self.query_one("#dependencies", Static).update(
            "[b]Dependencies[/b]\n\n" + "\n".join(dependencies + externals or ["No dependencies."])
        )
        modules = self.query_one("#modules-table", DataTable)
        modules.clear()
        for module in record.catalog.modules:
            modules.add_row(module.path, module.realm, module.kind, module.description)

    @on(Button.Pressed, "#create")
    def create_pressed(self) -> None:
        self.action_create()

    def action_create(self) -> None:
        if not self.busy:
            self.push_screen(CreatePackageScreen(), self._create_result)

    def _create_result(self, values: dict[str, Any] | None) -> None:
        if values:
            self._execute("Creating package", lambda: self.manager.create_package(**values))

    @on(Button.Pressed, "#edit")
    def edit_pressed(self) -> None:
        self.action_edit()

    def action_edit(self) -> None:
        record = self._selected_record()
        if record and not self.busy:
            self.push_screen(EditPackageScreen(record), self._edit_result)

    def _edit_result(self, values: dict[str, Any] | None) -> None:
        if values:
            self._execute("Updating package", lambda: self.manager.update_package(**values))

    @on(Button.Pressed, "#version")
    def version_pressed(self) -> None:
        self.action_version()

    def action_version(self) -> None:
        record = self._selected_record()
        if record and not self.busy:
            self.push_screen(VersionScreen(record), self._version_result)

    def _version_result(self, values: dict[str, Any] | None) -> None:
        if values:
            self._execute("Updating version", lambda: self.manager.set_version(**values))

    @on(Button.Pressed, "#remove")
    def remove_pressed(self) -> None:
        self.action_remove()

    def action_remove(self) -> None:
        record = self._selected_record()
        if record and not self.busy:
            self.push_screen(RemoveScreen(record, self.manager.reverse_dependencies(record.short_name)), self._remove_result)

    def _remove_result(self, values: dict[str, Any] | None) -> None:
        if values:
            self._execute(
                "Removing package", lambda: self.manager.remove_package(values["name"], confirmed=True)
            )

    @on(Button.Pressed, "#sync")
    def sync_pressed(self) -> None:
        self.action_sync()

    def action_sync(self) -> None:
        if not self.busy:
            self._execute("Synchronizing packages", self.manager.sync)

    @on(Button.Pressed, "#validate")
    def validate_pressed(self) -> None:
        self.action_validate()

    def action_validate(self) -> None:
        if not self.busy:
            self._execute("Validating packages", self.manager.validate)

    def _execute(self, label: str, operation: Callable[[], OperationResult]) -> None:
        self.busy = True
        self.query_one("#status", Static).update(f"{label}…")
        for button in self.query(Button):
            button.disabled = True
        self._run_operation(operation)

    @work(thread=True, exclusive=True, group="package-operations")
    def _run_operation(self, operation: Callable[[], OperationResult]) -> None:
        try:
            result = operation()
        except Exception as error:
            result = OperationResult(False, "Unexpected package-manager failure", diagnostics=(str(error),))
        self.call_from_thread(self._finish_operation, result)

    def _finish_operation(self, result: OperationResult) -> None:
        self.busy = False
        for button in self.query(Button):
            button.disabled = False
        color = "green" if result.ok else "red"
        self.query_one("#status", Static).update(f"[{color}]{result.summary}[/{color}]")
        log = self.query_one("#logs", RichLog)
        log.write(f"[{color}]{result.summary}[/{color}]")
        for diagnostic in result.diagnostics:
            log.write(f"[red]{diagnostic}[/red]")
        for output in result.logs:
            log.write(output)
        self.refresh_packages(self.query_one("#search", Input).value)

    def _selected_record(self) -> PackageRecord | None:
        return self._find_record(self.selected_name) if self.selected_name else None

    def _find_record(self, name: str) -> PackageRecord | None:
        return next((record for record in self.records if record.name == name), None)

    def _search_text(self, record: PackageRecord) -> str:
        return " ".join(
            (
                record.name,
                record.catalog.purpose,
                record.catalog.description,
                *record.catalog.tags,
                *record.exports,
            )
        ).casefold()


def run(manager: PackageManager | None = None) -> None:
    PackageManagerApp(manager or PackageManager()).run()
