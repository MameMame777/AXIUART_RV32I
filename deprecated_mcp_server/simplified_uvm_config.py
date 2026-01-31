"""
Simplified UVM Environment Configuration for MCP Server
Maps simplified testbench paths for DSIM execution
"""

from pathlib import Path

def get_simplified_config(workspace_root: Path) -> dict:
    """
    Get configuration for simplified UVM environment
    
    Args:
        workspace_root: Workspace root directory path
        
    Returns:
        Configuration dictionary for simplified environment
    """
    sim_dir = workspace_root / "sim" / "uvm"
    
    return {
        "name": "AXIUART Simplified UVM",
        "version": "1.0-UBUS",
        "sim_root": str(sim_dir),
        "config_file": str(sim_dir / "tb" / "dsim_config.f"),
        "log_dir": str(sim_dir / "logs"),
        "test_dir": str(sim_dir / "tb"),
        "top_module": "axiuart_tb_top",
        "work_lib": "work",
        "available_tests": [
            "axiuart_basic_test"
        ],
        "default_verbosity": "UVM_MEDIUM",
        "uvm_version": "1.2",
        "timescale": "1ns/1ps"
    }
