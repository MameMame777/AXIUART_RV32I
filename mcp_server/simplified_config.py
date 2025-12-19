#!/usr/bin/env python3
"""
Simplified UVM Environment Configuration
Maps MCP server to use sim/uvm_simplified instead of sim/uvm
"""

import os
from pathlib import Path

# Simplified UVM directories
SIMPLIFIED_UVM_ROOT = "sim/uvm"
SIMPLIFIED_TB_DIR = f"{SIMPLIFIED_UVM_ROOT}/tb"
SIMPLIFIED_SV_DIR = f"{SIMPLIFIED_UVM_ROOT}/sv"

# DSIM configuration for simplified environment
SIMPLIFIED_CONFIG = {
    "uvm_dir": SIMPLIFIED_UVM_ROOT,
    "tb_dir": SIMPLIFIED_TB_DIR,
    "sv_dir": SIMPLIFIED_SV_DIR,
    "config_file": f"{SIMPLIFIED_TB_DIR}/dsim_config.f",
    "top_module": "axiuart_tb_top",
    "default_test": "axiuart_basic_test",
    "work_dir": SIMPLIFIED_TB_DIR,
}

def get_simplified_paths(workspace: Path) -> dict:
    """Get absolute paths for simplified UVM environment"""
    return {
        "uvm_root": workspace / SIMPLIFIED_UVM_ROOT,
        "tb_dir": workspace / SIMPLIFIED_TB_DIR,
        "sv_dir": workspace / SIMPLIFIED_SV_DIR,
        "config_file": workspace / SIMPLIFIED_TB_DIR / "dsim_config.f",
        "work_dir": workspace / SIMPLIFIED_TB_DIR,
        "log_dir": workspace / "sim" / "exec" / "logs",
    }

def validate_simplified_env(workspace: Path) -> tuple[bool, str]:
    """Validate simplified environment exists"""
    paths = get_simplified_paths(workspace)
    
    if not paths["uvm_root"].exists():
        return False, f"Simplified UVM root not found: {paths['uvm_root']}"
    
    if not paths["config_file"].exists():
        return False, f"Config file not found: {paths['config_file']}"
    
    if not paths["sv_dir"].exists():
        return False, f"SV directory not found: {paths['sv_dir']}"
    
    return True, "Simplified environment validated"

def setup_dsim_environment() -> dict:
    """Setup DSIM environment variables for simplified UVM"""
    dsim_root = r"C:\Program Files\Altair\DSim\2025.1"
    
    env_vars = {
        'DSIM_HOME': dsim_root,
        'DSIM_ROOT': dsim_root,
        'DSIM_LIB_PATH': os.path.join(dsim_root, "lib"),
        'DSIM_LICENSE': os.path.join(dsim_root, "dsim-license.json"),
    }
    
    # Update current environment
    os.environ.update(env_vars)
    
    # Add DSIM bin to PATH for DLL resolution
    dsim_bin = os.path.join(dsim_root, "bin")
    if dsim_bin not in os.environ['PATH']:
        os.environ['PATH'] = dsim_bin + os.pathsep + os.environ['PATH']
    
    return env_vars

def get_dsim_executable() -> str:
    """Get full path to DSIM executable"""
    dsim_root = os.environ.get('DSIM_HOME', r"C:\Program Files\Altair\DSim\2025.1")
    return os.path.join(dsim_root, "bin", "dsim.exe")
