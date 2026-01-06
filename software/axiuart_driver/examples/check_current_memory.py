#!/usr/bin/env python3
"""Check current memory state"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

SERIAL_PORT = 'COM3'
BAUDRATE = 115200

CPU_HALT = (1 << 8)
CPU_HALTED = (1 << 9)
MEM_READ = (1 << 4)
MEM_BUSY = (1 << 6)

def halt_cpu(driver):
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.05)

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

def decode_insn(insn):
    """Simple instruction decoder"""
    opcode = insn & 0x7F
    if insn == 0x000048B7:
        return "LUI x17, 0x4"
    elif insn == 0x00F00093:
        return "ADDI x1, x0, 15"
    elif insn == 0x0618AE23:
        return "SW x1, 0x7C(x17)"
    elif insn == 0x0000006F:
        return "JAL x0, 0 (loop)"
    elif insn == 0x00800093:
        return "ADDI x1, x0, 8"
    elif insn == 0x00000000:
        return "(uninitialized)"
    else:
        return f"(unknown 0x{insn:08X})"

def main():
    driver = AXIUARTDriver(SERIAL_PORT, baudrate=BAUDRATE, debug=False)
    driver.open()
    
    print("Current CPU Memory State")
    print("="*70)
    
    halt_cpu(driver)
    
    ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
    halted = bool(ctrl & CPU_HALTED)
    print(f"CPU Status: HALTED={halted}\n")
    
    print("First 10 instructions:")
    print("-"*70)
    for addr in range(10):
        insn = read_cpu_mem(driver, addr)
        decoded = decode_insn(insn)
        print(f"  [{addr}] 0x{insn:08X}  {decoded}")
    
    print("\n" + "="*70)
    print("Expected for test_single_led.py (LED=0xF):")
    print("  [0] 0x000048B7  LUI x17, 0x4")
    print("  [1] 0x00F00093  ADDI x1, x0, 15")
    print("  [2] 0x0618AE23  SW x1, 0x7C(x17)")
    print("  [3] 0x0000006F  JAL x0, 0")
    print("="*70)
    
    driver.close()

if __name__ == "__main__":
    main()
