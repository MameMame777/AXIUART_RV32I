#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
RV32I Core Direct Compilation and Simulation Script
AXIUART方式に準拠したMCP経由実行スクリプト
"""

import subprocess
import sys
import os
from pathlib import Path
import json

def run_rv32i_compile():
    """Compile RV32I core using DSIM (AXIUART-style)"""
    
    workspace = Path(r"<repo-root>")
    tb_dir = workspace / "sim" / "uvm" / "tb"
    config_file = tb_dir / "rv32i_config.f"
    
    if not config_file.exists():
        print(f"ERROR: Config file not found: {config_file}")
        return False
    
    # Change to testbench directory (CRITICAL!)
    os.chdir(tb_dir)
    
    # Set DSIM environment variables (identical to AXIUART approach)
    dsim_root = r"C:\Program Files\Altair\DSim\2025.1"
    os.environ['DSIM_HOME'] = dsim_root
    os.environ['DSIM_ROOT'] = dsim_root
    os.environ['DSIM_LIB_PATH'] = os.path.join(dsim_root, "lib")
    os.environ['DSIM_LICENSE'] = os.path.join(dsim_root, "dsim-license.json")
    
    # Add DSIM bin to PATH for DLL resolution (CRITICAL!)
    dsim_bin = os.path.join(dsim_root, "bin")
    if dsim_bin not in os.environ['PATH']:
        os.environ['PATH'] = dsim_bin + os.pathsep + os.environ['PATH']
    
    dsim_exe = os.path.join(dsim_bin, "dsim.exe")  # Use full path
    
    # Compile command (AXIUART style with full path)
    compile_cmd = [
        dsim_exe,
        "-sv",
        "-timescale", "1ns/1ps",
        "-genimage", "rv32i_image",
        "-work", "dsim_work",
        "-f", "rv32i_config.f",
        "+acc+b",
        "+acc+rw",
    ]
    
    print("=" * 80)
    print("RV32I Core Compilation (AXIUART-style)")
    print("=" * 80)
    print(f"Working directory: {os.getcwd()}")
    print(f"Config file: {config_file}")
    print(f"DSIM_HOME: {os.environ.get('DSIM_HOME')}")
    print(f"PATH contains DSIM: {dsim_bin in os.environ['PATH']}")
    print(f"Command: {' '.join(compile_cmd)}")
    print("=" * 80)
    
    try:
        result = subprocess.run(
            compile_cmd,
            capture_output=True,
            text=True,
            timeout=180
        )
        
        print("STDOUT:")
        print(result.stdout)
        
        if result.stderr:
            print("STDERR:")
            print(result.stderr)
        
        print(f"RETURNCODE: {result.returncode}")
        
        if result.returncode == 0:
            print("\n[SUCCESS] Compilation completed successfully")
            return True
        else:
            print(f"\n[ERROR] Compilation failed with return code {result.returncode}")
            return False
            
    except subprocess.TimeoutExpired:
        print("[ERROR] Compilation timeout (180 seconds)")
        return False
    except Exception as e:
        print(f"[ERROR] Compilation exception: {e}")
        return False

def run_rv32i_simulation():
    """Run RV32I simulation using DSIM (AXIUART-style)"""
    
    workspace = Path(r"<repo-root>")
    tb_dir = workspace / "sim" / "uvm" / "tb"
    
    # Ensure we're in the correct directory
    os.chdir(tb_dir)
    
    # DSIM environment should already be set from compile
    dsim_root = r"C:\Program Files\Altair\DSim\2025.1"
    dsim_bin = os.path.join(dsim_root, "bin")
    dsim_exe = os.path.join(dsim_bin, "dsim.exe")
    
    sim_cmd = [
        dsim_exe,
        "-work", "dsim_work",
        "-image", "rv32i_image",
        "-sv",
        "+WAVES"
    ]
    
    print("=" * 80)
    print("RV32I Core Simulation (AXIUART-style)")
    print("=" * 80)
    print(f"Working directory: {os.getcwd()}")
    print(f"Command: {' '.join(sim_cmd)}")
    print("=" * 80)
    
    try:
        result = subprocess.run(
            sim_cmd,
            capture_output=True,
            text=True,
            timeout=300
        )
        
        print("STDOUT:")
        print(result.stdout)
        
        if result.stderr:
            print("STDERR:")
            print(result.stderr)
        
        print(f"RETURNCODE: {result.returncode}")
        
        if result.returncode == 0:
            print("\n[SUCCESS] Simulation completed successfully")
            return True
        else:
            print(f"\n[ERROR] Simulation failed with return code {result.returncode}")
            return False
            
    except subprocess.TimeoutExpired:
        print("[ERROR] Simulation timeout (300 seconds)")
        return False
    except Exception as e:
        print(f"[ERROR] Simulation exception: {e}")
        return False

def main():
    """Main execution function"""
    
    print("\n" + "=" * 80)
    print("RV32I Core Compilation and Simulation (AXIUART-style)")
    print("=" * 80 + "\n")
    
    # Step 1: Compile
    if not run_rv32i_compile():
        print("\n[FAILED] Compilation stage failed. Aborting.")
        sys.exit(1)
    
    print("\n")
    
    # Step 2: Run simulation
    if not run_rv32i_simulation():
        print("\n[FAILED] Simulation stage failed.")
        sys.exit(1)
    
    print("\n" + "=" * 80)
    print("[SUCCESS] RV32I Core test completed successfully")
    print("=" * 80 + "\n")
    
    sys.exit(0)

if __name__ == "__main__":
    main()

    sim_cmd = [
        str(dsim_exe),
        "-image", "rv32i_image",
        "-work", "dsim_work",
        "-waves", "rv32i_waves.mxd",
        "+WAVES"
    ]
    
    print("=" * 80)
    print("RV32I Core Simulation")
    print("=" * 80)
    print(f"Working directory: {tb_dir}")
    print(f"Command: {' '.join(sim_cmd)}")
    print("=" * 80)
    
    try:
        result = subprocess.run(
            sim_cmd,
            env=dsim_env,
            capture_output=True,
            text=True,
            timeout=300
        )
        
        print("STDOUT:")
        print(result.stdout)
        
        if result.stderr:
            print("STDERR:")
            print(result.stderr)
        
        if result.returncode == 0:
            print("\n[SUCCESS] Simulation completed successfully")
            return True
        else:
            print(f"\n[ERROR] Simulation failed with return code {result.returncode}")
            return False
            
    except subprocess.TimeoutExpired:
        print("[ERROR] Simulation timeout (300 seconds)")
        return False
    except Exception as e:
        print(f"[ERROR] Simulation exception: {e}")
        return False

def main():
    """Main execution function"""
    
    print("\n" + "=" * 80)
    print("RV32I Core Compilation and Simulation")
    print("=" * 80 + "\n")
    
    # Step 1: Compile
    if not run_rv32i_compile():
        print("\n[FAILED] Compilation stage failed. Aborting.")
        sys.exit(1)
    
    print("\n")
    
    # Step 2: Run simulation
    if not run_rv32i_simulation():
        print("\n[FAILED] Simulation stage failed.")
        sys.exit(1)
    
    print("\n" + "=" * 80)
    print("[SUCCESS] RV32I Core test completed successfully")
    print("=" * 80 + "\n")
    
    sys.exit(0)

if __name__ == "__main__":
    main()
