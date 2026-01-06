#!/usr/bin/env python3
"""
LED Test - Minimal Sequential Pattern
======================================
Write 3 LED patterns in sequence with no delays or branches.
Pattern 1 (0x1) → Pattern 2 (0x3) → Pattern 3 (0x7)

This tests if CPU can execute sequential SW instructions.
"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

def main():
    print("=" * 70)
    print("LED Test - Minimal Sequential Pattern")
    print("=" * 70)
    print()
    
    drv = AXIUARTDriver(port='COM3', baudrate=115200)
    drv.open()
    
    CPU_RUN = (1 << 7)
    CPU_HALT = (1 << 8)
    CPU_HALTED = (1 << 9)
    MEM_WRITE = (1 << 5)
    
    print("Halting CPU...")
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.1)
    
    print("Clearing memory...")
    for addr in range(20):
        byte_addr = addr * 4
        drv.write_reg32(drv.REG_CPU_MEM_ADDR, byte_addr)
        drv.write_reg32(drv.REG_CPU_MEM_WDATA, 0)
        drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT | MEM_WRITE | 0xF)
        time.sleep(0.001)
    
    print()
    print("Program: Write 3 LED patterns sequentially")
    print("  0: LUI x17, 0x4       # LED base address")
    print("  1: ADDI x1, x0, 1     # x1 = 1")
    print("  2: SW x1, 0x7C(x17)   # LED = 0x1 (0b0001)")
    print("  3: ADDI x1, x0, 3     # x1 = 3")
    print("  4: SW x1, 0x7C(x17)   # LED = 0x3 (0b0011)")
    print("  5: ADDI x1, x0, 7     # x1 = 7")
    print("  6: SW x1, 0x7C(x17)   # LED = 0x7 (0b0111)")
    print("  7: NOP")
    print()
    
    prog = [
        0x000048B7,  #  0: lui  x17, 0x4
        0x00100093,  #  1: addi x1, x0, 1
        0x0618AE23,  #  2: sw   x1, 0x7C(x17)   # LED = 1
        0x00300093,  #  3: addi x1, x0, 3
        0x0618AE23,  #  4: sw   x1, 0x7C(x17)   # LED = 3
        0x00700093,  #  5: addi x1, x0, 7
        0x0618AE23,  #  6: sw   x1, 0x7C(x17)   # LED = 7
        0x00000013,  #  7: nop
    ]
    
    print(f"Loading {len(prog)} instructions...")
    for i, insn in enumerate(prog):
        print(f"  [{i:2}] 0x{insn:08X}")
        byte_addr = i * 4
        drv.write_reg32(drv.REG_CPU_MEM_ADDR, byte_addr)
        drv.write_reg32(drv.REG_CPU_MEM_WDATA, insn)
        drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT | MEM_WRITE | 0xF)
        time.sleep(0.001)
    
    print()
    print("[OK] Program loaded")
    print()
    print("Running CPU...")
    
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_RUN)
    
    # Give CPU time to execute
    time.sleep(0.1)
    
    # Halt and check status
    print("Halting CPU to check result...")
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.05)
    
    ctrl = drv.read_reg32(drv.REG_CPU_MEM_CTRL)
    halted = bool(ctrl & CPU_HALTED)
    
    print()
    print("=" * 70)
    print("RESULT")
    print("=" * 70)
    print(f"CPU Status: {'HALTED' if halted else 'UNKNOWN'} (CTRL=0x{ctrl:08X})")
    print()
    print("What do the LEDs show?")
    print("  0x1 (0b0001, LSB only):  Stopped after 1st SW")
    print("  0x3 (0b0011, lower 2):   Stopped after 2nd SW")
    print("  0x7 (0b0111, lower 3):   SUCCESS - All 3 patterns executed!")
    print("  Other:                   Unexpected state")
    print()

if __name__ == '__main__':
    main()
