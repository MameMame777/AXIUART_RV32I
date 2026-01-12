"""
LOAD Instruction Test Generator for RV32I CPU

Tests all LOAD variants:
- LW (Load Word)
- LH (Load Halfword - sign extended)
- LHU (Load Halfword Unsigned - zero extended)
- LB (Load Byte - sign extended)
- LBU (Load Byte Unsigned - zero extended)
- Negative offset tests
- Critical: Load-to-use hazard test (LW followed by ADD using loaded value)

Memory Test Patterns:
[0x400] = 0x12345678
[0x404] = 0xAABBCCDD
[0x408] = 0x11223344
[0x40C] = 0xFFEEDDCC

Expected Results:
x16 = 0x12345678 (LW)
x17 = 0xFFFFCCDD (LH sign-extended from 0xCCDD)
x18 = 0x0000CCDD (LHU zero-extended)
x19 = 0x00000044 (LB positive)
x20 = 0x00000044 (LBU positive)
x21 = 0xFFFFFFCC (LB negative sign-extended from 0xCC)
x22 = 0x000000CC (LBU negative zero-extended)
x23 = 0xFFEEDDCC (LW with negative offset)
x24 = 0x12345678 (hazard test load)
x25 = 0x2468ACF0 (hazard test: x24 + x24)
LED = 0x2468ACF0
"""

