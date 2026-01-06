#!/usr/bin/env python3
"""LED Chika-chika pattern - Knight Rider style"""

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
    
    print("="*70)
    print("LED Chika Pattern - Knight Rider Style")
    print("="*70)
    
    halt_cpu(driver)
    
    # RV32I Program: LED chika pattern
    # Pattern: 0001 -> 0010 -> 0100 -> 1000 -> 0100 -> 0010 -> (repeat)
    
    prog = [
        # Initialization
        0x000048B7,  #  0: lui  x17, 0x4      # x17 = 0x4000 (LED base)
        0x00100093,  #  1: addi x1, x0, 1     # x1 = pattern (start with 0001)
        0x00800113,  #  2: addi x2, x0, 8     # x2 = max (1000)
        
        # Main loop
        0x0618AE23,  #  3: sw   x1, 0x7C(x17) # Write LED
        
        # Delay loop (short)
        0x01000193,  #  4: addi x3, x0, 16    # x3 = delay counter
        0xFFF18193,  #  5: addi x3, x3, -1    # x3--
        0xFE019EE3,  #  6: bnez x3, -4        # if x3!=0 goto 5
        
        # Shift left
        0x00109093,  #  7: slli x1, x1, 1     # x1 = x1 << 1
        
        # Check if reached max
        0x00209463,  #  8: bne  x1, x2, +8    # if x1 != 8, skip to 10
        
        # Reached max, reverse direction (right shift back to 0001)
        0x00100093,  #  9: addi x1, x0, 1     # x1 = 1 (restart)
        
        # Loop back
        0xFE5FF06F,  # 10: jal  x0, -28       # goto 3 (main loop)
    ]
    
    print("\nLoading LED chika program...")
    print("Pattern: 0001 -> 0010 -> 0100 -> 1000 -> (repeat)")
    print("\nProgram size:", len(prog), "instructions")
    
    for i, insn in enumerate(prog):
        write_cpu_mem(driver, i, insn)
        if i % 4 == 0:
            print(f"  Loaded instructions {i}-{min(i+3, len(prog)-1)}")
    
    print("\n[OK] Program loaded")
    print("\nStarting LED animation...")
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_RUN)
    
    print("\nLED should now be animating: 0001 -> 0010 -> 0100 -> 1000 -> ...")
    print("Watch the 4 LEDs on the board!")
    print("\nPress Ctrl+C to stop (LED will continue running)")
    
    try:
        # Monitor for a while
        for i in range(20):
            time.sleep(0.5)
            ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
            running = not bool(ctrl & CPU_HALTED)
            if not running:
                print("\n[WARN] CPU stopped unexpectedly")
                break
        print("\n[OK] LED animation running")
    except KeyboardInterrupt:
        print("\n\n[INFO] Monitoring stopped (CPU still running)")
    
    driver.close()
    print("\nTo stop LED animation, reset the FPGA or run halt_cpu script")

if __name__ == "__main__":
    main()
