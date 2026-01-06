#!/usr/bin/env python3
"""RV32I LED Control Demo - Simplified Version

Tests LED pattern execution without performance counter monitoring.

Usage:
    python led_demo_simple.py COM3 simple
    python led_demo_simple.py COM3 counter
    python led_demo_simple.py COM3 blink
"""

import sys
import os
import time

# Add parent directories to path for imports
script_dir = os.path.dirname(os.path.abspath(__file__))
rv32i_dir = os.path.dirname(script_dir)
software_dir = os.path.dirname(rv32i_dir)
sys.path.insert(0, software_dir)

from axiuart_driver import AXIUARTDriver

# Import rv32i package modules
sys.path.insert(0, rv32i_dir)
from rv32i import (
    halt_cpu, run_cpu, write_program, get_cpu_status,
    generate_led_simple, generate_led_blink, generate_led_count,
    generate_led_knight_rider
)


def main():
    if len(sys.argv) < 3:
        print("Usage: python led_demo_simple.py <port> <pattern>")
        print("  port: COM3, COM1, /dev/ttyUSB0, etc.")
        print("  pattern: simple, counter, blink")
        return 1
    
    port = sys.argv[1]
    pattern = sys.argv[2]
    
    # Generate pattern
    print(f"[PATTERN] Generating '{pattern}' pattern...")
    if pattern == 'simple':
        program = generate_led_simple(value1=0x5, value2=0xA)
        print(f"  Simple toggle: 0x5 (0b0101) <-> 0xA (0b1010)")
        print(f"  {len(program)} instructions (stops at EBREAK)")
    elif pattern == 'counter':
        program = generate_led_count(start=0, end=15, delay_cycles=5000000)
        print(f"  Binary counter: 0->15 (infinite loop)")
        print(f"  {len(program)} instructions")
    elif pattern == 'blink':
        program = generate_led_knight_rider()
        print(f"  Knight rider: 1->2->4->8->1 (infinite loop)")
        print(f"  {len(program)} instructions")
    else:
        print(f"[ERROR] Unknown pattern: {pattern}")
        return 1
    
    # Show first few instructions
    print(f"\n[CODE] First 4 instructions:")
    for i in range(min(4, len(program))):
        print(f"  0x{i*4:08x}: 0x{program[i]:08x}")
    
    # Connect to FPGA
    print(f"\n[UART] Connecting to {port} at 115200 baud...")
    try:
        with AXIUARTDriver(port, 115200) as driver:
            print("[UART] Connected OK")
            
            # Halt CPU
            print("\n[CPU] Halting...")
            halt_cpu(driver)
            status = get_cpu_status(driver)
            if status['halted']:
                print("[CPU] Halted OK")
            else:
                print("[CPU] FAILED to halt")
                return 1
            
            # Write program
            print(f"\n[MEM] Writing {len(program)} instructions...")
            write_program(driver, program, start_addr=0)
            print("[MEM] Program loaded OK")
            
            # Verify first instruction
            from rv32i.memory import read_cpu_mem
            verify = read_cpu_mem(driver, 0x0)
            print(f"[MEM] Verify addr 0x0: wrote 0x{program[0]:08x}, read 0x{verify:08x}")
            if verify == program[0]:
                print("[MEM] Verification PASS")
            else:
                print("[MEM] Verification FAIL!")
            
            # Run CPU
            print("\n[CPU] Starting execution - WATCH LEDs!")
            run_cpu(driver)
            print("[CPU] Running")
            
            # Wait and monitor status
            if pattern == 'simple':
                print("\n[INFO] Simple pattern stops at EBREAK. Waiting 2 seconds...")
                time.sleep(2)
                status = get_cpu_status(driver)
                print(f"[CPU] Status: halted={status['halted']}, break={status['break']}")
                if status['break']:
                    print("[CPU] Hit EBREAK - SUCCESS!")
            else:
                print("\n[INFO] Infinite loop. Press Ctrl+C to stop...")
                try:
                    while True:
                        time.sleep(5)
                        status = get_cpu_status(driver)
                        print(f"[CPU] Status: halted={status['halted']}, break={status['break']}")
                except KeyboardInterrupt:
                    print("\n[USER] Ctrl+C - Halting CPU...")
                    halt_cpu(driver)
                    print("[CPU] Halted")
            
            print("\n[DONE] Test complete!")
            return 0
            
    except Exception as e:
        print(f"\n[ERROR] {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
