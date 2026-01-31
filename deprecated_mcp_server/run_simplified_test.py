#!/usr/bin/env python3
"""
MCP Client for Simplified UVM Environment
Wrapper to execute tests in sim/uvm
"""

import sys
import json
import subprocess
from pathlib import Path
import argparse

def run_simplified_test(workspace: str, test_name: str = "axiuart_basic_test", 
                       verbosity: str = "UVM_MEDIUM", waves: bool = True,
                       timeout: int = 300):
    """Run simplified UVM test using DSIM"""
    
    workspace_path = Path(workspace)
    tb_dir = workspace_path / "sim" / "uvm" / "tb"
    config_file = tb_dir / "dsim_config.f"
    log_dir = workspace_path / "sim" / "exec" / "logs"
    
    # Ensure log directory exists
    log_dir.mkdir(parents=True, exist_ok=True)
    
    # Change to testbench directory
    import os
    os.chdir(tb_dir)
    
    # Set DSIM environment variables (critical for DLL loading)
    dsim_root = r"C:\Program Files\Altair\DSim\2025.1"
    os.environ['DSIM_HOME'] = dsim_root
    os.environ['DSIM_ROOT'] = dsim_root
    os.environ['DSIM_LIB_PATH'] = os.path.join(dsim_root, "lib")
    os.environ['DSIM_LICENSE'] = os.path.join(dsim_root, "dsim-license.json")
    
    # Add DSIM bin to PATH for DLL resolution (critical!)
    dsim_bin = os.path.join(dsim_root, "bin")
    if dsim_bin not in os.environ['PATH']:
        os.environ['PATH'] = dsim_bin + os.pathsep + os.environ['PATH']
    
    print(f"{'='*60}")
    print(f"AXIUART Simplified Test Runner")
    print(f"{'='*60}")
    print(f"Workspace: {workspace}")
    print(f"Test: {test_name}")
    print(f"Config: {config_file}")
    print(f"DSIM_HOME: {os.environ.get('DSIM_HOME')}")
    print(f"PATH contains DSIM: {dsim_bin in os.environ['PATH']}")
    print(f"{'='*60}\n")
    
    # Step 1: Compile
    print("[1/2] Compiling...")
    compile_cmd = [
        os.path.join(dsim_bin, "dsim.exe"),  # Use full path to executable
        "-uvm", "1.2",
        "-timescale", "1ns/1ps",
        "-work", "work",
        "-genimage", "image",
        "-f", str(config_file),
        "-top", "axiuart_tb_top",
        f"+UVM_TESTNAME={test_name}",
        f"+UVM_VERBOSITY={verbosity}",
        "+UVM_PHASE_TRACE",
        "+UVM_OBJECTION_TRACE",
        "+acc+b",
        "+acc+rw",
    ]
    
    result = subprocess.run(compile_cmd, capture_output=True, text=True)
    
    print("STDOUT:", result.stdout)
    print("STDERR:", result.stderr)
    print("RETURNCODE:", result.returncode)
    
    if result.returncode != 0:
        print(f"[ERROR] Compilation failed:")
        print(result.stdout)
        print(result.stderr)
        return False, {"status": "compile_failed", "output": result.stderr, "stdout": result.stdout}
    
    print("[OK] Compilation successful\n")
    
    # Step 2: Run simulation
    print("[2/2] Running simulation...")
    run_cmd = [
        os.path.join(dsim_bin, "dsim.exe"),  # Use full path to executable
        "-work", "work",
        "-image", "image",
        "-sv",
        f"+UVM_TESTNAME={test_name}",
        f"+UVM_VERBOSITY={verbosity}",
    ]
    
    if waves:
        run_cmd.extend(["-waves", "-mxdumpfile", "axiuart_simplified.mxd"])
    
    result = subprocess.run(run_cmd, capture_output=True, text=True, timeout=timeout)
    
    print(result.stdout)
    if result.stderr:
        print(result.stderr)
    
    # Parse results
    success = result.returncode == 0 and "UVM_FATAL" not in result.stdout
    
    output_data = {
        "status": "success" if success else "failed",
        "test_name": test_name,
        "returncode": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
        "waves_file": str(tb_dir / "axiuart_simplified.mxd") if waves else None,
    }
    
    if success:
        print(f"\n{'='*60}")
        print("[SUCCESS] Test completed")
        print(f"{'='*60}")
    else:
        print(f"\n{'='*60}")
        print("[FAILED] Test failed")
        print(f"{'='*60}")
    
    return success, output_data

def main():
    parser = argparse.ArgumentParser(description='Simplified UVM Test Runner')
    parser.add_argument('--workspace', required=True, help='Workspace root path')
    parser.add_argument('--test-name', default='axiuart_basic_test', help='Test name')
    parser.add_argument('--verbosity', default='UVM_MEDIUM', help='UVM verbosity')
    parser.add_argument('--waves', action='store_true', help='Enable waveforms')
    parser.add_argument('--timeout', type=int, default=300, help='Timeout in seconds')
    
    args = parser.parse_args()
    
    success, result = run_simplified_test(
        workspace=args.workspace,
        test_name=args.test_name,
        verbosity=args.verbosity,
        waves=args.waves,
        timeout=args.timeout
    )
    
    print("\n" + json.dumps(result, indent=2))
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
