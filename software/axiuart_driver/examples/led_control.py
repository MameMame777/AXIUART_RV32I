#!/usr/bin/env python3
"""Interactive LED control via CPU MMIO"""

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

def set_led(driver, value):
    """Set LED to specific value (0-15)"""
    prog = [
        0x000048B7,                      #  0: lui  x17, 0x4
        0x00000093 | (value << 20),      #  1: addi x1, x0, value
        0x0618AE23,                       #  2: sw   x1, 0x7C(x17)
        0x0000006F,                       #  3: jal  x0, 0 (infinite loop)
    ]
    
    halt_cpu(driver)
    for i, insn in enumerate(prog):
        write_cpu_mem(driver, i, insn)
    
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_RUN)
    time.sleep(0.01)

def main():
    driver = AXIUARTDriver(SERIAL_PORT, baudrate=BAUDRATE, debug=False)
    driver.open()
    
    print("="*70)
    print("Interactive LED Control via CPU MMIO")
    print("="*70)
    print("\nCommands:")
    print("  0-15 or 0x0-0xF : Set LED value")
    print("  b0000-b1111     : Set LED in binary")
    print("  q               : Quit")
    print("\nExamples:")
    print("  LED> 5          # Set LED to 5 (0b0101)")
    print("  LED> 0xA        # Set LED to 10 (0b1010)")
    print("  LED> b1111      # Set LED to 15 (all on)")
    print("="*70)
    
    try:
        while True:
            try:
                cmd = input("\nLED> ").strip().lower()
                
                if cmd in ['q', 'quit', 'exit']:
                    break
                
                if not cmd:
                    continue
                
                # Parse input
                value = None
                if cmd.startswith('0x'):
                    value = int(cmd, 16)
                elif cmd.startswith('0b') or cmd.startswith('b'):
                    value = int(cmd.replace('b', ''), 2)
                elif cmd.isdigit():
                    value = int(cmd)
                else:
                    print(f"[ERROR] Invalid input: {cmd}")
                    continue
                
                if value < 0 or value > 15:
                    print(f"[ERROR] Value must be 0-15, got: {value}")
                    continue
                
                # Set LED
                set_led(driver, value)
                print(f"[OK] LED = {value:2d} (0x{value:X}, 0b{value:04b})")
                
            except ValueError as e:
                print(f"[ERROR] Parse error: {e}")
            except KeyboardInterrupt:
                print("\n")
                break
    
    finally:
        halt_cpu(driver)
        print("\n[INFO] CPU halted, connection closed")
        driver.close()

if __name__ == "__main__":
    main()
