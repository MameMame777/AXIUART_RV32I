#!/usr/bin/env python3
"""Simple LED blink - 2 patterns with delay debugging"""

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
    print("LED Blink Debug - Simple 2-Pattern with Delay")
    print("="*70)
    
    halt_cpu(driver)
    
    # Clear memory first
    print("\nClearing memory...")
    for addr in range(30):
        write_cpu_mem(driver, addr, 0x00000000)
    
    # Very simple program:
    # Loop1: LED=1, delay, LED=14, delay, repeat
    # Use small delay counter for faster debugging
    
    prog = [
        # Setup
        0x000048B7,  #  0: lui  x17, 0x4          # x17 = 0x4000 (LED base)
        
        # Pattern 1: LED = 0001
        0x00100093,  #  1: addi x1, x0, 1         # x1 = 1
        0x0618AE23,  #  2: sw   x1, 0x7C(x17)     # Write LED = 1
        
        # Short delay (inner loop only)
        0x01000193,  #  3: addi x3, x0, 256       # x3 = 256 (delay counter)
        # Loop start at 4
        0xFFF18193,  #  4: addi x3, x3, -1        # x3--
        0xFE019EE3,  #  5: bne  x3, x0, -4        # if x3!=0, goto 4
        
        # Pattern 2: LED = 1110
        0x00E00093,  #  6: addi x1, x0, 14        # x1 = 14
        0x0618AE23,  #  7: sw   x1, 0x7C(x17)     # Write LED = 14
        
        # Short delay
        0x01000193,  #  8: addi x3, x0, 256       # x3 = 256
        0xFFF18193,  #  9: addi x3, x3, -1        # x3--
        0xFE019EE3,  # 10: bne  x3, x0, -4        # if x3!=0, goto 9
        
        # Loop back to pattern 1
        0xF55FF06F,  # 11: jal  x0, -172          # goto 1 (offset = 1-12 = -11 insn = -44 bytes)
    ]
    
    print("\nProgram structure:")
    print("  Pattern 1: LED = 0001")
    print("  Delay: 256 iterations")
    print("  Pattern 2: LED = 1110") 
    print("  Delay: 256 iterations")
    print("  Loop back")
    print(f"\nLoading {len(prog)} instructions...")
    
    for i, insn in enumerate(prog):
        write_cpu_mem(driver, i, insn)
        print(f"  [{i:2d}] 0x{insn:08X}")
    
    print("\n[OK] Program loaded")
    print("\nStarting LED blink...")
    print("Expected: LED alternates between 0001 and 1110")
    print("Delay: ~256 cycles per pattern (very fast, ~2μs @ 125MHz)")
    print("\nWatch LEDs - should blink rapidly")
    
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_RUN)
    
    time.sleep(3)
    print("\n[OK] Running. Check LED blinking.")
    print("If stuck at one value, delay loop may have issue.")
    
    driver.close()

if __name__ == "__main__":
    main()
