#!/usr/bin/env python3
"""LED chika - NO DELAY for testing"""

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
    
    print("LED Chika - NO DELAY (for testing)")
    print("="*70)
    
    halt_cpu(driver)
    
    # Simple: 0001 -> 0010 -> 0100 -> 1000, no delay
    prog = [
        0x000048B7,  #  0: lui  x17, 0x4        # x17 = 0x4000 (LED base)
        
        0x00100093,  #  1: addi x1, x0, 1       # x1 = 1
        0x0618AE23,  #  2: sw   x1, 0x7C(x17)   # LED = 0001
        
        0x00200093,  #  3: addi x1, x0, 2       # x1 = 2  
        0x0618AE23,  #  4: sw   x1, 0x7C(x17)   # LED = 0010
        
        0x00400093,  #  5: addi x1, x0, 4       # x1 = 4
        0x0618AE23,  #  6: sw   x1, 0x7C(x17)   # LED = 0100
        
        0x00800093,  #  7: addi x1, x0, 8       # x1 = 8
        0x0618AE23,  #  8: sw   x1, 0x7C(x17)   # LED = 1000
        
        0xFF1FF06F,  #  9: jal  x0, -16         # goto 1 (loop)
    ]
    
    print("Pattern: 0001 -> 0010 -> 0100 -> 1000 (no delay, very fast)")
    print(f"Program size: {len(prog)} instructions\n")
    
    for i, insn in enumerate(prog):
        write_cpu_mem(driver, i, insn)
        print(f"  [{i}] 0x{insn:08X}")
    
    print("\n[OK] Program loaded")
    print("\nStarting animation (very fast - LED should look bright/flickering)...")
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_RUN)
    
    time.sleep(3)
    print("\n[OK] Check LED - should be changing rapidly")
    
    driver.close()

if __name__ == "__main__":
    main()
