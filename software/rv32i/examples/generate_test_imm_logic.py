#!/usr/bin/env python3
"""
Test 1.3: Immediate Arithmetic/Logic Instructions
Tests: SLTI, SLTIU, XORI, ORI, ANDI

Coverage: 5 I-type instructions for comparison and bitwise operations
Expected registers: x1-x10 with specific test results
"""

import sys
from pathlib import Path

# Add parent directory to path to import encoder
sys.path.insert(0, str(Path(__file__).parent.parent))
from encoder import RV32IInstructionEncoder

def generate_instructions():
    """Generate test instructions for immediate arithmetic/logic operations"""
    encoder = RV32IInstructionEncoder()
    instructions = []
    
    # Initialize CSR: Set mtvec to 0x200 (exception handler)
    instructions.append(encoder.addi(rd=31, rs1=0, imm=0x200))
    instructions.append(encoder.csrrw(rd=0, csr=0x305, rs1=31))  # mtvec = 0x200
    
    # Setup test values
    # x11 = 10 (positive reference)
    instructions.append(encoder.addi(rd=11, rs1=0, imm=10))
    # x12 = -5 (negative reference)
    instructions.append(encoder.addi(rd=12, rs1=0, imm=-5))
    # x13 = 0x0F0 (bit pattern for logic ops)
    instructions.append(encoder.addi(rd=13, rs1=0, imm=0x0F0))
    
    # Test 1: SLTI - Set Less Than Immediate (signed)
    # x1 = (10 < 20) ? 1 : 0 → x1 = 1
    instructions.append(encoder.slti(rd=1, rs1=11, imm=20))
    
    # Test 2: SLTI with negative immediate
    # x2 = (10 < -5) ? 1 : 0 → x2 = 0
    instructions.append(encoder.slti(rd=2, rs1=11, imm=-5))
    
    # Test 3: SLTI with negative source
    # x3 = (-5 < 0) ? 1 : 0 → x3 = 1
    instructions.append(encoder.slti(rd=3, rs1=12, imm=0))
    
    # Test 4: SLTIU - Set Less Than Immediate Unsigned
    # x4 = (10 < 20) unsigned ? 1 : 0 → x4 = 1
    instructions.append(encoder.sltiu(rd=4, rs1=11, imm=20))
    
    # Test 5: SLTIU with -1 (0xFFF in 12-bit = 0xFFFFFFFF sign-extended)
    # x5 = (10 < 0xFFFFFFFF) unsigned ? 1 : 0 → x5 = 1
    instructions.append(encoder.sltiu(rd=5, rs1=11, imm=-1))
    
    # Test 6: XORI - XOR Immediate
    # x6 = 0x0F0 ^ 0x0FF → x6 = 0x00F
    instructions.append(encoder.xori(rd=6, rs1=13, imm=0x0FF))
    
    # Test 7: XORI with -1 (bitwise NOT)
    # x7 = 0x0F0 ^ 0xFFF → x7 = 0xFFFFFF0F
    instructions.append(encoder.xori(rd=7, rs1=13, imm=-1))
    
    # Test 8: ORI - OR Immediate
    # x8 = 0x0F0 | 0x00F → x8 = 0x0FF
    instructions.append(encoder.ori(rd=8, rs1=13, imm=0x00F))
    
    # Test 9: ANDI - AND Immediate
    # x9 = 0x0F0 & 0x0F0 → x9 = 0x0F0
    instructions.append(encoder.andi(rd=9, rs1=13, imm=0x0F0))
    
    # Test 10: ANDI with mask
    # x10 = 0x0F0 & 0x00F → x10 = 0x000
    instructions.append(encoder.andi(rd=10, rs1=13, imm=0x00F))
    
    # EBREAK to signal completion
    instructions.append(0x00100073)
    
    return instructions

def write_hex_file(instructions, filename):
    """Write instructions to hex file"""
    with open(filename, "w") as f:
        for insn in instructions:
            f.write(f"{insn:08x}\n")

def main():
    instructions = generate_instructions()
    
    # Write to hex file
    output_file = "sim/tests/rv32i_imm_logic_test.hex"
    write_hex_file(instructions, output_file)
    
    print(f"Generated {len(instructions)} instructions to {output_file}")
    print("\nExpected Results:")
    print("  x1  = 0x00000001 (SLTI: 10 < 20)")
    print("  x2  = 0x00000000 (SLTI: 10 < -5, signed)")
    print("  x3  = 0x00000001 (SLTI: -5 < 0)")
    print("  x4  = 0x00000001 (SLTIU: 10 < 20, unsigned)")
    print("  x5  = 0x00000001 (SLTIU: 10 < 0xFFFFFFFF, unsigned)")
    print("  x6  = 0x0000000F (XORI: 0x0F0 ^ 0x0FF)")
    print("  x7  = 0xFFFFFF0F (XORI: 0x0F0 ^ -1, bitwise NOT)")
    print("  x8  = 0x000000FF (ORI: 0x0F0 | 0x00F)")
    print("  x9  = 0x000000F0 (ANDI: 0x0F0 & 0x0F0)")
    print("  x10 = 0x00000000 (ANDI: 0x0F0 & 0x00F)")
    print("\nHelper registers:")
    print("  x11 = 0x0000000A (10)")
    print("  x12 = 0xFFFFFFFB (-5)")
    print("  x13 = 0x000000F0 (0x0F0)")

if __name__ == "__main__":
    main()
