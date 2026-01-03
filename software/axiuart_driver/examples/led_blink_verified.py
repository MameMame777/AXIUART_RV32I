#!/usr/bin/env python3
"""
LED Blink - Verified JAL Encoding
==================================
Carefully re-implemented JAL encoding per RISC-V spec.
Uses minimal delay for fast debugging.
"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

def encode_jal_verified(rd, offset_bytes):
    """
    Encode JAL instruction per RISC-V spec.
    
    JAL encoding: imm[20|10:1|11|19:12] rd opcode
    - opcode = 0x6F (bits 6:0)
    - rd = destination register (bits 11:7)
    - imm[20] = bit 31
    - imm[10:1] = bits 30:21
    - imm[11] = bit 20
    - imm[19:12] = bits 19:12
    
    Immediate is 21-bit signed, byte offset (bit 0 always 0).
    """
    if offset_bytes % 2 != 0:
        raise ValueError(f"JAL offset must be 2-byte aligned, got {offset_bytes}")
    
    # Sign extend to 32-bit if negative
    if offset_bytes < 0:
        imm = offset_bytes & 0x1FFFFF  # 21 bits
    else:
        imm = offset_bytes
    
    # Extract individual bits
    imm_20 = (imm >> 20) & 0x1        # bit 20
    imm_10_1 = (imm >> 1) & 0x3FF     # bits 10:1
    imm_11 = (imm >> 11) & 0x1        # bit 11
    imm_19_12 = (imm >> 12) & 0xFF    # bits 19:12
    
    # Assemble instruction
    opcode = 0x6F
    insn = (imm_20 << 31) | (imm_19_12 << 12) | (imm_11 << 20) | (imm_10_1 << 21) | (rd << 7) | opcode
    
    return insn & 0xFFFFFFFF

def main():
    print("=" * 70)
    print("LED Blink - Verified JAL + Simple Loop")
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
    print("Program: Simple loop with moderate delay")
    print("  Loop counter: 2000 iterations")
    print("  Pattern 1: 0001 → Pattern 2: 1110 → repeat")
    print()
    
    # Build program
    prog = [
        0x000048B7,  #  0: lui  x17, 0x4          # x17 = 0x4000 (LED base)
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
    
    # Add JAL: from addr 11 to addr 1
    # Offset = (target - current) * 4 = (1 - 11) * 4 = -40 bytes
    jal_offset = (1 - 11) * 4
    jal_insn = encode_jal_verified(rd=0, offset_bytes=jal_offset)
    prog.append(jal_insn)
    
    print(f"JAL instruction:")
    print(f"  From addr 11 to addr 1")
    print(f"  Offset: {jal_offset} bytes (0x{jal_offset & 0xFFFFFFFF:08X})")
    print(f"  Encoded: 0x{jal_insn:08X}")
    print()
    
    # Verify encoding manually
    print("JAL encoding verification:")
    imm_bits = jal_offset & 0x1FFFFF
    print(f"  Immediate (21-bit): 0x{imm_bits:06X}")
    print(f"  imm[20]: {(imm_bits >> 20) & 1}")
    print(f"  imm[19:12]: 0x{(imm_bits >> 12) & 0xFF:02X}")
    print(f"  imm[11]: {(imm_bits >> 11) & 1}")
    print(f"  imm[10:1]: 0x{(imm_bits >> 1) & 0x3FF:03X}")
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
    print("Expected: Fast alternating blink (2000 cycles/pattern ≈ 16μs)")
    print()
    
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_RUN)
    
    print("[OK] Running.")
    print()
    print("LED appearance should be:")
    print("  If both LEDs equally dim: Loop working! (too fast)")
    print("  If LSB only: Stuck at pattern 1")
    print("  If upper 3 only: JAL still broken")
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
