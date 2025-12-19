#!/usr/bin/env python3
"""
Simplified AXIUART Test Runner (Direct DSIM)
Bypasses MCP for simple test execution
"""

import subprocess
import sys
import os
from pathlib import Path

def run_simplified_test():
    """Run the simplified AXIUART test directly with DSIM"""
    
    # Paths
    workspace = Path(r"e:\Nautilus\workspace\fpgawork\AXIUART_")
    test_dir = workspace / "sim" / "uvm" / "tb"
    
    os.chdir(test_dir)
    
    print("=" * 60)
    print("AXIUART Simplified Test (UBUS Style)")
    print("=" * 60)
    
    # Step 1: Compile
    print("\n[1/2] Compiling...")
    compile_cmd = [
        "dsim",
        "-work", "work",
        "-genimage", "image",
        "-f", "dsim_config.f",
        "+define+UVM_NO_DEPRECATED",
        "+define+UVM_OBJECT_MUST_HAVE_CONSTRUCTOR"
    ]
    
    result = subprocess.run(compile_cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"[ERROR] Compilation failed:")
        print(result.stdout)
        print(result.stderr)
        return False
    
    print("[OK] Compilation successful")
    
    # Step 2: Run simulation
    print("\n[2/2] Running simulation...")
    run_cmd = [
        "dsim",
        "-work", "work",
        "-image", "image",
        "+UVM_TESTNAME=axiuart_basic_test",
        "+UVM_VERBOSITY=UVM_MEDIUM",
        "-waves",
        "-mxdumpfile", "axiuart_simplified.mxd"
    ]
    
    result = subprocess.run(run_cmd, capture_output=True, text=True)
    
    print(result.stdout)
    if result.stderr:
        print(result.stderr)
    
    if result.returncode == 0:
        print("\n[SUCCESS] Test completed")
        print(f"Waveform: {test_dir / 'axiuart_simplified.mxd'}")
        return True
    else:
        print("\n[FAILED] Test failed")
        return False

if __name__ == "__main__":
    success = run_simplified_test()
    sys.exit(0 if success else 1)
