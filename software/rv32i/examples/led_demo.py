#!/usr/bin/env python3
"""RV32I LED Control Demo

Interactive command-line tool for controlling FPGA LEDs via UART-AXI bridge.
Demonstrates RV32I instruction generation, CPU control, and pattern execution.

Usage:
    python led_demo.py --port COM3 --pattern simple
    python led_demo.py --port /dev/ttyUSB0 --pattern counter
    python led_demo.py --port COM3 --pattern blink

Patterns:
    simple  - Toggle between 0x5 and 0xA (no loop, stops at EBREAK)
    counter - Binary counter 0→15 (infinite loop)
    blink   - Knight rider shift 1→2→4→8→1 (infinite loop)
"""

import sys
import os
import argparse
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


# Performance counter registers
PERF_CYCLE_COUNT = 0x1260
PERF_INSN_COUNT = 0x1264


def main():
    parser = argparse.ArgumentParser(
        description='RV32I LED Control Demo',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument('--port', required=True, help='Serial port (e.g., COM3, /dev/ttyUSB0)')
    parser.add_argument('--baud', type=int, default=115200, help='Baud rate (default: 115200)')
    parser.add_argument('--pattern', required=True, 
                       choices=['simple', 'counter', 'blink'],
                       help='LED pattern to execute')
    
    args = parser.parse_args()
    
    # Generate pattern
    print(f"[PATTERN] Generating '{args.pattern}' pattern...")
    if args.pattern == 'simple':
        program = generate_led_simple(value1=0x5, value2=0xA)
        print(f"[PATTERN] Simple toggle: 0x5 (0b0101) ↔ 0xA (0b1010)")
        print(f"[PATTERN] Program: {len(program)} instructions (stops at EBREAK)")
    elif args.pattern == 'counter':
        program = generate_led_count(start=0, end=15, delay_cycles=5000000)
        print(f"[PATTERN] Binary counter: 0→1→2→...→15→0 (infinite loop)")
        print(f"[PATTERN] Program: {len(program)} instructions")
    elif args.pattern == 'blink':
        program = generate_led_knight_rider()
        print(f"[PATTERN] Knight rider: 1→2→4→8→1 (infinite loop)")
        print(f"[PATTERN] Program: {len(program)} instructions")
    
    # Connect to FPGA
    print(f"\n[UART] Connecting to {args.port} at {args.baud} baud...")
    try:
        with AXIUARTDriver(args.port, args.baud) as driver:
            print("[UART] ✓ Connected")
            
            # Halt CPU
            print("\n[CPU] Halting...")
            halt_cpu(driver)
            status = get_cpu_status(driver)
            if status['halted']:
                print("[CPU] ✓ Halted")
            else:
                print("[CPU] ✗ Failed to halt")
                return 1
            
            # Write program
            print(f"\n[MEM] Writing {len(program)} instructions to address 0x0000...")
            write_program(driver, program, start_addr=0)
            print("[MEM] ✓ Program loaded")
            
            # Run CPU
            print("\n[CPU] Starting execution...")
            run_cpu(driver)
            print("[CPU] ✓ Running - Watch the LEDs!")
            
            # Monitor performance counters
            if args.pattern == 'simple':
                print("\n[INFO] Simple pattern stops at EBREAK. Press Ctrl+C to exit.")
                time.sleep(2)
                status = get_cpu_status(driver)
                cycles = driver.read_reg32(PERF_CYCLE_COUNT)
                insns = driver.read_reg32(PERF_INSN_COUNT)
                print(f"[PERF] Cycles: {cycles} | Instructions: {insns}")
                if status['break']:
                    print("[CPU] ✓ Hit EBREAK as expected")
            else:
                print("\n[INFO] Infinite loop running. Press Ctrl+C to stop...")
                try:
                    while True:
                        time.sleep(5)
                        cycles = driver.read_reg32(PERF_CYCLE_COUNT)
                        insns = driver.read_reg32(PERF_INSN_COUNT)
                        print(f"[PERF] Cycles: {cycles:,} | Instructions: {insns:,}")
                except KeyboardInterrupt:
                    print("\n[USER] Ctrl+C detected")
                    halt_cpu(driver)
                    print("[CPU] ✓ Halted")
            
            print("\n[DONE] Demo complete!")
            return 0
            
    except Exception as e:
        print(f"\n[ERROR] {type(e).__name__}: {e}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
