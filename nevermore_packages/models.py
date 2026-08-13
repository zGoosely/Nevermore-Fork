"""Shared data models for package-management commands and user interfaces."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass(frozen=True, slots=True)
class ModuleEntry:
    """Human-readable metadata for one production module."""

    path: str
    realm: str
    kind: str
    description: str

    @classmethod
    def from_dict(cls, path: str, data: dict[str, Any]) -> ModuleEntry:
        return cls(
            path=path,
            realm=str(data.get("realm", "shared")),
            kind=str(data.get("kind", "Module")),
            description=str(data.get("description", "")),
        )

    def to_dict(self) -> dict[str, str]:
        return {
            "realm": self.realm,
            "kind": self.kind,
            "description": self.description,
        }


@dataclass(frozen=True, slots=True)
class CatalogEntry:
    """Canonical descriptive metadata stored beside a package manifest."""

    purpose: str
    description: str
    tags: tuple[str, ...] = ()
    modules: tuple[ModuleEntry, ...] = ()

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> CatalogEntry:
        raw_modules = data.get("modules", {})
        if not isinstance(raw_modules, dict):
            raise ValueError("catalog modules must be an object keyed by relative module path")
        modules = tuple(
            ModuleEntry.from_dict(str(path), module_data)
            for path, module_data in sorted(raw_modules.items())
            if isinstance(module_data, dict)
        )
        raw_tags = data.get("tags", [])
        if not isinstance(raw_tags, list):
            raise ValueError("catalog tags must be an array")
        return cls(
            purpose=str(data.get("purpose", "")),
            description=str(data.get("description", "")),
            tags=tuple(sorted({str(tag) for tag in raw_tags if str(tag)})),
            modules=modules,
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "purpose": self.purpose,
            "description": self.description,
            "tags": list(self.tags),
            "modules": {module.path: module.to_dict() for module in self.modules},
        }


@dataclass(frozen=True, slots=True)
class PackageRecord:
    """A package manifest and its associated catalog metadata."""

    root: Path
    name: str
    version: str
    exports: dict[str, str]
    dependencies: tuple[str, ...]
    externals: tuple[str, ...]
    catalog: CatalogEntry

    @property
    def short_name(self) -> str:
        return self.name.removeprefix("quenty/")

    @property
    def identifier(self) -> str:
        return f"{self.name}@{self.version}"


@dataclass(frozen=True, slots=True)
class OperationResult:
    """Structured outcome returned by all manager operations."""

    ok: bool
    summary: str
    changed_paths: tuple[Path, ...] = ()
    diagnostics: tuple[str, ...] = ()
    logs: tuple[str, ...] = ()


@dataclass(slots=True)
class CommandResult:
    """Captured result from one validation or generation command."""

    command: tuple[str, ...]
    returncode: int
    output: str = field(default="")

    @property
    def ok(self) -> bool:
        return self.returncode == 0