def encode_i_type(opcode, rd, funct3, rs1, imm):
    """Encode I-type instruction"""
    imm_12 = imm & 0xFFF
    return (imm_12 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_s_type(opcode, funct3, rs1, rs2, imm):
    """Encode S-type instruction"""
    imm_12 = imm & 0xFFF
    imm_11_5 = (imm_12 >> 5) & 0x7F
    imm_4_0 = imm_12 & 0x1F
    return (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_4_0 << 7) | opcode

def encode_r_type(opcode, rd, funct3, rs1, rs2, funct7):
    """Encode R-type instruction"""
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_u_type(opcode, rd, imm):
    """Encode U-type instruction"""
    imm_31_12 = (imm >> 12) & 0xFFFFF
    return (imm_31_12 << 12) | (rd << 7) | opcode

instructions = []

# Initialize CSR: Set mtvec to 0x200
instructions.append(0x20000f93)  # addi x31, x0, 0x200
instructions.append(0x305f9073)  # csrw mtvec, x31

# Initialize base address x10 = 0x400 (fits in 12-bit immediate)
instructions.append(encode_i_type(0b0010011, 10, 0b000, 0, 0x400))  # addi x10, x0, 0x400

# Store test patterns to memory
# [0x400] = 0x12345678
instructions.append(encode_u_type(0b0110111, 11, 0x12345 << 12))  # lui x11, 0x12345
instructions.append(encode_i_type(0b0010011, 11, 0b000, 11, 0x678))  # addi x11, x11, 0x678
instructions.append(encode_s_type(0b0100011, 0b010, 10, 11, 0))  # sw x11, 0(x10)

# [0x404] = 0xAABBCCDD
# Note: lui loads upper 20 bits, addi sign-extends 12-bit immediate
# 0xCDD has bit 11 set → sign-extends to 0xFFFFFCDD
# Solution: lui 0xAABBD, then addi -0x323 (0xCDD - 0x1000)
instructions.append(encode_u_type(0b0110111, 12, 0xAABBD << 12))  # lui x12, 0xAABBD
instructions.append(encode_i_type(0b0010011, 12, 0b000, 12, (-0x323) & 0xFFF))  # addi x12, x12, -0x323
instructions.append(encode_s_type(0b0100011, 0b010, 10, 12, 4))  # sw x12, 4(x10)

# [0x408] = 0x11223344
instructions.append(encode_u_type(0b0110111, 13, 0x11223 << 12))  # lui x13, 0x11223
instructions.append(encode_i_type(0b0010011, 13, 0b000, 13, 0x344))  # addi x13, x13, 0x344
instructions.append(encode_s_type(0b0100011, 0b010, 10, 13, 8))  # sw x13, 8(x10)

# [0x40C] = 0xFFEEDDCC
instructions.append(encode_u_type(0b0110111, 14, 0xFFEED << 12))  # lui x14, 0xFFEED
instructions.append(encode_i_type(0b0010011, 14, 0b000, 14, 0xDCC))  # addi x14, x14, 0xDCC
instructions.append(encode_s_type(0b0100011, 0b010, 10, 14, 12))  # sw x14, 12(x10)

# Test LOAD instructions
# LW x16, 0(x10) - Load word from [0x400] = 0x12345678
instructions.append(encode_i_type(0b0000011, 16, 0b010, 10, 0))

# LH x17, 4(x10) - Load halfword from [0x404+4=0x404] lower half = 0xCCDD (sign-extended to 0xFFFFCCDD)
instructions.append(encode_i_type(0b0000011, 17, 0b001, 10, 4))

# LHU x18, 4(x10) - Load halfword unsigned (zero-extended to 0x0000CCDD)
instructions.append(encode_i_type(0b0000011, 18, 0b101, 10, 4))

# LB x19, 8(x10) - Load byte from [0x408] = 0x44 (positive, sign-extended to 0x00000044)
instructions.append(encode_i_type(0b0000011, 19, 0b000, 10, 8))

# LBU x20, 8(x10) - Load byte unsigned (zero-extended to 0x00000044)
instructions.append(encode_i_type(0b0000011, 20, 0b100, 10, 8))

# LB x21, 12(x10) - Load byte from [0x40C] = 0xCC (negative, sign-extended to 0xFFFFFFCC)
instructions.append(encode_i_type(0b0000011, 21, 0b000, 10, 12))

# LBU x22, 12(x10) - Load byte unsigned (zero-extended to 0x000000CC)
instructions.append(encode_i_type(0b0000011, 22, 0b100, 10, 12))

# Test negative offset: x15 = 0x410, then LW x23, -4(x15) = [0x40C] = 0xFFEEDDCC
instructions.append(encode_i_type(0b0010011, 15, 0b000, 10, 16))  # addi x15, x10, 16
instructions.append(encode_i_type(0b0000011, 23, 0b010, 15, -4))  # lw x23, -4(x15)

# Critical: Load-to-use hazard test
# LW x24, 0(x10) - Load value from [0x400] = 0x12345678
instructions.append(encode_i_type(0b0000011, 24, 0b010, 10, 0))

# ADD x25, x24, x24 - Immediate use of loaded value (HAZARD!)
# Expected result: 0x12345678 + 0x12345678 = 0x2468ACF0
instructions.append(encode_r_type(0b0110011, 25, 0b000, 24, 24, 0b0000000))

# Store result to LED at 0x407C
instructions.append(encode_u_type(0b0110111, 26, 4))  # lui x26, 4 (x26 = 0x4000)
instructions.append(encode_i_type(0b0010011, 26, 0b000, 26, 0x7C))  # addi x26, x26, 0x7C (x26 = 0x407C)
instructions.append(encode_s_type(0b0100011, 0b010, 26, 25, 0))  # sw x25, 0(x26)

# EBREAK to signal completion
instructions.append(0x00100073)

# Write to hex file
output_file = "sim/tests/test_load_simple.hex"
with open(output_file, "w") as f:
    for insn in instructions:
        f.write(f"{insn:08x}\n")

print(f"Generated {len(instructions)} instructions to {output_file}")
print("\nExpected Results:")
print("  x16 = 0x12345678 (LW)")
print("  x17 = 0xFFFFCCDD (LH sign-extended)")
print("  x18 = 0x0000CCDD (LHU zero-extended)")
print("  x19 = 0x00000044 (LB positive)")
print("  x20 = 0x00000044 (LBU positive)")
print("  x21 = 0xFFFFFFCC (LB negative sign-extended)")
print("  x22 = 0x000000CC (LBU negative zero-extended)")
print("  x23 = 0xFFEEDDCC (LW negative offset)")
print("  x24 = 0x12345678 (hazard test load)")
print("  x25 = 0x2468ACF0 (hazard test: x24 + x24)")
print("  LED = 0x2468ACF0")
