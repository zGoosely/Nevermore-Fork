"""Installed console entry point."""

from __future__ import annotations

import sys

from .manager import PackageManager


def main() -> int:
    from .tui import run

    run(PackageManager())
    return 0


if __name__ == "__main__":
    sys.exit(main())
