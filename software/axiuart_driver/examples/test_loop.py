#!/usr/bin/env python3
"""Test with infinite loop before EBREAK to see if CPU stops"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

SERIAL_PORT = 'COM3'
BAUDRATE = 115200

CPU_RUN = (1 << 7)
CPU_HALT = (1 << 8)
CPU_HALTED = (1 << 9)
CPU_BREAK = (1 << 10)
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
    
    print("Test with Loop + EBREAK")
    print("="*70)
    
    halt_cpu(driver)
    
    # Program: Set LED to 0xC, then infinite loop
    prog = [
        0x000048B7,  # 0: LUI x17, 0x4 → x17=0x4000
        0x00C00093,  # 1: ADDI x1, x0, 0xC → x1=0xC
        0x0618AE23,  # 2: SW x1, 0x7C(x17) → MEM[0x407C]=0xC (LED)
        0x0000006F,  # 3: JAL x0, 0 → PC=PC+0 (infinite loop at addr 3)
    ]
    
    print("\nProgram:")
    print("  [0] LUI x17, 0x4")
    print("  [1] ADDI x1, x0, 0xC") 
    print("  [2] SW x1, 0x7C(x17)  → LED=0xC")
    print("  [3] JAL x0, 0         → Infinite loop")
    
    for i, insn in enumerate(prog):
        write_cpu_mem(driver, i, insn)
    
    print("\nStarting CPU...")
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_RUN)
    time.sleep(0.1)
    
    ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
    halted = bool(ctrl & CPU_HALTED)
    brk = bool(ctrl & CPU_BREAK)
    
    print(f"After 100ms: HALTED={halted}, BREAK={brk}")
    print(f"\nExpected LED: 0xC (0b1100)")
    print("CPU should be looping infinitely (not halted)")
    print("Check physical LED - should show 0xC")
    
    driver.close()

if __name__ == "__main__":
    main()
