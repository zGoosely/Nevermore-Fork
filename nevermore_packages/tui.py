"""Textual interface for the local Nevermore package catalog."""

from __future__ import annotations

import json
from collections.abc import Callable
from typing import Any

from rich.markup import escape
from rich.text import Text
from textual import on, work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.screen import ModalScreen
from textual.suggester import Suggester
from textual.theme import Theme
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

from .manager import PackageManager
from .models import ModuleEntry, OperationResult, PackageModule, PackageRecord, SnippetTemplate


GRUVBOX_THEME = Theme(
    name="gruvbox",
    primary="#d79921",
    secondary="#689d6a",
    warning="#fe8019",
    error="#fb4934",
    success="#b8bb26",
    accent="#83a598",
    foreground="#ebdbb2",
    background="#282828",
    surface="#1d2021",
    panel="#3c3836",
    boost="#504945",
    dark=True,
    variables={
        "muted": "#928374",
        "soft": "#a89984",
        "purple": "#d3869b",
    },
)


class DependencySuggester(Suggester):
    """Complete the final alias in a comma-separated dependency input."""

    def __init__(self, aliases: tuple[str, ...]) -> None:
        super().__init__(case_sensitive=True)
        self.aliases = aliases

    async def get_suggestion(self, value: str) -> str | None:
        prefix, separator, fragment = value.rpartition(",")
        leading_space = fragment[: len(fragment) - len(fragment.lstrip())]
        query = fragment.strip().casefold()
        selected = {item.strip().casefold() for item in prefix.split(",") if item.strip()}
        for alias in self.aliases:
            if alias.casefold() in selected:
                continue
            if alias.casefold().startswith(query):
                completed_prefix = f"{prefix}{separator}" if separator else ""
                return f"{completed_prefix}{leading_space}{alias}"
        return None


class DependencyInput(Input):
    """Accept dependency completions with Tab while preserving normal focus traversal."""

    BINDINGS = [*Input.BINDINGS, Binding("tab", "accept_suggestion", show=False)]

    def action_accept_suggestion(self) -> None:
        if self.cursor_at_end and self._suggestion:
            self.action_cursor_right()
        else:
            self.screen.focus_next()


class FormScreen(ModalScreen[dict[str, Any] | None]):
    """Base modal with conventional save and cancel actions."""

    BINDINGS = [("escape", "cancel", "Cancel")]

    def action_cancel(self) -> None:
        self.dismiss(None)


