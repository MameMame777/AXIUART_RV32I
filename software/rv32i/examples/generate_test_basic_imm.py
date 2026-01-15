#!/usr/bin/env python3
"""
Test 1.1: Basic Immediate Instruction Test Generator
Purpose: Verify register file writes and forwarding with ADDI instructions
Priority: CRITICAL - Blocks all subsequent tests
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from encoder import RV32IInstructionEncoder

def generate_basic_imm_test():
    """
    Generate test program with simple ADDI instructions
    
    Test cases:
    1. ADDI from x0 (zero register) with positive immediate
    2. ADDI from x0 with larger positive immediate  
    3. ADDI from x0 with negative immediate (sign extension)
    4. ADDI with register dependency (tests forwarding)
    """
    encoder = RV32IInstructionEncoder()
    instructions = []
    
    # Test 1: ADDI x1, x0, 10
    # Expected: x1 = 0x0000000A
    instructions.append(encoder.addi(rd=1, rs1=0, imm=10))
    
    # Test 2: ADDI x2, x0, 20
    # Expected: x2 = 0x00000014
    instructions.append(encoder.addi(rd=2, rs1=0, imm=20))
    
    # Test 3: ADDI x3, x0, -5
    # Expected: x3 = 0xFFFFFFFB (sign-extended)
    instructions.append(encoder.addi(rd=3, rs1=0, imm=-5))
    
    # Test 4: ADDI x4, x1, 100
    # Expected: x4 = x1 + 100 = 10 + 100 = 110 = 0x0000006E
    # This tests register forwarding (x1 written in previous cycle)
    instructions.append(encoder.addi(rd=4, rs1=1, imm=100))
    
    # EBREAK to stop simulation
    instructions.append(0x00100073)
    
    return instructions

def write_hex_file(instructions, filename):
    """Write instructions to hex file"""
    with open(filename, 'w') as f:
        for insn in instructions:
            f.write(f"{insn:08x}\n")

def print_assembly(instructions):
    """Print assembly code for reference"""
    print("# Test 1.1: Basic Immediate Instructions")
    print("# Expected results:")
    print("#   x1 = 0x0000000A (10)")
    print("#   x2 = 0x00000014 (20)")
    print("#   x3 = 0xFFFFFFFB (-5)")
    print("#   x4 = 0x0000006E (110)")
    print()
    
    asm_lines = [
        "ADDI x1, x0, 10      # x1 = 10",
        "ADDI x2, x0, 20      # x2 = 20",
        "ADDI x3, x0, -5      # x3 = -5 (0xFFFFFFFB)",
        "ADDI x4, x1, 100     # x4 = x1 + 100 = 110",
        "EBREAK               # Stop simulation"
    ]
    
    for i, (asm, insn) in enumerate(zip(asm_lines, instructions)):
        addr = i * 4
        print(f"0x{addr:04x}: {insn:08x}  {asm}")

if __name__ == "__main__":
    instructions = generate_basic_imm_test()
    
    # Output directory
    test_dir = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'sim', 'tests')
    os.makedirs(test_dir, exist_ok=True)
    
    # Write hex file
    hex_file = os.path.join(test_dir, 'rv32i_basic_imm_test.hex')
    write_hex_file(instructions, hex_file)
    
    print(f"Generated test file: {hex_file}\n")
    print_assembly(instructions)
    
    # Debug output
    print("\n# Encoding verification:")
    print(f"ADDI x1, x0, 10  = {instructions[0]:08x}")
    print(f"  Expected rd field [11:7] = 00001 (x1)")
    print(f"  Actual bits [11:7] = {(instructions[0] >> 7) & 0x1F:05b}")
