#!/usr/bin/env python3
"""
Complex LED Pattern Test - Multi-Mode Animation

This script demonstrates a complex LED pattern that automatically cycles through
4 distinct animation modes:

Mode 0: Binary Counter (0→15)
  - Counts from 0 to 15 in binary
  - Each LED represents a bit position
  - 16 iterations total

Mode 1: Knight Rider Scan (1→2→4→8→4→2→1)
  - Single LED scans left-to-right, then right-to-left
  - Classic "Kitt" animation effect
  - 30 iterations total

Mode 2: Blink All LEDs (0xF ↔ 0x0)
  - All 4 LEDs flash on/off simultaneously
  - Slower timing for visibility
  - 20 iterations total

Mode 3: Alternating Pattern (0x5 ↔ 0xA)
  - LEDs alternate between 0101 and 1010 patterns
  - Creates checkerboard effect
  - 50 iterations total

The program runs continuously, cycling through all modes. Each pattern
iteration takes approximately 40ms @ 125MHz clock, making changes clearly
visible to the human eye.

Usage:
    python test_led_complex.py [COM_PORT]
    
Example:
    python test_led_complex.py COM3
"""
import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

port = sys.argv[1] if len(sys.argv) > 1 else 'COM3'

print("="*70)
print("COMPLEX LED PATTERN TEST - Multi-Mode Animation")
print("="*70)
print()
print("This program cycles through 4 LED animation modes:")
print("  Mode 0: Binary counter (0→15)")
print("  Mode 1: Knight Rider scan (1→2→4→8→4→2→1)")
print("  Mode 2: Blink all LEDs (on/off)")
print("  Mode 3: Alternating pattern (0101 ↔ 1010)")
print()
print("Each mode runs for approximately 2 seconds before transitioning.")
print("="*70)
print()

with AXIUARTDriver(port, 115200) as driver:
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
    from rv32i import halt_cpu, run_cpu, get_cpu_status, generate_led_complex_pattern
    from rv32i.memory import write_cpu_mem
    
    print("[1/4] Halting CPU...")
    halt_cpu(driver)
    status = get_cpu_status(driver)
    print(f"      Status: {status}")
    
    print()
    print("[2/4] Generating complex pattern program...")
    program = generate_led_complex_pattern(delay_cycles=5000000)
    print(f"      Generated {len(program)} instructions")
    print(f"      Program size: {len(program) * 4} bytes")
    
    print()
    print("[3/4] Loading program into CPU memory...")
    for i, insn in enumerate(program):
        write_cpu_mem(driver, i * 4, insn)
        if (i + 1) % 20 == 0:
            print(f"      Progress: {i+1}/{len(program)} instructions loaded...")
    print(f"      Loaded all {len(program)} instructions")
    
    print()
    print("[4/4] Starting CPU execution...")
    run_cpu(driver)
    
    print()
    print("="*70)
    print("CPU IS NOW RUNNING - OBSERVE THE LED PATTERNS!")
    print("="*70)
    print()
    print("Pattern Sequence (repeats continuously):")
    print()
    print("  [Mode 0] Binary Counter")
    print("    → Watch LEDs count 0000→1111 in binary")
    print("    → Duration: ~2 seconds (16 steps)")
    print()
    print("  [Mode 1] Knight Rider Scan")
    print("    → Single LED sweeps left-right-left")
    print("    → Duration: ~2 seconds (30 steps)")
    print()
    print("  [Mode 2] Blink All")
    print("    → All 4 LEDs flash on/off")
    print("    → Duration: ~2 seconds (20 steps)")
    print()
    print("  [Mode 3] Alternating")
    print("    → LEDs alternate 0101↔1010 pattern")
    print("    → Duration: ~2 seconds (50 steps)")
    print()
    print("="*70)
    print()
    print("The pattern will loop continuously. Watch your FPGA board!")
    print()
    print("Technical Details:")
    print(f"  - Program size: {len(program)} instructions ({len(program)*4} bytes)")
    print(f"  - LED MMIO address: 0x407C")
    print(f"  - Delay cycles per step: 5M cycles (~40ms @ 125MHz)")
    print(f"  - Total cycle time: ~8 seconds for all 4 modes")
    print()
    input("Press Enter when you want to stop the CPU...")
    
    print()
    print("Halting CPU...")
    halt_cpu(driver)
    
    print("Done! LED pattern stopped.")