class CreatePackageScreen(FormScreen):
    """Collect package scaffolding and initial catalog metadata."""

    def __init__(self, templates: tuple[SnippetTemplate, ...], dependency_aliases: tuple[str, ...]) -> None:
        super().__init__()
        self.templates = {template.name: template for template in templates}
        self.dependency_aliases = dependency_aliases

    def compose(self) -> ComposeResult:
        with Vertical(id="dialog"):
            yield Label("New package", classes="dialog-title")
            with Horizontal(classes="form-row"):
                with Vertical(classes="field"):
                    yield Label("Package", classes="field-label")
                    yield Input(placeholder="package-name", id="name")
                with Vertical(classes="field version-field"):
                    yield Label("Version", classes="field-label")
                    yield Input(value="0.0.1", placeholder="0.0.1", id="version")
            options = [("Empty package", "")]
            options.extend(
                (
                    self._template_label(template.name),
                    template.name,
                )
                for template in self.templates.values()
            )
            default_template = (
                "Define a new Library" if "Define a new Library" in self.templates else next(iter(self.templates), "")
            )
            with Horizontal(classes="form-row"):
                with Vertical(classes="field"):
                    yield Label("Template", classes="field-label")
                    yield Select(options, value=default_template, prompt="Template", id="template")
                with Vertical(classes="field"):
                    yield Label("Public name", classes="field-label")
                    yield Input(placeholder="Derived from package", id="export")
            with Vertical(id="service-options"):
                with Horizontal(classes="form-row"):
                    with Vertical(classes="field realm-field"):
                        yield Label("Realm", classes="field-label")
                        yield Select(
                            (("Server", "server"), ("Client", "client"), ("Server & Client", "both")),
                            value="server",
                            id="service-realm",
                        )
                    with Vertical(classes="field preview-field"):
                        yield Label("Files", classes="field-label")
                        yield Static("", id="service-name-preview")
            with Horizontal(classes="form-row"):
                with Vertical(classes="field"):
                    yield Label("Purpose", classes="field-label")
                    yield Input(placeholder="What does it provide?", id="purpose")
                with Vertical(classes="field"):
                    yield Label("Tags", classes="field-label")
                    yield Input(placeholder="utility, data", id="tags")
            with Vertical(classes="field full-field"):
                yield Label("Description", classes="field-label")
                yield Input(placeholder="A short package summary", id="description")
            with Vertical(classes="field full-field dependency-field"):
                yield Label("Dependencies · Tab to complete", classes="field-label")
                yield DependencyInput(
                    placeholder="Maid, Promise, ServiceBag",
                    suggester=DependencySuggester(self.dependency_aliases),
                    id="dependencies",
                )
            with Horizontal(classes="dialog-actions"):
                yield Button("Create", variant="primary", id="save")
                yield Button("Cancel", id="cancel")

    def on_mount(self) -> None:
        self._update_template_options()

    @on(Select.Changed, "#template")
    def template_changed(self) -> None:
        self._update_template_options()

    @on(Select.Changed, "#service-realm")
    def service_realm_changed(self) -> None:
        self._update_service_preview()

    @on(Input.Changed, "#name")
    @on(Input.Changed, "#export")
    def package_name_changed(self) -> None:
        self._update_service_preview()

    @on(Button.Pressed, "#save")
    def save(self) -> None:
        selected_template = self.query_one("#template", Select).value
        template_name = selected_template if isinstance(selected_template, str) and selected_template else None
        template = self.templates.get(template_name) if template_name else None
        dependency_lookup = {alias.casefold(): alias for alias in self.dependency_aliases}
        dependencies = tuple(
            dict.fromkeys(
                dependency_lookup.get(item.strip().casefold(), item.strip())
                for item in self.query_one("#dependencies", Input).value.split(",")
                if item.strip()
            )
        )
        self.dismiss(
            {
                "name": self.query_one("#name", Input).value,
                "version": self.query_one("#version", Input).value,
                "kind": template.kind if template else "empty",
                "export_name": self.query_one("#export", Input).value or None,
                "purpose": self.query_one("#purpose", Input).value,
                "description": self.query_one("#description", Input).value,
                "tags": self.query_one("#tags", Input).value.split(","),
                "template_name": template_name,
                "service_realm": self.query_one("#service-realm", Select).value
                if template and template.kind == "service"
                else None,
                "dependencies": dependencies,
            }
        )

    def _update_template_options(self) -> None:
        selected = self.query_one("#template", Select).value
        template = self.templates.get(selected) if isinstance(selected, str) else None
        self.query_one("#service-options", Vertical).styles.display = (
            "block" if template and template.kind == "service" else "none"
        )
        self._update_service_preview()

    def _update_service_preview(self) -> None:
        preview = self.query_one("#service-name-preview", Static)
        selected = self.query_one("#template", Select).value
        template = self.templates.get(selected) if isinstance(selected, str) else None
        if not template or template.kind != "service":
            preview.update("")
            return

        explicit_name = self.query_one("#export", Input).value.strip()
        package_name = self.query_one("#name", Input).value.strip()
        base_name = explicit_name or "".join(
            part[:1].upper() + part[1:]
            for part in package_name.replace("_", "-").split("-")
            if part
        )
        if base_name.casefold().endswith("serviceclient"):
            base_name = f"{base_name[:-13]}Service"
        elif base_name.casefold().endswith("service"):
            base_name = f"{base_name[:-7]}Service"
        elif base_name:
            base_name += "Service"
        base_name = base_name or "PackageService"
        realm = self.query_one("#service-realm", Select).value
        names = [base_name] if realm == "server" else [f"{base_name}Client"]
        if realm == "both":
            names = [base_name, f"{base_name}Client"]
        preview.update("Creates " + " + ".join(f"{name}.luau" for name in names))

    @staticmethod
    def _template_label(name: str) -> str:
        label = name.removeprefix("Define a new ")
        label = label.removesuffix(" template")
        if " " not in label:
            return label[:1].upper() + label[1:]
        return "".join(part[:1].upper() + part[1:] for part in label.split())

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
    Screen {
        background: #282828;
        color: #ebdbb2;
    }

    Header {
        background: #1d2021;
        color: #fabd2f;
    }

    Footer {
        background: #1d2021;
        color: #a89984;
    }

    #toolbar {
        height: 4;
        padding: 0 1 1 1;
        background: #1d2021;
        border-bottom: solid #504945;
    }

    #search {
        width: 1fr;
    }

    Input, Select, TextArea {
        background: #32302f;
        color: #ebdbb2;
        border: tall #504945;
    }

    Input:focus, Select:focus, TextArea:focus {
        border: tall #d79921;
    }

    #create {
        min-width: 15;
        margin-left: 1;
    }

    #workspace {
        height: 1fr;
        padding: 1;
    }

    #browser {
        width: 38%;
        min-width: 36;
        margin-right: 1;
        background: #1d2021;
        border: round #504945;
    }

    #browser-heading {
        height: 2;
        padding: 0 1;
        color: #928374;
        content-align: left middle;
    }

    #packages {
        height: 1fr;
        background: #1d2021;
    }

    DataTable > .datatable--header {
        background: #3c3836;
        color: #fabd2f;
        text-style: bold;
    }

    DataTable > .datatable--cursor {
        background: #504945;
        color: #fbf1c7;
    }

    #details {
        width: 1fr;
        background: #1d2021;
        border: round #504945;
    }

    #selection-header {
        height: 3;
        padding: 0 1;
        border-bottom: solid #3c3836;
    }

    #selection-title {
        width: 1fr;
        color: #fabd2f;
        text-style: bold;
        content-align: left middle;
    }

    #detail-actions {
        width: auto;
        height: 3;
    }

    #detail-actions Button {
        min-width: 9;
        margin-left: 1;
    }

    Button {
        background: #3c3836;
        color: #ebdbb2;
        border: none;
    }

    Button:hover, Button:focus {
        background: #504945;
        color: #fbf1c7;
        text-style: bold;
    }

    Button.-primary {
        background: #d79921;
        color: #1d2021;
    }

    Button.-error {
        background: #9d0006;
        color: #fbf1c7;
    }

    Tabs {
        background: #1d2021;
        color: #928374;
    }

    Tab.-active {
        color: #fabd2f;
        text-style: bold;
    }

    Underline > .underline--bar {
        color: #d79921;
    }

    TabPane {
        padding: 1 2;
        background: #1d2021;
    }

    #overview-scroll, #logs, #modules-table {
        height: 1fr;
    }

    #module-actions {
        height: 3;
        margin-bottom: 1;
    }

    #module-summary {
        width: 1fr;
        color: #928374;
        content-align: left middle;
    }

    #module-actions Button {
        min-width: 11;
        margin-left: 1;
    }

    #overview {
        height: auto;
        color: #ebdbb2;
    }

    #dialog {
        width: 82;
        height: auto;
        max-height: 90%;
        padding: 1 2;
        background: #282828;
        border: round #d79921;
    }

    .wide-dialog {
        width: 100;
        height: 90%;
    }

    .wide-dialog TextArea {
        height: 10;
    }

    .dialog-title {
        height: 2;
        color: #fabd2f;
        text-style: bold;
    }

    .form-row {
        height: 4;
    }

    .field {
        width: 1fr;
        height: 4;
        margin-right: 1;
    }

    .field:last-child {
        margin-right: 0;
    }

    .version-field, .realm-field {
        width: 22;
    }

    .preview-field {
        width: 1fr;
    }

    .full-field {
        width: 100%;
        margin-right: 0;
    }

    .dependency-field {
        height: 4;
    }

    #service-options {
        height: auto;
        padding-left: 1;
        border-left: solid #d79921;
    }

    #service-options .form-row, #service-options .field {
        height: 5;
    }

    #service-name-preview {
        height: 3;
        padding: 1;
        color: #928374;
    }

    .field-label {
        height: 1;
        color: #d5c4a1;
    }

    .dialog-actions {
        height: 3;
        align-horizontal: right;
    }

    .dialog-actions Button {
        margin-left: 1;
    }

    FormScreen {
        align: center middle;
        background: rgba(29, 32, 33, 0.82);
    }

    #form-error {
        height: auto;
        color: #fb4934;
    }
    """
    BINDINGS = [
        Binding("ctrl+n", "create", "Create", show=False),
        Binding("ctrl+e", "edit", "Edit", show=False),
        Binding("ctrl+u", "version", "Version", show=False),
        Binding("delete", "remove", "Remove", show=False),
        ("ctrl+s", "sync", "Sync"),
        ("ctrl+r", "validate", "Check"),
        ("q", "quit", "Quit"),
    ]

    def __init__(self, manager: PackageManager) -> None:
        super().__init__()
        self.register_theme(GRUVBOX_THEME)
        self.theme = GRUVBOX_THEME.name
        self.manager = manager
        self.records: list[PackageRecord] = []
        self.modules: tuple[PackageModule, ...] = ()
        self.selected_name: str | None = None
        self.selected_module_target: str | None = None
        self.busy = False

    def compose(self) -> ComposeResult:
        yield Header()
        with Horizontal(id="toolbar"):
            yield Input(placeholder="Search packages", id="search")
            yield Button("New package", variant="primary", id="create")
        with Horizontal(id="workspace"):
            with Vertical(id="browser"):
                yield Static("Loading packages…", id="browser-heading")
                yield DataTable(id="packages", cursor_type="row", zebra_stripes=True)
            with Vertical(id="details"):
                with Horizontal(id="selection-header"):
                    yield Static("Select a package", id="selection-title")
                    with Horizontal(id="detail-actions"):
                        yield Button("Edit", id="edit")
                        yield Button("Version", id="version")
                        yield Button("Delete", variant="error", id="remove")
                with TabbedContent():
                    with TabPane("Overview", id="overview-tab"):
                        with VerticalScroll(id="overview-scroll"):
                            yield Static("Select a package", id="overview")
                    with TabPane("Modules", id="modules-tab"):
                        with Horizontal(id="module-actions"):
                            yield Static("No modules", id="module-summary")
                            yield Button("Expose", id="toggle-module")
                            yield Button("Expose all", id="expose-all")
                            yield Button("Hide all", id="hide-all")
                        yield DataTable(id="modules-table", cursor_type="row", zebra_stripes=True)
                    with TabPane("Activity", id="activity-tab"):
                        yield RichLog(id="logs", wrap=True, markup=True)
        yield Footer()

    def on_mount(self) -> None:
        packages = self.query_one("#packages", DataTable)
        packages.add_columns("Package", "Version")
        self.query_one("#modules-table", DataTable).add_columns("Module", "Public alias", "Exposed")
        self.refresh_packages()

    def refresh_packages(self, query: str = "") -> None:
        self.records = self.manager.list_packages()
        needle = query.casefold().strip()
        filtered = [record for record in self.records if not needle or self._search_text(record).find(needle) >= 0]
        table = self.query_one("#packages", DataTable)
        table.clear()
        for record in filtered:
            table.add_row(
                record.short_name,
                record.version,
                key=record.name,
            )
        package_word = "package" if len(filtered) == 1 else "packages"
        self.query_one("#browser-heading", Static).update(f"{len(filtered)} {package_word}")
        if filtered:
            selected = next((record for record in filtered if record.name == self.selected_name), filtered[0])
            selected_index = filtered.index(selected)
            table.move_cursor(row=selected_index, column=0, animate=False)
            self.show_record(selected)
        else:
            self.selected_name = None
            self.selected_module_target = None
            self.modules = ()
            self.query_one("#selection-title", Static).update("No matching packages")
            self.query_one("#overview", Static).update("No packages match the current search.")
            self.query_one("#module-summary", Static).update("No modules")
            self.query_one("#modules-table", DataTable).clear()
            self._update_module_toggle_label()

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
        if self.selected_name != record.name:
            self.selected_module_target = None
        self.selected_name = record.name
        self.modules = self.manager.list_package_modules(record.short_name)
        self.query_one("#selection-title", Static).update(record.name)

        tags = "  ".join(f"[black on #d79921] {escape(tag)} [/black on #d79921]" for tag in record.catalog.tags)
        exports = "\n".join(
            f"[#83a598]{escape(alias)}[/#83a598]  [#928374]→[/#928374]  {escape(target)}"
            for alias, target in sorted(record.exports.items())
        ) or "[#928374]None[/#928374]"
        dependencies = "\n".join(
            f"[#b8bb26]•[/#b8bb26] {escape(dependency)}" for dependency in record.dependencies
        )
        externals = "\n".join(
            f"[#928374]• {escape(external)}  (external)[/#928374]" for external in record.externals
        )
        dependency_text = "\n".join(filter(None, (dependencies, externals))) or "[#928374]None[/#928374]"
        relative_path = escape(str(record.root.relative_to(self.manager.root)))

        self.query_one("#overview", Static).update(
            f"[#fabd2f bold]PURPOSE[/#fabd2f bold]\n{escape(record.catalog.purpose)}\n\n"
            f"[#a89984]{escape(record.catalog.description)}[/#a89984]\n\n"
            f"[#fabd2f bold]PACKAGE[/#fabd2f bold]\n"
            f"Version   [#83a598]{escape(record.version)}[/#83a598]\n"
            f"Exports   [#83a598]{len(record.exports)}[/#83a598]\n"
            f"Modules   [#83a598]{len(self.modules)}[/#83a598]\n"
            f"{tags or '[#928374]No tags[/#928374]'}\n\n"
            f"[#fabd2f bold]EXPORTS[/#fabd2f bold]\n{exports}\n\n"
            f"[#fabd2f bold]DEPENDENCIES[/#fabd2f bold]\n{dependency_text}\n\n"
            f"[#928374]{relative_path}[/#928374]"
        )
        exposed_count = sum(module.is_exposed for module in self.modules)
        module_word = "module" if len(self.modules) == 1 else "modules"
        self.query_one("#module-summary", Static).update(
            f"{len(self.modules)} {module_word} · {exposed_count} exposed"
        )
        module_table = self.query_one("#modules-table", DataTable)
        module_table.clear()
        for module in self.modules:
            status = Text("Yes", style="bold #b8bb26") if module.is_exposed else Text("No", style="#928374")
            module_table.add_row(
                module.path,
                ", ".join(module.aliases) or "—",
                status,
                key=module.target,
            )
        if not any(module.target == self.selected_module_target for module in self.modules):
            self.selected_module_target = self.modules[0].target if self.modules else None
        if self.selected_module_target is not None:
            selected_index = next(
                index for index, module in enumerate(self.modules) if module.target == self.selected_module_target
            )
            module_table.move_cursor(row=selected_index, column=0, animate=False)
        self._update_module_toggle_label()

    @on(DataTable.RowHighlighted, "#modules-table")
    def module_row_highlighted(self, event: DataTable.RowHighlighted) -> None:
        if event.row_key.value is None:
            return
        self.selected_module_target = str(event.row_key.value)
        self._update_module_toggle_label()

    @on(Button.Pressed, "#toggle-module")
    def toggle_module_pressed(self) -> None:
        self.action_toggle_module()

    def action_toggle_module(self) -> None:
        record = self._selected_record()
        module = self._selected_module()
        if record and module and not self.busy:
            verb = "Hiding" if module.is_exposed else "Exposing"
            self._execute(
                f"{verb} module",
                lambda: self.manager.set_module_exposed(record.short_name, module.target, not module.is_exposed),
            )

    @on(Button.Pressed, "#expose-all")
    def expose_all_pressed(self) -> None:
        self._set_all_modules_exposed(True)

    @on(Button.Pressed, "#hide-all")
    def hide_all_pressed(self) -> None:
        self._set_all_modules_exposed(False)

    def _set_all_modules_exposed(self, exposed: bool) -> None:
        record = self._selected_record()
        if record and not self.busy:
            verb = "Exposing" if exposed else "Hiding"
            self._execute(
                f"{verb} all modules",
                lambda: self.manager.set_all_modules_exposed(record.short_name, exposed),
            )

    def _update_module_toggle_label(self) -> None:
        module = self._selected_module()
        button = self.query_one("#toggle-module", Button)
        button.label = "Hide" if module and module.is_exposed else "Expose"
        button.disabled = module is None or self.busy
        self.query_one("#expose-all", Button).disabled = not self.modules or self.busy
        self.query_one("#hide-all", Button).disabled = not self.modules or self.busy

    @on(Button.Pressed, "#create")
    def create_pressed(self) -> None:
        self.action_create()

    def action_create(self) -> None:
        if not self.busy:
            try:
                templates = self.manager.list_snippet_templates()
            except ValueError as error:
                self._show_error(str(error))
                return
            self.push_screen(
                CreatePackageScreen(templates, self.manager.list_dependency_aliases()),
                self._create_result,
            )

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

    def action_sync(self) -> None:
        if not self.busy:
            self._execute("Synchronizing packages", self.manager.sync)

    def action_validate(self) -> None:
        if not self.busy:
            self._execute("Validating packages", self.manager.validate)

    def _execute(self, label: str, operation: Callable[[], OperationResult]) -> None:
        self.busy = True
        self.query_one("#browser-heading", Static).update(f"[#fabd2f]{label}…[/#fabd2f]")
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
        color = "#b8bb26" if result.ok else "#fb4934"
        log = self.query_one("#logs", RichLog)
        log.write(f"[{color}]{result.summary}[/{color}]")
        for diagnostic in result.diagnostics:
            log.write(f"[red]{diagnostic}[/red]")
        for output in result.logs:
            log.write(output)
        self.refresh_packages(self.query_one("#search", Input).value)
        self.query_one("#browser-heading", Static).update(f"[{color}]{escape(result.summary)}[/{color}]")

    def _show_error(self, message: str) -> None:
        self.query_one("#logs", RichLog).write(f"[#fb4934]{escape(message)}[/#fb4934]")
        self.query_one("#browser-heading", Static).update("[#fb4934]Unable to load templates[/#fb4934]")

    def _selected_record(self) -> PackageRecord | None:
        return self._find_record(self.selected_name) if self.selected_name else None

    def _selected_module(self) -> PackageModule | None:
        return next(
            (module for module in self.modules if module.target == self.selected_module_target),
            None,
        )

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
