#!/usr/bin/env python3
"""
LED Blink - Single Long Loop (LUI+ADDI for large counter)
==========================================================
Uses LUI to load upper bits, ADDI for lower bits.
Target: ~100ms per pattern for clear visibility.
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
    
    imm = offset_bytes & 0x1FFFFF
    
    imm_20 = (imm >> 20) & 1
    imm_19_12 = (imm >> 12) & 0xFF
    imm_11 = (imm >> 11) & 1
    imm_10_1 = (imm >> 1) & 0x3FF
    
    inst = (imm_20 << 31) | (imm_10_1 << 21) | (imm_11 << 20) | (imm_19_12 << 12) | 0x6F
    return inst & 0xFFFFFFFF

def main():
    print("=" * 70)
    print("LED Blink - Single Long Loop")
    print("=" * 70)
    print()
    
    drv = AXIUARTDriver(port='COM3', baudrate=115200)
    drv.open()
    
    CPU_RUN = (1 << 7)
    CPU_HALT = (1 << 8)
    MEM_WRITE = (1 << 5)
    MEM_BUSY = (1 << 6)
    
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
    print("Program structure:")
    print("  Single loop: LUI + ADDI for large counter")
    print("  Target: ~12.5M cycles ≈ 100ms @ 125MHz")
    print("  Counter: 12,500,000 = 0xBEBC20")
    print("    Upper 20 bits (LUI): 0xBEBC (48828)")
    print("    Lower 12 bits (ADDI): 0x20 (32)")
    print()
    
    # Counter = 12,500,000 (0xBEBC20)
    # LUI loads upper 20 bits into register (bits 31:12)
    # LUI value: 0xBEBC20 >> 12 = 0xBEBC (48828)
    # But we need to add 1 if lower 12 bits >= 2048 (sign bit set)
    # Lower 12 bits: 0x20 (32) - no adjustment needed
    
    counter_target = 12_500_000  # ~100ms @ 125MHz
    lui_value = (counter_target >> 12) & 0xFFFFF
    addi_value = counter_target & 0xFFF
    
    # Check if ADDI value is negative (>= 2048)
    if addi_value >= 2048:
        lui_value += 1
        addi_value = addi_value - 4096  # Two's complement
    
    print(f"  LUI value: 0x{lui_value:05X} ({lui_value})")
    print(f"  ADDI value: 0x{addi_value:03X} ({addi_value})")
    print()
    
    # JAL from addr 11 to addr 1
    jal_offset = (1 - 11) * 4  # -40 bytes
    jal_insn = encode_jal(jal_offset)
    print(f"JAL instruction: 0x{jal_insn:08X} (offset {jal_offset} bytes)")
    print()
    
    prog = [
        # Setup LED base address
        0x000048B7,  #  0: lui  x17, 0x4          # x17 = 0x4000
        
        # ===== Pattern 1: LED = 1 =====
        0x00100093,  #  1: addi x1, x0, 1         # x1 = 1
        0x0618AE23,  #  2: sw   x1, 0x7C(x17)     # LED = 1 (0b0001)
        
        # Long delay loop 1
        (lui_value << 12) | 0x00000197,  #  3: lui  x3, lui_value
        0x00018193 | ((addi_value & 0xFFF) << 20),  #  4: addi x3, x3, addi_value
        0xFFF18193,  #  5: addi x3, x3, -1        # x3--
        0xFE019EE3,  #  6: bne  x3, x0, -4        # if x3!=0 goto addr 5
        
        # ===== Pattern 2: LED = 14 =====
        0x00E00093,  #  7: addi x1, x0, 14        # x1 = 14 (0b1110)
        0x0618AE23,  #  8: sw   x1, 0x7C(x17)     # LED = 14
        
        # Long delay loop 2
        (lui_value << 12) | 0x00000197,  #  9: lui  x3, lui_value
        0x00018193 | ((addi_value & 0xFFF) << 20),  # 10: addi x3, x3, addi_value
        0xFFF18193,  # 11: addi x3, x3, -1
        0xFE019EE3,  # 12: bne  x3, x0, -4        # goto addr 11
        
        jal_insn,    # 13: jal  x0, offset        # goto addr 1
    ]
    
    # Recalculate JAL for actual position
    jal_offset = (1 - 13) * 4  # -48 bytes
    prog[13] = encode_jal(jal_offset)
    
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
    print("Expected: ~200ms cycle (100ms per pattern)")
    print("Should see slow, clear alternating blink")
    print()
    
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_RUN)
    
    print("[OK] Running. Watch LEDs alternate: 0001 ↔ 1110")
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
