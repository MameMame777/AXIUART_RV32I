#!/usr/bin/env python3
"""Simple LED blink test - just two patterns"""

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

def encode_bne(rs1, rs2, offset):
    """Encode BNE instruction
    BNE rs1, rs2, offset
    Format: imm[12|10:5] | rs2 | rs1 | 001 | imm[4:1|11] | 1100011
    """
    imm12 = (offset >> 12) & 1
    imm11 = (offset >> 11) & 1
    imm10_5 = (offset >> 5) & 0x3F
    imm4_1 = (offset >> 1) & 0xF
    
    insn = 0x63  # opcode for BRANCH
    insn |= (1 << 12)  # funct3 = 001 (BNE)
    insn |= (rs1 << 15)
    insn |= (rs2 << 20)
    insn |= (imm11 << 7)
    insn |= (imm4_1 << 8)
    insn |= (imm10_5 << 25)
    insn |= (imm12 << 31)
    
    return insn

def encode_jal(rd, offset):
    """Encode JAL instruction
    JAL rd, offset
    Format: imm[20|10:1|11|19:12] | rd | 1101111
    """
    imm20 = (offset >> 20) & 1
    imm19_12 = (offset >> 12) & 0xFF
    imm11 = (offset >> 11) & 1
    imm10_1 = (offset >> 1) & 0x3FF
    
    insn = 0x6F  # opcode for JAL
    insn |= (rd << 7)
    insn |= (imm19_12 << 12)
    insn |= (imm11 << 20)
    insn |= (imm10_1 << 21)
    insn |= (imm20 << 31)
    
    return insn

def main():
    driver = AXIUARTDriver(SERIAL_PORT, baudrate=BAUDRATE, debug=False)
    driver.open()
    
    print("="*70)
    print("Simple LED Blink Test - Two Patterns")
    print("="*70)
    
    halt_cpu(driver)
    
    # Simple program: alternate between 0101 and 1010
    prog = [
        0x000048B7,  #  0: lui  x17, 0x4        # x17 = 0x4000 (LED base)
        
        # Loop start - pattern 1 (0101)
        0x00500093,  #  1: addi x1, x0, 5       # x1 = 0101
        0x0618AE23,  #  2: sw   x1, 0x7C(x17)   # Write LED = 0101
        
        # Delay 1
        0x00A00193,  #  3: addi x3, x0, 10      # x3 = 10 (delay counter)
        0xFFF18193,  #  4: addi x3, x3, -1      # x3--
    ]
    
    # BNE x3, x0, -4  (if x3 != 0, go back to addr 4)
    # Offset = 4 - 5 = -1 instructions = -4 bytes
    prog.append(encode_bne(3, 0, -4))  # 5
    
    # Pattern 2 (1010)
    prog.extend([
        0x00A00093,  #  6: addi x1, x0, 10      # x1 = 1010
        0x0618AE23,  #  7: sw   x1, 0x7C(x17)   # Write LED = 1010
        
        # Delay 2
        0x00A00193,  #  8: addi x3, x0, 10      # x3 = 10
        0xFFF18193,  #  9: addi x3, x3, -1      # x3--
    ])
    
    # BNE x3, x0, -4  (if x3 != 0, go back to addr 9)
    prog.append(encode_bne(3, 0, -4))  # 10
    
    # JAL x0, back to addr 1 (loop forever)
    # Current PC = 11, target = 1, offset = 1 - 11 = -10 instructions = -40 bytes
    prog.append(encode_jal(0, -40))  # 11
    
    print("\nProgram:")
    print("  Pattern 1: 0101 (0b0101)")
    print("  Pattern 2: 1010 (0b1010)")
    print("  Alternating with short delay")
    print(f"\n  Program size: {len(prog)} instructions")
    
    for i, insn in enumerate(prog):
        write_cpu_mem(driver, i, insn)
        print(f"  [{i:2d}] 0x{insn:08X}")
    
    print("\n[OK] Program loaded")
    print("\nStarting LED blink...")
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_RUN)
    
    print("\nLED should alternate: 0101 <-> 1010")
    print("Watch the LEDs!")
    print("Press Ctrl+C to exit\n")
    
    try:
        time.sleep(10)
        ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
        running = not bool(ctrl & CPU_HALTED)
        if running:
            print("[OK] CPU still running")
        else:
            print("[WARN] CPU stopped")
    except KeyboardInterrupt:
        print("\n[INFO] Exit")
    
    driver.close()

if __name__ == "__main__":
    main()
