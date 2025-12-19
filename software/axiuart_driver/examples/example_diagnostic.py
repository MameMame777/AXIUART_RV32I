#!/usr/bin/env python3
"""
AXIUART Driver Diagnostic Tool
Comprehensive register map testing and status reporting
"""

import sys
import time
import logging
from axiuart_driver import AXIUARTDriver, AXIUARTException, StatusCode


def print_register_map(driver: AXIUARTDriver):
    """Print complete register map with current values"""
    print("\n" + "=" * 80)
    print("REGISTER MAP")
    print("=" * 80)
    print(f"{'Address':<12} {'Name':<16} {'Value':<12} {'Access':<8} {'Status'}")
    print("-" * 80)
    
    # Define register map
    registers = [
        (driver.REG_CONTROL, "CONTROL", "RW"),
        (driver.REG_STATUS, "STATUS", "RO"),
        (driver.REG_CONFIG, "CONFIG", "RW"),
        (driver.REG_DEBUG, "DEBUG", "RW"),
        (driver.REG_TX_COUNT, "TX_COUNT", "RO"),
        (driver.REG_RX_COUNT, "RX_COUNT", "RO"),
        (driver.REG_FIFO_STAT, "FIFO_STAT", "RO"),
        (driver.REG_VERSION, "VERSION", "RO"),
        (driver.REG_TEST_0, "TEST_0", "RW"),
        (driver.REG_TEST_1, "TEST_1", "RW"),
        (driver.REG_TEST_2, "TEST_2", "RW"),
        (driver.REG_TEST_3, "TEST_3", "RW"),
        (driver.REG_TEST_4, "TEST_4", "RW"),
        (driver.REG_TEST_5, "TEST_5", "RW"),
        (driver.REG_TEST_6, "TEST_6", "RW"),
        (driver.REG_TEST_7, "TEST_7", "RW"),
    ]
    
    for addr, name, access in registers:
        try:
            value = driver.read_reg32(addr)
            print(f"0x{addr:08X}  {name:<16} 0x{value:08X}  {access:<8} ✓")
        except AXIUARTException as e:
            print(f"0x{addr:08X}  {name:<16} {'ERROR':<12} {access:<8} ✗ {e}")
    
    print("=" * 80)


def test_read_write(driver: AXIUARTDriver):
    """Test read/write functionality on all RW registers"""
    print("\n" + "=" * 80)
    print("READ/WRITE TEST")
    print("=" * 80)
    
    rw_registers = [
        (driver.REG_CONTROL, "CONTROL"),
        (driver.REG_CONFIG, "CONFIG"),
        (driver.REG_DEBUG, "DEBUG"),
        (driver.REG_TEST_0, "TEST_0"),
        (driver.REG_TEST_1, "TEST_1"),
        (driver.REG_TEST_2, "TEST_2"),
        (driver.REG_TEST_3, "TEST_3"),
        (driver.REG_TEST_4, "TEST_4"),
        (driver.REG_TEST_5, "TEST_5"),
        (driver.REG_TEST_6, "TEST_6"),
        (driver.REG_TEST_7, "TEST_7"),
    ]
    
    test_patterns = [0x00000000, 0xFFFFFFFF, 0xAAAAAAAA, 0x55555555]
    
    all_passed = True
    
    for addr, name in rw_registers:
        print(f"\nTesting {name} (0x{addr:08X})...")
        
        # Save original value
        try:
            original = driver.read_reg32(addr)
        except:
            original = None
        
        # Test patterns
        for pattern in test_patterns:
            try:
                driver.write_reg32(addr, pattern)
                readback = driver.read_reg32(addr)
                
                if readback == pattern:
                    print(f"  0x{pattern:08X} → 0x{readback:08X} ✓")
                else:
                    print(f"  0x{pattern:08X} → 0x{readback:08X} ✗ MISMATCH")
                    all_passed = False
            except AXIUARTException as e:
                print(f"  0x{pattern:08X} → ERROR: {e}")
                all_passed = False
        
        # Restore original value
        if original is not None:
            try:
                driver.write_reg32(addr, original)
            except:
                pass
    
    print("\n" + "-" * 80)
    if all_passed:
        print("✓ ALL READ/WRITE TESTS PASSED")
    else:
        print("✗ SOME READ/WRITE TESTS FAILED")
    print("=" * 80)
    
    return all_passed


