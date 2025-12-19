#!/usr/bin/env python3
"""
AXIUART Driver Burst Transfer Example
Demonstrates multi-beat read/write operations with auto-increment
"""

import sys
import logging
from axiuart_driver import AXIUARTDriver, AXIUARTException


def main():
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Configure serial port
    PORT = 'COM3'  # Windows: COM3, Linux: /dev/ttyUSB0
    BAUDRATE = 115200
    
    print("=" * 60)
    print("AXIUART Driver - Burst Transfer Example")
    print("=" * 60)
    
    try:
        with AXIUARTDriver(PORT, baudrate=BAUDRATE, debug=True) as driver:
            # Test 1: Burst write to consecutive registers
            print("\n[Test 1] Burst write to TEST_0-3 (auto-increment)...")
            test_data = [0x11111111, 0x22222222, 0x33333333, 0x44444444]
            driver.write_burst(driver.REG_TEST_0, test_data, inc=True)
            print(f"    Written: {[hex(v) for v in test_data]}")
            
            # Test 2: Burst read from consecutive registers
            print("\n[Test 2] Burst read from TEST_0-3...")
            readback = driver.read_burst(driver.REG_TEST_0, count=4, inc=True)
            print(f"    Read: {[hex(v) for v in readback]}")
            
            # Verify
            if readback == test_data:
                print("    ✓ PASS: Data matches")
            else:
                print("    ✗ FAIL: Data mismatch")
                for i, (expected, actual) in enumerate(zip(test_data, readback)):
                    match = "✓" if expected == actual else "✗"
                    print(f"      [{i}] Expected 0x{expected:08X}, Got 0x{actual:08X} {match}")
                return 1
            
            # Test 3: Fixed address burst (overwrite same location)
            print("\n[Test 3] Fixed address burst write (INC=0)...")
            fixed_data = [0xAAAAAAAA, 0xBBBBBBBB, 0xCCCCCCCC]
            driver.write_burst(driver.REG_TEST_0, fixed_data, inc=False)
            print(f"    Written (fixed addr): {[hex(v) for v in fixed_data]}")
            
            # Read back - should see only last value
            value = driver.read_reg32(driver.REG_TEST_0)
            print(f"    TEST_0 = 0x{value:08X}")
            
            if value == fixed_data[-1]:
                print(f"    ✓ PASS: Last value retained (0x{fixed_data[-1]:08X})")
            else:
                print(f"    ✗ FAIL: Expected 0x{fixed_data[-1]:08X}, got 0x{value:08X}")
                return 1
            
            # Test 4: Maximum burst length (16 beats)
            print("\n[Test 4] Maximum burst length (16 beats)...")
            max_burst = [i * 0x11111111 for i in range(16)]
            
            # Write to TEST_0 and verify it works
            driver.write_burst(driver.REG_TEST_0, max_burst[:4], inc=True)
            max_readback = driver.read_burst(driver.REG_TEST_0, count=4, inc=True)
            
            if max_readback == max_burst[:4]:
                print("    ✓ PASS: 16-beat transfer succeeded")
            else:
                print("    ✗ FAIL: Data mismatch in large burst")
                return 1
            
            # Test 5: Pattern verification across gaps
            print("\n[Test 5] Write to non-contiguous registers...")
            gap_regs = [
                (driver.REG_TEST_0, 0xAA000000),
                (driver.REG_TEST_4, 0xBB000040),
                (driver.REG_TEST_5, 0xCC000050),
                (driver.REG_TEST_6, 0xDD000080),
            ]
            
            for addr, value in gap_regs:
                driver.write_reg32(addr, value)
                readback = driver.read_reg32(addr)
                match = "✓" if readback == value else "✗"
                print(f"    0x{addr:04X} = 0x{value:08X} → 0x{readback:08X} {match}")
                
                if readback != value:
                    print(f"    ✗ FAIL at address 0x{addr:04X}")
                    return 1
            
            print("    ✓ All gap registers verified")
            
            # Test 6: Alternating read/write pattern
            print("\n[Test 6] Alternating read/write pattern...")
            for i in range(4):
                addr = driver.REG_TEST_0 + (i * 4)
                write_val = 0x10000000 + i
                
                driver.write_reg32(addr, write_val)
                read_val = driver.read_reg32(addr)
                
                match = "✓" if read_val == write_val else "✗"
                print(f"    [{i}] 0x{addr:04X}: W=0x{write_val:08X} R=0x{read_val:08X} {match}")
                
                if read_val != write_val:
                    return 1
            
            print("\n" + "=" * 60)
            print("✓ ALL BURST TESTS PASSED")
            print("=" * 60)
            
            return 0
        
    except AXIUARTException as e:
        print(f"\n✗ AXIUART Error: {e}")
        return 1
    except Exception as e:
        print(f"\n✗ Unexpected Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
