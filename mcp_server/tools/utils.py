"""Log analysis helpers for MCP DSIM integration."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, Iterable
import re

_SEVERITY_RE = re.compile(
    r"UVM_(INFO|WARNING|ERROR|FATAL)\s+.*?@\s*[^:]+:\s*([^\[]+)\[([^\]]+)\]\s*(.*)",
    re.IGNORECASE,
)
_ASSERT_FAIL_RE = re.compile(r"\*\*ASSERTION FAIL\*\*\s+(\S+)\s+@\s+([0-9_]+)")
_TESTNAME_RE = re.compile(r"Running test\s+([\w:$]+)", re.IGNORECASE)
_SEED_RE = re.compile(r"Random seed:\s*([0-9]+)")
_RUNTIME_RE = re.compile(r"Simulation terminated by \$finish at time\s+([0-9_]+)")
_COVERAGE_RE = re.compile(r"Total coverage:\s*([0-9]+(?:\.[0-9]+)?)%")


def _normalise_counts() -> Dict[str, int]:
    return {"info": 0, "warning": 0, "error": 0, "fatal": 0}


def _increment(bucket: Dict[str, Dict[str, int]], key: str, severity: str) -> None:
    entry = bucket.setdefault(key, _normalise_counts())
    entry[severity] += 1


def _read_lines(log_path: Path) -> Iterable[str]:
    with log_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            yield line.rstrip("\n")


def analyse_uvm_log(log_path: Path) -> Dict[str, Any]:
    if not log_path.exists():
        raise FileNotFoundError(f"Log file not found: {log_path}")

    severity_totals = _normalise_counts()
    by_component: Dict[str, Dict[str, int]] = {}
    by_id: Dict[str, Dict[str, int]] = {}
    warnings: list[Dict[str, str]] = []
    assertions: list[Dict[str, str]] = []
    first_error: Dict[str, str] | None = None

    test_name: str | None = None
    seed: int | None = None
    runtime_ps: int | None = None
    coverage_percent: float | None = None

    for line in _read_lines(log_path):
        severity_match = _SEVERITY_RE.search(line)
        if severity_match:
            severity = severity_match.group(1).lower()
            component = severity_match.group(2).strip()
            report_id = severity_match.group(3).strip()
            message = severity_match.group(4).strip()

            severity_totals[severity] += 1
            _increment(by_component, component, severity)
            _increment(by_id, report_id, severity)

            if severity == "warning":
                warnings.append({"component": component, "id": report_id, "message": message})
            elif severity in {"error", "fatal"} and first_error is None:
                first_error = {
                    "component": component,
                    "id": report_id,
                    "message": message,
                    "line": line,
                }

        assertion_match = _ASSERT_FAIL_RE.search(line)
        if assertion_match:
            assertions.append({
                "assertion": assertion_match.group(1),
                "time": assertion_match.group(2),
                "line": line,
            })

        if test_name is None:
            test_match = _TESTNAME_RE.search(line)
            if test_match:
                test_name = test_match.group(1)

        if seed is None:
            seed_match = _SEED_RE.search(line)
            if seed_match:
                seed = int(seed_match.group(1))

        if runtime_ps is None:
            runtime_match = _RUNTIME_RE.search(line)
            if runtime_match:
                runtime_ps = int(runtime_match.group(1).replace("_", ""))

        if coverage_percent is None:
            coverage_match = _COVERAGE_RE.search(line)
            if coverage_match:
                coverage_percent = float(coverage_match.group(1))

    return {
        "log_path": str(log_path),
        "severity": severity_totals,
        "by_component": by_component,
        "by_id": by_id,
        "warnings": warnings,
        "assertions": assertions,
        "first_error": first_error,
        "test_name": test_name,
        "seed": seed,
        "runtime_ps": runtime_ps,
        "runtime_human": _format_timespan_ps(runtime_ps) if runtime_ps is not None else None,
        "coverage_percent": coverage_percent,
    }


def _format_timespan_ps(ps_value: int) -> str:
    thresholds = [
        (1_000_000_000_000, "s"),
        (1_000_000_000, "ms"),
        (1_000_000, "µs"),
        (1_000, "ns"),
        (1, "ps"),
    ]
    for divisor, unit in thresholds:
        if ps_value >= divisor:
            value = ps_value / divisor
            return f"{value:.3f} {unit}"
    return f"{ps_value} ps"


def summarise_test_result(analysis: Dict[str, Any]) -> Dict[str, Any]:
    severity = analysis.get("severity", {})
    error_total = severity.get("error", 0) + severity.get("fatal", 0)
    assertion_count = len(analysis.get("assertions", []))
    status = "failure" if error_total > 0 or assertion_count > 0 else "success"

    first_issue = analysis.get("first_error")
    issue_text = None
    if first_issue:
        issue_text = f"[{first_issue['id']}] {first_issue['message']}"
    elif assertion_count:
        first_assert = analysis["assertions"][0]
        issue_text = f"Assertion {first_assert['assertion']} at {first_assert['time']}"

    summary_lines = [
        f"Test: {analysis.get('test_name') or 'unknown'}",
        f"Seed: {analysis.get('seed') if analysis.get('seed') is not None else 'n/a'}",
        f"Runtime: {analysis.get('runtime_human') or 'n/a'}",
        f"Coverage: {analysis.get('coverage_percent'):.2f}%" if analysis.get("coverage_percent") is not None else "Coverage: n/a",
        f"Severity counts - info: {severity.get('info', 0)}, warning: {severity.get('warning', 0)}, error: {severity.get('error', 0)}, fatal: {severity.get('fatal', 0)}",
        f"Assertion failures: {assertion_count}",
        f"First issue: {issue_text}" if issue_text else "First issue: none",
        f"Overall status: {status.upper()}",
    ]

    return {
        "status": status,
        "summary_text": "\n".join(summary_lines),
        "error_count": error_total,
        "assertion_failures": assertion_count,
        "first_issue": issue_text,
    }


def collect_assertion_summary(analysis: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "total_failures": len(analysis.get("assertions", [])),
        "failures": analysis.get("assertions", []),
    }
