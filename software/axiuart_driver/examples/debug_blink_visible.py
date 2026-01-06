#!/usr/bin/env python3
"""
LED Blink Debug - Visible Speed with Nested Delay
================================================
Simple 2-pattern blink with human-visible timing (~0.4s per pattern)
Uses nested loops for longer delays.
"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

def main():
    print("=" * 70)
    print("LED Blink Debug - Visible Speed (~0.4s blink)")
    print("=" * 70)
    print()
    
    drv = AXIUARTDriver(port='COM3', baudrate=115200)
    drv.open()  # Open serial port
    
    CPU_RUN = (1 << 7)
    CPU_HALT = (1 << 8)
    MEM_WRITE = (1 << 5)
    MEM_BUSY = (1 << 6)
    
    # Halt CPU first
    print("Halting CPU...")
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.1)
    
    # Clear memory
    print("Clearing memory...")
    for addr in range(30):
        byte_addr = addr * 4
        drv.write_reg32(drv.REG_CPU_MEM_ADDR, byte_addr)
        drv.write_reg32(drv.REG_CPU_MEM_WDATA, 0)
        drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT | MEM_WRITE | 0xF)
        time.sleep(0.001)
    
    print()
    print("Program structure:")
    print("  Pattern 1: LED = 0001")
    print("  Delay: Nested loop (outer=1000, inner=50000) ≈ 50M cycles ≈ 0.4s")
    print("  Pattern 2: LED = 1110")
    print("  Delay: Same nested loop")
    print("  Loop back")
    print()
    
    # RV32I program with nested delay loops
    # Target: ~50M cycles = 1000 * 50000 * 1 cycle/iteration
    # @ 125MHz: 50M cycles = 0.4 seconds
    
    prog = [
        # Setup LED base address
        0x000048B7,  #  0: lui  x17, 0x4          # x17 = 0x4000 (LED base)
        
        # ===== Pattern 1: LED = 1 =====
        0x00100093,  #  1: addi x1, x0, 1         # x1 = 1
        0x0618AE23,  #  2: sw   x1, 0x7C(x17)     # LED = 1 (0b0001)
        
        # Outer delay loop 1
        0x3E800213,  #  3: addi x4, x0, 1000      # x4 = outer counter = 1000
        # Inner delay loop 1
        0xC3500193,  #  4: addi x3, x0, 50000     # x3 = inner counter = 50000 (0xC350)
        0xFFF18193,  #  5: addi x3, x3, -1        # x3--
        0xFE019EE3,  #  6: bne  x3, x0, -4        # if x3!=0 goto addr 5
        # Outer loop control 1
        0xFFF20213,  #  7: addi x4, x4, -1        # x4--
        0xFE021AE3,  #  8: bne  x4, x0, -12       # if x4!=0 goto addr 4
        
        # ===== Pattern 2: LED = 14 =====
        0x00E00093,  #  9: addi x1, x0, 14        # x1 = 14 (0b1110)
        0x0618AE23,  # 10: sw   x1, 0x7C(x17)     # LED = 14
        
        # Outer delay loop 2
        0x3E800213,  # 11: addi x4, x0, 1000      # x4 = 1000
        # Inner delay loop 2
        0xC3500193,  # 12: addi x3, x0, 50000     # x3 = 50000
        0xFFF18193,  # 13: addi x3, x3, -1        # x3--
        0xFE019EE3,  # 14: bne  x3, x0, -4        # if x3!=0 goto addr 13
        # Outer loop control 2
        0xFFF20213,  # 15: addi x4, x4, -1        # x4--
        0xFE021AE3,  # 16: bne  x4, x0, -12       # if x4!=0 goto addr 12
        
        # Loop back to Pattern 1
        0xF61FF06F,  # 17: jal  x0, -160          # goto addr 1 (byte offset: 1*4 - 18*4 = -68 = -0xA0)
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
    print("Starting LED blink...")
    print("Expected: LED alternates between 0001 and 1110")
    print("Speed: ~0.4 seconds per pattern (visible to human eye)")
    print()
    print("Watch the LEDs - should blink slowly and clearly")
    print()
    
    # Run CPU
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_RUN)
    
    print("[OK] Running. LEDs should blink visibly (~0.8s cycle).")
    print("Press Ctrl+C to stop")
    print()
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[OK] Stopping...")
        drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT)

if __name__ == '__main__':
    main()
