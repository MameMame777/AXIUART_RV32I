#!/usr/bin/env python3
"""
Single test debug - detailed execution trace
"""

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from axiuart_driver import AXIUARTDriver, registers
from td4cpu import isa


def main():
    PORT = 'COM3'
    BAUDRATE = 115200
    
    driver = AXIUARTDriver(PORT, baudrate=BAUDRATE)
    driver.open()
    
    print("=" * 70)
    print("Single Test Debug: ADD R1, R2 (1+2=3)")
    print("=" * 70)
    
    # 1. Check status and halt
    print("\n[1] Initial status...")
    status = driver.read_reg32(registers.REG_CPU_DBG_STATUS)
    print(f"    Status: 0x{status:08X}, Halted={status&1}, Running={status>>1&1}")
    
    driver.write_reg32(registers.REG_CPU_DBG_CTRL, 0x00000001)  # Halt
    time.sleep(0.01)
    status = driver.read_reg32(registers.REG_CPU_DBG_STATUS)
    print(f"    After halt: 0x{status:08X}, Halted={status&1}")
    
    # 2. Setup registers
    print("\n[2] Writing R1=0x0001, R2=0x0002...")
    
    def write_reg(idx, val):
        driver.write_reg32(registers.REG_CPU_REG_INDEX, idx)
        time.sleep(0.005)
        driver.write_reg32(registers.REG_CPU_REG_DATA, val)
        time.sleep(0.005)
    
    def read_reg(idx):
        driver.write_reg32(registers.REG_CPU_REG_INDEX, idx)
        time.sleep(0.005)
        _ = driver.read_reg32(registers.REG_CPU_REG_INDEX)  # Confirm index
        val = driver.read_reg32(registers.REG_CPU_REG_DATA)
        return val & 0xFFFF
    
    write_reg(1, 0x0001)
    write_reg(2, 0x0002)
    
    print(f"    R1 readback: 0x{read_reg(1):04X}")
    print(f"    R2 readback: 0x{read_reg(2):04X}")
    
    # 3. Load instruction at address 0
    instruction = isa.ADD(1, 2)  # ADD R1, R2 -> result in R1
    print(f"\n[3] Loading instruction 0x{instruction:04X} at address 0...")
    print(f"    Opcode: ADD, Rd=R1, Rs1=R1, Rs2=R2")
    
    driver.write_reg32(registers.REG_CPU_MEM_ADDR, 0)
    time.sleep(0.002)
    driver.write_reg32(registers.REG_CPU_MEM_WDATA, instruction)
    time.sleep(0.002)
    driver.write_reg32(registers.REG_CPU_MEM_CTRL, 0x00000002)  # Write
    time.sleep(0.005)
    
    # Read back memory
    driver.write_reg32(registers.REG_CPU_MEM_ADDR, 0)
    time.sleep(0.002)
    driver.write_reg32(registers.REG_CPU_MEM_CTRL, 0x00000001)  # Read
    time.sleep(0.005)
    mem_val = driver.read_reg32(registers.REG_CPU_MEM_RDATA)
    print(f"    Memory[0] readback: 0x{mem_val:04X}")
    
    # 4. Set PC to 0
    print("\n[4] Setting PC=0...")
    driver.write_reg32(registers.REG_CPU_PC, 0)
    time.sleep(0.002)
    pc = driver.read_reg32(registers.REG_CPU_PC)
    print(f"    PC readback: 0x{pc:04X}")
    
    # 5. Execute single step
    print("\n[5] Executing single step...")
    driver.write_reg32(registers.REG_CPU_DBG_CTRL, 0x00000004)  # STEP bit
    time.sleep(0.05)  # Wait longer for 4-stage pipeline
    
    status = driver.read_reg32(registers.REG_CPU_DBG_STATUS)
    print(f"    Status after step: 0x{status:08X}, Halted={status&1}")
    
    pc = driver.read_reg32(registers.REG_CPU_PC)
    print(f"    PC after step: 0x{pc:04X}")
    
    # 6. Read result
    print("\n[6] Reading results...")
    r1 = read_reg(1)
    r2 = read_reg(2)
    flags = driver.read_reg32(registers.REG_CPU_FLAGS)
    
    print(f"    R1: 0x{r1:04X} (expected 0x0003)")
    print(f"    R2: 0x{r2:04X} (should be unchanged)")
    print(f"    Flags: 0x{flags:02X} (Z={flags>>2&1}, N={flags>>1&1}, C={flags&1})")
    
    if r1 == 0x0003:
        print("\n✓ SUCCESS!")
    else:
        print(f"\n✗ FAIL: R1={r1:04X}, expected 0x0003")
    
    driver.close()


if __name__ == '__main__':
    main()
