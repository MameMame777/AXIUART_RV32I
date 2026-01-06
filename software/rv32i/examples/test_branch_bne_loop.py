#!/usr/bin/env python3
"""
BNE Loop Test - Debug branch instructions without LED
Tests a simple counting loop using BNE instruction
"""
import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

port = sys.argv[1] if len(sys.argv) > 1 else 'COM3'

print("="*70)
print("BNE Loop Test - Branch Instruction Debug")
print("="*70)

with AXIUARTDriver(port, 115200) as driver:
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
    from rv32i import reset_cpu, halt_cpu, run_cpu, get_cpu_status
    from rv32i.memory import write_cpu_mem, read_cpu_mem
    from rv32i.registers import read_cpu_register
    from rv32i.encoder import RV32IInstructionEncoder
    
    enc = RV32IInstructionEncoder()
    
    # CRITICAL: Always reset first
    print("\n1. Resetting CPU...")
    reset_cpu(driver)
    time.sleep(0.1)
    
    print("2. Halting CPU...")
    halt_cpu(driver)
    
    print("3. Loading BNE loop program...")
    print("   Program: Count from 0 to 4")
    print("   x10 = 0")
    print("   x11 = 4")
    print("   LOOP:")
    print("     x10++")
    print("     if (x10 != x11) goto LOOP")
    print("   EBREAK")
    
    program = [
        enc.addi(10, 0, 0),         # x10 = 0 (counter)
        enc.addi(11, 0, 4),         # x11 = 4 (target)
        # LOOP: (PC = 0x008)
        enc.addi(10, 10, 1),        # x10++ 
        enc.bne(10, 11, -4),        # if x10 != x11, goto LOOP (offset=-4 bytes)
        enc.ebreak(),               # EBREAK
    ]
    
    # Verify encoding (BNE with offset=-4 bytes should be 0xFEB51EE3)
    print(f"\nInstruction encoding verification:")
    print(f"  BNE x10, x11, -4 = 0x{program[3]:08X} (expected: 0xFEB51EE3)")
    
    for i, insn in enumerate(program):
        write_cpu_mem(driver, i * 4, insn)
    
    print(f"   Loaded {len(program)} instructions")
    
    print("\n4. Starting CPU...")
    run_cpu(driver)
    
    # Wait for EBREAK
    print("5. Waiting for CPU to complete...")
    for attempt in range(50):
        time.sleep(0.01)
        status = get_cpu_status(driver)
        if status.get('break_asserted', False):
            print("   ✓ EBREAK detected")
            break
    else:
        print("   ⚠ EBREAK not detected (timeout)")
    
    print("\n6. Reading results...")
    halt_cpu(driver)
    
    x10 = read_cpu_register(driver, 10)
    x11 = read_cpu_register(driver, 11)
    
    print(f"   x10 = {x10} (expected: 4)")
    print(f"   x11 = {x11} (expected: 4)")
    
    print("\n" + "="*70)
    if x10 == 4:
        print("✓ TEST PASSED: BNE loop executed correctly")
    else:
        print(f"✗ TEST FAILED: Counter is {x10}, expected 4")
    print("="*70)
