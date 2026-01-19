"""
Test 1.2: Upper Immediate Instructions Generator for RV32I CPU

Tests LUI and AUIPC instructions with various immediate values.

LUI (Load Upper Immediate):
- Loads 20-bit immediate into upper 20 bits of register (bits [31:12])
- Lower 12 bits are set to 0

AUIPC (Add Upper Immediate to PC):
- Adds 20-bit immediate (shifted left 12 bits) to current PC
- Used for PC-relative addressing

Expected Results:
x1 = 0x12345000 (LUI with 0x12345)
x2 = 0xABCDE000 (LUI with 0xABCDE)
x3 = 0xFFFFF000 (LUI with 0xFFFFF - all 1s)
x4 = 0x00001014 (AUIPC at PC=0x14, offset=0x1000)
x5 = 0x7FFFF018 (AUIPC at PC=0x18, offset=0x7FFFF000)
x6 = 0x12345678 (LUI + ADDI combination)
x7 = 0x00000020 (AUIPC at PC=0x20, offset=0)
x8 = 0x00000010 (x7 - 0x10 via ADDI)
x9 = 0x00000000 (LUI 0x00000)
x10 = 0x0000002C (AUIPC at PC=0x2C, offset=0)
"""

import sys
from pathlib import Path

# Add parent directory to path to import encoder
sys.path.insert(0, str(Path(__file__).parent.parent))
from encoder import RV32IInstructionEncoder

def generate_instructions():
    """Generate test instructions for LUI/AUIPC test"""
    encoder = RV32IInstructionEncoder()
    instructions = []
    
    # Initialize CSR: Set mtvec to 0x200 (exception handler)
    instructions.append(encoder.addi(rd=31, rs1=0, imm=0x200))
    instructions.append(encoder.csrrw(rd=0, csr=0x305, rs1=31))  # mtvec = 0x200
    
    # Test 1: LUI with typical value
    # LUI x1, 0x12345 → x1 = 0x12345000
    instructions.append(encoder.lui(rd=1, imm=0x12345))
    
    # Test 2: LUI with large value
    # LUI x2, 0xABCDE → x2 = 0xABCDE000
    instructions.append(encoder.lui(rd=2, imm=0xABCDE))
    
    # Test 3: LUI with all 1s (tests sign extension behavior)
    # LUI x3, 0xFFFFF → x3 = 0xFFFFF000
    instructions.append(encoder.lui(rd=3, imm=0xFFFFF))
    
    # Test 4: AUIPC with small offset
    # AUIPC x4, 0x00001 → x4 = PC + 0x1000
    # PC at this instruction = 0x14
    # Expected: x4 = 0x14 + 0x1000 = 0x00001014
    instructions.append(encoder.auipc(rd=4, imm=0x00001))
    
    # Test 5: AUIPC with large positive offset
    # AUIPC x5, 0x7FFFF → x5 = PC + 0x7FFFF000
    # PC at this instruction = 0x18
    # Expected: x5 = 0x18 + 0x7FFFF000 = 0x7FFFF018
    instructions.append(encoder.auipc(rd=5, imm=0x7FFFF))
    
    # Test 6: LUI + ADDI combination (common pattern for loading 32-bit constants)
    # x1 already = 0x12345000
    # ADDI x6, x1, 0x678 → x6 = 0x12345000 + 0x678 = 0x12345678
    instructions.append(encoder.addi(rd=6, rs1=1, imm=0x678))
    
    # Test 7: AUIPC + ADDI for PC-relative addressing with negative offset
    # AUIPC x7, 0x00000 → x7 = PC (0x20)
    # PC at this instruction = 0x20
    # Expected: x7 = 0x00000020
    instructions.append(encoder.auipc(rd=7, imm=0x00000))
    
    # ADDI x8, x7, -0x10 → x8 = x7 - 16 = 0x20 - 0x10 = 0x10
    instructions.append(encoder.addi(rd=8, rs1=7, imm=-0x10))
    
    # Test 8: Zero immediate values
    # LUI x9, 0x00000 → x9 = 0x00000000
    instructions.append(encoder.lui(rd=9, imm=0x00000))
    
    # AUIPC x10, 0x00000 → x10 = PC
    # PC at this instruction = 0x2C
    # Expected: x10 = 0x0000002C
    instructions.append(encoder.auipc(rd=10, imm=0x00000))
    
    # EBREAK to signal completion
    instructions.append(0x00100073)
    
    return instructions

def write_hex_file(instructions, filename):
    """Write instructions to hex file"""
    with open(filename, 'w') as f:
        for insn in instructions:
            f.write(f'{insn:08x}\n')

def main():
    instructions = generate_instructions()
    
    # Write to hex file
    output_file = "sim/tests/rv32i_upper_imm_test.hex"
    write_hex_file(instructions, output_file)
    
    print(f"Generated {len(instructions)} instructions to {output_file}")
    print("\nExpected Results:")
    print("  x1  = 0x12345000 (LUI 0x12345)")
    print("  x2  = 0xABCDE000 (LUI 0xABCDE)")
    print("  x3  = 0xFFFFF000 (LUI 0xFFFFF)")
    print("  x4  = 0x00001014 (AUIPC at PC=0x14, offset=0x1000)")
    print("  x5  = 0x7FFFF018 (AUIPC at PC=0x18, offset=0x7FFFF000)")
    print("  x6  = 0x12345678 (LUI + ADDI combination)")
    print("  x7  = 0x00000020 (AUIPC at PC=0x20, offset=0)")
    print("  x8  = 0x00000010 (x7 - 0x10)")
    print("  x9  = 0x00000000 (LUI 0x00000)")
    print("  x10 = 0x0000002C (AUIPC at PC=0x2C, offset=0)")
    print("\nNote: AUIPC results are PC-relative and depend on instruction addresses")

if __name__ == "__main__":
    main()
