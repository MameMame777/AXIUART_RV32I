#!/usr/bin/env python3
"""
Minimal CPU Test - Verify CPU Execution
Tests if CPU can execute even a single instruction

"""
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from axiuart_driver import AXIUARTDriver

port = sys.argv[1] if len(sys.argv) > 1 else 'COM3'

print("="*60)
print("MINIMAL CPU EXECUTION TEST")
print("="*60)

with AXIUARTDriver(port, 115200) as driver:
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
    from rv32i import halt_cpu, run_cpu, get_cpu_status
    from rv32i.memory import write_cpu_mem, read_cpu_mem
    from rv32i.encoder import RV32IInstructionEncoder
    
    enc = RV32IInstructionEncoder()
    
    # Test 1: Verify memory write/read
    print("\n[TEST 1] Memory Write/Read")
    halt_cpu(driver)
    
    test_val = 0xDEADBEEF
    print(f"  Writing 0x{test_val:08x} to address 0x0...")
    write_cpu_mem(driver, 0x0, test_val)
    
    readback = read_cpu_mem(driver, 0x0)
    print(f"  Readback: 0x{readback:08x}")
    if readback == test_val:
        print("  ✓ Memory access works!")
    else:
        print("  ✗ Memory access FAILED!")
        sys.exit(1)
    
    # Test 2: Load simplest possible program
    print("\n[TEST 2] Load Simple Program")
    # Program: LUI x15, 0x4 -> LUI x15, 0x8 -> EBREAK
    # This doesn't touch LED at all, just tests CPU execution
    program = [
        enc.lui(15, 0x4),      # x15 = 0x4000
        enc.lui(15, 0x8),      # x15 = 0x8000 (overwrite)
        enc.ebreak()           # Stop
    ]
    
    for i, insn in enumerate(program):
        addr = i * 4
        print(f"  Writing instruction {i}: 0x{insn:08x} to 0x{addr:04x}")
        write_cpu_mem(driver, addr, insn)
    
    # Verify
    print("\n  Verifying program...")
    for i in range(len(program)):
        addr = i * 4
        readback = read_cpu_mem(driver, addr)
        if readback == program[i]:
            print(f"    [√] 0x{addr:04x}: 0x{readback:08x}")
        else:
            print(f"    [X] 0x{addr:04x}: wrote 0x{program[i]:08x}, read 0x{readback:08x}")
    
    # Test 3: Run CPU and check if it stops at EBREAK
    print("\n[TEST 3] Run CPU")
    status = get_cpu_status(driver)
    print(f"  Before run: halted={status['halted']}, break={status['break']}")
    
    print("  Starting CPU...")
    run_cpu(driver)
    
    import time
    time.sleep(0.5)
    
    status = get_cpu_status(driver)
    print(f"  After 0.5s: halted={status['halted']}, break={status['break']}")
    
    if status['break']:
        print("  ✓ CPU executed and hit EBREAK!")
    else:
        print("  ✗ CPU did NOT hit EBREAK")
        print("  Possible issues:")
        print("    - CPU not executing")
        print("    - PC not advancing")
        print("    - EBREAK not working")
    
    # Test 4: Try LED write
    print("\n[TEST 4] LED Write via CPU Program")
    halt_cpu(driver)
    
    # Simplest LED program
    led_program = [
        enc.lui(15, 0x4),        # x15 = 0x4000
        enc.addi(16, 15, 0x7C),  # x16 = x15 + 0x7C = 0x407C
        enc.addi(17, 0, 0xF),    # x17 = 15 (all LEDs on)
        enc.sw(17, 16, 0),       # MEM[x16] = x17 -> LED = 0xF
        enc.ebreak()
    ]
    
    print("  Loading LED program...")
    for i, insn in enumerate(led_program):
        write_cpu_mem(driver, i * 4, insn)
    
    print("  Starting CPU...")
    run_cpu(driver)
    time.sleep(1)
    
    status = get_cpu_status(driver)
    print(f"  Status: halted={status['halted']}, break={status['break']}")
    print("  Check LEDs - Are ALL 4 LEDs on (0b1111)?")
    
    response = input("  Are LEDs ON? (y/n): ").strip().lower()
    if response == 'y':
        print("  ✓ LED control works!")
    else:
        print("  ✗ LED control does NOT work")
        print("  This means CPU is executing but LED write is not working")

print("\n" + "="*60)
print("TEST COMPLETE")
print("="*60)
