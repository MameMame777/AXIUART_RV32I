#!/usr/bin/env python3
"""
Simple UART Connection Test
Tests basic UART communication without CPU access
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

port = sys.argv[1] if len(sys.argv) > 1 else 'COM3'

print("="*60)
print("UART Connection Test")
print("="*60)
print(f"Port: {port}")
print()
print("INSTRUCTIONS:")
print("1. Check FPGA board - is it powered on?")
print("2. Check RESET button - is it released (NOT pressed)?")
print("3. If reset button was pressed, release it and wait 1 second")
print()
input("Press Enter when ready to test UART connection...")

try:
    from axiuart_driver import AXIUARTDriver
    
    print("\nOpening UART port...")
    with AXIUARTDriver(port, 115200, timeout=2.0) as driver:
        print("✓ UART port opened")
        
        print("\nTesting register read (STATUS register)...")
        try:
            status = driver.read_reg32(0x1004)  # STATUS register
            print(f"✓ Register read successful: 0x{status:08x}")
            print()
            print("="*60)
            print("SUCCESS - UART Communication Working!")
            print("="*60)
            print()
            print("Now you can run LED test:")
            print("  python test_led_simple.py COM3")
            
        except Exception as e:
            print(f"✗ Register read failed: {e}")
            print()
            print("="*60)
            print("DIAGNOSIS: UART opens but no response")
            print("="*60)
            print()
            print("Possible causes:")
            print("  1. FPGA is in RESET (button pressed or stuck)")
            print("  2. FPGA not programmed with correct bitstream")
            print("  3. Wrong COM port")
            print()
            print("SOLUTION:")
            print("  1. Press and RELEASE reset button once")
            print("  2. Wait 1 second")
            print("  3. Run this script again")

except Exception as e:
    print(f"✗ Failed to open UART port: {e}")
    print()
    print("Possible causes:")
    print("  1. Wrong COM port (try COM4, COM5, etc.)")
    print("  2. USB cable disconnected")
    print("  3. FPGA board not powered")
    print("  4. Another program using the port")
