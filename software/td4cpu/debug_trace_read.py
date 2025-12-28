#!/usr/bin/env python3
"""Debug script to test trace buffer read"""
import sys
import logging

sys.path.insert(0, '..')

# Enable debug logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

from axiuart_driver import AXIUARTDriver, registers

def main():
    driver = AXIUARTDriver('COM3', 115200)
    
    try:
        driver.open()
        print("\n=== Testing Trace Buffer Read ===")
        print(f"Trace buffer base: 0x{registers.REG_CPU_TRACE_BASE:04X}")
        
        # Test reading first trace entry
        test_addr = 0x1300
        print(f"\nAttempting read at 0x{test_addr:04X}...")
        
        try:
            data = driver.read_reg32(test_addr)
            print(f"✓ SUCCESS: Read 0x{test_addr:04X} = 0x{data:08X}")
            instruction = (data >> 16) & 0xFFFF
            result = data & 0xFFFF
            print(f"  Instruction: 0x{instruction:04X}")
            print(f"  Result:      0x{result:04X}")
        except Exception as e:
            print(f"✗ FAILED: {e}")
            print(f"  Error type: {type(e).__name__}")
        
    finally:
        driver.close()

if __name__ == '__main__':
    main()
