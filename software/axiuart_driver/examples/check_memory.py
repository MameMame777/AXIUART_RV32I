#!/usr/bin/env python3
"""Check what's actually in CPU memory at address 0"""

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
    """Halt the CPU and wait for confirmation"""
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_HALT)
    for _ in range(10):
        time.sleep(0.001)
        ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
        if ctrl & CPU_HALTED:
            return True
    return False

def read_cpu_mem(driver, word_addr):
    """Read from CPU memory via debug interface"""
    driver.write_reg32(driver.REG_CPU_MEM_ADDR, word_addr)
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, MEM_READ | CPU_HALT)
    
    for _ in range(10):
        time.sleep(0.001)
        ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
        if not (ctrl & MEM_BUSY):
            break
    
    return driver.read_reg32(driver.REG_CPU_MEM_RDATA)

def main():
    driver = AXIUARTDriver(SERIAL_PORT, baudrate=BAUDRATE, debug=False)
    driver.open()
    
    print("CPU Memory Check\n" + "="*60)
    
    # Halt CPU first
    if not halt_cpu(driver):
        print("[ERROR] Failed to halt CPU")
        driver.close()
        return
    
    print("[OK] CPU halted\n")
    
    # Read first 8 words from CPU memory
    print("Memory contents at address 0x0000-0x001C:")
    print("-" * 60)
    for addr in range(8):
        data = read_cpu_mem(driver, addr)
        print(f"  Word[{addr}] (0x{addr*4:04X}): 0x{data:08X}")
        
        # Try to decode as instruction
        if data == 0x00000000:
            print(f"                         (NOP / uninitialized)")
        elif (data & 0x7F) == 0x6F:  # JAL
            print(f"                         (JAL instruction)")
        elif (data & 0x7F) == 0x37:  # LUI
            print(f"                         (LUI instruction)")
        elif (data & 0x7F) == 0x73:  # SYSTEM
            if data == 0x00100073:
                print(f"                         (EBREAK)")
            else:
                print(f"                         (SYSTEM instruction)")
    
    print("\n")
    driver.close()

if __name__ == "__main__":
    main()
