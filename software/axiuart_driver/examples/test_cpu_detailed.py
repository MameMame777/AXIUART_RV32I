#!/usr/bin/env python3
"""Detailed test with step-by-step verification"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

SERIAL_PORT = 'COM3'
BAUDRATE = 115200
LED_MMIO_ADDR = 0x407C

CPU_RUN = (1 << 7)
CPU_HALT = (1 << 8)
CPU_HALTED = (1 << 9)
CPU_BREAK = (1 << 10)
MEM_READ = (1 << 4)
MEM_WRITE = (1 << 5)
MEM_BUSY = (1 << 6)

def halt_cpu(driver):
    """Halt CPU and confirm"""
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_HALT)
    for _ in range(20):
        time.sleep(0.005)
        ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
        if ctrl & CPU_HALTED:
            return True
    return False

def write_cpu_mem(driver, word_addr, data):
    """Write word to CPU memory"""
    byte_addr = word_addr * 4
    driver.write_reg32(driver.REG_CPU_MEM_ADDR, byte_addr)
    driver.write_reg32(driver.REG_CPU_MEM_WDATA, data)
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_HALT | MEM_WRITE | 0xF)
    
    # Wait for operation completion
    time.sleep(0.002)  # Give hardware time to process
    for _ in range(20):
        ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
        if not (ctrl & MEM_BUSY):
            break
        time.sleep(0.001)

def read_cpu_mem(driver, word_addr):
    """Read word from CPU memory"""
    byte_addr = word_addr * 4
    driver.write_reg32(driver.REG_CPU_MEM_ADDR, byte_addr)
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_HALT | MEM_READ)
    
    for _ in range(10):
        ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
        if not (ctrl & MEM_BUSY):
            break
        time.sleep(0.001)
    
    return driver.read_reg32(driver.REG_CPU_MEM_RDATA)

def run_cpu(driver):
    """Start CPU execution"""
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_RUN)

def main():
    driver = AXIUARTDriver(SERIAL_PORT, baudrate=BAUDRATE, debug=False)
    driver.open()
    
    print("="*70)
    print("RV32I CPU Debug Test - Step by Step")
    print("="*70)
    
    # Step 1: Initial status
    print("\n[STEP 1] Check initial CPU status")
    ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
    print(f"  CPU_MEM_CTRL = 0x{ctrl:08X}")
    print(f"    HALTED = {bool(ctrl & CPU_HALTED)}")
    print(f"    BREAK  = {bool(ctrl & CPU_BREAK)}")
    print(f"    RUN    = {bool(ctrl & CPU_RUN)}")
    
    # Step 2: Halt CPU
    print("\n[STEP 2] Halt CPU")
    if not halt_cpu(driver):
        print("  [FAIL] Cannot halt CPU!")
        driver.close()
        return
    print("  [OK] CPU halted")
    
    # Step 3: Load simple program
    print("\n[STEP 3] Load test program (4 instructions)")
    TEST_VALUE = 0x5
    insn_lui   = 0x000048B7                      # LUI x17, 0x4 → x17=0x4000
    insn_addi  = 0x00000093 | (TEST_VALUE << 20)  # ADDI x1, x0, 0x5 → x1=0x5
    insn_sw    = 0x0618AE23                       # SW x1, 0x7C(x17) → MEM[0x407C]=x1
    insn_ebreak = 0x00100073                      # EBREAK
    
    write_cpu_mem(driver, 0, insn_lui)
    write_cpu_mem(driver, 1, insn_addi)
    write_cpu_mem(driver, 2, insn_sw)
    write_cpu_mem(driver, 3, insn_ebreak)
    print(f"  [0] 0x{insn_lui:08X}    (LUI x17, 0x4)")
    print(f"  [1] 0x{insn_addi:08X} (ADDI x1, x0, {TEST_VALUE})")
    print(f"  [2] 0x{insn_sw:08X}    (SW x1, 0x7C(x17))")
    print(f"  [3] 0x{insn_ebreak:08X} (EBREAK)")
    
    # Step 4: Verify program
    print("\n[STEP 4] Verify program in memory")
    verify_ok = True
    for i, expected in enumerate([insn_lui, insn_addi, insn_sw, insn_ebreak]):
        actual = read_cpu_mem(driver, i)
        match = "[OK]" if actual == expected else "[FAIL]"
        print(f"  [{i}] Expected: 0x{expected:08X}, Got: 0x{actual:08X} {match}")
        if actual != expected:
            verify_ok = False
    
    if not verify_ok:
        print("\n[ABORT] Program verification failed!")
        driver.close()
        return
    
    # Step 5: Start CPU
    print("\n[STEP 5] Start CPU execution")
    run_cpu(driver)
    time.sleep(0.01)
    
    ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
    print(f"  CPU_MEM_CTRL = 0x{ctrl:08X}")
    print(f"    HALTED = {bool(ctrl & CPU_HALTED)} (should be False - running)")
    print(f"    BREAK  = {bool(ctrl & CPU_BREAK)}  (should become True after EBREAK)")
    
    # Step 6: Wait for EBREAK
    print("\n[STEP 6] Wait for EBREAK (max 500ms)")
    ebreak_hit = False
    for i in range(50):
        time.sleep(0.010)
        ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
        if ctrl & CPU_BREAK:
            print(f"  [OK] EBREAK detected after {(i+1)*10}ms")
            ebreak_hit = True
            break
        if i == 10 or i == 25:
            print(f"    ... {(i+1)*10}ms - still waiting (HALTED={bool(ctrl & CPU_HALTED)}, BREAK={bool(ctrl & CPU_BREAK)})")
    
    if not ebreak_hit:
        print(f"  [FAIL] EBREAK not detected after 500ms")
        print(f"    Final status: HALTED={bool(ctrl & CPU_HALTED)}, BREAK={bool(ctrl & CPU_BREAK)}")
    
    # Step 7: Read LED value
    print("\n[STEP 7] Read LED value")
    led_word_addr = LED_MMIO_ADDR >> 2
    led_value = read_cpu_mem(driver, led_word_addr) & 0xF
    print(f"  LED address: 0x{LED_MMIO_ADDR:04X} (word addr: 0x{led_word_addr:04X})")
    print(f"  LED value: 0x{led_value:X} (binary: {led_value:04b})")
    
    if led_value == TEST_VALUE:
        print(f"  [OK] LED matches expected value ({TEST_VALUE})")
    else:
        print(f"  [FAIL] LED={led_value}, expected={TEST_VALUE}")
    
    # Summary
    print("\n" + "="*70)
    if ebreak_hit and led_value == TEST_VALUE:
        print("TEST PASSED - CPU executed program correctly")
    else:
        print("TEST FAILED - See details above")
    print("="*70)
    
    driver.close()

if __name__ == "__main__":
    main()
