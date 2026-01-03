#!/usr/bin/env python3
"""
LED Blink - Nested Loop with LUI+ADDI (Human Visible Speed)
============================================================
Uses LUI+ADDI to load large loop counters.
Target: ~0.5 second per pattern for clear visibility.
"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

def encode_jal(offset_bytes):
    """Encode JAL immediate (20-bit signed, byte offset)"""
    if offset_bytes % 2 != 0:
        raise ValueError("JAL offset must be 2-byte aligned")
    
    imm = offset_bytes & 0x1FFFFF  # 21 bits (bit 0 always 0)
    
    # JAL format: imm[20|10:1|11|19:12] rd opcode
    imm_20 = (imm >> 20) & 1
    imm_19_12 = (imm >> 12) & 0xFF
    imm_11 = (imm >> 11) & 1
    imm_10_1 = (imm >> 1) & 0x3FF
    
    inst = (imm_20 << 31) | (imm_10_1 << 21) | (imm_11 << 20) | (imm_19_12 << 12) | 0x6F
    return inst & 0xFFFFFFFF

def main():
    print("=" * 70)
    print("LED Blink - Nested Loop (Visible Speed)")
    print("=" * 70)
    print()
    
    drv = AXIUARTDriver(port='COM3', baudrate=115200)
    drv.open()
    
    CPU_RUN = (1 << 7)
    CPU_HALT = (1 << 8)
    MEM_WRITE = (1 << 5)
    MEM_BUSY = (1 << 6)
    
    # Halt CPU
    print("Halting CPU...")
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.1)
    
    # Clear memory
    print("Clearing memory...")
    for addr in range(40):
        byte_addr = addr * 4
        drv.write_reg32(drv.REG_CPU_MEM_ADDR, byte_addr)
        drv.write_reg32(drv.REG_CPU_MEM_WDATA, 0)
        drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT | MEM_WRITE | 0xF)
        time.sleep(0.001)
    
    print()
    print("Program structure:")
    print("  Nested loop: outer × inner = total cycles")
    print("  Outer loop: 800 iterations")
    print("  Inner loop: 2047 iterations (max ADDI immediate)")
    print("  Total: 800 × 2047 × ~3 cycles/iter ≈ 4.9M cycles ≈ 39ms @ 125MHz")
    print()
    print("  Pattern 1: LED = 0001 → delay → Pattern 2: LED = 1110 → delay → repeat")
    print()
    
    # Calculate JAL offset for loop back
    # From addr 19 to addr 1: offset = (1 - 19) * 4 = -72 bytes
    jal_offset = (1 - 19) * 4
    jal_insn = encode_jal(jal_offset)
    print(f"JAL instruction: 0x{jal_insn:08X} (offset {jal_offset} bytes)")
    print()
    
    prog = [
        # Setup LED base address
        0x000048B7,  #  0: lui  x17, 0x4          # x17 = 0x4000 (LED base)
        
        # ===== Pattern 1: LED = 1 =====
        0x00100093,  #  1: addi x1, x0, 1         # x1 = 1
        0x0618AE23,  #  2: sw   x1, 0x7C(x17)     # LED = 1 (0b0001)
        
        # Outer loop 1: 800 iterations
        0x00000237,  #  3: lui  x4, 0x0           # x4 upper = 0
        0x32020213,  #  4: addi x4, x4, 800       # x4 = 800 (0x320)
        
        # Inner loop 1: 2047 iterations (max 12-bit immediate)
        0x7FF00193,  #  5: addi x3, x0, 2047      # x3 = 2047 (0x7FF)
        0xFFF18193,  #  6: addi x3, x3, -1        # x3--
        0xFE019EE3,  #  7: bne  x3, x0, -4        # if x3!=0 goto addr 6 (offset -4)
        
        # Outer decrement 1
        0xFFF20213,  #  8: addi x4, x4, -1        # x4--
        0xFE021AE3,  #  9: bne  x4, x0, -12       # if x4!=0 goto addr 5 (offset -16)
        
        # ===== Pattern 2: LED = 14 =====
        0x00E00093,  # 10: addi x1, x0, 14        # x1 = 14 (0b1110)
        0x0618AE23,  # 11: sw   x1, 0x7C(x17)     # LED = 14
        
        # Outer loop 2: 800 iterations
        0x00000237,  # 12: lui  x4, 0x0
        0x32020213,  # 13: addi x4, x4, 800
        
        # Inner loop 2: 2047 iterations
        0x7FF00193,  # 14: addi x3, x0, 2047
        0xFFF18193,  # 15: addi x3, x3, -1
        0xFE019EE3,  # 16: bne  x3, x0, -4        # goto addr 15
        
        # Outer decrement 2
        0xFFF20213,  # 17: addi x4, x4, -1
        0xFE021AE3,  # 18: bne  x4, x0, -12       # goto addr 14
        
        # Loop back to Pattern 1
        jal_insn,    # 19: jal  x0, offset        # goto addr 1
    ]
    
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
    print("Starting LED blink...")
    print("Expected: ~78ms cycle (39ms per pattern)")
    print("Should see clear alternating blink")
    print()
    
    # Run CPU
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_RUN)
    
    print("[OK] Running. Watch LEDs alternate between 0001 and 1110.")
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
