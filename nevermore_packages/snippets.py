"""Read and render package-ready Luau templates from VS Code snippets."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from .models import SnippetTemplate


PLACEHOLDER = re.compile(r"\$\{(?P<braced_index>\d+)(?::(?P<default>[^}]*))?\}|\$(?P<plain_index>\d+)")
PACKAGE_REQUIRE = re.compile(
    r'^const (?P<binding>[A-Za-z_][A-Za-z0-9_]*) = require\((?:Packages\.(?P<property_alias>[A-Za-z_][A-Za-z0-9_]*)'
    r'|"@game/(?:ReplicatedStorage/Packages|ServerStorage/ServerPackages)/'
    r'(?P<path_alias>[A-Za-z_][A-Za-z0-9_]*)")\)$'
)
PACKAGE_ROOT = re.compile(
    r"^const (?:Packages|ServerPackages) = "
    r"(?:ReplicatedStorage\.Packages|ServerStorage\.ServerPackages)$"
)


def load_snippet_templates(path: Path) -> tuple[SnippetTemplate, ...]:
    """Load complete Luau module templates from a VS Code snippet file."""

    data = _read_snippet_file(path)
    templates = []
    for name, value in data.items():
        if not isinstance(value, dict):
            continue
        body = _body_text(value.get("body"))
        if not _is_complete_module(body):
            continue
        templates.append(
            SnippetTemplate(
                name=name,
                description=str(value.get("description", "")),
                kind=_infer_kind(name),
            )
        )
    return tuple(sorted(templates, key=lambda template: template.name.casefold()))


def render_snippet_template(path: Path, template_name: str, public_name: str) -> str:
    """Render one named snippet, resolving its VS Code tab stops to usable defaults."""

    value = _read_snippet_file(path).get(template_name)
    if not isinstance(value, dict):
        raise ValueError(f"Unknown VS Code snippet template: {template_name}")
    body = _body_text(value.get("body"))
    if not _is_complete_module(body):
        raise ValueError(f"Snippet is not a complete Luau module: {template_name}")

    values = {"1": public_name}

    def replace(match: re.Match[str]) -> str:
        index = match.group("braced_index") or match.group("plain_index")
        assert index is not None
        if index not in values:
            values[index] = match.group("default") or ""
        return values[index]

    rendered = PLACEHOLDER.sub(replace, body)
    rendered = "\n".join("" if not line.strip() else line.rstrip() for line in rendered.splitlines())
    return rendered.rstrip() + "\n"


def inject_package_requires(
    source: str,
    aliases: tuple[str, ...],
    alias_realms: dict[str, str] | None = None,
    source_realm: str = "shared",
) -> str:
    """Add sorted public package requires to a rendered module without duplicates."""

    requested = set(aliases)
    realms = alias_realms or {}

    lines = source.rstrip().splitlines()
    existing = {}
    retained = []
    for line in lines:
        match = PACKAGE_REQUIRE.fullmatch(line)
        if match:
            alias = match.group("property_alias") or match.group("path_alias")
            existing[alias] = match.group("binding")
        elif PACKAGE_ROOT.fullmatch(line):
            continue
        else:
            retained.append(line)

    for service_name in ("ReplicatedStorage", "ServerStorage"):
        declaration = f'const {service_name} = game:GetService("{service_name}")'
        if sum(line.count(service_name) for line in retained) == 1:
            retained = [line for line in retained if line != declaration]

    all_aliases = sorted(existing.keys() | requested, key=str.casefold)
    require_lines = []
    for alias in all_aliases:
        target_realm = realms.get(alias, "shared")
        allowed = (
            target_realm == "shared"
            or source_realm == "server" and target_realm == "server"
            or source_realm == "client" and target_realm == "client"
        )
        if not allowed:
            raise ValueError(f"{source_realm} module cannot require {target_realm} export {alias}")
        runtime_root = (
            "@game/ServerStorage/ServerPackages"
            if target_realm == "server"
            else "@game/ReplicatedStorage/Packages"
        )
        require_lines.append(f'const {existing.get(alias, alias)} = require("{runtime_root}/{alias}")')

    if require_lines:
        header_index = next((index + 1 for index, line in enumerate(retained) if line == "]=]"), 1)
        while header_index < len(retained) and not retained[header_index].strip():
            header_index += 1
        retained[header_index:header_index] = [*require_lines, ""]

    normalized_lines = []
    for line in retained:
        normalized = "" if not line.strip() else line.rstrip()
        if not normalized and normalized_lines and not normalized_lines[-1]:
            continue
        normalized_lines.append(normalized)
    rendered = "\n".join(normalized_lines)
    return rendered.rstrip() + "\n"


def _read_snippet_file(path: Path) -> dict[str, Any]:
    try:
        source = path.read_text(encoding="utf-8")
        data = json.loads(_normalize_jsonc(source))
    except FileNotFoundError as error:
        raise ValueError(f"VS Code snippet file was not found: {path}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"VS Code snippet file is invalid JSON: {path}: {error}") from error
    if not isinstance(data, dict):
        raise ValueError(f"VS Code snippet file must contain an object: {path}")
    return data


def _normalize_jsonc(source: str) -> str:
    """Remove JSONC comments and trailing commas without changing string contents."""

    output = []
    index = 0
    in_string = False
    escaped = False
    while index < len(source):
        character = source[index]
        if in_string:
            output.append(character)
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            index += 1
            continue
        if character == '"':
            in_string = True
            output.append(character)
            index += 1
            continue
        if source.startswith("//", index):
            end = source.find("\n", index + 2)
            index = len(source) if end < 0 else end
            continue
        if source.startswith("/*", index):
            end = source.find("*/", index + 2)
            if end < 0:
                raise ValueError("Unterminated block comment in VS Code snippet file")
            output.extend("\n" for character in source[index : end + 2] if character == "\n")
            index = end + 2
            continue
        if character == ",":
            next_index = index + 1
            while next_index < len(source) and source[next_index].isspace():
                next_index += 1
            if next_index < len(source) and source[next_index] in "}]":
                index += 1
                continue
        output.append(character)
        index += 1
    return "".join(output)


def _body_text(body: object) -> str:
    if isinstance(body, str):
        return body
    if isinstance(body, list) and all(isinstance(line, str) for line in body):
        return "\n".join(body)
    return ""


def _is_complete_module(body: str) -> bool:
    lines = [line.strip() for line in body.splitlines() if line.strip()]
    return bool(lines and lines[0] == "--!strict" and any(line.startswith("return ") for line in lines))


def _infer_kind(name: str) -> str:
    normalized = name.casefold()
    if any(
        term in normalized
        for term in ("class", "binder", "pane", "provider", "input key map", "translator")
    ):
        return "class"
    if "service" in normalized:
        return "service"
    if any(term in normalized for term in ("enum", "interface", "data module")):
        return "types"
    return "utility"
