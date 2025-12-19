#!/usr/bin/env python3
"""
Simplified UVM Test Launcher via Existing MCP Infrastructure
Uses the working MCP client but points to simplified environment
"""

import sys
import subprocess
from pathlib import Path

def main():
    workspace = Path(r"e:\Nautilus\workspace\fpgawork\AXIUART_")
    mcp_client = workspace / "mcp_server" / "mcp_client.py"
    
    # Temporarily modify the environment to point to simplified paths
    # This is a workaround - the real solution is to update MCP server config
    
    print("=" * 70)
    print("簡素化UVM環境テストランチャー")
    print("注意: 現在は既存MCPインフラを使用（簡素化版パスは未対応）")
    print("=" * 70)
    print()
    print("[WORKAROUND] 既存環境でテストを実行します...")
    print()
    
    # Run using existing environment for now
    cmd = [
        sys.executable,
        str(mcp_client),
        "--workspace", str(workspace),
        "--tool", "run_uvm_simulation",
        "--test-name", "uart_axi4_basic_test",
        "--mode", "compile",
        "--verbosity", "UVM_LOW",
        "--timeout", "120"
    ]
    
    result = subprocess.run(cmd)
    
    if result.returncode == 0:
        print()
        print("=" * 70)
        print("次のステップ:")
        print("1. sim/uvm/の構造を確認")
        print("2. MCPサーバーに簡素化版設定パスを追加")
        print("3. 簡素化版専用のMCPツールを実装")
        print("=" * 70)
    
    return result.returncode

if __name__ == "__main__":
    sys.exit(main())
