#!/usr/bin/env python3
"""Batch compile-and-run workflow using shared MCP client helpers."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path
from typing import Any, Dict


try:
    from .client_api import call_tool, parse_result_json
except ImportError:  # pragma: no cover - script path fallback
    repo_root = Path(__file__).resolve().parent.parent
    sys.path.insert(0, str(repo_root))
    from mcp_server.client_api import call_tool, parse_result_json


def _invoke_simulation(workspace: Path, tool_args: Dict[str, Any]) -> Dict[str, Any]:
    result = call_tool(workspace, "run_uvm_simulation", tool_args=tool_args)
    payload = parse_result_json(result)
    if payload is None:
        raise RuntimeError("Unexpected response: missing JSON payload")
    return payload


def _phase_header(name: str) -> None:
    print(f"\n{'=' * 60}")
    print(f"{name}")
    print(f"{'=' * 60}")


def _print_summary(prefix: str, payload: Dict[str, Any]) -> None:
    analysis = payload.get("analysis", {})
    status = payload.get("status", "unknown")
    print(f"{prefix} status: {status}")
    if analysis:
        duration = analysis.get("runtime_seconds")
        uvm_errors = analysis.get("uvm_error_count")
        if duration is not None:
            print(f"  runtime_seconds: {duration}")
        if uvm_errors is not None:
            print(f"  uvm_error_count: {uvm_errors}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Batch compile-and-run for DSIM UVM tests")
    parser.add_argument("--test-name", required=True, help="UVM test name to execute")
    parser.add_argument("--verbosity", default="UVM_DEBUG", help="UVM verbosity level (default: UVM_DEBUG)")
    parser.add_argument("--waves", dest="waves", action="store_true", help="Enable waveform generation (default)")
    parser.add_argument("--no-waves", dest="waves", action="store_false", help="Disable waveform generation")
    parser.set_defaults(waves=True)
    parser.add_argument("--coverage", action="store_true", help="Enable coverage collection")
    parser.add_argument("--compile-timeout", type=int, default=120, help="Compile timeout in seconds (default: 120)")
    parser.add_argument("--run-timeout", type=int, default=300, help="Run timeout in seconds (default: 300)")
    parser.add_argument("--workspace", type=Path, default=Path.cwd(), help="Workspace root directory")

    args = parser.parse_args(argv)

    print("=" * 60)
    print("DSIM UVM Batch Compile-and-Run")
    print("=" * 60)
    print(f"Test Name:        {args.test_name}")
    print(f"Verbosity:        {args.verbosity}")
    print(f"Waveforms:        {'Enabled' if args.waves else 'Disabled'}")
    print(f"Coverage:         {'Enabled' if args.coverage else 'Disabled'}")
    print(f"Compile Timeout:  {args.compile_timeout}s")
    print(f"Run Timeout:      {args.run_timeout}s")
    print("=" * 60)

    # Phase 1: Compile
    _phase_header("[PHASE 1] COMPILING")
    compile_payload = _invoke_simulation(
        args.workspace,
        {
            "test_name": args.test_name,
            "mode": "compile",
            "verbosity": "UVM_DEBUG",
            "waves": False,
            "wave_format": "MXD",
            "coverage": False,
            "timeout": args.compile_timeout,
        },
    )
    _print_summary("Compile", compile_payload)

    if compile_payload.get("status") != "success":
        print("\n❌ COMPILATION FAILED")
        return 1

    print("\n✅ COMPILATION SUCCESSFUL")

    print("\nWaiting 2 seconds for license release...")
    time.sleep(2)

    # Phase 2: Run
    _phase_header("[PHASE 2] RUNNING SIMULATION")
    run_payload = _invoke_simulation(
        args.workspace,
        {
            "test_name": args.test_name,
            "mode": "run",
            "verbosity": args.verbosity,
            "waves": args.waves,
            "wave_format": "MXD",
            "coverage": args.coverage,
            "timeout": args.run_timeout,
        },
    )
    _print_summary("Run", run_payload)

    if run_payload.get("status") != "success":
        print("\n❌ SIMULATION FAILED")
        return 1

    print("\n✅ SIMULATION SUCCESSFUL")
    print("\n" + "=" * 60)
    print("BATCH EXECUTION COMPLETED SUCCESSFULLY")
    print("=" * 60)

    return 0


if __name__ == "__main__":
    sys.exit(main())
