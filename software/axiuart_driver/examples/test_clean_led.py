#!/usr/bin/env python3
"""Clear CPU memory and set LED to specific value"""

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
    
    TEST_VALUE = 0x3  # 0b0011
    
    print("="*70)
    print(f"Clean Test - Set LED to 0x{TEST_VALUE:X} (0b{TEST_VALUE:04b})")
    print("="*70)
    
    halt_cpu(driver)
    
    # Clear memory (write NOPs/zeros to first 20 words)
    print("\nClearing memory (0-19)...")
    for addr in range(20):
        write_cpu_mem(driver, addr, 0x00000000)
        if addr % 5 == 4:
            print(f"  Cleared {addr+1} words...")
    
    print("[OK] Memory cleared")
    
    # Write clean program
    print(f"\nLoading program (LED=0x{TEST_VALUE:X})...")
    prog = [
        0x000048B7,                          #  0: lui  x17, 0x4
        0x00000093 | (TEST_VALUE << 20),     #  1: addi x1, x0, TEST_VALUE
        0x0618AE23,                           #  2: sw   x1, 0x7C(x17)
        0x0000006F,                           #  3: jal  x0, 0 (loop)
    ]
    
    for i, insn in enumerate(prog):
        write_cpu_mem(driver, i, insn)
        print(f"  [{i}] 0x{insn:08X}")
    
    print("\n[OK] Program loaded")
    
    # Start CPU
    print("\nStarting CPU...")
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_RUN)
    time.sleep(0.05)
    
    print("\n" + "="*70)
    print(f"Expected: LED = 0x{TEST_VALUE:X} (0b{TEST_VALUE:04b})")
    print("="*70)
    
    driver.close()

if __name__ == "__main__":
    main()
