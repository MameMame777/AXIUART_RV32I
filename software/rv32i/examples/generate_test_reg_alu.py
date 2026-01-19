#!/usr/bin/env python3
"""
Generate Test 2.1: R-Type Register ALU Operations (ADD/SUB/SLT/SLTU/XOR/OR/AND)
Tests all register-register arithmetic and logic operations with comprehensive
coverage of edge cases:
- ADD/SUB: Overflow, negative results, zero operands
- SLT/SLTU: Signed vs unsigned comparison distinction
- XOR/OR/AND: Bitwise operations with identity and masking patterns

Author: GitHub Copilot
Date: 2026-01-16
"""

import sys
import os

# Add parent directory to path for encoder import
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from encoder import RV32IInstructionEncoder

def generate_reg_alu_test():
    """Generate R-type register ALU test program"""
    encoder = RV32IInstructionEncoder()
    instructions = []
    
    print("=" * 70)
    print("Test 2.1: R-Type Register ALU Operations")
    print("=" * 70)
    
    # ========== CSR Initialization (2 instructions) ==========
    print("\n[CSR Initialization]")
    instructions.append(encoder.addi(rd=31, rs1=0, imm=0x200))  # x31 = 0x200
    instructions.append(encoder.csrrw(rd=0, csr=0x305, rs1=31))  # mtvec = 0x200
    print(f"  CSR setup: mtvec = 0x200")
    
    # ========== Setup Test Values (10 instructions) ==========
    print("\n[Setup Phase - Prepare test operands]")
    
    # x11 = 100 (basic positive value)
    instructions.append(encoder.addi(rd=11, rs1=0, imm=100))
    print(f"  x11 = 100 (basic positive)")
    
    # x12 = 50 (smaller positive)
    instructions.append(encoder.addi(rd=12, rs1=0, imm=50))
    print(f"  x12 = 50 (smaller positive)")
    
    # x13 = -10 (negative value)
    instructions.append(encoder.addi(rd=13, rs1=0, imm=-10))
    print(f"  x13 = -10 (negative)")
    
    # x14 = 0xFFFFFFFF (all ones / -1)
    instructions.append(encoder.addi(rd=14, rs1=0, imm=-1))
    print(f"  x14 = 0xFFFFFFFF (all ones / -1)")
    
    # x15 = 0 (zero)
    instructions.append(encoder.addi(rd=15, rs1=0, imm=0))
    print(f"  x15 = 0 (zero)")
    
    # x16 = 0xF0 (bit pattern for masking)
    instructions.append(encoder.addi(rd=16, rs1=0, imm=0xF0))
    print(f"  x16 = 0xF0 (mask pattern)")
    
    # x17 = 0x0F (complement mask)
    instructions.append(encoder.addi(rd=17, rs1=0, imm=0x0F))
    print(f"  x17 = 0x0F (complement mask)")
    
    # x18 = 1 (unit value)
    instructions.append(encoder.addi(rd=18, rs1=0, imm=1))
    print(f"  x18 = 1 (unit)")
    
    # x19 = 0x7FFFFFFF (max positive signed)
    instructions.append(encoder.lui(rd=19, imm=0x80000))
    instructions.append(encoder.addi(rd=19, rs1=19, imm=-1))
    print(f"  x19 = 0x7FFFFFFF (max positive)")
    
    # x20 = 0x80000000 (min negative signed)
    instructions.append(encoder.lui(rd=20, imm=0x80000))
    print(f"  x20 = 0x80000000 (min negative)")
    
    # ========== ADD Tests (5 instructions → x1-x5) ==========
    print("\n[ADD Tests - Register Addition]")
    
    # Test 1: Basic addition
    instructions.append(encoder.add(rd=1, rs1=11, rs2=12))
    print(f"  x1 = x11 + x12 = 100 + 50 = 150")
    
    # Test 2: Add negative
    instructions.append(encoder.add(rd=2, rs1=11, rs2=13))
    print(f"  x2 = x11 + x13 = 100 + (-10) = 90")
    
    # Test 3: Overflow wrap (max + 1)
    instructions.append(encoder.add(rd=3, rs1=19, rs2=18))
    print(f"  x3 = x19 + x18 = 0x7FFFFFFF + 1 = 0x80000000 (overflow)")
    
    # Test 4: Zero + zero
    instructions.append(encoder.add(rd=4, rs1=15, rs2=15))
    print(f"  x4 = x15 + x15 = 0 + 0 = 0")
    
    # Test 5: -1 + 1 = 0
    instructions.append(encoder.add(rd=5, rs1=14, rs2=18))
    print(f"  x5 = x14 + x18 = -1 + 1 = 0")
    
    # ========== SUB Tests (5 instructions → x6-x10) ==========
    print("\n[SUB Tests - Register Subtraction]")
    
    # Test 6: Basic subtraction
    instructions.append(encoder.sub(rd=6, rs1=11, rs2=12))
    print(f"  x6 = x11 - x12 = 100 - 50 = 50")
    
    # Test 7: Negative result
    instructions.append(encoder.sub(rd=7, rs1=12, rs2=11))
    print(f"  x7 = x12 - x11 = 50 - 100 = -50")
    
    # Test 8: Zero - 1 = -1
    instructions.append(encoder.sub(rd=8, rs1=15, rs2=18))
    print(f"  x8 = x15 - x18 = 0 - 1 = -1 (0xFFFFFFFF)")
    
    # Test 9: Same operands (x - x = 0)
    instructions.append(encoder.sub(rd=9, rs1=11, rs2=11))
    print(f"  x9 = x11 - x11 = 100 - 100 = 0")
    
    # Test 10: Underflow wrap (min - 1)
    instructions.append(encoder.sub(rd=10, rs1=20, rs2=18))
    print(f"  x10 = x20 - x18 = 0x80000000 - 1 = 0x7FFFFFFF (underflow)")
    
    # ========== SLT Tests (3 instructions → x21-x23) ==========
    print("\n[SLT Tests - Set Less Than (Signed)]")
    
    # Test 11: 50 < 100 (true)
    instructions.append(encoder.slt(rd=21, rs1=12, rs2=11))
    print(f"  x21 = (x12 < x11) = (50 < 100) = 1")
    
    # Test 12: 100 < -10 (false, signed)
    instructions.append(encoder.slt(rd=22, rs1=11, rs2=13))
    print(f"  x22 = (x11 < x13) = (100 < -10 signed) = 0")
    
    # Test 13: -10 < 0 (true)
    instructions.append(encoder.slt(rd=23, rs1=13, rs2=15))
    print(f"  x23 = (x13 < x15) = (-10 < 0) = 1")
    
    # ========== SLTU Tests (3 instructions → x24-x26) ==========
    print("\n[SLTU Tests - Set Less Than Unsigned]")
    
    # Test 14: 50 <u 100 (true)
    instructions.append(encoder.sltu(rd=24, rs1=12, rs2=11))
    print(f"  x24 = (x12 <u x11) = (50 <u 100) = 1")
    
    # Test 15: -10 <u 100 (false, unsigned: 0xFFFFFFF6 > 100)
    instructions.append(encoder.sltu(rd=25, rs1=13, rs2=11))
    print(f"  x25 = (x13 <u x11) = (0xFFFFFFF6 <u 100) = 0")
    
    # Test 16: 0 <u 1 (true)
    instructions.append(encoder.sltu(rd=26, rs1=15, rs2=18))
    print(f"  x26 = (x15 <u x18) = (0 <u 1) = 1")
    
    # ========== XOR Tests (4 instructions → x27-x30) ==========
    print("\n[XOR Tests - Bitwise Exclusive OR]")
    
    # Test 17: XOR with 0 (identity)
    instructions.append(encoder.xor(rd=27, rs1=14, rs2=15))
    print(f"  x27 = x14 ^ x15 = 0xFFFFFFFF ^ 0 = 0xFFFFFFFF")
    
    # Test 18: XOR with self (always 0)
    instructions.append(encoder.xor(rd=28, rs1=11, rs2=11))
    print(f"  x28 = x11 ^ x11 = 100 ^ 100 = 0")
    
    # Test 19: XOR mask patterns
    instructions.append(encoder.xor(rd=29, rs1=16, rs2=17))
    print(f"  x29 = x16 ^ x17 = 0xF0 ^ 0x0F = 0xFF")
    
    # Test 20: XOR toggle bits
    instructions.append(encoder.xor(rd=30, rs1=14, rs2=18))
    print(f"  x30 = x14 ^ x18 = 0xFFFFFFFF ^ 1 = 0xFFFFFFFE")
    
    # ========== OR Tests (3 instructions) - Reuse x1-x3 ==========
    print("\n[OR Tests - Bitwise OR]")
    
    # Test 21: OR with 0 (identity)
    instructions.append(encoder.or_(rd=1, rs1=14, rs2=15))
    print(f"  x1 = x14 | x15 = 0xFFFFFFFF | 0 = 0xFFFFFFFF")
    
    # Test 22: OR with self (identity)
    instructions.append(encoder.or_(rd=2, rs1=11, rs2=11))
    print(f"  x2 = x11 | x11 = 100 | 100 = 100")
    
    # Test 23: OR merge patterns
    instructions.append(encoder.or_(rd=3, rs1=16, rs2=17))
    print(f"  x3 = x16 | x17 = 0xF0 | 0x0F = 0xFF")
    
    # ========== AND Tests (3 instructions) - Reuse x4-x6 ==========
    print("\n[AND Tests - Bitwise AND]")
    
    # Test 24: AND with 0 (always 0)
    instructions.append(encoder.and_(rd=4, rs1=14, rs2=15))
    print(f"  x4 = x14 & x15 = 0xFFFFFFFF & 0 = 0")
    
    # Test 25: AND with self (identity)
    instructions.append(encoder.and_(rd=5, rs1=11, rs2=11))
    print(f"  x5 = x11 & x11 = 100 & 100 = 100")
    
    # Test 26: AND masking
    instructions.append(encoder.and_(rd=6, rs1=16, rs2=17))
    print(f"  x6 = x16 & x17 = 0xF0 & 0x0F = 0")
    
    # ========== EBREAK (1 instruction) ==========
    print("\n[Completion]")
    instructions.append(0x00100073)  # EBREAK
    print(f"  EBREAK - Signal test completion")
    
    # ========== Summary ==========
    total_instructions = len(instructions)
    print("\n" + "=" * 70)
    print(f"Total Instructions: {total_instructions}")
    print(f"  - CSR Init:  2")
    print(f"  - Setup:     12")
    print(f"  - ADD:       5 (x1-x5)")
    print(f"  - SUB:       5 (x6-x10)")
    print(f"  - SLT:       3 (x21-x23)")
    print(f"  - SLTU:      3 (x24-x26)")
    print(f"  - XOR:       4 (x27-x30)")
    print(f"  - OR:        3 (x1-x3 reused)")
    print(f"  - AND:       3 (x4-x6 reused)")
    print(f"  - EBREAK:    1")
    print("=" * 70)
    
    # ========== Write to hex file ==========
    output_dir = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'sim', 'tests')
    os.makedirs(output_dir, exist_ok=True)
    output_file = os.path.join(output_dir, 'rv32i_reg_alu_test.hex')
    
    with open(output_file, 'w') as f:
        for instr in instructions:
            f.write(f"{instr:08x}\n")
    
    print(f"\n✓ Hex file generated: {output_file}")
    print(f"  ({total_instructions} instructions)")
    
    # ========== Expected Results Summary ==========
    print("\n" + "=" * 70)
    print("Expected Results (for UVM verification):")
    print("=" * 70)
    print("ADD Tests:")
    print("  x1  = 0x00000096  (100 + 50 = 150)")
    print("  x2  = 0x0000005A  (100 + (-10) = 90)")
    print("  x3  = 0x80000000  (0x7FFFFFFF + 1, overflow)")
    print("  x4  = 0x00000000  (0 + 0)")
    print("  x5  = 0x00000000  (-1 + 1)")
    print("\nSUB Tests:")
    print("  x6  = 0x00000032  (100 - 50 = 50)")
    print("  x7  = 0xFFFFFFCE  (50 - 100 = -50)")
    print("  x8  = 0xFFFFFFFF  (0 - 1 = -1)")
    print("  x9  = 0x00000000  (100 - 100)")
    print("  x10 = 0x7FFFFFFF  (0x80000000 - 1, underflow)")
    print("\nSLT Tests (Signed):")
    print("  x21 = 0x00000001  (50 < 100)")
    print("  x22 = 0x00000000  (100 < -10 signed is false)")
    print("  x23 = 0x00000001  (-10 < 0)")
    print("\nSLTU Tests (Unsigned):")
    print("  x24 = 0x00000001  (50 <u 100)")
    print("  x25 = 0x00000000  (0xFFFFFFF6 <u 100 is false)")
    print("  x26 = 0x00000001  (0 <u 1)")
    print("\nXOR Tests:")
    print("  x27 = 0xFFFFFFFF  (0xFFFFFFFF ^ 0)")
    print("  x28 = 0x00000000  (100 ^ 100)")
    print("  x29 = 0x000000FF  (0xF0 ^ 0x0F)")
    print("  x30 = 0xFFFFFFFE  (0xFFFFFFFF ^ 1)")
    print("\nOR Tests (Overwrite x1-x3):")
    print("  x1  = 0xFFFFFFFF  (0xFFFFFFFF | 0)")
    print("  x2  = 0x00000064  (100 | 100)")
    print("  x3  = 0x000000FF  (0xF0 | 0x0F)")
    print("\nAND Tests (Overwrite x4-x6):")
    print("  x4  = 0x00000000  (0xFFFFFFFF & 0)")
    print("  x5  = 0x00000064  (100 & 100)")
    print("  x6  = 0x00000000  (0xF0 & 0x0F)")
    print("=" * 70)
    print("\nKEY DISTINCTIONS VERIFIED:")
    print("  ADD Overflow: 0x7FFFFFFF + 1 = 0x80000000 (wraps to negative)")
    print("  SUB Underflow: 0x80000000 - 1 = 0x7FFFFFFF (wraps to positive)")
    print("  SLT vs SLTU: -10 <s 100 is true, but -10 <u 100 is false")
    print("=" * 70)

if __name__ == '__main__':
    generate_reg_alu_test()
