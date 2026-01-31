#!/usr/bin/env python3
"""
Quick test script for VexRiscv MCP tools
"""
import sys
from pathlib import Path

# Add mcp_server to path
sys.path.insert(0, str(Path(__file__).parent))

from dsim_fastmcp_server import (
    set_workspace_path,
    _classify_vexriscv_test,
    _parse_vexriscv_hex,
    _extract_tohost_value,
    _extract_cycle_count,
    _find_latest_mxd
)

def test_classify():
    print("Testing _classify_vexriscv_test:")
    tests = [
        ("rv32ui-p-add", "isa"),
        ("rv32ui-p-sub", "isa"),
        ("I-ADD-01", "compliance"),
        ("dhrystone", "benchmark"),
        ("custom_test", "custom")
    ]
    
    for test_name, expected in tests:
        result = _classify_vexriscv_test(test_name)
        status = "✓" if result == expected else "✗"
        print(f"  {status} {test_name:20s} -> {result:12s} (expected: {expected})")

def test_parse_hex():
    print("\nTesting _parse_vexriscv_hex:")
    workspace = Path(__file__).parent.parent
    hex_file = workspace / "vexriscv_reference" / "source" / "src" / "test" / "resources" / "hex" / "rv32ui-p-add.hex"
    
    if not hex_file.exists():
        print(f"  ✗ Hex file not found: {hex_file}")
        return
    
    try:
        result = _parse_vexriscv_hex(hex_file, address_offset=-0x80000000)
        print(f"  ✓ Parsed successfully")
        print(f"    Memory bytes: {len(result['memory_data'])}")
        print(f"    Memory words: {len(result['word_data'])}")
        print(f"    tohost addr:  0x{result['special_addresses']['tohost']:08X}")
        print(f"    fromhost addr: 0x{result['special_addresses']['fromhost']:08X}")
    except Exception as e:
        print(f"  ✗ Parse failed: {e}")

def test_extract_tohost():
    print("\nTesting _extract_tohost_value:")
    test_cases = [
        ("tohost = 0x00000001", 1),
        ("TEST PASSED tohost: 0x1", 1),
        ("tohost_value = 0x00000005", 5),
        ("TEST PASSED", 1),  # Default
        ("random output", 0),  # No match
    ]
    
    for output, expected in test_cases:
        result = _extract_tohost_value(output)
        status = "✓" if result == expected else "✗"
        print(f"  {status} '{output[:30]:30s}' -> {result} (expected: {expected})")

def test_extract_cycles():
    print("\nTesting _extract_cycle_count:")
    test_cases = [
        ("Test completed in 1234 cycles", 1234),
        ("cycle count: 567", 567),
        ("total cycles: 890", 890),
        ("no cycles here", 0),  # No match
    ]
    
    for output, expected in test_cases:
        result = _extract_cycle_count(output)
        status = "✓" if result == expected else "✗"
        print(f"  {status} '{output[:30]:30s}' -> {result} (expected: {expected})")

def test_list_tests():
    print("\nTesting list_vexriscv_tests (via file glob):")
    workspace = Path(__file__).parent.parent
    test_dir = workspace / "vexriscv_reference" / "source" / "src" / "test" / "resources" / "hex"
    
    if not test_dir.exists():
        print(f"  ✗ Test directory not found: {test_dir}")
        return
    
    # Count by category
    categories = {"isa": 0, "compliance": 0, "benchmark": 0, "custom": 0}
    
    for hex_file in test_dir.glob("*.hex"):
        category = _classify_vexriscv_test(hex_file.stem)
        categories[category] += 1
    
    print(f"  ✓ Test directory: {test_dir}")
    for cat, count in categories.items():
        if count > 0:
            print(f"    {cat:12s}: {count:3d} tests")

if __name__ == "__main__":
    print("=" * 60)
    print("VexRiscv MCP Tools Test Suite")
    print("=" * 60)
    
    # Set workspace
    workspace = Path(__file__).parent.parent
    set_workspace_path(str(workspace))
    
    test_classify()
    test_parse_hex()
    test_extract_tohost()
    test_extract_cycles()
    test_list_tests()
    
    print("\n" + "=" * 60)
    print("✓ All tests complete")
    print("=" * 60)
