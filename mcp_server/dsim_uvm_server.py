#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DSIM UVM Simulation MCP Server - FastMCP Edition
Model Context Protocol server for executing DSIM SystemVerilog UVM simulations

Created: October 13, 2025 (FastMCP Migration)
Purpose: Enable MCP clients to execute DSIM simulations with enhanced debugging
Architecture: FastMCP → Agent AI → DSIM Tools (92% → 98% Best Practice Compliance)
"""

import asyncio
import json
import logging
import os
import subprocess
import sys
from pathlib import Path
from typing import List, Optional, Literal, Dict, Any, cast
import argparse
from datetime import datetime, timedelta
import re

from tools.utils import analyse_uvm_log, summarise_test_result, collect_assertion_summary

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

# Configure stdout/stderr encoding for Windows compatibility  
if sys.platform == "win32":
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

# FastMCP imports (Latest Best Practice)
try:
    from mcp.server.fastmcp import FastMCP
except ImportError as e:
    print(f"Error: FastMCP not found. Install with: pip install mcp", file=sys.stderr)
    sys.exit(1)

# Configure enhanced logging with detailed formatting
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stderr),  # MCP best practice: use stderr for logging
    ]
)
logger = logging.getLogger("dsim-fastmcp-server")

# ASCII-safe status symbols for Windows compatibility
STATUS_OK = "[OK]"
STATUS_FAIL = "[FAIL]" 
STATUS_WARN = "[WARN]"
STATUS_INFO = "[INFO]"

# Initialize FastMCP server (Official Best Practice Pattern)
mcp = FastMCP("dsim-uvm-server")

# Global configuration
workspace_root: Optional[Path] = None
dsim_home: Optional[str] = None
MAX_LOG_FILES = 50  # keep the most recent DSIM log files to control disk usage

def setup_dsim_environment():
    """Auto-setup DSIM environment with enhanced error reporting."""
    global dsim_home

    dsim_home = os.environ.get('DSIM_HOME')
    if dsim_home:
        dsim_path_candidate = Path(dsim_home)
        # Some setups incorrectly append /bin; normalize so DSIM_HOME points to install root
        if dsim_path_candidate.name.lower() == "bin" and dsim_path_candidate.parent.exists():
            dsim_path_candidate = dsim_path_candidate.parent
            dsim_home = str(dsim_path_candidate)
            os.environ['DSIM_HOME'] = dsim_home
    if not dsim_home:
        logger.info("DSIM_HOME not set - invoking setup_dsim_env helper")
        try:
            from setup_dsim_env import setup_dsim_environment as helper_setup
        except ImportError as exc:
            logger.warning("Failed to import setup_dsim_env helper: %s", exc)
            return False

        helper_success = helper_setup()
        if not helper_success:
            logger.warning("setup_dsim_env helper did not complete successfully")
            return False

        dsim_home = os.environ.get('DSIM_HOME')
        if not dsim_home:
            logger.warning("setup_dsim_env helper failed to configure DSIM_HOME")
            return False

    dsim_path = Path(dsim_home)
    if not dsim_path.exists():
        logger.warning("Configured DSIM_HOME does not exist: %s", dsim_home)
        return False

    os.environ.setdefault('DSIM_ROOT', dsim_home)
    os.environ.setdefault('DSIM_LIB_PATH', str(dsim_path / "lib"))

    # Always force DSIM 2025.1 standard library locations to avoid stale overrides
    std_libs_path = dsim_path / "std_pkgs" / "lib"
    if std_libs_path.exists():
        os.environ['STD_LIBS'] = str(std_libs_path)

    uvm_default = dsim_path / "uvm" / "1.2"
    if uvm_default.exists():
        os.environ['UVM_HOME'] = str(uvm_default)

    radflex_path = dsim_path / "radflex"
    if radflex_path.exists():
        os.environ['RADFLEX_PATH'] = str(radflex_path)

    # Ensure PATH contains the DSIM tool directories exactly once
    required_path_entries = [
        str(dsim_path / "bin"),
        str(dsim_path / "mingw" / "bin"),
        str(dsim_path / "dsim_deps" / "bin"),
        str(dsim_path / "lib"),
    ]

    current_path = os.environ.get('PATH', '')
    path_components = current_path.split(os.pathsep) if current_path else []
    for entry in required_path_entries:
        if entry and entry not in path_components:
            path_components.insert(0, entry)
    os.environ['PATH'] = os.pathsep.join(path_components)

    # Auto-configure DSIM_LICENSE if not set
    if not os.environ.get('DSIM_LICENSE') and dsim_home:
        license_locations = [
            Path(dsim_home).parent / "dsim-license.json",
            Path(dsim_home) / "dsim-license.json",
            Path("C:/Users/Nautilus/AppData/Local/metrics-ca/dsim-license.json")
        ]

        for license_path in license_locations:
            if license_path.exists():
                os.environ['DSIM_LICENSE'] = str(license_path)
                logger.info(f"Auto-configured DSIM_LICENSE: {license_path}")
                break

    return True

class DSIMError(Exception):
    """Enhanced DSIM-specific error with diagnostic information."""
    def __init__(self, message: str, error_type: str = "general", 
                 suggestion: str = "", exit_code: Optional[int] = None):
        self.message = message
        self.error_type = error_type
        self.suggestion = suggestion
        self.exit_code = exit_code
        super().__init__(self.message)


def cleanup_old_logs(log_dir: Path, max_logs: int = MAX_LOG_FILES) -> None:
    """Remove older DSIM log files while keeping the newest max_logs entries."""
    # Preserve logs by default. Automatic deletion was found to remove
    # historical simulation artifacts that are useful for debugging.
    # To re-enable cleanup (not recommended by default), set
    # environment variable DSIM_ALLOW_LOG_CLEANUP=1
    if os.environ.get("DSIM_ALLOW_LOG_CLEANUP", "0") != "1":
        logger.info(
            "Preserving DSIM logs in %s (set DSIM_ALLOW_LOG_CLEANUP=1 to enable automatic cleanup)",
            log_dir,
        )
        return

    if max_logs <= 0 or not log_dir.exists():
        return

    try:
        log_files = sorted(
            (p for p in log_dir.glob("*.log") if p.is_file()),
            key=lambda file_path: file_path.stat().st_mtime,
            reverse=True,
        )
    except OSError as exc:
        logger.warning("Failed to examine DSIM log directory: %s", exc)
        return

    for old_file in log_files[max_logs:]:
        try:
            old_file.unlink()
            logger.info("Removed old DSIM log: %s", old_file.name)
        except OSError as exc:
            logger.warning("Unable to delete DSIM log %s: %s", old_file.name, exc)


def remove_existing_logs(log_dir: Path) -> None:
    """Delete all existing DSIM log files to ensure only the newest run remains."""
    # Preserve existing logs by default to aid post-run debugging and forensics.
    # If automatic wiping of logs is explicitly desired, set
    # environment variable DSIM_ALLOW_LOG_CLEANUP=1
    if os.environ.get("DSIM_ALLOW_LOG_CLEANUP", "0") != "1":
        logger.info(
            "Preserving existing DSIM logs in %s (set DSIM_ALLOW_LOG_CLEANUP=1 to enable removal)",
            log_dir,
        )
        return

    if not log_dir.exists():
        return

    for log_file in log_dir.glob("*.log"):
        try:
            log_file.unlink()
            logger.debug("Removed stale DSIM log: %s", log_file.name)
        except OSError as exc:
            logger.warning("Unable to delete DSIM log %s: %s", log_file.name, exc)


def parse_dsim_error(stderr_output: str, exit_code: int) -> DSIMError:
    """Parse DSIM error output and provide specific diagnostics."""
    
    if "No such file or directory" in stderr_output:
        return DSIMError(
            "DSIM executable not found",
            "environment",
            "Check DSIM_HOME environment variable and ensure DSIM is properly installed",
            exit_code
        )
    elif "License" in stderr_output or "license" in stderr_output:
        return DSIMError(
            "DSIM license issue detected",
            "license", 
            "Verify DSIM_LICENSE environment variable points to valid license file",
            exit_code
        )
    elif "UVM_ERROR" in stderr_output:
        uvm_errors = re.findall(r'UVM_ERROR[^\n]*', stderr_output)
        return DSIMError(
            f"UVM simulation errors detected: {len(uvm_errors)} errors",
            "simulation",
            "Check testbench logic and UVM configuration. Review simulation logs for details",
            exit_code
        )
    elif "Compilation failed" in stderr_output or "compile error" in stderr_output:
        return DSIMError(
            "SystemVerilog compilation failed", 
            "compilation",
            "Check RTL syntax and file paths in dsim_config.f",
            exit_code
        )
    elif "timeout" in stderr_output.lower():
        return DSIMError(
            "Simulation timeout occurred",
            "timeout",
            "Investigate RTL or testbench stalls using DSIM logs and waveforms; resolve handshake or loop deadlocks before adjusting execution limits",
            exit_code
        )
    else:
        return DSIMError(
            f"DSIM execution failed with exit code {exit_code}",
            "unknown",
            "Check DSIM logs for detailed error information",
            exit_code
        )

def _run_subprocess_sync(cmd: List[str], timeout: int, cwd: Path) -> subprocess.CompletedProcess[bytes]:
    """Run subprocess and drain its pipes to avoid deadlocks on large DSIM output.
    
    CRITICAL: Windows DLL resolution requires explicit PATH in environment.
    """
    
    # Ensure DSIM environment is fully configured
    if not setup_dsim_environment():
        raise DSIMError(
            "DSIM environment setup failed",
            "environment",
            "Verify DSIM_HOME is set and points to valid DSIM installation"
        )
    
    # Create fresh environment with current os.environ (includes PATH updates)
    env = os.environ.copy()
    
    # CRITICAL: Explicitly verify PATH contains DSIM bin directory
    dsim_bin = Path(dsim_home) / "bin" if dsim_home else None
    if dsim_bin and str(dsim_bin) not in env.get('PATH', ''):
        logger.warning(f"DSIM bin not in PATH, forcing: {dsim_bin}")
        env['PATH'] = str(dsim_bin) + os.pathsep + env.get('PATH', '')
    
    logger.debug(f"Subprocess environment PATH (first 500 chars): {env.get('PATH', '')[:500]}")
    logger.debug(f"DSIM_HOME: {env.get('DSIM_HOME', 'NOT SET')}")
    
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=cwd,
        env=env
    )

    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        proc.terminate()
        try:
            stdout, stderr = proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            stdout, stderr = proc.communicate()
        raise subprocess.TimeoutExpired(exc.cmd, exc.timeout, output=stdout, stderr=stderr)

    return subprocess.CompletedProcess(cmd, proc.returncode, stdout, stderr)


async def execute_dsim_command(cmd: List[str], timeout: int = 300, cwd: Optional[Path] = None) -> str:
    """Execute DSIM command with enhanced error handling and diagnostics."""
    
    logger.info(f"Executing DSIM: {' '.join(cmd)}")
    
    if workspace_root is None:
        raise DSIMError(
            "Workspace root not configured",
            "configuration",
            "Call setup_workspace before invoking DSIM commands",
        )

    try:
        loop = asyncio.get_running_loop()
        logger.debug(f"Current asyncio loop: {type(loop)}")
        # Execute with timeout and capture output
        # Change working directory to sim/uvm for correct relative path resolution
        uvm_work_dir = cwd if cwd is not None else workspace_root / "sim" / "uvm"

        if sys.platform == "win32":
            completed = await asyncio.to_thread(
                _run_subprocess_sync,
                cmd,
                timeout,
                uvm_work_dir
            )
            stdout: bytes = completed.stdout
            stderr: bytes = completed.stderr
            return_code = completed.returncode
            
            # CRITICAL: Wait for DSIM to flush log file buffers
            # DSIM writes logs asynchronously, process.returncode=0 doesn't guarantee
            # log file is complete. Add small delay to ensure all data is written.
            await asyncio.sleep(0.5)  # 500ms buffer flush time
        else:
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=uvm_work_dir
            )
            stdout, stderr = await asyncio.wait_for(
                process.communicate(), 
                timeout=timeout
            )
            return_code = process.returncode
            
            # CRITICAL: Wait for DSIM to flush log file buffers (non-Windows)
            await asyncio.sleep(0.5)
        
        stdout_text = stdout.decode('utf-8', errors='replace')
        stderr_text = stderr.decode('utf-8', errors='replace')
        
        if return_code != 0:
            # Parse and enhance error information
            dsim_error = parse_dsim_error(stderr_text, return_code)
            error_msg = f"""
{STATUS_FAIL} DSIM Execution Failed

