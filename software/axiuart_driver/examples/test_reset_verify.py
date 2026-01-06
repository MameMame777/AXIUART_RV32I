#!/usr/bin/env python3
"""
LED Test - With Full CPU Reset Sequence
========================================
Implements complete reset and verification:
1. Force CPU halt
2. Clear ALL memory (larger range)
3. Verify memory is cleared
4. Load program
5. Verify program loaded correctly
6. Reset PC to 0
7. Run CPU
"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

def read_cpu_mem(drv, byte_addr, cpu_halt_flag):
    """Read CPU memory via debug interface"""
    drv.write_reg32(drv.REG_CPU_MEM_ADDR, byte_addr)
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, cpu_halt_flag | (1 << 4))  # MEM_READ
    time.sleep(0.002)
    return drv.read_reg32(drv.REG_CPU_MEM_RDATA)

def main():
    print("=" * 70)
    print("LED Test - Full Reset & Verification")
    print("=" * 70)
    print()
    
    drv = AXIUARTDriver(port='COM3', baudrate=115200)
    drv.open()
    
    CPU_RUN = (1 << 7)
    CPU_HALT = (1 << 8)
    CPU_HALTED = (1 << 9)
    MEM_WRITE = (1 << 5)
    MEM_BUSY = (1 << 6)
    
    # Step 1: Force halt
    print("[1/7] Forcing CPU halt...")
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.2)  # Longer wait
    
    ctrl = drv.read_reg32(drv.REG_CPU_MEM_CTRL)
    if not (ctrl & CPU_HALTED):
        print(f"[WARN] CPU may not be halted (CTRL=0x{ctrl:08X})")
    else:
        print(f"[OK] CPU halted (CTRL=0x{ctrl:08X})")
    
    # Step 2: Clear large memory range
    print("[2/7] Clearing memory (0-99 words = 400 bytes)...")
    for addr in range(100):
        byte_addr = addr * 4
        drv.write_reg32(drv.REG_CPU_MEM_ADDR, byte_addr)
        drv.write_reg32(drv.REG_CPU_MEM_WDATA, 0)
        drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT | MEM_WRITE | 0xF)
        time.sleep(0.001)
        # Wait for write complete
        for _ in range(10):
            ctrl = drv.read_reg32(drv.REG_CPU_MEM_CTRL)
            if not (ctrl & MEM_BUSY):
                break
            time.sleep(0.001)
    print("[OK] Memory cleared")
    
    # Step 3: Verify first few locations are 0
    print("[3/7] Verifying memory cleared...")
    all_zero = True
    for addr in range(10):
        byte_addr = addr * 4
        data = read_cpu_mem(drv, byte_addr, CPU_HALT)
        if data != 0:
            print(f"[WARN] Memory[{addr}] = 0x{data:08X} (expected 0)")
            all_zero = False
    if all_zero:
        print("[OK] Memory verification passed")
    
    # Step 4: Load program
    print("[4/7] Loading program...")
    prog = [
        0x000048B7,  #  0: lui  x17, 0x4
        0x00100093,  #  1: addi x1, x0, 1
        0x0618AE23,  #  2: sw   x1, 0x7C(x17)   # LED = 1
        0x00300093,  #  3: addi x1, x0, 3
        0x0618AE23,  #  4: sw   x1, 0x7C(x17)   # LED = 3
        0x00700093,  #  5: addi x1, x0, 7
        0x0618AE23,  #  6: sw   x1, 0x7C(x17)   # LED = 7
        0x00000013,  #  7: nop
    ]
    
    for i, insn in enumerate(prog):
        byte_addr = i * 4
        drv.write_reg32(drv.REG_CPU_MEM_ADDR, byte_addr)
        drv.write_reg32(drv.REG_CPU_MEM_WDATA, insn)
        drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT | MEM_WRITE | 0xF)
        time.sleep(0.002)
        # Wait for write
        for _ in range(10):
            ctrl = drv.read_reg32(drv.REG_CPU_MEM_CTRL)
            if not (ctrl & MEM_BUSY):
                break
            time.sleep(0.001)
    print("[OK] Program loaded")
    
    # Step 5: Verify program
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
    
    # Step 6: Ensure CPU is halted before run
    print("[6/7] Confirming CPU halt before run...")
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.1)
    ctrl = drv.read_reg32(drv.REG_CPU_MEM_CTRL)
    print(f"[OK] Pre-run CTRL=0x{ctrl:08X}")
    
    # Step 7: Run CPU
    print("[7/7] Running CPU...")
    print()
    print("Starting execution NOW...")
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_RUN)
    
    # Give CPU plenty of time
    time.sleep(0.5)
    
    print("Halting CPU...")
    drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT)
    time.sleep(0.1)
    
    ctrl = drv.read_reg32(drv.REG_CPU_MEM_CTRL)
    print()
    print("=" * 70)
    print("RESULT")
    print("=" * 70)
    print(f"Final CTRL: 0x{ctrl:08X}")
    print()
    print("Check LEDs now:")
    print("  0x1 (0b0001): Stopped after 1st SW")
    print("  0x3 (0b0011): Stopped after 2nd SW")
    print("  0x7 (0b0111): SUCCESS!")
    print()
    print("Run this test multiple times and report:")
    print("  - Does LED value stay consistent?")
    print("  - What is the LED value?")
    print()

if __name__ == '__main__':
    main()
