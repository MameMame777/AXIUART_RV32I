#!/usr/bin/env python3
"""Simple CPU debug - check if CPU is running at all"""

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

def main():
    driver = AXIUARTDriver(SERIAL_PORT, baudrate=BAUDRATE, debug=False)
    driver.open()
    
    print("CPU Debug Test\n" + "="*60)
    
    # Check initial status
    ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
    print(f"\nInitial CPU_MEM_CTRL: 0x{ctrl:08X}")
    print(f"  - CPU_RUN bit (7):    {(ctrl >> 7) & 1}")
    print(f"  - CPU_HALT bit (8):   {(ctrl >> 8) & 1}")
    print(f"  - CPU_HALTED bit (9): {(ctrl >> 9) & 1}")
    print(f"  - CPU_BREAK bit (10): {(ctrl >> 10) & 1}")
    
    # Try to halt
    print("\nHalting CPU...")
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.01)
    
    ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
    print(f"After HALT - CPU_MEM_CTRL: 0x{ctrl:08X}")
    print(f"  - CPU_HALTED: {bool(ctrl & CPU_HALTED)}")
    
    # Try to start
    print("\nStarting CPU...")
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_RUN)
    time.sleep(0.01)
    
    ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
    print(f"After RUN - CPU_MEM_CTRL: 0x{ctrl:08X}")
    print(f"  - CPU_HALTED: {bool(ctrl & CPU_HALTED)}")
    print(f"  - CPU_BREAK:  {bool(ctrl & CPU_BREAK)}")
    
    # Wait a bit and check again
    time.sleep(0.1)
    ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
    print(f"\nAfter 100ms - CPU_MEM_CTRL: 0x{ctrl:08X}")
    print(f"  - CPU_HALTED: {bool(ctrl & CPU_HALTED)}")
    print(f"  - CPU_BREAK:  {bool(ctrl & CPU_BREAK)}")
    
    driver.close()

if __name__ == "__main__":
    main()
