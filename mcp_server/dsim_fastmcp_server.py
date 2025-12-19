#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FastMCP Unified DSIM Server - Production Ready Implementation
完全統一されたFastMCP 2.12.4ベースのDSIM UVMサーバー

Created: October 14, 2025
Architecture: FastMCP 2.12.4 → Unified Tools → DSIM Environment
Purpose: 実用的な専門家レベルのMCPサーバー実装
"""

import asyncio
import logging
import os
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Union, Literal
import json
import argparse
from datetime import datetime

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

# FastMCP 2.12.4 imports
from fastmcp import FastMCP
from dsim_uvm_server import (
    setup_workspace as dsim_setup_workspace,
    check_dsim_environment as dsim_check_environment_async,
    run_uvm_simulation as dsim_run_uvm_simulation_async,
    DSIMError,
    analyze_vcd_waveform as dsim_analyze_vcd_waveform_async,
)

# Configure logging 
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stderr)]
)
logger = logging.getLogger("dsim-fastmcp-unified")

# ===============================================================================
# Global State Management
# ===============================================================================

# Global workspace path
_workspace_path: Optional[Path] = None

def set_workspace_path(path: str) -> None:
    """Set the global workspace path"""
    global _workspace_path
    _workspace_path = Path(path)

def get_workspace_path() -> Path:
    """Get the global workspace path"""
    if _workspace_path is None:
        raise ValueError("Workspace path not initialized")
    return _workspace_path

# ===============================================================================
# Core Utility Helpers
# ===============================================================================

def _load_test_metadata(tests_dir: Path) -> List[Dict[str, str]]:
    """Collect metadata for each *_test.sv file in the tests directory."""
    test_entries: List[Dict[str, str]] = []

    for test_file in sorted(tests_dir.glob("*_test.sv")):
        entry: Dict[str, str] = {
            "file": test_file.name,
            "class": test_file.stem,
            "description": "No description available",
            "status": "ok",
        }

        try:
            content = test_file.read_text(encoding="utf-8")
        except Exception as exc:  # pragma: no cover - file IO failure
            entry["description"] = f"Unable to read file ({exc})"
            entry["status"] = "error"
            test_entries.append(entry)
            continue

        class_match = re.search(r"class\s+(\w+)\s+extends", content)
        if class_match:
            entry["class"] = class_match.group(1)

        desc_match = re.search(r"//\s*Description:\s*(.+)", content, re.IGNORECASE)
        if desc_match:
            entry["description"] = desc_match.group(1).strip()

        test_entries.append(entry)

    return test_entries


def _format_test_report(tests_dir: Path, tests: List[Dict[str, str]]) -> str:
    """Generate a human-readable test discovery report."""
    lines: List[str] = [
        "[INFO] Available UVM Tests Discovery Report",
        "=" * 60,
        f"Search Directory: {tests_dir}",
        f"Found {len(tests)} test files",
        "",
    ]

    for index, test in enumerate(tests, 1):
        lines.append(f"{index:2d}. {test['class']}")
        lines.append(f"    File: {test['file']}")
        lines.append(f"    Description: {test['description']}")
        if test["status"] != "ok":
            lines.append(f"    Status: {test['status']}")
        lines.append("")

    lines.append("=" * 60)
    lines.append("[OK] Test Discovery Complete")
    lines.append("[INFO] Use test class names (not file names) with run_uvm_simulation")

    return "\n".join(lines)


def _analyze_simulation_output(output: str, waves: bool) -> Dict[str, Union[bool, str, int]]:
    """Extract useful status indicators from DSIM output text."""

    error_match = re.search(r"UVM_ERROR\s*:\s*(\d+)", output)
    fatal_match = re.search(r"UVM_FATAL\s*:\s*(\d+)", output)

    error_count = int(error_match.group(1)) if error_match else None
    fatal_count = int(fatal_match.group(1)) if fatal_match else None

    has_explicit_error_counts = error_count is not None or fatal_count is not None

    if has_explicit_error_counts:
        uvm_errors_present = (error_count or 0) > 0 or (fatal_count or 0) > 0
    else:
        # Fall back to keyword detection when summary counts are absent
        uvm_errors_present = "UVM_ERROR" in output or "UVM_FATAL" in output

    test_passed = (
        "TEST PASSED" in output
        or (
            has_explicit_error_counts
            and (error_count or 0) == 0
            and (fatal_count or 0) == 0
        )
    )

    result: Dict[str, Union[bool, str, int]] = {
        "test_passed": test_passed,
        "uvm_errors_present": uvm_errors_present,
        # DSIM may report MXD or VCD waveforms depending on invocation
        "waveform_hint": waves and (".mxd" in output.lower() or ".vcd" in output.lower() or "waves" in output.lower()),
    }

    if error_count is not None:
        result["uvm_error_count"] = error_count
    if fatal_count is not None:
        result["uvm_fatal_count"] = fatal_count

    return result

# ===============================================================================
# FastMCP Server and Tools Setup
# ===============================================================================

def create_fastmcp_server() -> FastMCP:
    """
    FastMCP サーバーを専門家レベルの設定で作成
    """
    mcp = FastMCP(
        name="DSIM-UVM-Unified-Server",
        instructions="""
        統一DSIM UVMシミュレーション環境サーバー。
        
        このサーバーは以下の機能を提供します：
        - DSIM環境の自動検証と診断
        - UVMテストの実行とコンパイル
        - 波形生成（MXD形式）とカバレッジ収集
        - テスト一覧とステータス監視
        - エラー診断と推奨事項
        
        実行方式：
        1. 環境確認 → 2. テスト選択 → 3. 実行 → 4. 結果確認
        """
    )
    
    # ===============================================================================
    # Tool Definitions
    # ===============================================================================
    
    workspace = get_workspace_path()
    dsim_setup_workspace(str(workspace))

    async def _execute_simulation(
        test_name: str,
        mode: Literal["compile", "run", "elaborate"],
        verbosity: Literal[
            "UVM_NONE",
            "UVM_LOW",
            "UVM_MEDIUM",
            "UVM_HIGH",
            "UVM_FULL",
            "UVM_DEBUG",
        ],
        waves: bool,
        coverage: bool,
        seed: Optional[int],
        timeout: int,
    wave_format: Literal["VPD", "MXD", "VCD"] = "MXD",
        plusargs: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        effective_seed = seed if seed is not None else 1

        try:
            output_text = await dsim_run_uvm_simulation_async(
                test_name=test_name,
                mode=mode,
                verbosity=verbosity,
                waves=waves,
                wave_format=wave_format,
                coverage=coverage,
                seed=effective_seed,
                timeout=timeout,
                plusargs=plusargs,
            )
        except DSIMError as exc:  # pragma: no cover - delegated diagnostics
            return {
                "status": "error",
                "error_type": exc.error_type,
                "message": exc.message,
                "suggestion": exc.suggestion,
                "exit_code": exc.exit_code if exc.exit_code is not None else -1,
            }

        analysis = _analyze_simulation_output(output_text, waves)

        return {
            "status": "success",
            "output": output_text,
            "analysis": analysis,
            "test_name": test_name,
            "mode": mode,
            "verbosity": verbosity,
            "waves": waves,
            "coverage": coverage,
            "seed": effective_seed,
            "timeout": timeout,
            "plusargs": plusargs or [],
        }

    @mcp.tool
    async def check_dsim_environment() -> Dict[str, Any]:
        """Run the DSIM environment diagnostic using the unified server."""
        try:
            report_text = await dsim_check_environment_async()
            return {
                "status": "success",
                "report": report_text,
                "environment_variables": {
                    "DSIM_HOME": os.environ.get("DSIM_HOME", ""),
                    "DSIM_ROOT": os.environ.get("DSIM_ROOT", ""),
                    "DSIM_LIB_PATH": os.environ.get("DSIM_LIB_PATH", ""),
                    "DSIM_LICENSE": os.environ.get("DSIM_LICENSE", ""),
                },
            }
        except DSIMError as exc:  # pragma: no cover - delegated diagnostics
            return {
                "status": "error",
                "error_type": exc.error_type,
                "message": exc.message,
                "suggestion": exc.suggestion,
                "exit_code": exc.exit_code if exc.exit_code is not None else -1,
            }

    @mcp.tool
    def list_available_tests() -> Dict[str, Any]:
        """Enumerate available UVM tests without spawning helper scripts."""
        tests_dir = workspace / "sim" / "uvm" / "tb"

        if not tests_dir.exists():
            return {
                "status": "error",
                "message": f"UVM tests directory not found: {tests_dir}",
                "tests": [],
                "total_count": 0,
            }

        tests = _load_test_metadata(tests_dir)
        report = _format_test_report(tests_dir, tests)

        ok_tests = [test for test in tests if test["status"] == "ok"]

        return {
            "status": "success",
            "total_count": len(ok_tests),
            "tests": tests,
            "report": report,
        }

    @mcp.tool
    async def run_uvm_simulation(
        test_name: str,
        mode: Literal["compile", "run", "elaborate"] = "run",
        verbosity: Literal[
            "UVM_NONE",
            "UVM_LOW",
            "UVM_MEDIUM",
            "UVM_HIGH",
            "UVM_FULL",
            "UVM_DEBUG",
    ] = "UVM_DEBUG",
    waves: bool = True,
    wave_format: Literal["VPD", "MXD", "VCD"] = "MXD",
        coverage: bool = False,
        seed: Optional[int] = None,
        timeout: int = 300,
        plusargs: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """Execute a DSIM UVM simulation via the unified async API."""
        # Ensure PHASE_TRACE and OBJECTION_TRACE are always enabled
        if plusargs is None:
            plusargs = []
        
        if "+UVM_PHASE_TRACE" not in plusargs:
            plusargs.append("+UVM_PHASE_TRACE")
        if "+UVM_OBJECTION_TRACE" not in plusargs:
            plusargs.append("+UVM_OBJECTION_TRACE")
        
        return await _execute_simulation(
            test_name=test_name,
            mode=mode,
            verbosity=verbosity,
            waves=waves,
            wave_format=wave_format,
            coverage=coverage,
            seed=seed,
            timeout=timeout,
            plusargs=plusargs,
        )

    @mcp.tool
    async def compile_design_only(
        test_name: str,
        verbosity: Literal["UVM_NONE", "UVM_LOW", "UVM_MEDIUM", "UVM_HIGH", "UVM_DEBUG"] = "UVM_DEBUG",
        timeout: int = 120,
    ) -> Dict[str, Any]:
        """Run a compile-only pass using the unified simulation path."""
        return await _execute_simulation(
            test_name=test_name,
            mode="compile",
            verbosity=verbosity,
            waves=False,
            coverage=False,
            seed=1,
            timeout=timeout,
        )

    @mcp.tool
    async def run_uvm_simulation_batch(
        test_name: str,
        verbosity: Literal[
            "UVM_NONE",
            "UVM_LOW",
            "UVM_MEDIUM",
            "UVM_HIGH",
            "UVM_FULL",
            "UVM_DEBUG",
        ] = "UVM_DEBUG",
        waves: bool = True,
    wave_format: Literal["VPD", "MXD", "VCD"] = "MXD",
        coverage: bool = False,
        seed: Optional[int] = None,
        compile_timeout: int = 120,
        run_timeout: int = 300,
        plusargs: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """
        一括実行: コンパイル → 実行を自動的に順次実行
        
        Execute DSIM UVM simulation in batch mode (compile then run automatically).
        This is the recommended method for normal test execution.
        
        Args:
            test_name: UVM test name to execute
            verbosity: UVM verbosity level (default: UVM_DEBUG)

            waves: Enable waveform generation (default: True)
            wave_format: Waveform format - MXD (binary) or VCD (text) (default: MXD)
            coverage: Enable coverage collection (default: False)
            seed: Random seed (default: auto-generated)
            compile_timeout: Compilation timeout in seconds (default: 120)
            run_timeout: Simulation timeout in seconds (default: 300)
            plusargs: Additional plusargs for simulation
            
        Returns:
            Combined results from both compile and run phases
        """
        logger.info(f"[BATCH] Starting batch execution for test: {test_name}")
        
        # Ensure PHASE_TRACE and OBJECTION_TRACE are always enabled
        if plusargs is None:
            plusargs = []
        
        # Add trace plusargs if not already present
        if "+UVM_PHASE_TRACE" not in plusargs:
            plusargs.append("+UVM_PHASE_TRACE")
        if "+UVM_OBJECTION_TRACE" not in plusargs:
            plusargs.append("+UVM_OBJECTION_TRACE")
        
        logger.info(f"[BATCH] Active plusargs: {plusargs}")
        
        # Phase 1: Compile
        logger.info("[BATCH] Phase 1/2: Compiling...")
        compile_result = await _execute_simulation(
            test_name=test_name,
            mode="compile",
            verbosity="UVM_LOW",  # Low verbosity for compilation
            waves=False,
            coverage=False,
            seed=seed if seed is not None else 1,
            timeout=compile_timeout,
            wave_format=wave_format,
            plusargs=plusargs,  # Pass plusargs to compile for consistency
        )
        
        if compile_result.get("status") != "success":
            logger.error("[BATCH] Compilation failed, aborting batch execution")
            return {
                "status": "error",
                "phase": "compile",
                "error_type": "compilation_failed",
                "message": "Batch execution aborted: compilation failed",
                "compile_result": compile_result,
                "run_result": None,
            }
        
        logger.info("[BATCH] Phase 1/2: Compilation successful")
        
        # Small delay to ensure license release
        logger.info("[BATCH] Waiting 2 seconds for license release...")
        await asyncio.sleep(2)
        
        # Phase 2: Run
        logger.info("[BATCH] Phase 2/2: Running simulation...")
        run_result = await _execute_simulation(
            test_name=test_name,
            mode="run",
            verbosity=verbosity,
            waves=waves,
            wave_format=wave_format,
            coverage=coverage,
            seed=seed if seed is not None else 1,
            timeout=run_timeout,
            plusargs=plusargs,
        )
        
        if run_result.get("status") != "success":
            logger.error("[BATCH] Simulation run failed")
            return {
                "status": "error",
                "phase": "run",
                "error_type": "simulation_failed",
                "message": "Batch execution completed compilation but simulation failed",
                "compile_result": compile_result,
                "run_result": run_result,
            }
        
        logger.info("[BATCH] Phase 2/2: Simulation successful")
        logger.info("[BATCH] Batch execution completed successfully")
        
        return {
            "status": "success",
            "phase": "batch_complete",
            "message": "Batch execution completed: compile + run successful",
            "compile_result": compile_result,
            "run_result": run_result,
            "test_name": test_name,
            "verbosity": verbosity,
            "waves": waves,
            "coverage": coverage,
            "seed": seed if seed is not None else 1,
        }

    @mcp.tool
    async def analyze_vcd_waveform(path: str) -> Dict[str, Any]:
        """Parse VCD header information for quick diagnostics."""
        try:
            result_text = await dsim_analyze_vcd_waveform_async(path)
        except DSIMError as exc:  # pragma: no cover - delegated diagnostics
            return {
                "status": "error",
                "error_type": exc.error_type,
                "message": exc.message,
                "suggestion": exc.suggestion,
                "exit_code": exc.exit_code if exc.exit_code is not None else -1,
            }

        try:
            parsed: Dict[str, Any] = json.loads(result_text)
        except json.JSONDecodeError:
            parsed = {"status": "success", "raw": result_text}

        return parsed

    @mcp.tool  
    def get_simulation_logs(log_type: str = "latest") -> Dict[str, Any]:
        """
        シミュレーションログの取得と解析
        
        Args:
            log_type: 取得するログの種類 ("latest", "all", "errors")
            
        Returns:
            ログデータ
        """
        logs_data: Dict[str, Any] = {
            "log_type": log_type,
            "timestamp": datetime.now().isoformat(),
            "logs": [],
            "summary": {}
        }
        
        try:
            # シミュレーションディレクトリのログファイルを探索
            workspace = get_workspace_path()
            sim_dir = workspace / "sim" / "exec"
            if sim_dir.exists():
                log_files = list(sim_dir.glob("*.log"))
                log_files.extend(sim_dir.glob("dsim.log"))
                
                for log_file in log_files:
                    if log_file.exists():
                        with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
                            content = f.read()
                            logs_data["logs"].append({
                                "file": str(log_file.name),
                                "content": content[-2000:],  # 最後の2000文字
                                "size": len(content)
                            })
                
                logs_data["summary"] = {
                    "files_found": len(log_files),
                    "status": "success"
                }
            else:
                logs_data["summary"] = {
                    "files_found": 0,
                    "status": "no_simulation_directory",
                    "message": f"Simulation directory not found: {sim_dir}"
                }
                
        except Exception as e:
            logs_data["summary"] = {
                "status": "error",
                "error": str(e)
            }
        
        return logs_data

    return mcp

# ===============================================================================
# Server Execution and Configuration
# ===============================================================================

def main():
    """メイン実行関数"""
    parser = argparse.ArgumentParser(description="FastMCP Unified DSIM Server")
    parser.add_argument("--workspace", required=True, help="Workspace directory path")
    parser.add_argument("--transport", choices=["stdio", "http"], default="stdio", 
                       help="Transport method")
    parser.add_argument("--host", default="localhost", help="HTTP host (for HTTP transport)")
    parser.add_argument("--port", type=int, default=8000, help="HTTP port (for HTTP transport)")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging")
    
    args = parser.parse_args()
    
    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)
        logger.debug("Debug logging enabled")
    
    # ワークスペースパスを設定
    set_workspace_path(args.workspace)
    
    # FastMCP server initialization
    mcp = create_fastmcp_server()
    
    logger.info(f"Starting FastMCP Unified Server (transport: {args.transport})")
    logger.info(f"Workspace: {args.workspace}")
    
    # Server execution based on transport
    if args.transport == "stdio":
        logger.info("Starting STDIO transport...")
        try:
            mcp.run(transport="stdio", show_banner=True)
        except KeyboardInterrupt:
            logger.info("Server stopped by user")
        except Exception as e:
            logger.error(f"Server error: {e}")
            sys.exit(1)
    elif args.transport == "http":
        logger.info(f"Starting HTTP transport on {args.host}:{args.port}")
        mcp.run(transport="streamable-http", host=args.host, port=args.port)

if __name__ == "__main__":
    main()