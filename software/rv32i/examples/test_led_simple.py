#!/usr/bin/env python3
"""
Simple LED Test - Just load program and observe LEDs
Do not read back memory while CPU is running
"""
import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

port = sys.argv[1] if len(sys.argv) > 1 else 'COM3'

print("="*60)
print("Simple LED Test - Load and Run")
print("="*60)

with AXIUARTDriver(port, 115200) as driver:
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
    from rv32i import halt_cpu, run_cpu, get_cpu_status
    from rv32i.memory import write_cpu_mem
    from rv32i.encoder import RV32IInstructionEncoder
    
    enc = RV32IInstructionEncoder()
    
    print("\n1. Halting CPU...")
    halt_cpu(driver)
    
    print("2. Loading program...")
    # Simpler program: just write to LED and loop
    program = [
        enc.lui(15, 0x4),           # x15 = 0x4000
        enc.addi(16, 15, 0x7C),     # x16 = 0x407C (LED address)
        enc.addi(17, 0, 0xF),       # x17 = 15 (all LEDs)
        enc.sw(17, 16, 0),          # MEM[0x407C] = 0xF
        enc.jal(0, -4),             # Loop: jump to SW instruction
    ]
    
    for i, insn in enumerate(program):
        write_cpu_mem(driver, i * 4, insn)
    
    print(f"   Loaded {len(program)} instructions")
    
    print("3. Starting CPU...")
    run_cpu(driver)
    
    print("\n" + "="*60)
    print("CPU IS NOW RUNNING")
    print("="*60)
    print()
    print("Check the FPGA board:")
    print("  → Are ALL 4 LEDs ON?")
    print()
    print("If YES: CPU is writing to LED successfully!")
    print("If NO:  There's an issue with MMIO or CPU execution")
    print()
    input("Press Enter when ready to stop CPU...")
    
    print("\nHalting CPU...")
    halt_cpu(driver)
    
    print("Done")
