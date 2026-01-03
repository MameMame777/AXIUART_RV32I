#!/usr/bin/env python3
"""
LED Blink Debug - Simple delay (ADDI-safe immediate values)
=============================================================
Fixed: Use only 12-bit immediate values (max 2047)
Simple single-loop delay for visibility test.
"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

def main():
    print("=" * 70)
    print("LED Blink Debug - Simple Delay (Fixed Immediate)")
    print("=" * 70)
    print()
    
    drv = AXIUARTDriver(port='COM3', baudrate=115200)
    drv.open()
    
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
    print("  Delay: 2000 iterations (ADDI immediate safe: max 2047)")
    print("  Pattern 2: LED = 1110")
    print("  Delay: 2000 iterations")
    print("  Loop back")
    print()
    print("Delay timing:")
    print("  2000 cycles @ 125MHz = 16μs (too fast for human, but will test loop)")
    print()
    
    # RV32I program with SAFE immediate values (12-bit signed: -2048 to 2047)
    prog = [
        # Setup LED base address
        0x000048B7,  #  0: lui  x17, 0x4          # x17 = 0x4000
        
        # ===== Pattern 1: LED = 1 =====
        0x00100093,  #  1: addi x1, x0, 1         # x1 = 1
        0x0618AE23,  #  2: sw   x1, 0x7C(x17)     # LED = 1 (0b0001)
        
        # Delay loop 1: 2000 iterations (0x7D0, within 12-bit range)
        0x7D000193,  #  3: addi x3, x0, 2000      # x3 = 2000 (0x7D0)
        0xFFF18193,  #  4: addi x3, x3, -1        # x3--
        0xFE019EE3,  #  5: bne  x3, x0, -4        # if x3!=0 goto addr 4
        
        # ===== Pattern 2: LED = 14 =====
        0x00E00093,  #  6: addi x1, x0, 14        # x1 = 14 (0b1110)
        0x0618AE23,  #  7: sw   x1, 0x7C(x17)     # LED = 14
        
        # Delay loop 2: 2000 iterations
        0x7D000193,  #  8: addi x3, x0, 2000      # x3 = 2000
        0xFFF18193,  #  9: addi x3, x3, -1        # x3--
        0xFE019EE3,  # 10: bne  x3, x0, -4        # if x3!=0 goto addr 9
        
        # Loop back to Pattern 1
        0xF75FF06F,  # 11: jal  x0, -140          # goto addr 1 (offset: 1*4 - 12*4 = -44 = -0x2C)
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
    print("Speed: 2000 cycles/pattern = 16μs @ 125MHz (too fast, but tests loop)")
    print()
    print("If LEDs appear as:")
    print("  - Both dim/equal brightness: Loop working, delay too fast")
    print("  - Only LSB bright: Still stuck at Pattern 1")
    print("  - Only upper 3 bright: Pattern 2 working but not looping back")
    print()
    
    # Run CPU
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_RUN)
    
    print("[OK] Running. Check LED appearance.")
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
