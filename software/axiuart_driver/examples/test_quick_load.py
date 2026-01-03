#!/usr/bin/env python3
"""Load program and immediately check memory"""

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
MEM_READ = (1 << 4)
MEM_WRITE = (1 << 5)
MEM_BUSY = (1 << 6)

def halt_cpu(driver):
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.01)
    return True

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

def read_cpu_mem(driver, word_addr):
    byte_addr = word_addr * 4
    driver.write_reg32(driver.REG_CPU_MEM_ADDR, byte_addr)
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_HALT | MEM_READ)
    time.sleep(0.002)
    for _ in range(20):
        ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
        if not (ctrl & MEM_BUSY):
            break
        time.sleep(0.001)
    return driver.read_reg32(driver.REG_CPU_MEM_RDATA)

def main():
    driver = AXIUARTDriver(SERIAL_PORT, baudrate=BAUDRATE, debug=False)
    driver.open()
    
    print("="*70)
    print("Load Program and Verify Immediately")
    print("="*70)
    
    halt_cpu(driver)
    print("\n[1] CPU halted")
    
    # Program
    TEST_VALUE = 0xA
    prog = [
        0x000048B7,                      # LUI x17, 0x4
        0x00000093 | (TEST_VALUE << 20), # ADDI x1, x0, 0xA
        0x0618AE23,                       # SW x1, 0x7C(x17)
        0x00100073                        # EBREAK
    ]
    
    print(f"\n[2] Writing program (TEST_VALUE=0x{TEST_VALUE:X})")
    for i, insn in enumerate(prog):
        write_cpu_mem(driver, i, insn)
        print(f"    [{i}] Wrote: 0x{insn:08X}")
    
    print(f"\n[3] Immediate readback")
    for i in range(4):
        actual = read_cpu_mem(driver, i)
        expected = prog[i]
        match = "OK" if actual == expected else "FAIL"
        print(f"    [{i}] Expected: 0x{expected:08X}, Got: 0x{actual:08X} [{match}]")
    
    print(f"\n[4] Start CPU")
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_RUN)
    time.sleep(0.05)
    
    ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
    halted = bool(ctrl & CPU_HALTED)
    brk = bool(ctrl & CPU_BREAK)
    print(f"    After 50ms: HALTED={halted}, BREAK={brk}")
    
    if brk:
        print("\n[SUCCESS] EBREAK detected!")
        print(f"Expected LED: 0x{TEST_VALUE:X} (0b{TEST_VALUE:04b})")
        print("Check physical LED on board")
    else:
        print("\n[WARN] EBREAK not detected yet")
        print(f"Expected LED: 0x{TEST_VALUE:X} (0b{TEST_VALUE:04b})")
        print("Check physical LED on board")
    
    driver.close()

if __name__ == "__main__":
    main()
