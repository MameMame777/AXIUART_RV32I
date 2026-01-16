#!/usr/bin/env python3
"""
Generate Test 2.3: R-Type Register Shift Operations (SLL/SRL/SRA)
Tests register-sourced shift operations vs immediate variants (Test 1.4).
Validates register-based shift amounts and critical SRL/SRA distinction on negative operands.

Author: GitHub Copilot
Date: 2026-01-17
"""

import sys
import os

# Add parent directory to path for encoder import
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from encoder import RV32IInstructionEncoder

def generate_reg_shift_test():
    """Generate R-type register shift test program"""
    encoder = RV32IInstructionEncoder()
    instructions = []
    
    print("=" * 70)
    print("Test 2.3: R-Type Register Shift Operations")
    print("=" * 70)
    
    # ========== CSR Initialization (2 instructions) ==========
    print("\n[CSR Initialization]")
    instructions.append(encoder.addi(rd=31, rs1=0, imm=0x200))  # x31 = 0x200
    instructions.append(encoder.csrrw(rd=0, csr=0x305, rs1=31))  # mtvec = 0x200
    print(f"  CSR setup: mtvec = 0x200")
    
    # ========== Setup Test Values (14 instructions) ==========
    print("\n[Setup Phase - Prepare operands and shift amounts]")
    
    # Test operands
    # x11 = 0x00000001 (basic bit pattern)
    instructions.append(encoder.addi(rd=11, rs1=0, imm=1))
    print(f"  x11 = 0x00000001 (basic pattern)")
    
    # x12 = 0x80000000 (sign bit - critical for SRL/SRA distinction)
    instructions.append(encoder.lui(rd=12, imm=0x80000))
    print(f"  x12 = 0x80000000 (sign bit)")
    
    # x13 = 0x12345678 (complex pattern)
    instructions.append(encoder.lui(rd=13, imm=0x12345))
    instructions.append(encoder.addi(rd=13, rs1=13, imm=0x678))
    print(f"  x13 = 0x12345678 (complex pattern)")
    
    # x14 = 0xFFFFFFFF (all ones / -1)
    instructions.append(encoder.addi(rd=14, rs1=0, imm=-1))
    print(f"  x14 = 0xFFFFFFFF (all ones / -1)")
    
    # x24 = 0 (zero for identity tests)
    instructions.append(encoder.addi(rd=24, rs1=0, imm=0))
    print(f"  x24 = 0 (zero shift amount)")
    
    # Shift amounts in separate registers
    # x25 = 1
    instructions.append(encoder.addi(rd=25, rs1=0, imm=1))
    print(f"  x25 = 1 (shift by 1)")
    
    # x26 = 8
    instructions.append(encoder.addi(rd=26, rs1=0, imm=8))
    print(f"  x26 = 8 (shift by 8)")
    
    # x27 = 16
    instructions.append(encoder.addi(rd=27, rs1=0, imm=16))
    print(f"  x27 = 16 (shift by 16)")
    
    # x28 = 31
    instructions.append(encoder.addi(rd=28, rs1=0, imm=31))
    print(f"  x28 = 31 (max shift)")
    
    # x29 = 4 (nibble shift)
    instructions.append(encoder.addi(rd=29, rs1=0, imm=4))
    print(f"  x29 = 4 (nibble shift)")
    
    # x30 = 32 (>31, should use only lower 5 bits = 0)
    instructions.append(encoder.addi(rd=30, rs1=0, imm=32))
    print(f"  x30 = 32 (tests lower 5-bit masking)")
    
    # ========== SLL Tests (6 instructions → x1-x6) ==========
    print("\n[SLL Tests - Shift Left Logical]")
    
    # Test 1: Identity shift (amount = 0)
    instructions.append(encoder.sll(rd=1, rs1=11, rs2=24))
    print(f"  x1 = x11 << x24 = 0x00000001 << 0 = 0x00000001 (identity)")
    
    # Test 2: Shift by 1
    instructions.append(encoder.sll(rd=2, rs1=11, rs2=25))
    print(f"  x2 = x11 << x25 = 0x00000001 << 1 = 0x00000002")
    
    # Test 3: Byte shift
    instructions.append(encoder.sll(rd=3, rs1=11, rs2=26))
    print(f"  x3 = x11 << x26 = 0x00000001 << 8 = 0x00000100")
    
    # Test 4: Max shift (bit 0 → bit 31)
    instructions.append(encoder.sll(rd=4, rs1=11, rs2=28))
    print(f"  x4 = x11 << x28 = 0x00000001 << 31 = 0x80000000")
    
    # Test 5: Complex pattern overflow
    instructions.append(encoder.sll(rd=5, rs1=13, rs2=29))
    print(f"  x5 = x13 << x29 = 0x12345678 << 4 = 0x23456780 (overflow)")
    
    # Test 6: >31 shift amount (should use only lower 5 bits)
    instructions.append(encoder.sll(rd=6, rs1=11, rs2=30))
    print(f"  x6 = x11 << x30 = 0x00000001 << (32&0x1F) = 0x00000001 (masked)")
    
    # ========== SRL Tests (6 instructions → x7-x10, x15-x16) - Zero-fill ==========
    print("\n[SRL Tests - Shift Right Logical (Zero-fill)]")
    
    # Test 7: All ones >> 1 (zero-fill)
    instructions.append(encoder.srl(rd=7, rs1=14, rs2=25))
    print(f"  x7 = x14 >>u x25 = 0xFFFFFFFF >> 1 = 0x7FFFFFFF (zero-fill)")
    
    # Test 8: Sign bit >> 16 (CRITICAL: zero-fill, NOT sign-extend)
    instructions.append(encoder.srl(rd=8, rs1=12, rs2=27))
    print(f"  x8 = x12 >>u x27 = 0x80000000 >> 16 = 0x00008000 (CRITICAL)")
    
    # Test 9: Complex pattern >> 4
    instructions.append(encoder.srl(rd=9, rs1=13, rs2=29))
    print(f"  x9 = x13 >>u x29 = 0x12345678 >> 4 = 0x01234567")
    
    # Test 10: Max shift
    instructions.append(encoder.srl(rd=10, rs1=14, rs2=28))
    print(f"  x10 = x14 >>u x28 = 0xFFFFFFFF >> 31 = 0x00000001")
    
    # Test 11: Identity (shift by 0)
    instructions.append(encoder.srl(rd=15, rs1=11, rs2=24))
    print(f"  x15 = x11 >>u x24 = 0x00000001 >> 0 = 0x00000001")
    
    # Test 12: >31 shift amount masking
    instructions.append(encoder.srl(rd=16, rs1=14, rs2=30))
    print(f"  x16 = x14 >>u x30 = 0xFFFFFFFF >> (32&0x1F) = 0xFFFFFFFF")
    
    # ========== SRA Tests (6 instructions → x17-x22) - Sign-extend ==========
    print("\n[SRA Tests - Shift Right Arithmetic (Sign-extend)]")
    
    # Test 13: Positive number (same as SRL)
    instructions.append(encoder.sra(rd=17, rs1=13, rs2=29))
    print(f"  x17 = x13 >>s x29 = 0x12345678 >> 4 = 0x01234567 (positive)")
    
    # Test 14: -1 >> 1 (sign-extend to -1)
    instructions.append(encoder.sra(rd=18, rs1=14, rs2=25))
    print(f"  x18 = x14 >>s x25 = 0xFFFFFFFF >> 1 = 0xFFFFFFFF (sign-extend)")
    
    # Test 15: Sign bit >> 16 (CRITICAL: sign-extend, NOT zero-fill)
    instructions.append(encoder.sra(rd=19, rs1=12, rs2=27))
    print(f"  x19 = x12 >>s x27 = 0x80000000 >> 16 = 0xFFFF8000 (CRITICAL)")
    
    # Test 16: Sign bit >> 8 (partial sign-extend)
    instructions.append(encoder.sra(rd=20, rs1=12, rs2=26))
    print(f"  x20 = x12 >>s x26 = 0x80000000 >> 8 = 0xFF800000")
    
    # Test 17: Max shift (all sign bits)
    instructions.append(encoder.sra(rd=21, rs1=12, rs2=28))
    print(f"  x21 = x12 >>s x28 = 0x80000000 >> 31 = 0xFFFFFFFF")
    
    # Test 18: Identity (shift by 0)
    instructions.append(encoder.sra(rd=22, rs1=13, rs2=24))
    print(f"  x22 = x13 >>s x24 = 0x12345678 >> 0 = 0x12345678")
    
    # ========== EBREAK (1 instruction) ==========
    print("\n[Completion]")
    instructions.append(0x00100073)  # EBREAK
    print(f"  EBREAK - Signal test completion")
    
    # ========== Summary ==========
    total_instructions = len(instructions)
    print("\n" + "=" * 70)
    print(f"Total Instructions: {total_instructions}")
    print(f"  - CSR Init:  2")
    print(f"  - Setup:     14 (4 operands + 7 shift amounts + 3 multi-instruction)")
    print(f"  - SLL:       6 (x1-x6)")
    print(f"  - SRL:       6 (x7-x10, x15-x16)")
    print(f"  - SRA:       6 (x17-x22)")
    print(f"  - EBREAK:    1")
    print("=" * 70)
    
    # ========== Write to hex file ==========
    output_dir = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'sim', 'tests')
    os.makedirs(output_dir, exist_ok=True)
    output_file = os.path.join(output_dir, 'rv32i_reg_shift_test.hex')
    
    with open(output_file, 'w') as f:
        for instr in instructions:
            f.write(f"{instr:08x}\n")
    
    print(f"\n✓ Hex file generated: {output_file}")
    print(f"  ({total_instructions} instructions)")
    
    # ========== Expected Results Summary ==========
    print("\n" + "=" * 70)
    print("Expected Results (for UVM verification):")
    print("=" * 70)
    print("SLL Tests (Shift Left Logical):")
    print("  x1  = 0x00000001  (identity: 1 << 0)")
    print("  x2  = 0x00000002  (1 << 1)")
    print("  x3  = 0x00000100  (1 << 8)")
    print("  x4  = 0x80000000  (1 << 31, max shift)")
    print("  x5  = 0x23456780  (complex pattern overflow)")
    print("  x6  = 0x00000001  (32&0x1F = 0, identity)")
    print("\nSRL Tests (Shift Right Logical - Zero-fill):")
    print("  x7  = 0x7FFFFFFF  (0xFFFFFFFF >> 1, zero-fill)")
    print("  x8  = 0x00008000  (CRITICAL: 0x80000000 >> 16, zero-fill)")
    print("  x9  = 0x01234567  (0x12345678 >> 4)")
    print("  x10 = 0x00000001  (0xFFFFFFFF >> 31)")
    print("  x15 = 0x00000001  (identity: 1 >> 0)")
    print("  x16 = 0xFFFFFFFF  (32&0x1F = 0, identity)")
    print("\nSRA Tests (Shift Right Arithmetic - Sign-extend):")
    print("  x17 = 0x01234567  (positive, same as SRL)")
    print("  x18 = 0xFFFFFFFF  (-1 >> 1, sign-extend to -1)")
    print("  x19 = 0xFFFF8000  (CRITICAL: 0x80000000 >> 16, sign-extend)")
    print("  x20 = 0xFF800000  (0x80000000 >> 8)")
    print("  x21 = 0xFFFFFFFF  (0x80000000 >> 31, all ones)")
    print("  x22 = 0x12345678  (identity: positive >> 0)")
    print("=" * 70)
    print("\nKEY DISTINCTIONS VERIFIED:")
    print("  SRL (x8):  0x80000000 >> 16 = 0x00008000 (zero-fill)")
    print("  SRA (x19): 0x80000000 >> 16 = 0xFFFF8000 (sign-extend)")
    print("  Shift amount masking: Only lower 5 bits used (rs2[4:0])")
    print("=" * 70)

if __name__ == '__main__':
    generate_reg_shift_test()
