#!/usr/bin/env python3
"""
Generate Test 1.4: Shift Immediate Instructions (SLLI/SRLI/SRAI)
Tests all three shift immediate variants with comprehensive edge case coverage:
- SLLI: Identity, byte shift, max shift, overflow, boundary conditions
- SRLI: Zero-fill verification on negative numbers
- SRAI: Sign-extension verification (critical distinction from SRLI)

Author: GitHub Copilot
Date: 2026-01-16
"""

import sys
import os

# Add parent directory to path for encoder import
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from encoder import RV32IInstructionEncoder

def generate_shift_imm_test():
    """Generate shift immediate test program"""
    encoder = RV32IInstructionEncoder()
    instructions = []
    
    print("=" * 70)
    print("Test 1.4: Shift Immediate Instructions (SLLI/SRLI/SRAI)")
    print("=" * 70)
    
    # ========== CSR Initialization (2 instructions) ==========
    print("\n[CSR Initialization]")
    # Set mtvec (exception handler base address) to 0x200
    instructions.append(encoder.addi(rd=31, rs1=0, imm=0x200))  # x31 = 0x200
    instructions.append(encoder.csrrw(rd=0, csr=0x305, rs1=31))  # mtvec = 0x200
    print(f"  CSR setup: mtvec = 0x200")
    
    # ========== Setup Test Values (7 instructions) ==========
    print("\n[Setup Phase - Prepare test operands]")
    
    # x11 = 1 (basic value for shift testing)
    instructions.append(encoder.addi(rd=11, rs1=0, imm=1))
    print(f"  x11 = 0x00000001 (basic shift operand)")
    
    # x12 = 0x80000000 (sign bit only - critical for SRAI testing)
    instructions.append(encoder.lui(rd=12, imm=0x80000))  # x12 = 0x80000000
    print(f"  x12 = 0x80000000 (sign bit - critical for SRLI/SRAI distinction)")
    
    # x13 = 0x12345678 (complex bit pattern)
    instructions.append(encoder.lui(rd=13, imm=0x12345))   # x13 = 0x12345000
    instructions.append(encoder.addi(rd=13, rs1=13, imm=0x678))  # x13 = 0x12345678
    print(f"  x13 = 0x12345678 (complex bit pattern)")
    
    # x14 = -1 = 0xFFFFFFFF (all ones)
    instructions.append(encoder.addi(rd=14, rs1=0, imm=-1))
    print(f"  x14 = 0xFFFFFFFF (all ones)")
    
    # x15 = -2 = 0xFFFFFFFE
    instructions.append(encoder.addi(rd=15, rs1=0, imm=-2))
    print(f"  x15 = 0xFFFFFFFE (negative even)")
    
    # x16 = 0x7FFFFFFF (maximum positive)
    instructions.append(encoder.lui(rd=16, imm=0x80000))   # x16 = 0x80000000
    instructions.append(encoder.addi(rd=16, rs1=16, imm=-1))  # x16 = 0x7FFFFFFF
    print(f"  x16 = 0x7FFFFFFF (max positive)")
    
    # ========== SLLI Tests (5 instructions → x1-x5) ==========
    print("\n[SLLI Tests - Shift Left Logical Immediate]")
    
    # Test 1: Identity (shift by 0)
    instructions.append(encoder.slli(rd=1, rs1=11, shamt=0))
    print(f"  x1 = x11 << 0  = 0x00000001 (identity test)")
    
    # Test 2: Byte shift
    instructions.append(encoder.slli(rd=2, rs1=11, shamt=8))
    print(f"  x2 = x11 << 8  = 0x00000100 (byte shift)")
    
    # Test 3: Maximum shift (creates sign bit)
    instructions.append(encoder.slli(rd=3, rs1=11, shamt=31))
    print(f"  x3 = x11 << 31 = 0x80000000 (max shift → sign bit)")
    
    # Test 4: Overflow (high bits discarded)
    instructions.append(encoder.slli(rd=4, rs1=13, shamt=4))
    print(f"  x4 = x13 << 4  = 0x23456780 (overflow: high nibble 0x1 lost)")
    
    # Test 5: Boundary (positive to negative)
    instructions.append(encoder.slli(rd=5, rs1=16, shamt=1))
    print(f"  x5 = x16 << 1  = 0xFFFFFFFE (positive→negative boundary)")
    
    # ========== SRLI Tests (5 instructions → x6-x10) ==========
    print("\n[SRLI Tests - Shift Right Logical Immediate (Zero-fill)]")
    
    # Test 6: Zero-fill on all ones
    instructions.append(encoder.srli(rd=6, rs1=14, shamt=1))
    print(f"  x6 = x14 >>u 1  = 0x7FFFFFFF (zero-fill from MSB)")
    
    # Test 7: Zero-fill on sign bit (CRITICAL - distinguishes from SRAI)
    instructions.append(encoder.srli(rd=7, rs1=12, shamt=16))
    print(f"  x7 = x12 >>u 16 = 0x00008000 (SRLI: zero-fill on 0x80000000)")
    
    # Test 8: Nibble shift on complex pattern
    instructions.append(encoder.srli(rd=8, rs1=13, shamt=4))
    print(f"  x8 = x13 >>u 4  = 0x01234567 (nibble shift)")
    
    # Test 9: Maximum shift (31 bits)
    instructions.append(encoder.srli(rd=9, rs1=14, shamt=31))
    print(f"  x9 = x14 >>u 31 = 0x00000001 (max shift → single bit)")
    
    # Test 10: Identity on minimal value
    instructions.append(encoder.srli(rd=10, rs1=11, shamt=0))
    print(f"  x10 = x11 >>u 0  = 0x00000001 (identity)")
    
    # ========== SRAI Tests (5 instructions → x11-x15) ==========
    print("\n[SRAI Tests - Shift Right Arithmetic Immediate (Sign-extend)]")
    
    # Test 11: Positive number (same as SRLI for positive)
    instructions.append(encoder.srai(rd=17, rs1=13, shamt=4))
    print(f"  x17 = x13 >>s 4  = 0x01234567 (positive: same as SRLI)")
    
    # Test 12: Sign-extend negative (-2 → -1)
    instructions.append(encoder.srai(rd=18, rs1=15, shamt=1))
    print(f"  x18 = x15 >>s 1  = 0xFFFFFFFF (sign-extend: -2 → -1)")
    
    # Test 13: Sign-extend on sign bit (CRITICAL - distinguishes from SRLI)
    instructions.append(encoder.srai(rd=19, rs1=12, shamt=8))
    print(f"  x19 = x12 >>s 8  = 0xFF800000 (SRAI: sign-extend on 0x80000000)")
    
    # Test 14: Maximum shift to all ones
    instructions.append(encoder.srai(rd=20, rs1=12, shamt=31))
    print(f"  x20 = x12 >>s 31 = 0xFFFFFFFF (max shift → all ones)")
    
    # Test 15: Positive stays positive
    instructions.append(encoder.srai(rd=21, rs1=16, shamt=1))
    print(f"  x21 = x16 >>s 1  = 0x3FFFFFFF (positive preserved)")
    
    # ========== EBREAK (1 instruction) ==========
    print("\n[Completion]")
    instructions.append(0x00100073)  # EBREAK
    print(f"  EBREAK - Signal test completion")
    
    # ========== Summary ==========
    total_instructions = len(instructions)
    print("\n" + "=" * 70)
    print(f"Total Instructions: {total_instructions}")
    print(f"  - CSR Init:  2")
    print(f"  - Setup:     8")
    print(f"  - SLLI:      5 (x1-x5)")
    print(f"  - SRLI:      5 (x6-x10)")
    print(f"  - SRAI:      5 (x17-x21)")
    print(f"  - EBREAK:    1")
    print("=" * 70)
    
    # ========== Write to hex file ==========
    output_dir = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'sim', 'tests')
    os.makedirs(output_dir, exist_ok=True)
    output_file = os.path.join(output_dir, 'rv32i_shift_imm_test.hex')
    
    with open(output_file, 'w') as f:
        for instr in instructions:
            f.write(f"{instr:08x}\n")
    
    print(f"\n✓ Hex file generated: {output_file}")
    print(f"  ({total_instructions} instructions)")
    
    # ========== Expected Results Summary ==========
    print("\n" + "=" * 70)
    print("Expected Results (for UVM verification):")
    print("=" * 70)
    print("SLLI Tests:")
    print("  x1  = 0x00000001  (1 << 0)")
    print("  x2  = 0x00000100  (1 << 8)")
    print("  x3  = 0x80000000  (1 << 31)")
    print("  x4  = 0x23456780  (0x12345678 << 4)")
    print("  x5  = 0xFFFFFFFE  (0x7FFFFFFF << 1)")
    print("\nSRLI Tests (Zero-fill):")
    print("  x6  = 0x7FFFFFFF  (0xFFFFFFFF >>u 1)")
    print("  x7  = 0x00008000  (0x80000000 >>u 16) ← CRITICAL: zero-fill")
    print("  x8  = 0x01234567  (0x12345678 >>u 4)")
    print("  x9  = 0x00000001  (0xFFFFFFFF >>u 31)")
    print("  x10 = 0x00000001  (1 >>u 0)")
    print("\nSRAI Tests (Sign-extend):")
    print("  x17 = 0x01234567  (0x12345678 >>s 4)")
    print("  x18 = 0xFFFFFFFF  (0xFFFFFFFE >>s 1)")
    print("  x19 = 0xFF800000  (0x80000000 >>s 8) ← CRITICAL: sign-extend")
    print("  x20 = 0xFFFFFFFF  (0x80000000 >>s 31)")
    print("  x21 = 0x3FFFFFFF  (0x7FFFFFFF >>s 1)")
    print("=" * 70)
    print("\nKEY DISTINCTION:")
    print("  x7 (SRLI): 0x80000000 >>u 16 = 0x00008000 (zero-fill)")
    print("  x19 (SRAI): 0x80000000 >>s 8 = 0xFF800000 (sign-extend)")
    print("  → Different behavior on same negative source!")
    print("=" * 70)

if __name__ == '__main__':
    generate_shift_imm_test()
