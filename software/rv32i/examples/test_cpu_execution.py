#!/usr/bin/env python3
"""
Test CPU Program Execution
Verify that CPU actually executes instructions by monitoring register changes
"""
import sys
import os
import time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from axiuart_driver import AXIUARTDriver

port = sys.argv[1] if len(sys.argv) > 1 else 'COM3'

print("="*60)
print("CPU EXECUTION VERIFICATION TEST")
print("="*60)

with AXIUARTDriver(port, 115200) as driver:
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
    from rv32i import halt_cpu, run_cpu, get_cpu_status
    from rv32i.memory import write_cpu_mem, read_cpu_mem
    from rv32i.encoder import RV32IInstructionEncoder
    
    enc = RV32IInstructionEncoder()
    
    print("\n[STEP 1] Halt CPU and load counter program")
    halt_cpu(driver)
    
    # Program that writes incremental values to memory location 0x1000
    # Loop 10 times, writing 1,2,3,...10 to 0x1000, then EBREAK
    program = [
        # x1 = 0x1000 (target address)
        enc.lui(1, 0x1),         # 0x00: x1 = 0x1000
        # x2 = 0 (counter)
        enc.addi(2, 0, 0),       # 0x04: x2 = 0
        # x3 = 10 (loop limit)
        enc.addi(3, 0, 10),      # 0x08: x3 = 10
        
        # LOOP:
        # x2 = x2 + 1
        enc.addi(2, 2, 1),       # 0x0C: x2 = x2 + 1
        # MEM[x1] = x2
        enc.sw(2, 1, 0),         # 0x10: MEM[0x1000] = x2
        # if (x2 < x3) goto LOOP
        enc.blt(2, 3, -8),       # 0x14: if x2 < 10, jump to 0x0C
        
        # Done
        enc.ebreak()             # 0x18: Stop
    ]
    
    print(f"  Loading {len(program)} instructions...")
    for i, insn in enumerate(program):
        addr = i * 4
        write_cpu_mem(driver, addr, insn)
        print(f"    0x{addr:04x}: 0x{insn:08x}")
    
    print("\n[STEP 2] Clear target memory location")
    write_cpu_mem(driver, 0x1000, 0x00000000)
    val = read_cpu_mem(driver, 0x1000)
    print(f"  0x1000 = 0x{val:08x} (should be 0)")
    
    print("\n[STEP 3] Run CPU and monitor execution")
    print("  Starting CPU...")
    run_cpu(driver)
    
    # Monitor memory location for changes
    print("\n  Monitoring 0x1000 for 5 seconds...")
    for t in range(50):  # 50 x 0.1s = 5 seconds
        time.sleep(0.1)
        val = read_cpu_mem(driver, 0x1000)
        status = get_cpu_status(driver)
        
        if t % 5 == 0:  # Print every 0.5 seconds
            print(f"    t={t*0.1:.1f}s: 0x1000=0x{val:08x} (={val:>3d}), "
                  f"halted={status['halted']}, break={status['break']}")
        
        if status['break']:
            print(f"\n  ✓ CPU hit EBREAK at t={t*0.1:.1f}s")
            break
        
        if val == 10:
            print(f"\n  ✓ Counter reached 10 at t={t*0.1:.1f}s")
            # Give CPU time to hit EBREAK
            time.sleep(0.5)
            status = get_cpu_status(driver)
            if status['break']:
                print("  ✓ CPU stopped at EBREAK")
            else:
                print("  ⚠ Counter reached 10 but CPU did NOT hit EBREAK")
            break
    else:
        print("\n  ✗ Timeout - CPU did not execute program")
        final_val = read_cpu_mem(driver, 0x1000)
        status = get_cpu_status(driver)
        print(f"  Final state: 0x1000=0x{final_val:08x}, "
              f"halted={status['halted']}, break={status['break']}")
        
        if final_val == 0:
            print("\n  DIAGNOSIS: Memory did not change")
            print("  → CPU is NOT executing instructions")
            print("  → Possible causes:")
            print("      1. CPU is stuck in reset")
            print("      2. PC is not advancing")
            print("      3. 'running' flag not set correctly")
        elif final_val > 0 and final_val < 10:
            print("\n  DIAGNOSIS: Partial execution")
            print("  → CPU executed some instructions but got stuck")
            print(f"  → Stopped at counter value {final_val}")
        elif final_val == 10:
            print("\n  DIAGNOSIS: Loop completed but EBREAK not working")
            print("  → CPU executed full program")
            print("  → EBREAK instruction not stopping CPU")

print("\n" + "="*60)
print("TEST COMPLETE")
print("="*60)
