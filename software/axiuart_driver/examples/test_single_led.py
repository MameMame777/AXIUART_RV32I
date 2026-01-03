#!/usr/bin/env python3
"""Step-by-step LED test - set one value and verify"""

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
MEM_WRITE = (1 << 5)
MEM_BUSY = (1 << 6)

def halt_cpu(driver):
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.01)
    ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
    return bool(ctrl & CPU_HALTED)

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
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_HALT | (1 << 4))  # MEM_READ
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
    
    TEST_VALUE = 0xF  # All LEDs on
    
    print("="*70)
    print(f"Single LED Test - Set to 0x{TEST_VALUE:X} (0b{TEST_VALUE:04b})")
    print("="*70)
    
    # Step 1: Halt CPU
    print("\n[STEP 1] Halt CPU")
    if halt_cpu(driver):
        print("  [OK] CPU halted")
    else:
        print("  [FAIL] CPU not halted")
        driver.close()
        return
    
    # Step 2: Load program
    print(f"\n[STEP 2] Load program (LED value = 0x{TEST_VALUE:X})")
    prog = [
        0x000048B7,                          #  0: lui  x17, 0x4
        0x00000093 | (TEST_VALUE << 20),     #  1: addi x1, x0, TEST_VALUE
        0x0618AE23,                           #  2: sw   x1, 0x7C(x17)
        0x0000006F,                           #  3: jal  x0, 0 (loop forever)
    ]
    
    for i, insn in enumerate(prog):
        write_cpu_mem(driver, i, insn)
        print(f"  [{i}] Wrote: 0x{insn:08X}")
    
    # Step 3: Verify program
    print("\n[STEP 3] Verify program in memory")
    all_ok = True
    for i, expected in enumerate(prog):
        actual = read_cpu_mem(driver, i)
        match = "OK" if actual == expected else "FAIL"
        print(f"  [{i}] Expected: 0x{expected:08X}, Got: 0x{actual:08X} [{match}]")
        if actual != expected:
            all_ok = False
    
    if not all_ok:
        print("\n[ABORT] Program verification failed")
        driver.close()
        return
    
    print("\n[OK] Program verified")
    
    # Step 4: Start CPU
    print("\n[STEP 4] Start CPU execution")
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_RUN)
    time.sleep(0.05)
    
    ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
    halted = bool(ctrl & CPU_HALTED)
    print(f"  CPU status: HALTED={halted}")
    
    if halted:
        print("  [WARN] CPU stopped immediately")
    else:
        print("  [OK] CPU running")
    
    # Step 5: Check result
    print("\n[STEP 5] Check physical LED")
    print("="*70)
    print(f"Expected: LED = 0x{TEST_VALUE:X} (0b{TEST_VALUE:04b})")
    print("All 4 LEDs should be ON")
    print("="*70)
    
    driver.close()

if __name__ == "__main__":
    main()
