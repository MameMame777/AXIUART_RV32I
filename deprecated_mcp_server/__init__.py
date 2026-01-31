"""Shared utilities for DSIM MCP server tooling."""

from __future__ import annotations

from pathlib import Path

__all__ = ["get_workspace_root"]


def get_workspace_root(current_file: str | Path) -> Path:
    """Return the repository workspace root derived from a file path."""
    path = Path(current_file).resolve()
    return path.parent.parent
