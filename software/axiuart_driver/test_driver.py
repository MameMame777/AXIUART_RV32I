#!/usr/bin/env python3
"""
AXIUART Driver Test & Debug Script
Tests connection and basic register operations with deployed FPGA
"""

import sys
import time
import logging

# Add parent directory to path
sys.path.insert(0, '..')

from axiuart_driver import AXIUARTDriver, AXIUARTException

# Configuration
SERIAL_PORT = 'COM3'  # Change to your port (e.g., '/dev/ttyUSB0' on Linux)
BAUDRATE = 115200
DEBUG = True

def test_connection(driver):
    """Test basic connection and register access"""
    print("\n[TEST 1] Connection and Version Check")
    print("-" * 60)
    try:
        version = driver.read_reg32(driver.REG_VERSION)
        print(f"✓ VERSION register: 0x{version:08X}")
        return True
    except Exception as e:
        print(f"✗ Failed to read VERSION: {e}")
        return False

def test_status_registers(driver):
    """Test status register reads"""
    print("\n[TEST 2] Status Registers")
    print("-" * 60)
    try:
        status = driver.read_reg32(driver.REG_STATUS)
        print(f"✓ STATUS register: 0x{status:08X}")
        
        config = driver.read_reg32(driver.REG_CONFIG)
        print(f"✓ CONFIG register: 0x{config:08X}")
        
        return True
    except Exception as e:
        print(f"✗ Failed to read status: {e}")
        return False

def test_test_registers(driver):
    """Test read/write to test registers"""
    print("\n[TEST 3] Test Register Access (REG_TEST_0)")
    print("-" * 60)
    
    test_values = [0x12345678, 0xDEADBEEF, 0xCAFEBABE, 0x00000000, 0xFFFFFFFF]
    
    for i, test_val in enumerate(test_values, 1):
        try:
            # Write
            driver.write_reg32(driver.REG_TEST_0, test_val)
            print(f"  [{i}] Wrote: 0x{test_val:08X}")
            
            # Read back
            read_val = driver.read_reg32(driver.REG_TEST_0)
            print(f"      Read:  0x{read_val:08X}", end="")
            
            # Verify
            if read_val == test_val:
                print(" ✓ MATCH")
            else:
                print(f" ✗ MISMATCH (expected 0x{test_val:08X})")
                return False
                
        except Exception as e:
            print(f"✗ Test {i} failed: {e}")
            return False
    
    return True

def test_cpu_registers(driver):
    """Test CPU control register access"""
    print("\n[TEST 4] CPU Control Registers")
    print("-" * 60)
    
    try:
        revision = driver.read_reg32(driver.REG_REVISION)
        print(f"✓ REVISION: 0x{revision:08X}")
        
        ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
        print(f"✓ CPU_MEM_CTRL: 0x{ctrl:08X}")
        print(f"    - cpu_halted: {(ctrl >> 9) & 1}")
        print(f"    - cpu_break:  {(ctrl >> 10) & 1}")
        print(f"    - busy:       {(ctrl >> 6) & 1}")
        
        return True
    except Exception as e:
        print(f"✗ Failed to read CPU registers: {e}")
        return False

def test_burst_transfer(driver):
    """Test burst read/write operations"""
    print("\n[TEST 5] Burst Transfer")
    print("-" * 60)
    
    try:
        # Write burst of 4 values
        write_data = [0x11111111, 0x22222222, 0x33333333, 0x44444444]
        print(f"Writing burst: {[hex(v) for v in write_data]}")
        driver.write_burst(driver.REG_TEST_0, write_data)
        print("✓ Burst write completed")
        
        # Read burst back
        read_data = driver.read_burst(driver.REG_TEST_0, count=4)
        print(f"Read burst:    {[hex(v) for v in read_data]}")
        
        # Verify
        if read_data == write_data:
            print("✓ Burst data MATCH")
            return True
        else:
            print("✗ Burst data MISMATCH")
            return False
            
    except Exception as e:
        print(f"✗ Burst test failed: {e}")
        return False

def main():
    """Main test routine"""
    print("=" * 60)
    print("AXIUART Driver Test & Debug")
    print("=" * 60)
    print(f"Port: {SERIAL_PORT}")
    print(f"Baudrate: {BAUDRATE}")
    print(f"Debug: {DEBUG}")
    
    # Setup logging if debug enabled
    if DEBUG:
        logging.basicConfig(
            level=logging.DEBUG,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
    
    # Initialize driver
    driver = AXIUARTDriver(SERIAL_PORT, baudrate=BAUDRATE, debug=DEBUG)
    
    try:
        # Open connection
        print("\nOpening connection...")
        driver.open()
        print("✓ Connection established")
        
        # Run tests
        results = []
        results.append(("Connection & Version", test_connection(driver)))
        results.append(("Status Registers", test_status_registers(driver)))
        results.append(("Test Registers", test_test_registers(driver)))
        results.append(("CPU Registers", test_cpu_registers(driver)))
        results.append(("Burst Transfer", test_burst_transfer(driver)))
        
        # Summary
        print("\n" + "=" * 60)
        print("TEST SUMMARY")
        print("=" * 60)
        
        passed = 0
        failed = 0
        for name, result in results:
            status = "PASS" if result else "FAIL"
            symbol = "✓" if result else "✗"
            print(f"{symbol} {name:30s} [{status}]")
            if result:
                passed += 1
            else:
                failed += 1
        
        print("-" * 60)
        print(f"Total: {passed + failed}, Passed: {passed}, Failed: {failed}")
        
        if failed == 0:
            print("\n🎉 All tests PASSED!")
        else:
            print(f"\n⚠️  {failed} test(s) FAILED")
        
        return 0 if failed == 0 else 1
        
    except AXIUARTException as e:
        print(f"\n✗ Driver error: {e}")
        return 1
        
    except Exception as e:
        print(f"\n✗ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 1
        
    finally:
        # Close connection
        if driver.serial and driver.serial.is_open:
            driver.close()
            print("\nConnection closed")

if __name__ == "__main__":
    sys.exit(main())
