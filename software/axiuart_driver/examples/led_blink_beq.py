#!/usr/bin/env python3
"""
LED Blink - BEQ-based Loop (JAL alternative)
=============================================
Uses BEQ x0, x0 for unconditional branch instead of JAL.
BEQ has 13-bit offset, sufficient for small loops.
"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

def encode_beq(rs1, rs2, offset_bytes):
    """
    Encode BEQ instruction.
    
    BEQ format: imm[12|10:5] rs2 rs1 000 imm[4:1|11] opcode
    - opcode = 0x63 (branch)
    - funct3 = 0x0 (BEQ)
    - Immediate is 13-bit signed, byte offset (bit 0 always 0)
    """
    if offset_bytes % 2 != 0:
        raise ValueError(f"Branch offset must be 2-byte aligned, got {offset_bytes}")
    
    # Sign extend to handle negative offsets
    if offset_bytes < 0:
        imm = offset_bytes & 0x1FFF  # 13 bits
    else:
        imm = offset_bytes
    
    # Extract bits
    imm_12 = (imm >> 12) & 0x1
    imm_11 = (imm >> 11) & 0x1
    imm_10_5 = (imm >> 5) & 0x3F
    imm_4_1 = (imm >> 1) & 0xF
    
    # Assemble: imm[12|10:5] rs2 rs1 000 imm[4:1|11] 1100011
    insn = ((imm_12 << 31) | (imm_10_5 << 25) | (rs2 << 20) | (rs1 << 15) | 
            (0x0 << 12) | (imm_4_1 << 8) | (imm_11 << 7) | 0x63)
    
    return insn & 0xFFFFFFFF

def main():
    print("=" * 70)
    print("LED Blink - BEQ Loop (JAL Alternative)")
    print("=" * 70)
    print()
    
    drv = AXIUARTDriver(port='COM3', baudrate=115200)
    drv.open()
    
    CPU_RUN = (1 << 7)
    CPU_HALT = (1 << 8)
    MEM_WRITE = (1 << 5)
    
    print("Halting CPU...")
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.1)
    
    print("Clearing memory...")
    for addr in range(40):
        byte_addr = addr * 4
        drv.write_reg32(drv.REG_CPU_MEM_ADDR, byte_addr)
        drv.write_reg32(drv.REG_CPU_MEM_WDATA, 0)
        drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT | MEM_WRITE | 0xF)
        time.sleep(0.001)
    
    print()
    print("Program: Using BEQ x0,x0 for unconditional loop")
    print("  Pattern 1: 0001 → delay → Pattern 2: 1110 → delay → repeat")
    print("  Loop: BEQ x0, x0, offset (always branches)")
    print()
    
    prog = [
        0x000048B7,  #  0: lui  x17, 0x4          # x17 = 0x4000
        0x00100093,  #  1: addi x1, x0, 1         # x1 = 1
        0x0618AE23,  #  2: sw   x1, 0x7C(x17)     # LED = 1
        0x7D000193,  #  3: addi x3, x0, 2000      # x3 = 2000
        0xFFF18193,  #  4: addi x3, x3, -1        # x3--
        0xFE019EE3,  #  5: bne  x3, x0, -4        # if x3!=0 goto 4
        0x00E00093,  #  6: addi x1, x0, 14        # x1 = 14
        0x0618AE23,  #  7: sw   x1, 0x7C(x17)     # LED = 14
        0x7D000193,  #  8: addi x3, x0, 2000      # x3 = 2000
        0xFFF18193,  #  9: addi x3, x3, -1        # x3--
        0xFE019EE3,  # 10: bne  x3, x0, -4        # if x3!=0 goto 9
    ]
    
    # Add BEQ x0, x0: from addr 11 to addr 1
    # Offset = (1 - 11) * 4 = -40 bytes
    beq_offset = (1 - 11) * 4
    beq_insn = encode_beq(rs1=0, rs2=0, offset_bytes=beq_offset)
    prog.append(beq_insn)
    
    print(f"BEQ x0,x0 instruction:")
    print(f"  From addr 11 to addr 1")
    print(f"  Offset: {beq_offset} bytes (0x{beq_offset & 0xFFFFFFFF:08X})")
    print(f"  Encoded: 0x{beq_insn:08X}")
    print()
    
    # Verify encoding
    imm_bits = beq_offset & 0x1FFF
    print("BEQ encoding verification:")
    print(f"  Immediate (13-bit): 0x{imm_bits:04X}")
    print(f"  imm[12]: {(imm_bits >> 12) & 1}")
    print(f"  imm[11]: {(imm_bits >> 11) & 1}")
    print(f"  imm[10:5]: 0x{(imm_bits >> 5) & 0x3F:02X}")
    print(f"  imm[4:1]: 0x{(imm_bits >> 1) & 0xF:X}")
    print()
    
    print(f"Loading {len(prog)} instructions...")
    for i, insn in enumerate(prog):
        print(f"  [{i:2}] 0x{insn:08X}")
        byte_addr = i * 4
        drv.write_reg32(drv.REG_CPU_MEM_ADDR, byte_addr)
        drv.write_reg32(drv.REG_CPU_MEM_WDATA, insn)
        drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT | MEM_WRITE | 0xF)
        time.sleep(0.001)
    
    print()
    print("[OK] Program loaded")
    print()
    print("Starting execution...")
    print("Using BEQ instead of JAL for loop")
    print()
    
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_RUN)
    
    print("[OK] Running.")
    print()
    print("Expected LED behavior:")
    print("  Both LEDs equally bright: Loop working! (BEQ success)")
    print("  Upper 3 only: BEQ also failing (CPU JAL/branch issue?)")
    print("  LSB only: Stuck at pattern 1")
    print()
    print("Press Ctrl+C to stop")
    print()
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[OK] Stopping...")
        drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT)

if __name__ == '__main__':
    main()