Error Type: {dsim_error.error_type.upper()}
Exit Code: {dsim_error.exit_code}
Message: {dsim_error.message}

Suggestion: {dsim_error.suggestion}

Command: {' '.join(cmd)}
Working Directory: {cwd}

STDERR Output:
{stderr_text}

STDOUT Output: 
{stdout_text}
            """.strip()
            
            raise DSIMError(error_msg, dsim_error.error_type, dsim_error.suggestion, dsim_error.exit_code)
        
        # Success case with detailed output
        result = f"""
{STATUS_OK} DSIM Execution Successful

Command: {' '.join(cmd)}
Exit Code: 0
Working Directory: {cwd}
Working Directory: {uvm_work_dir}

Output:
{stdout_text}

{f'Warnings/Info: {stderr_text}' if stderr_text.strip() else 'No warnings or additional info'}
        """.strip()
        
        logger.info("DSIM command completed successfully")
        return result
        
    except DSIMError:
        raise
    except subprocess.TimeoutExpired:
        raise DSIMError(
            f"DSIM command timed out after {timeout} seconds",
            "timeout",
            "Inspect RTL/testbench for blocking conditions; review DSIM logs, waveforms, and handshake monitors to eliminate stalls instead of extending the timeout"
        )
    except asyncio.TimeoutError:
        raise DSIMError(
            f"DSIM command timed out after {timeout} seconds",
            "timeout",
            "Inspect RTL/testbench for blocking conditions; review DSIM logs, waveforms, and handshake monitors to eliminate stalls instead of extending the timeout"
        )
    except FileNotFoundError as e:
        raise DSIMError(
            f"DSIM executable not found: {str(e)}",
            "environment",
            "Verify DSIM_HOME environment variable and PATH configuration"
        )
    except Exception as e:
        logger.exception("Unexpected error during DSIM execution")
        raise DSIMError(
            f"Unexpected error during DSIM execution: {type(e).__name__}: {str(e)}",
            "system",
            "Check system resources and DSIM installation integrity"
        )

# FastMCP Tool Definitions with Enhanced Type Safety and Documentation

@mcp.tool()
async def run_uvm_simulation(
    test_name: str = "axiuart_basic_test",
    mode: Literal["run", "compile", "elaborate"] = "run",
    verbosity: Literal["UVM_NONE", "UVM_LOW", "UVM_MEDIUM", "UVM_HIGH", "UVM_FULL", "UVM_DEBUG"] = "UVM_DEBUG",
    waves: bool = True,
    wave_format: Literal["VCD", "MXD"] = "MXD",
    coverage: bool = True,
    seed: int = 1,
    timeout: int = 300,
    plusargs: Optional[List[str]] = None,
    use_simplified: bool = True
) -> str:
    """Execute DSIM UVM simulation with comprehensive options and enhanced error diagnostics.
    
    Args:
        test_name: UVM test class name to execute (default: uart_axi4_basic_test)
        mode: Simulation mode - run (full sim), compile (syntax check), elaborate (build only)
        verbosity: UVM verbosity level for detailed debugging output
    waves: Enable waveform capture for signal analysis (default: True)
    wave_format: Waveform format - MXD (binary, DSIM native, default) or VCD (text, portable)
        coverage: Enable coverage collection for verification metrics  
        seed: Random simulation seed for reproducible results
        timeout: Maximum execution time in seconds before timeout
        plusargs: Additional plusargs for simulation
        
    Returns:
        Detailed simulation results with enhanced error diagnostics
        
    Raises:
        DSIMError: Enhanced DSIM-specific errors with actionable suggestions
    """
    
    # Environment validation
    if not setup_dsim_environment():
        raise DSIMError(
            "DSIM environment not properly configured",
            "environment", 
            "Set DSIM_HOME environment variable to DSIM installation directory"
        )
    if workspace_root is None:
        raise DSIMError(
            "Workspace root not configured",
            "configuration",
            "Call setup_workspace before invoking DSIM tools",
        )
    if dsim_home is None:
        raise DSIMError(
            "DSIM_HOME not set",
            "environment",
            "Set DSIM_HOME environment variable to point at the DSIM install directory",
        )
    
    # Build DSIM command with validation
    dsim_exe = Path(dsim_home) / "bin" / "dsim.exe"
    if not dsim_exe.exists():
        raise DSIMError(
            f"DSIM executable not found at {dsim_exe}",
            "environment",
            f"Verify DSIM installation in {dsim_home}"
        )
        
    # Use simplified environment (only environment available)
    uvm_dir = workspace_root / "sim" / "uvm" / "tb"
    config_file = uvm_dir / "dsim_config.f"
    top_module = "axiuart_tb_top"

    if not config_file.exists():
        raise DSIMError(
            f"DSIM configuration file not found: {config_file}",
            "configuration",
            f"Ensure dsim_config.f exists in {uvm_dir}"
        )
    
    # Create timestamped log directory and prune older entries to limit clutter
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_dir = workspace_root / "sim" / "exec" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    # Ensure stale logs do not accumulate – keep only the upcoming run
    remove_existing_logs(log_dir)
    
    # Use correct relative path from sim/uvm/tb working directory
    # sim/uvm/tb -> ../../exec/logs (two levels up to sim, then exec/logs)
    # Add mode suffix to distinguish compile vs run logs
    mode_suffix = f"_{mode}" if mode in ("compile", "elaborate") else ""
    log_file_relative = f"../../exec/logs/{test_name}_{timestamp}{mode_suffix}.log"
    
    # Build command with enhanced options
    # Use relative config file path since we're executing from sim/uvm directory
    # Note: -uvm must be specified BEFORE mode-specific options (DSIM requirement)
    if use_simplified:
        config_relative = "dsim_config.f"  # Already in tb/ directory
    else:
        config_relative = "config/dsim_config.f"  # In config/ subdirectory
    
    cmd = [
        str(dsim_exe),
        "-uvm", "1.2",  # CRITICAL: UVM library version (DSIM official requirement)
        "-timescale", "1ns/1ps",  # Global timescale to fix 1000x slowdown issue
        "-f", config_relative,
        "-top", top_module,  # Top-level module specification
        f"+UVM_TESTNAME={test_name}",
        f"+UVM_VERBOSITY={verbosity}",
        "-sv_seed", str(seed),
        "-l", log_file_relative
    ]
    
    # Mode-specific options (do NOT add -uvm again)
    if mode == "compile":
        cmd.extend(["-genimage", "compiled_image"])
    elif mode == "elaborate": 
        cmd.extend(["-elaborate"])
    else:  # run mode
        cmd.extend(["-image", "compiled_image"])
    
    # Enhanced feature options
    waves_file: Optional[Path] = None
    wave_plusargs: List[str] = []
    enable_waves = waves and (mode == "run")
    if enable_waves:
        waves_dir = workspace_root / "sim" / "exec" / "wave"
        waves_dir.mkdir(parents=True, exist_ok=True)

        if wave_format == "MXD":
            waves_file = waves_dir / f"{test_name}_{timestamp}.mxd"
            cmd.extend(["-waves", str(waves_file)])
        else:  # VCD request
            waves_file = waves_dir / f"{test_name}_{timestamp}.vcd"
            wave_plusargs.append(f"+WAVE_FILE={waves_file.as_posix()}")
        wave_plusargs.append("+WAVES_ON=1")
        
    if coverage:
        cmd.extend(["+cover+fsm+line+cond+tgl+branch"])

    # Add waveform format selection hint for the testbench
    if enable_waves:
        if wave_format == "VCD":
            cmd.append("+WAVE_FORMAT=VCD")
        else:
            cmd.append("+WAVE_FORMAT=MXD")

    # Default UVM trace options (always enabled for better debugging)
    cmd.append("+UVM_PHASE_TRACE")
    cmd.append("+UVM_OBJECTION_TRACE")

    plusargs_applied: List[str] = []
    if plusargs:
        for entry in plusargs:
            if not entry:
                continue
            candidate = entry.strip()
            if not candidate:
                continue
            if candidate.startswith("+"):
                plusargs_applied.append(candidate)
            else:
                plusargs_applied.append(f"+{candidate}")
        if plusargs_applied:
            cmd.extend(plusargs_applied)

    if wave_plusargs:
        cmd.extend(wave_plusargs)

    require_callback_access = enable_waves or (mode in ("compile", "elaborate"))
    if require_callback_access:
        callback_requested = False
        for entry in cmd:
            if not entry:
                continue
            if entry.startswith("+acc") or entry.startswith("+access") or entry.startswith("-pli_access"):
                callback_requested = True
                break
        if not callback_requested:
            cmd.extend(["+acc+b", "+acc+rw"])
    
    # Execute with enhanced error handling
    try:
        logger.info(f"[DEBUG] DSIM command: {' '.join(cmd)}")
        logger.info(f"[DEBUG] Working directory: {uvm_dir}")
        result_text = await execute_dsim_command(cmd, timeout, cwd=uvm_dir)

        log_file_absolute = (uvm_dir / log_file_relative).resolve()

        analysis: Dict[str, Any] = {}
        summary_report: Dict[str, Any] = {}
        warning_messages: List[str] = []
        status = "success"

        assertion_summary: Dict[str, Any] = {}

        try:
            analysis = analyse_uvm_log(log_file_absolute)
            summary_report = summarise_test_result(analysis)
            status = summary_report.get("status", "success")

            assertion_summary = collect_assertion_summary(analysis)

            raw_warnings: List[Dict[str, Any]] = []
            if analysis:
                warnings_value = analysis.get("warnings", [])
                if isinstance(warnings_value, list):
                    for item in cast(List[Any], warnings_value):
                        if isinstance(item, dict):
                            raw_warnings.append(cast(Dict[str, Any], item))

            warning_messages = [
                f"[{entry.get('id', 'UNKNOWN')}] {entry.get('message', '')}" for entry in raw_warnings[:10]
            ]
            if raw_warnings and len(raw_warnings) > 10:
                warning_messages.append("Additional warnings truncated")
            
            # Clean up old logs and waveforms (older than 2 days)
            try:
                cleanup_old_files(workspace_root)
            except Exception as cleanup_exc:
                logger.warning(f"Failed to cleanup old files: {cleanup_exc}")
                
        except FileNotFoundError:
            warning_messages.append("Log file not found for analysis. Skipping analytics phase.")
        except Exception as exc:  # pragma: no cover - defensive catch
            warning_messages.append(f"Log analysis failed: {exc}")

        response: Dict[str, Any] = {
            "status": status,
            "test_name": analysis.get("test_name") or test_name,
            "mode": mode,
            "verbosity": verbosity,
            "seed": analysis.get("seed") if analysis.get("seed") is not None else seed,
            "log_file": log_file_relative,
            "log_file_absolute": str(log_file_absolute),
            "waves_file": str(waves_file) if waves_file else None,
            "waves_requested": waves,
            "waves_enabled": enable_waves,
            "wave_format": wave_format if enable_waves else None,
            "coverage_requested": coverage,
            "plusargs_requested": plusargs_applied,
            "analysis": {
                **analysis,
                "warnings": (analysis.get("warnings", [])[:10] if analysis else []),
                "assertions": (analysis.get("assertions", [])[:10] if analysis else []),
            } if analysis else {},
            "summary": summary_report,
            "assertion_summary": assertion_summary,
            "details": result_text,
            "warnings": warning_messages,
        }

        return json.dumps(response, ensure_ascii=False)

    except DSIMError as e:
        enhanced_error: Dict[str, Any] = {
            "status": "failure",
            "test_name": test_name,
            "mode": mode,
            "verbosity": verbosity,
            "seed": seed,
            "timeout": timeout,
            "plusargs": plusargs_applied,
            "error": str(e),
            "log_file": log_file_relative,
        }

        raise DSIMError(json.dumps(enhanced_error, ensure_ascii=False), e.error_type, e.suggestion, e.exit_code)

def cleanup_old_files(workspace: Path, max_age_days: int = 1) -> None:
    """Delete log and waveform files older than max_age_days.
    
    Args:
        workspace: Workspace root path
        max_age_days: Maximum age in days (default: 1 - removes files older than 1 day)
    """
    cutoff_time = datetime.now() - timedelta(days=max_age_days)
    today_date = datetime.now().strftime("%Y%m%d")
    
    # Cleanup log files
    logs_dir = workspace / "sim" / "exec" / "logs"
    if logs_dir.exists():
        deleted_logs = 0
        for log_file in logs_dir.glob("*.log"):
            try:
                file_mtime = datetime.fromtimestamp(log_file.stat().st_mtime)
                # Extract date from filename (format: test_YYYYMMDD_HHMMSS.log)
                filename_date_match = re.search(r'_(\d{8})_\d{6}', log_file.stem)
                if filename_date_match:
                    file_date = filename_date_match.group(1)
                    # Delete if not today's date
                    if file_date != today_date or file_mtime < cutoff_time:
                        log_file.unlink()
                        deleted_logs += 1
                        logger.debug(f"Deleted old log: {log_file.name} (date: {file_date})")
                elif file_mtime < cutoff_time:
                    # Fallback to modification time for files without date in name
                    log_file.unlink()
                    deleted_logs += 1
                    logger.debug(f"Deleted old log: {log_file.name}")
            except Exception as e:
                logger.warning(f"Failed to delete log {log_file.name}: {e}")
        
        if deleted_logs > 0:
            logger.info(f"Cleaned up {deleted_logs} log file(s) older than {max_age_days} day(s)")
    
    # Cleanup waveform files
    wave_dir = workspace / "sim" / "exec" / "wave"
    if wave_dir.exists():
        deleted_waves = 0
        for wave_file in wave_dir.glob("*"):
            if wave_file.suffix.lower() in (".mxd", ".vcd", ".vpd"):
                try:
                    file_mtime = datetime.fromtimestamp(wave_file.stat().st_mtime)
                    # Extract date from filename (format: test_YYYYMMDD_HHMMSS.mxd/vcd)
                    filename_date_match = re.search(r'_(\d{8})_\d{6}', wave_file.stem)
                    if filename_date_match:
                        file_date = filename_date_match.group(1)
                        # Delete if not today's date
                        if file_date != today_date or file_mtime < cutoff_time:
                            wave_file.unlink()
                            deleted_waves += 1
                            logger.debug(f"Deleted old waveform: {wave_file.name} (date: {file_date})")
                    elif file_mtime < cutoff_time:
                        # Fallback to modification time
                        wave_file.unlink()
                        deleted_waves += 1
                        logger.debug(f"Deleted old waveform: {wave_file.name}")
                except Exception as e:
                    logger.warning(f"Failed to delete waveform {wave_file.name}: {e}")
        
        if deleted_waves > 0:
            logger.info(f"Cleaned up {deleted_waves} waveform file(s) older than {max_age_days} day(s)")

@mcp.tool()
async def analyze_uvm_log(log_path: str, limit: int = 10) -> str:
    """Analyse a DSIM UVM log file and return structured insight as JSON."""

    if workspace_root is None:
        raise DSIMError(
            "Workspace root not configured",
            "configuration",
            "Call setup_workspace before invoking DSIM tools",
        )

    if limit <= 0:
        raise DSIMError(
            "Limit must be greater than zero",
            "configuration",
            "Provide a positive integer for the limit parameter",
        )

    candidate_path = Path(log_path)
    if not candidate_path.is_absolute():
        candidate_path = workspace_root / candidate_path

    candidate_path = candidate_path.resolve()

    try:
        analysis = analyse_uvm_log(candidate_path)
    except FileNotFoundError as exc:
        raise DSIMError(str(exc), "io", "Verify the log file path", -1) from exc

    summary = summarise_test_result(analysis)
    assertion_summary = collect_assertion_summary(analysis)

    warnings_subset: List[Dict[str, Any]] = []
    warnings_value = analysis.get("warnings", [])
    if isinstance(warnings_value, list):
        for item in cast(List[Any], warnings_value[:limit]):
            if isinstance(item, dict):
                warnings_subset.append(cast(Dict[str, Any], item))

    assertions_subset: List[Dict[str, Any]] = []
    assertions_value = analysis.get("assertions", [])
    if isinstance(assertions_value, list):
        for item in cast(List[Any], assertions_value[:limit]):
            if isinstance(item, dict):
                assertions_subset.append(cast(Dict[str, Any], item))

    try:
        workspace_relative = str(candidate_path.relative_to(workspace_root))
    except ValueError:
        workspace_relative = None

    response: Dict[str, Any] = {
        "status": summary.get("status", "unknown"),
        "log_file": analysis.get("log_path", str(candidate_path)),
        "workspace_relative": workspace_relative,
        "summary": summary,
        "analysis": {
            **analysis,
            "warnings": warnings_subset,
            "assertions": assertions_subset,
        },
        "assertion_summary": assertion_summary,
        "limits": {
            "warnings": limit,
            "assertions": limit,
        },
    }

    return json.dumps(response, ensure_ascii=False)


@mcp.tool()
async def analyze_vcd_waveform(
    wave_path: str,
    max_lines: int = 1000
) -> str:
    """Parse a VCD file header and return variables, timescale, and a small summary.

    This is a lightweight parser that reads the textual VCD header (which is human-readable)
    and extracts $timescale, $scope/$var declarations, and the initial timestamp.
    """

    if workspace_root is None:
        raise DSIMError(
            "Workspace root not configured",
            "configuration",
            "Call setup_workspace before invoking DSIM tools",
        )

    candidate = Path(wave_path)
    if not candidate.is_absolute():
        candidate = workspace_root / candidate

    candidate = candidate.resolve()
    if not candidate.exists():
        raise DSIMError(f"VCD file not found: {candidate}", "io", "Verify the path", -1)

    if candidate.suffix.lower() != ".vcd":
        logger.warning("analyze_vcd_waveform invoked on non-VCD file: %s", candidate)

    variables: List[Dict[str, Any]] = []
    timescale = None
    scopes: List[str] = []
    line_count = 0

    try:
        with candidate.open("r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line_count += 1
                if line_count > max_lines:
                    break
                stripped = line.strip()
                if stripped.startswith("$timescale"):
                    # collect until $end
                    ts = stripped[len("$timescale"):].strip()
                    if ts.endswith("$end"):
                        timescale = ts[:-4].strip()
                    else:
                        # read following tokens until $end
                        parts = [ts]
                        while True:
                            l = fh.readline()
                            line_count += 1
                            if not l:
                                break
                            if l.strip().endswith("$end"):
                                parts.append(l.strip()[:-4])
                                break
                            parts.append(l.strip())
                        timescale = ' '.join(parts).strip()
                elif stripped.startswith("$scope"):
                    # format: $scope module <name> $end
                    tokens = stripped.split()
                    if len(tokens) >= 3:
                        scopes.append(tokens[2])
                elif stripped.startswith("$var"):
                    # $var wire 1 ! signal_name [msb:lsb] $end
                    parts = stripped.split()
                    if len(parts) >= 4:
                        vtype = parts[1]
                        size = parts[2]
                        code = parts[3]
                        name = parts[4] if len(parts) > 4 else ""
                        variables.append({"type": vtype, "size": size, "code": code, "name": name})
                elif stripped.startswith("$enddefinitions"):
                    break
    except OSError as exc:
        raise DSIMError(f"Failed to read VCD: {exc}", "io", "Check file permissions", -1) from exc

    payload: Dict[str, Any] = {
        "status": "success",
        "path": str(candidate),
        "timescale": timescale,
        "scope_hierarchy": scopes,
        "variable_count": len(variables),
        "variables_sample": variables[:50],
    }

    return json.dumps(payload, ensure_ascii=False)

@mcp.tool()
async def check_dsim_environment() -> str:
    """Verify DSIM environment setup and configuration with detailed diagnostics.
    
    Returns:
        Comprehensive environment status report with specific recommendations
    """
    
    report = [f"{STATUS_INFO} DSIM Environment Diagnostic Report"]
    report.append("=" * 50)
    
    # Check DSIM_HOME
    dsim_home_val = os.environ.get('DSIM_HOME')
    if dsim_home_val:
        dsim_path = Path(dsim_home_val)
        if dsim_path.exists():
            report.append(f"{STATUS_OK} DSIM_HOME: {dsim_home_val}")
            
            # Check DSIM executable
            dsim_exe = dsim_path / "bin" / "dsim.exe"
            if dsim_exe.exists():
                report.append(f"{STATUS_OK} DSIM Executable: {dsim_exe}")
            else:
                report.append(f"{STATUS_FAIL} DSIM Executable not found: {dsim_exe}")
                report.append(f"{STATUS_WARN} Check DSIM installation integrity")
        else:
            report.append(f"{STATUS_FAIL} DSIM_HOME path does not exist: {dsim_home_val}")
            report.append(f"{STATUS_WARN} Verify DSIM installation directory")
    else:
        report.append(f"{STATUS_FAIL} DSIM_HOME not set")
        report.append(f"{STATUS_WARN} Set DSIM_HOME to DSIM installation directory")
    
    # Check DSIM_LICENSE
    dsim_license = os.environ.get('DSIM_LICENSE')
    if dsim_license:
        license_path = Path(dsim_license)
        if license_path.exists():
            report.append(f"{STATUS_OK} DSIM_LICENSE: {dsim_license}")
        else:
            report.append(f"{STATUS_FAIL} DSIM license file not found: {dsim_license}")
            report.append(f"{STATUS_WARN} Verify license file location")
    else:
        report.append(f"{STATUS_WARN} DSIM_LICENSE not set (may use default)")
    
    # Check workspace structure
    if workspace_root:
        uvm_dir = workspace_root / "sim" / "uvm"
        config_file = uvm_dir / "config" / "dsim_config.f"
        
        if config_file.exists():
            report.append(f"{STATUS_OK} DSIM Config: {config_file}")
        else:
            report.append(f"{STATUS_FAIL} DSIM Config not found: {config_file}")
            report.append(f"{STATUS_WARN} Ensure dsim_config.f exists in sim/uvm/config/")
            
        # Check log directory
        log_dir = workspace_root / "sim" / "exec" / "logs"
        report.append(f"{STATUS_OK} Log Directory: {log_dir} {'(exists)' if log_dir.exists() else '(will be created)'}")
    else:
        report.append(f"{STATUS_FAIL} Workspace root not configured")
    
    # Environment summary
    report.append("=" * 50)
    
    all_checks = [line for line in report if STATUS_FAIL in line]
    if not all_checks:
        report.append(f"{STATUS_OK} Environment Status: READY")
        report.append(f"{STATUS_INFO} All DSIM components properly configured")
    else:
        report.append(f"{STATUS_FAIL} Environment Status: ISSUES DETECTED")
        report.append(f"{STATUS_WARN} Fix {len(all_checks)} issues before running simulations")
    
    return "\n".join(report)

@mcp.tool()
async def list_available_tests() -> str:
    """List all available UVM test classes in the project with enhanced discovery.
    
    Returns:
        Comprehensive list of UVM tests with file locations and descriptions
    """
    
    if not workspace_root:
        return f"{STATUS_FAIL} Workspace root not configured"
    
    uvm_tests_dir = workspace_root / "sim" / "uvm" / "tb"
    
    if not uvm_tests_dir.exists():
        return f"{STATUS_FAIL} UVM tests directory not found: {uvm_tests_dir}"
    
    test_files = list(uvm_tests_dir.glob("*_test.sv"))
    
    if not test_files:
        return f"{STATUS_WARN} No UVM test files found in {uvm_tests_dir}"
    
    report = [f"{STATUS_INFO} Available UVM Tests Discovery Report"]
    report.append("=" * 60)
    report.append(f"Search Directory: {uvm_tests_dir}")
    report.append(f"Found {len(test_files)} test files")
    report.append("")
    
    for i, test_file in enumerate(sorted(test_files), 1):
        test_name = test_file.stem  # Remove .sv extension
        
        # Try to extract class name and description from file
        try:
            content = test_file.read_text(encoding='utf-8')
            
            # Look for class declaration
            class_match = re.search(r'class\s+(\w+)\s+extends', content)
            class_name = class_match.group(1) if class_match else test_name
            
            # Look for description comment
            desc_match = re.search(r'//\s*Description:\s*(.+)', content, re.IGNORECASE)
            description = desc_match.group(1).strip() if desc_match else "No description available"
            
            report.append(f"{i:2d}. {class_name}")
            report.append(f"    File: {test_file.name}")
            report.append(f"    Description: {description}")
            report.append("")
            
        except Exception as e:
            report.append(f"{i:2d}. {test_name}")
            report.append(f"    File: {test_file.name}")
            report.append(f"    Status: Could not read file ({str(e)})")
            report.append("")
    
    report.append("=" * 60)
    report.append(f"{STATUS_OK} Test Discovery Complete")
    report.append(f"{STATUS_INFO} Use test class names (not file names) with run_uvm_simulation")
    
    return "\n".join(report)

@mcp.tool()
async def compile_design(
    test_name: str = "uart_axi4_basic_test",
    verbosity: Literal["UVM_NONE", "UVM_LOW", "UVM_MEDIUM", "UVM_HIGH"] = "UVM_DEBUG", 
    timeout: int = 120
) -> str:
    """Compile SystemVerilog design and testbench only (no simulation execution).
    
    Fast syntax and elaboration checking for development workflow.
    
    Args:
        test_name: Test name for compilation target
        verbosity: UVM verbosity level (lower for faster compilation)
        timeout: Compilation timeout in seconds
        
    Returns:
        Compilation results with enhanced error diagnostics
    """
    
    return await run_uvm_simulation(
        test_name=test_name,
        mode="compile",
        verbosity=verbosity,
        waves=False,
        coverage=False,
        seed=1,
        timeout=timeout
    )

@mcp.tool()
async def run_simulation(
    test_name: str = "uart_axi4_basic_test",
    verbosity: Literal["UVM_NONE", "UVM_LOW", "UVM_MEDIUM", "UVM_HIGH", "UVM_FULL", "UVM_DEBUG"] = "UVM_DEBUG",
    seed: int = 1,
    timeout: int = 300
) -> str:
    """Execute simulation using pre-compiled design for faster iteration.
    
    Args:
        test_name: Test name to execute
        verbosity: UVM verbosity level for debugging detail
        seed: Random seed for reproducible results
        timeout: Simulation timeout in seconds
        
    Returns:
        Simulation results with enhanced diagnostics
    """
    
    return await run_uvm_simulation(
        test_name=test_name,
        mode="run", 
        verbosity=verbosity,
        waves=True,
        wave_format="MXD",
        coverage=True,
        seed=seed,
        timeout=timeout
    )

@mcp.tool()
async def generate_waveforms(
    test_name: str = "uart_axi4_basic_test",
    format: Literal["vpd", "mxd", "vcd", "both"] = "mxd",
    depth: Literal["all", "top_level", "selected"] = "all",
    timeout: int = 300
) -> str:
    """Generate waveform files during simulation for debugging and analysis.
    
    Args:
        test_name: Test name for waveform generation
    format: Waveform format (mxd default and recommended for DSIM)
        depth: Signal depth for waveform capture
        timeout: Simulation timeout in seconds
        
    Returns:
        Waveform generation results with file locations
    """
    
    format_normalized = format.lower()
    wave_format = "MXD"
    if format_normalized == "mxd":
        wave_format = "MXD"
    elif format_normalized == "vcd":
        wave_format = "VCD"
    elif format_normalized == "both":
        # Default to VCD for MCP orchestration when both is requested
        wave_format = "VCD"

    result_json = await run_uvm_simulation(
        test_name=test_name,
        mode="run",
        verbosity="UVM_MEDIUM", 
        waves=True,
        coverage=True,
        seed=1,
        timeout=timeout,
        wave_format=wave_format
    )

    try:
        parsed = json.loads(result_json)
    except json.JSONDecodeError:
        parsed = {"details": result_json}

    waves_file = parsed.get("waves_file")
    if waves_file is None and workspace_root is not None:
        # Fallback when waveform path is not reported (e.g., VCD dump)
        waves_dir = workspace_root / "sim" / "exec" / "wave"
        extension = wave_format.lower()
        waves_file = str(waves_dir / f"{test_name}.{extension}")

    waveform_info: Dict[str, Any] = {
        "status": parsed.get("status", "unknown"),
        "format": wave_format,
        "depth": depth,
        "waves_file": waves_file,
        "run_result": parsed,
    }

    return json.dumps(waveform_info, ensure_ascii=False)

def setup_workspace(workspace_path: str):
    """Setup workspace configuration with validation."""
    global workspace_root
    
    workspace_root = Path(workspace_path)
    if not workspace_root.exists():
        raise DSIMError(
            f"Workspace directory does not exist: {workspace_path}",
            "configuration",
            "Ensure the workspace path is correct and accessible"
        )
        
    logger.info(f"Workspace configured: {workspace_root}")

def main():
    """Enhanced main function with better argument handling and diagnostics."""
    
    parser = argparse.ArgumentParser(
        description="DSIM UVM MCP Server - FastMCP Edition",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --workspace /path/to/project
  %(prog)s --workspace /path/to/project --debug
        """
    )
    
    parser.add_argument(
        "--workspace", 
        required=True,
        help="Workspace root directory containing the UVM project"
    )
    parser.add_argument(
        "--debug",
        action="store_true", 
        help="Enable debug logging for detailed diagnostics"
    )
    parser.add_argument(
        "--test-tools",
        action="store_true",
        help="Test MCP server tools and exit"
    )
    
    args = parser.parse_args()
    
    # Configure debug logging
    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)
        logger.debug("Debug logging enabled")
    
    try:
        # Setup workspace
        setup_workspace(args.workspace)
        
        # Setup DSIM environment
        if not setup_dsim_environment():
            logger.warning("DSIM environment setup incomplete - some tools may not work")
        
        if args.test_tools:
            # Test mode - validate tools and exit
            logger.info("Testing MCP server tools...")
            
            # Test environment check
            env_result = asyncio.run(check_dsim_environment())
            print("Environment Check Result:")
            print(env_result)
            print("\nMCP Server tools test completed")
            return
        
        # Start MCP server
        logger.info(f"Starting DSIM UVM FastMCP server for workspace: {workspace_root}")
        logger.info("Enhanced with detailed error diagnostics and debugging support")
        
        # Run FastMCP server with stdio transport
        mcp.run(transport='stdio')
        
    except Exception as e:
        logger.error(f"Failed to start MCP server: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()