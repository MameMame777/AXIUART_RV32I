#!/usr/bin/env python3
"""Halt CPU completely"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

SERIAL_PORT = 'COM3'
BAUDRATE = 115200

CPU_HALT = (1 << 8)
CPU_HALTED = (1 << 9)

def main():
    driver = AXIUARTDriver(SERIAL_PORT, baudrate=BAUDRATE, debug=False)
    driver.open()
    
    print("Halting CPU...")
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.05)
    
    ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
    halted = bool(ctrl & CPU_HALTED)
    
    if halted:
        print(f"[OK] CPU halted (CTRL=0x{ctrl:08X})")
        print("LED should stop changing")
    else:
        print(f"[FAIL] CPU still running (CTRL=0x{ctrl:08X})")
    
    driver.close()

if __name__ == "__main__":
    main()
