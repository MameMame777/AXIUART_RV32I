#!/usr/bin/env python3
"""LED blink with longer delay"""

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
    
    print("LED Blink - SLOW (visible delay)")
    print("="*70)
    
    halt_cpu(driver)
    
    # Very slow blink for visibility
    # At 125MHz, need ~125M cycles for 1 second
    # Use nested loops: outer * inner = total delay
    
    prog = [
        0x000048B7,  #  0: lui  x17, 0x4          # x17 = 0x4000 (LED base)
        
        # Pattern 1: 0001
        0x00100093,  #  1: addi x1, x0, 1         # x1 = 0001
        0x0618AE23,  #  2: sw   x1, 0x7C(x17)     # Write LED
        
        # Long delay (nested loop)
        0x03200213,  #  3: addi x4, x0, 50        # x4 = outer loop (50)
        0x7D000193,  #  4: addi x3, x0, 2000      # x3 = inner loop (2000)
        0xFFF18193,  #  5: addi x3, x3, -1        # x3--
        0xFE019EE3,  #  6: bne  x3, x0, -4        # if x3!=0 goto 5
        0xFFF20213,  #  7: addi x4, x4, -1        # x4--
        0xFE021CE3,  #  8: bne  x4, x0, -8        # if x4!=0 goto 4
        
        # Pattern 2: 1110
        0x00E00093,  #  9: addi x1, x0, 14        # x1 = 1110
        0x0618AE23,  # 10: sw   x1, 0x7C(x17)     # Write LED
        
        # Long delay again
        0x03200213,  # 11: addi x4, x0, 50        # x4 = 50
        0x7D000193,  # 12: addi x3, x0, 2000      # x3 = 2000
        0xFFF18193,  # 13: addi x3, x3, -1        # x3--
        0xFE019EE3,  # 14: bne  x3, x0, -4        # if x3!=0 goto 13
        0xFFF20213,  # 15: addi x4, x4, -1        # x4--
        0xFE021CE3,  # 16: bne  x4, x0, -8        # if x4!=0 goto 12
        
        # Loop back to start
        0xFB5FF06F,  # 17: jal  x0, -76           # goto 1
    ]
    
    print("\nPattern: 0001 <-> 1110 (slow blink)")
    print(f"Delay: ~100K cycles per pattern (~0.8ms @ 125MHz)")
    print(f"Program size: {len(prog)} instructions\n")
    
    for i, insn in enumerate(prog):
        write_cpu_mem(driver, i, insn)
    
    print("[OK] Program loaded")
    print("\nStarting slow LED blink...")
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_RUN)
    
    print("\nWatch LEDs: should blink between 0001 and 1110")
    print("Pattern changes every ~0.8ms (visible blink)")
    
    time.sleep(5)
    print("\n[OK] Running")
    
    driver.close()

if __name__ == "__main__":
    main()
