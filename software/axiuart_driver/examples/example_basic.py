#!/usr/bin/env python3
"""
Basic AXIUART Driver Usage Example
Demonstrates single register read/write operations
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
    
    # Configure serial port (adjust for your system)
    PORT = 'COM3'  # Linux: /dev/ttyUSB0, Windows: COM3/COM4
    BAUDRATE = 115200
    
    print("=" * 60)
    print("AXIUART Driver - Basic Example")
    print("=" * 60)
    
    try:
        # Create driver instance
        driver = AXIUARTDriver(PORT, baudrate=BAUDRATE, debug=True)
        
        # Open connection
        print(f"\n[1] Opening {PORT} at {BAUDRATE} baud...")
        driver.open()
        print("    ✓ Connected")
        
        # Read VERSION register
        print("\n[2] Reading VERSION register (0x101C)...")
        version = driver.get_version()
        print(f"    VERSION = 0x{version:08X}")
        
        # Read STATUS register
        print("\n[3] Reading STATUS register (0x1004)...")
        status = driver.get_status()
        print(f"    STATUS = 0x{status:08X}")
        
        # Write test pattern to TEST_0
        print("\n[4] Writing test pattern to TEST_0 (0x1020)...")
        test_value = 0xDEADBEEF
        driver.write_reg32(driver.REG_TEST_0, test_value)
        print(f"    Written: 0x{test_value:08X}")
        
        # Read back and verify
        print("\n[5] Reading back TEST_0...")
        readback = driver.read_reg32(driver.REG_TEST_0)
        print(f"    Read: 0x{readback:08X}")
        
        if readback == test_value:
            print("    ✓ PASS: Value matches")
        else:
            print(f"    ✗ FAIL: Expected 0x{test_value:08X}, got 0x{readback:08X}")
            return 1
        
        # Test multiple patterns
        print("\n[6] Testing multiple patterns...")
        test_patterns = [
            0x00000000,
            0xFFFFFFFF,
            0xAAAAAAAA,
            0x55555555,
            0x12345678,
        ]
        
        for i, pattern in enumerate(test_patterns, 1):
            driver.write_reg32(driver.REG_TEST_0, pattern)
            value = driver.read_reg32(driver.REG_TEST_0)
            
            match = "✓" if value == pattern else "✗"
            print(f"    [{i}/5] 0x{pattern:08X} → 0x{value:08X} {match}")
            
            if value != pattern:
                print(f"    ✗ FAIL at pattern {i}")
                return 1
        
        print("    ✓ All patterns verified")
        
        # Read counters
        print("\n[7] Reading transaction counters...")
        tx_count = driver.get_tx_count()
        rx_count = driver.get_rx_count()
        print(f"    TX_COUNT = {tx_count}")
        print(f"    RX_COUNT = {rx_count}")
        
        # Read FIFO status
        print("\n[8] Reading FIFO status...")
        fifo_stat = driver.get_fifo_status()
        print(f"    FIFO_STAT = 0x{fifo_stat:02X}")
        
        # Close connection
        print("\n[9] Closing connection...")
        driver.close()
        print("    ✓ Closed")
        
        print("\n" + "=" * 60)
        print("✓ ALL TESTS PASSED")
        print("=" * 60)
        
        return 0
        
    except AXIUARTException as e:
        print(f"\n✗ AXIUART Error: {e}")
        return 1
    except Exception as e:
        print(f"\n✗ Unexpected Error: {e}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
