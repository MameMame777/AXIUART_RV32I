#!/usr/bin/env python3
"""DSIM Environment Setup Script"""

import os
import sys
from pathlib import Path

def setup_dsim_environment():
    """Setup DSIM environment variables"""
    
    # Default DSIM installation path (DSIM 2025.1)
    dsim_home = "C:\\Program Files\\Altair\\DSim\\2025.1"
    
    print("Setting up DSIM environment variables...")
    
    # Set environment variables
    os.environ['DSIM_HOME'] = dsim_home
    os.environ['DSIM_ROOT'] = dsim_home
    os.environ['DSIM_LIB_PATH'] = f"{dsim_home}\\lib"
    os.environ['STD_LIBS'] = f"{dsim_home}\\std_pkgs\\lib"
    os.environ['RADFLEX_PATH'] = f"{dsim_home}\\radflex"
    uvm_home = Path(dsim_home) / "uvm" / "1.2"
    if uvm_home.exists():
        os.environ['UVM_HOME'] = str(uvm_home)
    
    # Check if DSIM_LICENSE is already set, if not try to auto-configure
    if not os.environ.get('DSIM_LICENSE'):
        license_paths = [
            Path(dsim_home).parent / "dsim-license.json",
            Path(dsim_home) / "dsim-license.json",
            Path("C:\\Users\\Nautilus\\AppData\\Local\\metrics-ca\\dsim-license.json")
        ]
        
        for license_path in license_paths:
            if license_path.exists():
                os.environ['DSIM_LICENSE'] = str(license_path)
                print(f"Auto-configured DSIM_LICENSE: {license_path}")
                break

    # Prepend DSIM binaries to PATH for processes launched afterwards
    required_paths = [
        f"{dsim_home}\\bin",
        f"{dsim_home}\\mingw\\bin",
        f"{dsim_home}\\dsim_deps\\bin",
        f"{dsim_home}\\lib",
    ]

    current_path = os.environ.get('PATH', '')
    path_parts = current_path.split(os.pathsep) if current_path else []
    for entry in required_paths:
        if entry not in path_parts:
            path_parts.insert(0, entry)
    os.environ['PATH'] = os.pathsep.join(path_parts)
    
    # Verify setup
    print("\\n=== DSIM Environment Status ===")
    print(f"DSIM_HOME: {os.environ.get('DSIM_HOME', 'NOT SET')}")
    print(f"DSIM_ROOT: {os.environ.get('DSIM_ROOT', 'NOT SET')}")
    print(f"DSIM_LIB_PATH: {os.environ.get('DSIM_LIB_PATH', 'NOT SET')}")
    print(f"DSIM_LICENSE: {os.environ.get('DSIM_LICENSE', 'NOT SET')}")
    print(f"STD_LIBS: {os.environ.get('STD_LIBS', 'NOT SET')}")
    print(f"UVM_HOME: {os.environ.get('UVM_HOME', 'NOT SET')}")
    
    # Check DSIM executable
    dsim_exe = Path(dsim_home) / "bin" / "dsim.exe"
    if dsim_exe.exists():
        print(f"✅ DSIM Executable: {dsim_exe}")
    else:
        print(f"❌ DSIM Executable not found: {dsim_exe}")
        return False
    
    print("\\n✅ DSIM environment setup completed successfully!")
    return True

if __name__ == "__main__":
    success = setup_dsim_environment()
    sys.exit(0 if success else 1)