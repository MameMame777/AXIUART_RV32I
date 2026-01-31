#!/usr/bin/env python3
"""
Direct test runner for simplified UVM environment via subprocess
"""
import sys
import subprocess
from pathlib import Path

def main():
    workspace = Path("e:/Nautilus/workspace/fpgawork/AXIUART_")
    mcp_client = workspace / "mcp_server" / "mcp_client.py"
    
    print("=" * 60)
    print("Simplified UVM Test - MCP Client Invocation")
    print("=" * 60)
    
    # Note: use_simplified parameter requires server restart
    # For now, manually invoke with simplified-specific config
    
    cmd = [
        sys.executable,
        str(mcp_client),
        "--workspace", str(workspace),
        "--tool", "run_uvm_simulation", 
        "--test-name", "axiuart_basic_test",
        "--mode", "compile",
        "--verbosity", "UVM_MEDIUM",
        "--timeout", "120",
        "--use-simplified"  # Add this flag
    ]
    
    print(f"\nExecuting: {' '.join(cmd)}\n")
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    print(result.stdout)
    if result.stderr:
        print("STDERR:", result.stderr, file=sys.stderr)
    
    return result.returncode

if __name__ == "__main__":
    sys.exit(main())
