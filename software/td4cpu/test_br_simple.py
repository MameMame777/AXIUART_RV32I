#!/usr/bin/env python3
"""Simple BR instruction test"""

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from axiuart_driver import AXIUARTDriver, registers
from td4cpu import isa

def test_simple_br():
    """Test simple unconditional branch loop"""
    d = AXIUARTDriver('COM3')
    d.open()
    
    # Reset CPU
    d.write_reg32(registers.REG_CPU_DBG_CTRL, 1)  # HALT
    time.sleep(0.01)
    d.write_reg32(registers.REG_CPU_PC, 0)
    
    # Build simple 2-instruction loop:
    # [0]: LDI R0, #0xF (load LED pattern)
    # [1]: BR.AL -1 (branch back to [0])
    program = [
        (isa.OP_LDI << 12) | (0 << 9) | 0xF,  # LDI R0, #0xF
        (isa.OP_BR << 12) | (0 << 9) | (-1 & 0x1FF),  # BR.AL offset=-1 (loop to PC=0)
    ]
    
    print(f"Program:")
    for i, insn in enumerate(program):
        op = insn >> 12
        cond = (insn >> 9) & 7
        off = insn & 0x1FF
        print(f"  [{i}] 0x{insn:04X} | op={op} cond={cond} off=0x{off:03X} (signed={(off if off < 256 else off-512)})")
    
    # Load to RAM
    for addr, insn in enumerate(program):
        d.write_reg32(registers.REG_CPU_MEM_ADDR, addr)
        d.write_reg32(registers.REG_CPU_MEM_WDATA, insn)
        d.write_reg32(registers.REG_CPU_MEM_CTRL, 2)  # WRITE
    
    print("\nVerifying...")
    for addr, expected in enumerate(program):
        d.write_reg32(registers.REG_CPU_MEM_ADDR, addr)
        d.write_reg32(registers.REG_CPU_MEM_CTRL, 1)  # READ
        time.sleep(0.001)
        actual = d.read_reg32(registers.REG_CPU_MEM_RDATA) & 0xFFFF
        print(f"  RAM[{addr}] = 0x{actual:04X} (expected 0x{expected:04X}) {'✓' if actual == expected else '✗'}")
    
    # Run CPU
    print("\nStarting CPU...")
    d.write_reg32(registers.REG_CPU_DBG_CTRL, 2)  # RUN
    
    # Sample PC multiple times
    print("\nPC samples:")
    for i in range(10):
        time.sleep(0.01)
        pc = d.read_reg32(registers.REG_CPU_PC)
        status = d.read_reg32(registers.REG_CPU_DBG_STATUS)
        print(f"  [{i}] PC=0x{pc:04X}, Status=0x{status:08X} (HALTED={status&1})")
    
    # Halt
    d.write_reg32(registers.REG_CPU_DBG_CTRL, 1)
    d.close()

if __name__ == '__main__':
    test_simple_br()
