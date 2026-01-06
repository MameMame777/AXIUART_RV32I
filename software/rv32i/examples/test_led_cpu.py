#!/usr/bin/env python3
"""
Test LED Control via RV32I CPU Execution
Uses same RV32I instructions as DSIM simulation
"""
import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

port = sys.argv[1] if len(sys.argv) > 1 else 'COM3'

print("="*60)
print("RV32I CPU LED Control Test")
print("Using same instructions as DSIM simulation")
print("="*60)

with AXIUARTDriver(port, 115200) as driver:
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
    from rv32i import halt_cpu, run_cpu, get_cpu_status
    from rv32i.memory import write_cpu_mem, read_cpu_mem
    from rv32i.encoder import RV32IInstructionEncoder
    
    enc = RV32IInstructionEncoder()
    
    print("\n[STEP 1] Halt CPU and load LED control program")
    halt_cpu(driver)
    
    # RV32I program to write 0xF to LED address 0x407C
    # Same instruction format as DSIM simulation
    program = [
        # x15 = 0x4000 (base address)
        enc.lui(15, 0x4),           # 0x00: x15 = 0x4000
        
        # x16 = 0x407C (LED MMIO address)
        enc.addi(16, 15, 0x7C),     # 0x04: x16 = x15 + 0x7C = 0x407C
        
        # x17 = 0xF (all LEDs on)
        enc.addi(17, 0, 0xF),       # 0x08: x17 = 15
        
        # Write to LED
        enc.sw(17, 16, 0),          # 0x0C: MEM[x16 + 0] = x17 -> LED = 0xF
        
        # Try different patterns in loop
        enc.addi(17, 0, 0x5),       # 0x10: x17 = 5
        enc.sw(17, 16, 0),          # 0x14: LED = 0x5
        
        enc.addi(17, 0, 0xA),       # 0x18: x17 = 10
        enc.sw(17, 16, 0),          # 0x1C: LED = 0xA
        
        enc.addi(17, 0, 0xF),       # 0x20: x17 = 15
        enc.sw(17, 16, 0),          # 0x24: LED = 0xF
        
        # Infinite loop (since EBREAK doesn't work reliably)
        enc.jal(0, -8),             # 0x28: jump to 0x20 (keep LED at 0xF)
    ]
    
    print(f"  Loading {len(program)} instructions...")
    for i, insn in enumerate(program):
        addr = i * 4
        write_cpu_mem(driver, addr, insn)
        
        # Decode instruction for display
        insn_str = ""
        if i == 0:
            insn_str = "LUI x15, 0x4"
        elif i == 1:
            insn_str = "ADDI x16, x15, 0x7C"
        elif i == 2:
            insn_str = "ADDI x17, x0, 0xF"
        elif i == 3:
            insn_str = "SW x17, 0(x16)"
        elif i == 4:
            insn_str = "ADDI x17, x0, 0x5"
        elif i == 5:
            insn_str = "SW x17, 0(x16)"
        elif i == 6:
            insn_str = "ADDI x17, x0, 0xA"
        elif i == 7:
            insn_str = "SW x17, 0(x16)"
        elif i == 8:
            insn_str = "ADDI x17, x0, 0xF"
        elif i == 9:
            insn_str = "SW x17, 0(x16)"
        elif i == 10:
            insn_str = "JAL x0, -8"
            
        print(f"    0x{addr:04x}: 0x{insn:08x}  # {insn_str}")
    
    print("\n[STEP 2] Verify program loaded correctly")
    verify_ok = True
    for i in range(len(program)):
        addr = i * 4
        readback = read_cpu_mem(driver, addr)
        if readback != program[i]:
            print(f"  ✗ 0x{addr:04x}: Expected 0x{program[i]:08x}, got 0x{readback:08x}")
            verify_ok = False
    
    if verify_ok:
        print("  ✓ All instructions verified")
    else:
        print("  ✗ Program verification FAILED!")
        sys.exit(1)
    
    print("\n[STEP 3] Start CPU execution")
    print("  Program will:")
    print("    1. Set LED = 0xF (all on)")
    print("    2. Set LED = 0x5 (pattern)")
    print("    3. Set LED = 0xA (pattern)")
    print("    4. Set LED = 0xF (all on)")
    print("    5. Loop forever keeping LED = 0xF")
    
    status_before = get_cpu_status(driver)
    print(f"\n  Before: halted={status_before['halted']}, break={status_before['break']}")
    
    print("\n  Starting CPU...")
    run_cpu(driver)
    
    print("\n  Waiting 2 seconds for execution...")
    time.sleep(2)
    
    status_after = get_cpu_status(driver)
    print(f"\n  After: halted={status_after['halted']}, break={status_after['break']}")
    
    print("\n[STEP 4] Check LEDs")
    print("  Expected: ALL 4 LEDs should be ON (pattern 0b1111)")
    print()
    print("  Physical LED Status:")
    response = input("  Are all 4 LEDs ON? (y/n): ").strip().lower()
    
    if response == 'y':
        print("\n  ✓✓✓ SUCCESS! CPU is controlling LEDs! ✓✓✓")
        print()
        print("  This confirms:")
        print("    - CPU is executing RV32I instructions")
        print("    - SW (Store Word) instruction works")
        print("    - MMIO write to 0x407C reaches LED hardware")
        print("    - Same code path as DSIM simulation")
    else:
        print("\n  ✗ LEDs not responding")
        print()
        print("  Debug Information:")
        print(f"    CPU Status: halted={status_after['halted']}, break={status_after['break']}")
        print("    Possible issues:")
        print("      1. CPU not executing (stuck in reset?)")
        print("      2. PC not advancing properly")
        print("      3. MMIO write not reaching LED register")
        print("      4. LED hardware connection issue")
        
        # Try to read some memory to verify CPU is alive
        print("\n  Reading first instruction back:")
        insn0 = read_cpu_mem(driver, 0x0)
        print(f"    0x0000: 0x{insn0:08x} (expected 0x{program[0]:08x})")
        
        if insn0 == program[0]:
            print("    ✓ Memory intact")
        else:
            print("    ✗ Memory corrupted!")

print("\n" + "="*60)
print("Test Complete")
print("="*60)
