#!/usr/bin/env python3
"""Batch UVM test execution using the shared MCP client API."""

from __future__ import annotations

import asyncio
import json
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Tuple


try:
    from .client_api import call_tool_async, extract_text, parse_result_json
except ImportError:  # pragma: no cover - script path fallback
    repo_root = Path(__file__).resolve().parent.parent
    import sys

    sys.path.insert(0, str(repo_root))
    from mcp_server.client_api import call_tool_async, extract_text, parse_result_json


WORKSPACE_ROOT = Path(__file__).resolve().parent.parent


TESTS_TO_RUN: List[Tuple[str, str, int]] = [
    ("uart_axi4_minimal_test", "Minimal test - no sequences", 60),
    ("uart_axi4_basic_test", "Basic functional test - VERSION 5 sequence", 120),
    ("uart_axi4_simple_write_test", "Simple write operation", 120),
    ("uart_axi4_single_read_test", "Simple read operation", 120),
    ("uart_axi4_qa_basic_test", "QA basic verification", 120),
    ("uart_axi4_write_protocol_test", "Write protocol verification", 150),
    ("uart_axi4_read_protocol_test", "Read protocol verification", 150),
    ("uart_axi4_error_protocol_test", "Error protocol test", 120),
    ("uart_axi4_register_block_test", "Register block test", 150),
    ("simple_register_test", "Simple register access", 90),
]


async def run_single_test(test_name: str, description: str, timeout: int) -> Dict[str, Any]:
    print(f"\n{'=' * 80}")
    print(f"[TEST] {test_name}")
    print(f"[DESC] {description}")
    print(f"[TIMEOUT] {timeout}s")
    print(f"{'=' * 80}")

    start_time = datetime.now()

    try:
        result = await call_tool_async(
            WORKSPACE_ROOT,
            "run_uvm_simulation",
            tool_args={
                "test_name": test_name,
                "mode": "run",
                "verbosity": "UVM_DEBUG",
                "waves": False,
                "wave_format": "MXD",
                "coverage": False,
                "timeout": timeout,
            },
        )

        duration = (datetime.now() - start_time).total_seconds()
        payload = parse_result_json(result) or {}
        text_payload = extract_text(result)

        status = payload.get("status", "unknown")
        analysis = payload.get("analysis", {})
        is_timeout = status == "timeout"

        if status == "success":
            print(f"[✅ SUCCESS] Test completed in {duration:.1f}s")
        elif is_timeout:
            print(f"[❌ TIMEOUT] Test timed out after {timeout}s")
        else:
            print("[❌ FAILED] Test failed")

        return {
            "test_name": test_name,
            "description": description,
            "timeout_setting": timeout,
            "status": status,
            "is_timeout": is_timeout,
            "duration_seconds": duration,
            "analysis": analysis,
            "raw_output": text_payload,
        }

    except Exception as exc:  # pragma: no cover - runtime diagnostics
        duration = (datetime.now() - start_time).total_seconds()
        print(f"[💥 EXCEPTION] {exc}")
        return {
            "test_name": test_name,
            "description": description,
            "timeout_setting": timeout,
            "status": "exception",
            "is_timeout": False,
            "duration_seconds": duration,
            "exception": str(exc),
        }


async def main() -> None:
    print(
        f"""
╔══════════════════════════════════════════════════════════════╗
║  UVM Test Suite - Batch Execution & Timeout Analysis        ║
║  Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}                              ║
╚══════════════════════════════════════════════════════════════╝
    """
    )

    all_results: List[Dict[str, Any]] = []

    for test_name, description, timeout in TESTS_TO_RUN:
        result = await run_single_test(test_name, description, timeout)
        all_results.append(result)
        await asyncio.sleep(5)

    print(f"\n\n{'=' * 80}")
    print("BATCH EXECUTION SUMMARY")
    print(f"{'=' * 80}\n")

    success_count = sum(1 for r in all_results if r["status"] == "success")
    timeout_count = sum(1 for r in all_results if r.get("is_timeout"))
    failed_count = sum(
        1
        for r in all_results
        if r["status"] not in {"success", "unknown"} and not r.get("is_timeout")
    )
    exception_count = sum(1 for r in all_results if r["status"] == "exception")

    print(f"Total Tests: {len(all_results)}")
    print(f"✅ Success:   {success_count}")
    print(f"❌ Timeout:   {timeout_count}")
    print(f"❌ Failed:    {failed_count}")
    print(f"💥 Exception: {exception_count}")

    print(f"\n{'=' * 80}")
    print("DETAILED RESULTS")
    print(f"{'=' * 80}\n")

    for index, result in enumerate(all_results, 1):
        status_icon = "✅" if result["status"] == "success" else "⏱️" if result.get("is_timeout") else "❌"
        print(f"{index:2d}. {status_icon} {result['test_name']}")
        print(f"    Duration: {result['duration_seconds']:.1f}s / {result['timeout_setting']}s")
        print(f"    Status: {result['status']}")
        if result.get("is_timeout"):
            print("    ⚠️  TIMEOUT - Test did not complete")
        print()

    output_file = Path("sim/exec/logs/batch_test_results.json")
    output_file.parent.mkdir(parents=True, exist_ok=True)

    report_data: Dict[str, Any] = {
        "execution_time": datetime.now().isoformat(),
        "summary": {
            "total": len(all_results),
            "success": success_count,
            "timeout": timeout_count,
            "failed": failed_count,
            "exception": exception_count,
        },
        "results": all_results,
    }

    with output_file.open("w", encoding="utf-8") as handle:
        json.dump(report_data, handle, indent=2)

    print(f"[INFO] Full results saved to: {output_file}")

    if timeout_count > 0:
        print(f"\n{'=' * 80}")
        print("TIMEOUT ANALYSIS")
        print(f"{'=' * 80}\n")

        timeout_tests = [r for r in all_results if r.get("is_timeout")]
        print(f"Tests with timeout ({len(timeout_tests)}):")
        for entry in timeout_tests:
            print(f"  - {entry['test_name']}: {entry['description']}")

        percentage = (timeout_count / len(all_results)) * 100 if all_results else 0
        print(f"\n[FINDING] {timeout_count}/{len(all_results)} tests timed out ({percentage:.1f}%)")

        if timeout_count == len(all_results):
            print("[CRITICAL] ALL tests timed out - systemic issue likely")
        elif timeout_count > len(all_results) / 2:
            print("[WARNING] Majority of tests timeout - common root cause suspected")
        else:
            print("[INFO] Selective timeouts - test-specific issues")


if __name__ == "__main__":
    asyncio.run(main())
