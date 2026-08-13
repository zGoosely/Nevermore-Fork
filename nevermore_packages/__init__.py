"""Local package-management tools for the Nevermore fork."""

from .manager import PackageManager
from .models import CatalogEntry, ModuleEntry, OperationResult, PackageRecord

__all__ = [
    "CatalogEntry",
    "ModuleEntry",
    "OperationResult",
    "PackageManager",
    "PackageRecord",
]
