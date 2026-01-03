#!/usr/bin/env python3
"""LED chika with CORRECTED branch offsets"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

SERIAL_PORT = 'COM3'
BAUDRATE = 115200

CPU_RUN = (1 << 7)
CPU_HALT = (1 << 8)
MEM_WRITE = (1 << 5)
MEM_BUSY = (1 << 6)

def halt_cpu(driver):
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.01)

def write_cpu_mem(driver, word_addr, data):
    byte_addr = word_addr * 4
    driver.write_reg32(driver.REG_CPU_MEM_ADDR, byte_addr)
    driver.write_reg32(driver.REG_CPU_MEM_WDATA, data)
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_HALT | MEM_WRITE | 0xF)
    time.sleep(0.002)
    for _ in range(20):
        ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
        if not (ctrl & MEM_BUSY):
            break
        time.sleep(0.001)

def main():
    driver = AXIUARTDriver(SERIAL_PORT, baudrate=BAUDRATE, debug=False)
    driver.open()
    
    print("="*70)
    print("LED Chika - FIXED Branch Offsets")
    print("="*70)
    
    halt_cpu(driver)
    
    # Much shorter delay for quick testing: outer(100) × inner(5000) = 500K cycles
    # At 125MHz, 500K cycles = 4ms per pattern (clearly visible)
    
    prog = [
        0x000048B7,  #  0: lui  x17, 0x4          # x17 = 0x4000 (LED base)
        
        # ===== Pattern 1: 0001 =====
        0x00100093,  #  1: addi x1, x0, 1         # x1 = 1
        0x0618AE23,  #  2: sw   x1, 0x7C(x17)     # Write LED = 0001
        
        # Delay: outer(100) × inner(5000)
        0x06400213,  #  3: addi x4, x0, 100       # x4 = outer
        # Inner loop start (addr 4)
        0x000012B7,  #  4: lui  x5, 0x1           # x5 = 0x1000 = 4096
        0x38828293,  #  5: addi x5, x5, 904       # x5 = 5000
        # Inner loop body (addr 6)
        0xFFF28293,  #  6: addi x5, x5, -1        # x5--
        0xFE029EE3,  #  7: bne  x5, x0, -4        # if x5!=0, goto 6 (PC=8, target=6, offset=-2=-8bytes)
        # Outer loop
        0xFFF20213,  #  8: addi x4, x4, -1        # x4--
        0xFE021AE3,  #  9: bne  x4, x0, -12       # if x4!=0, goto 4 (PC=10, target=4, offset=-6=-24bytes)
        
        # ===== Pattern 2: 0010 =====
        0x00200093,  # 10: addi x1, x0, 2         # x1 = 2
        0x0618AE23,  # 11: sw   x1, 0x7C(x17)     # Write LED = 0010
        
        # Same delay
        0x06400213,  # 12: addi x4, x0, 100
        0x000012B7,  # 13: lui  x5, 0x1
        0x38828293,  # 14: addi x5, x5, 904
        0xFFF28293,  # 15: addi x5, x5, -1
        0xFE029EE3,  # 16: bne  x5, x0, -4
        0xFFF20213,  # 17: addi x4, x4, -1
        0xFE021AE3,  # 18: bne  x4, x0, -12
        
        # ===== Pattern 3: 0100 =====
        0x00400093,  # 19: addi x1, x0, 4         # x1 = 4
        0x0618AE23,  # 20: sw   x1, 0x7C(x17)     # Write LED = 0100
        
        # Same delay
        0x06400213,  # 21: addi x4, x0, 100
        0x000012B7,  # 22: lui  x5, 0x1
        0x38828293,  # 23: addi x5, x5, 904
        0xFFF28293,  # 24: addi x5, x5, -1
        0xFE029EE3,  # 25: bne  x5, x0, -4
        0xFFF20213,  # 26: addi x4, x4, -1
        0xFE021AE3,  # 27: bne  x4, x0, -12
        
        # ===== Pattern 4: 1000 =====
        0x00800093,  # 28: addi x1, x0, 8         # x1 = 8
        0x0618AE23,  # 29: sw   x1, 0x7C(x17)     # Write LED = 1000
        
        # Same delay
        0x06400213,  # 30: addi x4, x0, 100
        0x000012B7,  # 31: lui  x5, 0x1
        0x38828293,  # 32: addi x5, x5, 904
        0xFFF28293,  # 33: addi x5, x5, -1
        0xFE029EE3,  # 34: bne  x5, x0, -4
        0xFFF20213,  # 35: addi x4, x4, -1
        0xFE021AE3,  # 36: bne  x4, x0, -12
        
        # Loop back to pattern 1
        0xF2DFF06F,  # 37: jal  x0, -212          # goto 1 (PC=38, target=1, offset=-37=-148bytes)
    ]
    
    print("\nPattern: 0001 -> 0010 -> 0100 -> 1000 (repeat)")
    print("Delay: ~40ms per pattern (fast but visible)")
    print(f"Program size: {len(prog)} instructions\n")
    
    for i, insn in enumerate(prog):
        write_cpu_mem(driver, i, insn)
    
    print("[OK] Program loaded")
    print("\nStarting LED animation...")
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_RUN)
    
    print("\n" + "="*70)
    print("LED should now animate quickly: 0001 -> 0010 -> 0100 -> 1000")
    print("Watch for movement!")
    print("="*70)
    
    time.sleep(3)
    print("\n[OK] Check animation")
    
    driver.close()

if __name__ == "__main__":
    main()
