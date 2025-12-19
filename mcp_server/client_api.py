"""Shared MCP client utilities for DSIM tooling."""

from __future__ import annotations

import asyncio
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, Optional

try:
    from mcp.client.session import ClientSession
    from mcp.client.stdio import StdioServerParameters, stdio_client
    from mcp.types import TextContent
except ImportError as exc:  # pragma: no cover - dependency guard
    raise RuntimeError(
        "MCP client package not found. Install it with: pip install mcp"
    ) from exc

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

DEFAULT_ENV_OVERRIDES: Dict[str, str] = {
    "DSIM_HOME": r"C:\\Program Files\\Altair\\DSim\\2025.1",
    "DSIM_ROOT": r"C:\\Program Files\\Altair\\DSim\\2025.1",
    "DSIM_LIB_PATH": r"C:\\Program Files\\Altair\\DSim\\2025.1\\lib",
    "DSIM_LICENSE": r"C:\\Users\\Nautilus\\AppData\\Local\\metrics-ca\\dsim-license.json",
}


def _build_environment(overrides: Optional[Dict[str, str]] = None) -> Dict[str, str]:
    env = os.environ.copy()
    for key, value in DEFAULT_ENV_OVERRIDES.items():
        env.setdefault(key, value)
    if overrides:
        env.update(overrides)
    return env


def build_server_parameters(
    workspace: Path,
    env_overrides: Optional[Dict[str, str]] = None,
) -> StdioServerParameters:
    server_script = workspace / "mcp_server" / "dsim_fastmcp_server.py"
    if not server_script.exists():
        raise FileNotFoundError(f"Server script not found: {server_script}")

    env = _build_environment(env_overrides)

    return StdioServerParameters(
        command=sys.executable,
        args=[str(server_script), "--workspace", str(workspace)],
        env=env,
        cwd=str(server_script.parent),
        encoding="utf-8",
        encoding_error_handler="replace",
    )


def _require_tool(tools: Iterable[Any], tool_name: str) -> None:
    names = {tool.name for tool in tools}
    if tool_name not in names:
        raise ValueError(f"Tool '{tool_name}' is not available. Found: {sorted(names)}")


def _normalise_tool_args(tool_args: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    return dict(tool_args) if tool_args else {}


def _ensure_workspace_path(workspace: Path) -> Path:
    resolved = workspace.resolve()
    if not resolved.exists():
        raise FileNotFoundError(f"Workspace folder does not exist: {resolved}")
    return resolved


def _collect_text_content(result: Any) -> str:
    if not getattr(result, "content", None):
        return ""
    parts = [c.text for c in result.content if isinstance(c, TextContent)]
    return "\n".join(part.strip() for part in parts if part.strip())


def parse_result_json(result: Any) -> Optional[Dict[str, Any]]:
    payload = _collect_text_content(result)
    if not payload:
        return None
    try:
        return json.loads(payload)
    except json.JSONDecodeError:
        return None


async def list_tools_async(
    workspace: Path,
    env_overrides: Optional[Dict[str, str]] = None,
) -> list[str]:
    workspace_path = _ensure_workspace_path(workspace)
    params = build_server_parameters(workspace_path, env_overrides)

    async with stdio_client(params) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            tools_result = await session.list_tools()
            return sorted(tool.name for tool in tools_result.tools)


def list_tools(
    workspace: Path,
    env_overrides: Optional[Dict[str, str]] = None,
) -> list[str]:
    return asyncio.run(list_tools_async(workspace, env_overrides))


async def call_tool_async(
    workspace: Path,
    tool_name: str,
    *,
    tool_args: Optional[Dict[str, Any]] = None,
    env_overrides: Optional[Dict[str, str]] = None,
) -> Any:
    workspace_path = _ensure_workspace_path(workspace)
    params = build_server_parameters(workspace_path, env_overrides)

    async with stdio_client(params) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            tools_result = await session.list_tools()
            _require_tool(tools_result.tools, tool_name)
            args = _normalise_tool_args(tool_args)
            return await session.call_tool(tool_name, args)


def call_tool(
    workspace: Path,
    tool_name: str,
    *,
    tool_args: Optional[Dict[str, Any]] = None,
    env_overrides: Optional[Dict[str, str]] = None,
) -> Any:
    return asyncio.run(
        call_tool_async(
            workspace,
            tool_name,
            tool_args=tool_args,
            env_overrides=env_overrides,
        )
    )


def extract_text(result: Any) -> str:
    return _collect_text_content(result)
