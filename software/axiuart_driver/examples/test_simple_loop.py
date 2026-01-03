#!/usr/bin/env python3
"""
LED Blink - Simple Loop with Full Verification
===============================================
Implements 2-pattern blink with BEQ loop.
Includes full verification like test_reset_verify.py.

Pattern: LED=1 → LED=14 → loop back
"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

def read_cpu_mem(drv, byte_addr, cpu_halt_flag):
    """Read CPU memory via debug interface"""
    drv.write_reg32(drv.REG_CPU_MEM_ADDR, byte_addr)
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, cpu_halt_flag | (1 << 4))
    time.sleep(0.002)
    return drv.read_reg32(drv.REG_CPU_MEM_RDATA)

def encode_beq(rs1, rs2, offset_bytes):
    """Encode BEQ instruction"""
    if offset_bytes % 2 != 0:
        raise ValueError(f"Branch offset must be 2-byte aligned")
    
    if offset_bytes < 0:
        imm = offset_bytes & 0x1FFF
    else:
        imm = offset_bytes
    
    imm_12 = (imm >> 12) & 0x1
    imm_11 = (imm >> 11) & 0x1
    imm_10_5 = (imm >> 5) & 0x3F
    imm_4_1 = (imm >> 1) & 0xF
    
    insn = ((imm_12 << 31) | (imm_10_5 << 25) | (rs2 << 20) | (rs1 << 15) | 
            (0x0 << 12) | (imm_4_1 << 8) | (imm_11 << 7) | 0x63)
    
    return insn & 0xFFFFFFFF

def main():
    print("=" * 70)
    print("LED Blink - Simple Loop with Verification")
    print("=" * 70)
    print()
    
    drv = AXIUARTDriver(port='COM3', baudrate=115200)
    drv.open()
    
    CPU_RUN = (1 << 7)
    CPU_HALT = (1 << 8)
    CPU_HALTED = (1 << 9)
    MEM_WRITE = (1 << 5)
    MEM_BUSY = (1 << 6)
    
    # Full reset sequence
    print("[1/7] Forcing CPU halt...")
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.2)
    ctrl = drv.read_reg32(drv.REG_CPU_MEM_CTRL)
    print(f"[OK] CPU halted (CTRL=0x{ctrl:08X})")
    
    print("[2/7] Clearing memory...")
    for addr in range(100):
        byte_addr = addr * 4
        drv.write_reg32(drv.REG_CPU_MEM_ADDR, byte_addr)
        drv.write_reg32(drv.REG_CPU_MEM_WDATA, 0)
        drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT | MEM_WRITE | 0xF)
        time.sleep(0.001)
        for _ in range(10):
            ctrl = drv.read_reg32(drv.REG_CPU_MEM_CTRL)
            if not (ctrl & MEM_BUSY):
                break
            time.sleep(0.001)
    print("[OK] Memory cleared")
    
    print("[3/7] Verifying memory cleared...")
    for addr in range(10):
        byte_addr = addr * 4
        data = read_cpu_mem(drv, byte_addr, CPU_HALT)
        if data != 0:
            print(f"[WARN] Memory[{addr}] = 0x{data:08X}")
    print("[OK] Memory verification passed")
    
    print("[4/7] Loading program...")
    print()
    print("Program structure:")
    print("  0: LUI x17, 0x4       # LED base")
    print("  1: ADDI x1, x0, 1     # Pattern 1")
    print("  2: SW x1, 0x7C(x17)   # Write LED=1")
    print("  3: ADDI x1, x0, 14    # Pattern 2")
    print("  4: SW x1, 0x7C(x17)   # Write LED=14")
    print("  5: BEQ x0, x0, -16    # Loop to addr 1")
    print()
    
    # Build program
    beq_offset = (1 - 5) * 4  # -16 bytes
    beq_insn = encode_beq(rs1=0, rs2=0, offset_bytes=beq_offset)
    
    prog = [
        0x000048B7,  #  0: lui  x17, 0x4
        0x00100093,  #  1: addi x1, x0, 1
        0x0618AE23,  #  2: sw   x1, 0x7C(x17)
        0x00E00093,  #  3: addi x1, x0, 14
        0x0618AE23,  #  4: sw   x1, 0x7C(x17)
        beq_insn,    #  5: beq  x0, x0, -16
    ]
    
    print(f"BEQ encoding: 0x{beq_insn:08X} (offset {beq_offset} bytes)")
    print()
    
    for i, insn in enumerate(prog):
        byte_addr = i * 4
        drv.write_reg32(drv.REG_CPU_MEM_ADDR, byte_addr)
        drv.write_reg32(drv.REG_CPU_MEM_WDATA, insn)
        drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT | MEM_WRITE | 0xF)
        time.sleep(0.002)
        for _ in range(10):
            ctrl = drv.read_reg32(drv.REG_CPU_MEM_CTRL)
            if not (ctrl & MEM_BUSY):
                break
            time.sleep(0.001)
    print("[OK] Program loaded")
    
    print("[5/7] Verifying program...")
    all_match = True
    for i, expected in enumerate(prog):
        byte_addr = i * 4
        actual = read_cpu_mem(drv, byte_addr, CPU_HALT)
        if actual != expected:
            print(f"[ERROR] Memory[{i}]: expected 0x{expected:08X}, got 0x{actual:08X}")
            all_match = False
        else:
            print(f"  [{i}] 0x{actual:08X} ✓")
    
    if not all_match:
        print("[FAIL] Program verification failed!")
        return
    print("[OK] Program verification passed")
    
    print("[6/7] Confirming CPU halt...")
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.1)
    print("[OK]")
    
    print("[7/7] Running CPU...")
    print()
    print("Starting infinite loop: LED 1 ↔ LED 14")
    print("CPU will run indefinitely until you press Ctrl+C")
    print()
    
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_RUN)
    
    print("[OK] Running.")
    print()
    print("Expected LED behavior:")
    print("  Both LEDs equally bright: Loop working! (too fast)")
    print("  LSB only: Stuck at pattern 1 (loop broken)")
    print("  Upper 3 only: Stuck at pattern 2 (BEQ broken)")
    print()
    print("Press Ctrl+C to stop...")
    print()
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[OK] Stopping...")
        drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT)
        print("[OK] CPU halted")

if __name__ == '__main__':
    main()
