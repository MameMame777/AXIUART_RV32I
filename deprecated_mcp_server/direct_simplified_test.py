#!/usr/bin/env python3
"""
Direct simplified environment test - bypass MCP for immediate execution
"""
import sys
import subprocess
import json
from pathlib import Path
from datetime import datetime

def run_dsim_compile_simplified():
    """Directly invoke DSIM for simplified environment compilation"""
    
    workspace = Path("e:/Nautilus/workspace/fpgawork/AXIUART_")
    dsim_home = Path(r"C:\Program Files\Altair\DSim\2025.1")
    dsim_exe = dsim_home / "bin" / "dsim.exe"
    
    # CRITICAL: Setup DSIM environment variables
    import os
    os.environ['DSIM_HOME'] = str(dsim_home)
    os.environ['DSIM_ROOT'] = str(dsim_home)
    os.environ['DSIM_LIB_PATH'] = str(dsim_home / "lib")
    
    # CRITICAL: Add DSIM bin to PATH for DLL resolution
    dsim_bin = str(dsim_home / "bin")
    dsim_mingw = str(dsim_home / "mingw" / "bin")
    dsim_deps = str(dsim_home / "dsim_deps" / "bin")
    dsim_lib = str(dsim_home / "lib")
    
    current_path = os.environ.get('PATH', '')
    new_path = os.pathsep.join([dsim_bin, dsim_mingw, dsim_deps, dsim_lib, current_path])
    os.environ['PATH'] = new_path
    
    print(f"DSIM_HOME: {os.environ['DSIM_HOME']}")
    print(f"PATH (first 200 chars): {os.environ['PATH'][:200]}")
    
    # Simplified environment paths
    tb_dir = workspace / "sim" / "uvm" / "tb"
    config_file = tb_dir / "dsim_config.f"
    
    if not config_file.exists():
        print(f"ERROR: Config not found: {config_file}")
        return 1
    
    # Create log directory
    log_dir = workspace / "sim" / "exec" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = log_dir / f"axiuart_basic_test_{timestamp}_simplified_compile.log"
    
    # DSIM command for simplified environment
    cmd = [
        str(dsim_exe),
        "-uvm", "1.2",
        "-timescale", "1ns/1ps",
        "-f", "dsim_config.f",
        "-top", "axiuart_tb_top",
        "+UVM_TESTNAME=axiuart_basic_test",
        "+UVM_VERBOSITY=UVM_MEDIUM",
        "-sv_seed", "1",
        "-l", str(log_file),
        "-genimage", "compiled_image_simplified",
        "+UVM_PHASE_TRACE",
        "+UVM_OBJECTION_TRACE",
    ]
    
    print("=" * 70)
    print("DSIM Simplified Environment - Direct Compilation")
    print("=" * 70)
    print(f"Working Dir: {tb_dir}")
    print(f"Config: {config_file}")
    print(f"Log: {log_file}")
    print(f"\nCommand:\n{' '.join(cmd)}\n")
    print("=" * 70)
    
    # Execute DSIM with explicit environment
    result = subprocess.run(
        cmd,
        cwd=str(tb_dir),
        capture_output=True,
        text=True,
        env=os.environ.copy()  # Use updated environment
    )
    
    print(f"\nExit Code: {result.returncode}")
    
    if result.stdout:
        print("\n--- STDOUT ---")
        print(result.stdout)
    
    if result.stderr:
        print("\n--- STDERR ---")
        print(result.stderr)
    
    # Read log file if exists
    if log_file.exists():
        print(f"\n--- LOG FILE: {log_file.name} ---")
        with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
            print(f.read())
    
    if result.returncode == 0:
        print("\n[SUCCESS] Compilation SUCCESSFUL")
        return 0
    else:
        print(f"\n[FAILED] Compilation FAILED (exit code: {result.returncode})")
        return 1

if __name__ == "__main__":
    sys.exit(run_dsim_compile_simplified())