def test_burst_operations(driver: AXIUARTDriver):
    """Test burst read/write operations"""
    print("\n" + "=" * 80)
    print("BURST OPERATION TEST")
    print("=" * 80)
    
    # Test burst to TEST_0-3 (contiguous)
    print("\nTest 1: Burst write/read TEST_0-3 (4 registers)...")
    burst_data = [0x11111111, 0x22222222, 0x33333333, 0x44444444]
    
    try:
        driver.write_burst(driver.REG_TEST_0, burst_data, inc=True)
        readback = driver.read_burst(driver.REG_TEST_0, count=4, inc=True)
        
        if readback == burst_data:
            print("  ✓ Burst operation successful")
            for i, (w, r) in enumerate(zip(burst_data, readback)):
                print(f"    [{i}] W=0x{w:08X} R=0x{r:08X}")
            result1 = True
        else:
            print("  ✗ Burst data mismatch")
            result1 = False
    except AXIUARTException as e:
        print(f"  ✗ Burst operation failed: {e}")
        result1 = False
    
    print("\n" + "-" * 80)
    if result1:
        print("✓ BURST TEST PASSED")
    else:
        print("✗ BURST TEST FAILED")
    print("=" * 80)
    
    return result1


def main():
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    
    # Configure serial port
    PORT = 'COM3'  # Windows: COM3, Linux: /dev/ttyUSB0
    BAUDRATE = 115200
    
    print("\n" + "=" * 80)
    print("AXIUART DIAGNOSTIC TOOL")
    print("=" * 80)
    print(f"Port: {PORT}")
    print(f"Baudrate: {BAUDRATE}")
    print("=" * 80)
    
    try:
        # Connect to device
        print("\nConnecting to device...")
        driver = AXIUARTDriver(PORT, baudrate=BAUDRATE, debug=False)
        driver.open()
        print("✓ Connected")
        
        # Print register map
        print_register_map(driver)
        
        # Wait for user
        input("\nPress Enter to continue with read/write tests...")
        
        # Test read/write
        rw_result = test_read_write(driver)
        
        # Wait for user
        input("\nPress Enter to continue with burst tests...")
        
        # Test burst operations
        burst_result = test_burst_operations(driver)
        
        # Final statistics
        print("\n" + "=" * 80)
        print("FINAL STATISTICS")
        print("=" * 80)
        
        tx_count = driver.get_tx_count()
        rx_count = driver.get_rx_count()
        status = driver.get_status()
        
        print(f"TX Transactions: {tx_count}")
        print(f"RX Transactions: {rx_count}")
        print(f"Status Register: 0x{status:08X}")
        
        # Close connection
        print("\nClosing connection...")
        driver.close()
        print("✓ Closed")
        
        # Summary
        print("\n" + "=" * 80)
        print("DIAGNOSTIC SUMMARY")
        print("=" * 80)
        print(f"Register Map:      ✓")
        print(f"Read/Write Test:   {'✓ PASS' if rw_result else '✗ FAIL'}")
        print(f"Burst Test:        {'✓ PASS' if burst_result else '✗ FAIL'}")
        print("=" * 80)
        
        if rw_result and burst_result:
            print("\n✓ ALL DIAGNOSTICS PASSED")
            return 0
        else:
            print("\n✗ SOME DIAGNOSTICS FAILED")
            return 1
        
    except AXIUARTException as e:
        print(f"\n✗ AXIUART Error: {e}")
        return 1
    except KeyboardInterrupt:
        print("\n\nDiagnostic interrupted by user")
        return 1
    except Exception as e:
        print(f"\n✗ Unexpected Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
