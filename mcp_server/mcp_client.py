#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""MCP client entry point with reusable tooling helpers."""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Any, Dict, Tuple

logger = logging.getLogger("mcp-client")


try:
    from .client_api import call_tool, extract_text, list_tools, parse_result_json
except ImportError:  # pragma: no cover - script path fallback
    repo_root = Path(__file__).resolve().parent.parent
    sys.path.insert(0, str(repo_root))
    from mcp_server.client_api import call_tool, extract_text, list_tools, parse_result_json


def _parse_arguments(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="DSIM UVM MCP Client")
    parser.add_argument("--workspace", type=str, default=".", help="Workspace path")
    parser.add_argument("--tool", type=str, required=True, help="Tool name to execute")
    parser.add_argument(
        "--mode",
        type=str,
        default="batch",
        choices=["compile", "run", "batch"],
        help="Execution mode: compile only, run only, or batch (compile+run, default)",
    )
    parser.add_argument("--test-name", type=str, help="Test name for simulation")
    parser.add_argument("--verbosity", type=str, default="UVM_DEBUG", help="UVM verbosity level")
    parser.add_argument("--waves", dest="waves", action="store_true", help="Enable waveform generation (default)")
    parser.add_argument("--no-waves", dest="waves", action="store_false", help="Disable waveform generation")
    parser.set_defaults(waves=True)
    parser.add_argument(
        "--wave-format",
        type=str,
        default="MXD",
        choices=["MXD", "VCD"],
        help="Waveform format: MXD (default) or VCD",
    )
    parser.add_argument("--coverage", action="store_true", help="Collect coverage")
    parser.add_argument("--timeout", type=int, default=300, help="Timeout in seconds")
    parser.add_argument("--compile-timeout", type=int, default=120, help="Compile timeout in seconds (batch mode only)")
    parser.add_argument(
        "--plusarg",
        action="append",
        default=[],
        help="DSIM plus-argument (e.g. SIM_TIMEOUT_MS=60000). Repeat for multiple values",
    )
    parser.add_argument("--path", type=str, help="File path for analysis tools")
    parser.add_argument("--test-scenario", type=str, default="", help="Scenario name to append to plusargs")
    parser.add_argument("--list-tools", action="store_true", help="List available tools and exit")
    return parser.parse_args(argv)


def _default_test_name(args: argparse.Namespace) -> str:
    return args.test_name or "axiuart_basic_test"


def _merge_plusargs(args: argparse.Namespace) -> list[str]:
    plusargs = list(args.plusarg or [])
    scenario = args.test_scenario.strip()
    if scenario:
        plusargs.append(f"TEST_SCENARIO={scenario}")
    return plusargs


def _resolve_tool_invocation(args: argparse.Namespace) -> Tuple[str, Dict[str, Any]]:
    plusargs = _merge_plusargs(args)

    if args.tool == "run_uvm_simulation_batch" or (args.tool == "run_uvm_simulation" and args.mode == "batch"):
        actual_tool = "run_uvm_simulation_batch"
        tool_args: Dict[str, Any] = {
            "test_name": _default_test_name(args),
            "verbosity": args.verbosity,
            "waves": args.waves,
            "wave_format": args.wave_format,
            "coverage": args.coverage,
            "compile_timeout": args.compile_timeout,
            "run_timeout": args.timeout,
        }
        if plusargs:
            tool_args["plusargs"] = plusargs
        return actual_tool, tool_args

    if args.tool == "run_uvm_simulation":
        waves_setting = args.waves if args.mode != "compile" else False
        tool_args = {
            "test_name": _default_test_name(args),
            "mode": args.mode,
            "verbosity": args.verbosity,
            "waves": waves_setting,
            "wave_format": args.wave_format,
            "coverage": args.coverage,
            "timeout": args.timeout,
        }
        if plusargs:
            tool_args["plusargs"] = plusargs
        return "run_uvm_simulation", tool_args

    if args.tool in {"compile_design", "compile_design_only"}:
        tool_args = {
            "test_name": _default_test_name(args),
            "verbosity": args.verbosity,
            "timeout": args.timeout,
        }
        return args.tool, tool_args

    if args.tool == "run_simulation":
        tool_args = {
            "test_name": _default_test_name(args),
            "verbosity": args.verbosity,
            "timeout": args.timeout,
        }
        if plusargs:
            tool_args["plusargs"] = plusargs
        return args.tool, tool_args

    tool_args: Dict[str, Any] = {}
    if args.path:
        tool_args["path"] = args.path
    if plusargs:
        tool_args["plusargs"] = plusargs
    return args.tool, tool_args


def execute(argv: list[str] | None = None) -> int:
    args = _parse_arguments(argv)
    workspace_path = Path(args.workspace).resolve()

    if args.list_tools:
        for name in list_tools(workspace_path):
            print(name)
        return 0

    actual_tool, tool_args = _resolve_tool_invocation(args)
    logger.info("Invoking tool '%s' with args %s", actual_tool, tool_args)

    try:
        result = call_tool(workspace_path, actual_tool, tool_args=tool_args)
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        return 130
    except Exception as exc:  # pragma: no cover - runtime diagnostics
        logger.error("MCP communication error: %s", exc, exc_info=True)
        print(
            "ERROR: MCP communication failed. Ensure the FastMCP server is running and reachable.",
            file=sys.stderr,
        )
        return 1

    payload = parse_result_json(result)
    if payload is not None:
        print(json.dumps(payload, indent=2))
    else:
        text = extract_text(result)
        if text:
            print(text)
        else:
            print("No content returned")

    return 0


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )
    return execute(argv)


if __name__ == "__main__":
    sys.exit(main())