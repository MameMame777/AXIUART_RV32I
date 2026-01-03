#!/usr/bin/env python3
"""
LED Blink - No Branches (Linear Code)
======================================
Uses straight-line code without any branches.
Writes many patterns sequentially, then CPU halts naturally.
This tests if the issue is with branch instructions.
"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

def main():
    print("=" * 70)
    print("LED Blink - No Branches Test")
    print("=" * 70)
    print()
    
    drv = AXIUARTDriver(port='COM3', baudrate=115200)
    drv.open()
    
    CPU_RUN = (1 << 7)
    CPU_HALT = (1 << 8)
    MEM_WRITE = (1 << 5)
    
    print("Halting CPU...")
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.1)
    
    print("Clearing memory...")
    for addr in range(200):
        byte_addr = addr * 4
        drv.write_reg32(drv.REG_CPU_MEM_ADDR, byte_addr)
        drv.write_reg32(drv.REG_CPU_MEM_WDATA, 0)
        drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT | MEM_WRITE | 0xF)
        time.sleep(0.0005)
    
    print()
    print("Program: Straight-line code with delays, NO BRANCHES")
    print("  Will alternate between Pattern 1 (0001) and Pattern 2 (1110)")
    print("  Repeats 20 times, then CPU executes NOPs and halts")
    print()
    print("  Delay per pattern: 2000 cycles ≈ 16μs @ 125MHz")
    print("  Total: 20 patterns × 32μs ≈ 640μs execution")
    print()
    
    prog = [
        0x000048B7,  # lui  x17, 0x4          # x17 = 0x4000 (LED base)
    ]
    
    # Generate 20 alternating patterns without any loops
    for i in range(20):
        if i % 2 == 0:
            # Pattern 1: LED = 1
            prog.extend([
                0x00100093,  # addi x1, x0, 1
                0x0618AE23,  # sw   x1, 0x7C(x17)
            ])
        else:
            # Pattern 2: LED = 14
            prog.extend([
                0x00E00093,  # addi x1, x0, 14
                0x0618AE23,  # sw   x1, 0x7C(x17)
            ])
        
        # Simple delay without loop (just execute many NOPs or ADDI)
        # Use ADDI x2, x2, 1 repeated many times as delay
        for _ in range(100):  # 100 instructions ≈ small delay
            prog.append(0x00110113)  # addi x2, x2, 1 (throwaway computation)
    
    # Add NOPs at end
    for _ in range(10):
        prog.append(0x00000013)  # nop (addi x0, x0, 0)
    
    print(f"Loading {len(prog)} instructions...")
    print(f"  [  0] 0x{prog[0]:08X}  # LUI x17")
    print(f"  [  1] 0x{prog[1]:08X}  # Pattern 1 start")
    print(f"  [  2] 0x{prog[2]:08X}  # SW")
    print(f"  ... delay instructions ...")
    print(f"  [{len(prog)-1:3}] 0x{prog[-1]:08X}  # NOP at end")
    print()
    
    for i, insn in enumerate(prog):
        byte_addr = i * 4
        drv.write_reg32(drv.REG_CPU_MEM_ADDR, byte_addr)
        drv.write_reg32(drv.REG_CPU_MEM_WDATA, insn)
        drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT | MEM_WRITE | 0xF)
        if i % 50 == 0:
            print(f"  Writing... {i}/{len(prog)}", end='\r')
        time.sleep(0.0005)
    
    print(f"  Writing... {len(prog)}/{len(prog)} [OK]")
    print()
    print("[OK] Program loaded")
    print()
    print("Starting execution...")
    print("CPU will run through all patterns once, then halt")
    print()
    
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_RUN)
    
    print("[OK] Running.")
    print()
    print("Expected behavior:")
    print("  LEDs should blink briefly (~640μs total)")
    print("  Then LEDs will freeze at whatever the last pattern was")
    print()
    print("If you see BOTH patterns lit equally:")
    print("  → Execution is going through all patterns (too fast to see)")
    print("If you see only Pattern 2 (upper 3):")
    print("  → Execution is stopping early")
    print("If you see only Pattern 1 (LSB):")
    print("  → CPU not executing past first pattern")
    print()
    
    time.sleep(2)
    
    print("Halting CPU to check final state...")
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT)
    
    print()
    print("What do the LEDs show now?")
    print("(This is the final LED value written by the program)")

if __name__ == '__main__':
    main()
