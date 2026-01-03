#!/usr/bin/env python3
"""Debug write operation step by step"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

SERIAL_PORT = 'COM3'
BAUDRATE = 115200

CPU_HALT = (1 << 8)
CPU_HALTED = (1 << 9)
MEM_WRITE = (1 << 5)
MEM_BUSY = (1 << 6)

def main():
    driver = AXIUARTDriver(SERIAL_PORT, baudrate=BAUDRATE, debug=False)
    driver.open()
    
    print("="*70)
    print("Debug Single Write Operation")
    print("="*70)
    
    # Halt CPU
    print("\n[1] Halt CPU")
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.01)
    ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
    print(f"    CPU_MEM_CTRL = 0x{ctrl:08X}, HALTED={bool(ctrl & CPU_HALTED)}")
    
    # Write address
    byte_addr = 0x0004  # Word 1
    print(f"\n[2] Write address: 0x{byte_addr:04X} (word 1)")
    driver.write_reg32(driver.REG_CPU_MEM_ADDR, byte_addr)
    readback_addr = driver.read_reg32(driver.REG_CPU_MEM_ADDR)
    print(f"    Readback: 0x{readback_addr:08X}")
    
    # Write data
    test_data = 0xDEADBEEF
    print(f"\n[3] Write data: 0x{test_data:08X}")
    driver.write_reg32(driver.REG_CPU_MEM_WDATA, test_data)
    readback_data = driver.read_reg32(driver.REG_CPU_MEM_WDATA)
    print(f"    Readback: 0x{readback_data:08X}")
    
    # Trigger write
    ctrl_value = CPU_HALT | MEM_WRITE | 0xF
    print(f"\n[4] Trigger write: 0x{ctrl_value:08X}")
    print(f"    CPU_HALT={bool(ctrl_value & CPU_HALT)}")
    print(f"    MEM_WRITE={bool(ctrl_value & MEM_WRITE)}")
    print(f"    Byte enables={ctrl_value & 0xF:04b}")
    
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, ctrl_value)
    
    # Wait for completion
    print("\n[5] Wait for BUSY clear")
    for i in range(20):
        time.sleep(0.001)
        ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
        busy = bool(ctrl & MEM_BUSY)
        print(f"    Iteration {i}: BUSY={busy}, CTRL=0x{ctrl:08X}")
        if not busy:
            print(f"    Write completed after {i+1} iterations")
            break
    
    # Read back from memory
    print(f"\n[6] Read back from address 0x{byte_addr:04X}")
    driver.write_reg32(driver.REG_CPU_MEM_ADDR, byte_addr)
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_HALT | (1 << 4))  # MEM_READ
    
    time.sleep(0.005)
    result = driver.read_reg32(driver.REG_CPU_MEM_RDATA)
    print(f"    Result: 0x{result:08X}")
    
    if result == test_data:
        print("\n[SUCCESS] Write/read verified!")
    else:
        print(f"\n[FAIL] Expected 0x{test_data:08X}, got 0x{result:08X}")
    
    driver.close()

if __name__ == "__main__":
    main()
