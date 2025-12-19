#!/usr/bin/env python3
"""Test run_uvm_simulation return value format"""

import asyncio
import sys
from pathlib import Path

# Setup path
sys.path.insert(0, str(Path(__file__).parent))

# Import and configure
from dsim_uvm_server import run_uvm_simulation
import dsim_uvm_server

dsim_uvm_server.workspace_root = Path(__file__).parent.parent

async def test_minimal():
    result = await run_uvm_simulation(
        test_name="uart_axi4_minimal_test",
        mode="run",
        verbosity="UVM_DEBUG",
        timeout=60,
        waves=False,
        coverage=False
    )
    
    print(f"\n{'='*80}")
    print("RESULT TYPE:", type(result))
    print(f"{'='*80}")
    print("RESULT CONTENT (FULL JSON):")
    
    # Pretty print JSON
    import json
    try:
        result_json = json.loads(result)
        print(json.dumps(result_json, indent=2))
    except:
        print(result)
    
    print(f"{'='*80}")
    print("\nCHECKS:")
    print(f"  Contains '$finish': {'$finish' in result}")
    print(f"  Contains 'UVM_ERROR': {'UVM_ERROR' in result}")
    print(f"  Contains 'TEST PASSED': {'TEST PASSED' in result}")
    print(f"  Contains 'terminated after specified run time': {'Simulation terminated after specified run time' in result}")

if __name__ == "__main__":
    asyncio.run(test_minimal())
