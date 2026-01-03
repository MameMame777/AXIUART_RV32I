r"""
RV32I ISA Python Encoder

Provides Python functions to encode RV32I instructions.
Based on RISC-V Instruction Set Architecture Volume I: Unprivileged ISA Version 2.1

Architecture: 5-stage pipeline (IF/ID/EX/MEM/WB)
Registers: 32 x 32-bit (x0 hardwired to zero)
Memory: Byte-addressed, 8KB internal RAM
"""

# =============================================================================
# Constants
# =============================================================================

WORD_MASK = 0xFFFFFFFF
HALFWORD_MASK = 0xFFFF
BYTE_MASK = 0xFF

# Opcodes (7-bit)
OP_LOAD     = 0b0000011  # LB, LH, LW, LBU, LHU
OP_MISC_MEM = 0b0001111  # FENCE, FENCE.I
OP_OP_IMM   = 0b0010011  # ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
OP_AUIPC    = 0b0010111  # AUIPC
OP_STORE    = 0b0100011  # SB, SH, SW
OP_OP       = 0b0110011  # ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
OP_LUI      = 0b0110111  # LUI
OP_BRANCH   = 0b1100011  # BEQ, BNE, BLT, BGE, BLTU, BGEU
OP_JALR     = 0b1100111  # JALR
OP_JAL      = 0b1101111  # JAL
OP_SYSTEM   = 0b1110011  # ECALL, EBREAK, CSR*

# Funct3 codes
# ALU Immediate
F3_ADDI  = 0b000
F3_SLTI  = 0b010
F3_SLTIU = 0b011
F3_XORI  = 0b100
F3_ORI   = 0b110
F3_ANDI  = 0b111
F3_SLLI  = 0b001
F3_SRLI  = 0b101  # SRLI/SRAI distinguished by imm[10]

# ALU Register
F3_ADD  = 0b000  # ADD/SUB distinguished by funct7
F3_SLL  = 0b001
F3_SLT  = 0b010
F3_SLTU = 0b011
F3_XOR  = 0b100
F3_SRL  = 0b101  # SRL/SRA distinguished by funct7
F3_OR   = 0b110
F3_AND  = 0b111

# Load
F3_LB  = 0b000
F3_LH  = 0b001
F3_LW  = 0b010
F3_LBU = 0b100
F3_LHU = 0b101

# Store
F3_SB = 0b000
F3_SH = 0b001
F3_SW = 0b010

# Branch
F3_BEQ  = 0b000
F3_BNE  = 0b001
F3_BLT  = 0b100
F3_BGE  = 0b101
F3_BLTU = 0b110
F3_BGEU = 0b111

# System
F3_PRIV = 0b000  # ECALL, EBREAK

# Funct7 codes
F7_NORMAL = 0b0000000  # ADD, SRL, SLL
F7_ALT    = 0b0100000  # SUB, SRA

# =============================================================================
# Register Name Mapping (ABI names)
# =============================================================================

REG_MAP = {
    'x0': 0, 'zero': 0,
    'x1': 1, 'ra': 1,
    'x2': 2, 'sp': 2,
    'x3': 3, 'gp': 3,
    'x4': 4, 'tp': 4,
    'x5': 5, 't0': 5,
    'x6': 6, 't1': 6,
    'x7': 7, 't2': 7,
    'x8': 8, 's0': 8, 'fp': 8,
    'x9': 9, 's1': 9,
    'x10': 10, 'a0': 10,
    'x11': 11, 'a1': 11,
    'x12': 12, 'a2': 12,
    'x13': 13, 'a3': 13,
    'x14': 14, 'a4': 14,
    'x15': 15, 'a5': 15,
    'x16': 16, 'a6': 16,
    'x17': 17, 'a7': 17,
    'x18': 18, 's2': 18,
    'x19': 19, 's3': 19,
    'x20': 20, 's4': 20,
    'x21': 21, 's5': 21,
    'x22': 22, 's6': 22,
    'x23': 23, 's7': 23,
    'x24': 24, 's8': 24,
    'x25': 25, 's9': 25,
    'x26': 26, 's10': 26,
    'x27': 27, 's11': 27,
    'x28': 28, 't3': 28,
    'x29': 29, 't4': 29,
    'x30': 30, 't5': 30,
    'x31': 31, 't6': 31,
}

def reg(name_or_num):
    """Convert register name/number to register index"""
    if isinstance(name_or_num, str):
        return REG_MAP[name_or_num.lower()]
    return int(name_or_num) & 0x1F

# =============================================================================
# Sign Extension Helpers
# =============================================================================

def sign_extend(value: int, bits: int) -> int:
    """Sign-extend value from 'bits' to 32 bits"""
    if value & (1 << (bits - 1)):
        return value | (0xFFFFFFFF << bits)
    return value & ((1 << bits) - 1)

def _mask32(x: int) -> int:
    """Mask to 32 bits"""
    return x & WORD_MASK

# =============================================================================
# Instruction Encoding Functions
# =============================================================================

def encode_r_type(opcode: int, rd: int, funct3: int, rs1: int, rs2: int, funct7: int) -> int:
    """Encode R-type instruction"""
    return _mask32(
        (funct7 << 25) |
        ((rs2 & 0x1F) << 20) |
        ((rs1 & 0x1F) << 15) |
        ((funct3 & 0x7) << 12) |
        ((rd & 0x1F) << 7) |
        (opcode & 0x7F)
    )

def encode_i_type(opcode: int, rd: int, funct3: int, rs1: int, imm: int) -> int:
    """Encode I-type instruction"""
    return _mask32(
        ((imm & 0xFFF) << 20) |
        ((rs1 & 0x1F) << 15) |
        ((funct3 & 0x7) << 12) |
        ((rd & 0x1F) << 7) |
        (opcode & 0x7F)
    )

def encode_s_type(opcode: int, funct3: int, rs1: int, rs2: int, imm: int) -> int:
    """Encode S-type instruction"""
    imm_11_5 = (imm >> 5) & 0x7F
    imm_4_0 = imm & 0x1F
    return _mask32(
        (imm_11_5 << 25) |
        ((rs2 & 0x1F) << 20) |
        ((rs1 & 0x1F) << 15) |
        ((funct3 & 0x7) << 12) |
        (imm_4_0 << 7) |
        (opcode & 0x7F)
    )

def encode_b_type(opcode: int, funct3: int, rs1: int, rs2: int, imm: int) -> int:
    """Encode B-type instruction (branch)"""
    imm_12 = (imm >> 12) & 0x1
    imm_10_5 = (imm >> 5) & 0x3F
    imm_4_1 = (imm >> 1) & 0xF
    imm_11 = (imm >> 11) & 0x1
    return _mask32(
        (imm_12 << 31) |
        (imm_10_5 << 25) |
        ((rs2 & 0x1F) << 20) |
        ((rs1 & 0x1F) << 15) |
        ((funct3 & 0x7) << 12) |
        (imm_4_1 << 8) |
        (imm_11 << 7) |
        (opcode & 0x7F)
    )

def encode_u_type(opcode: int, rd: int, imm: int) -> int:
    """Encode U-type instruction (upper immediate)"""
    return _mask32(
        ((imm & 0xFFFFF) << 12) |
        ((rd & 0x1F) << 7) |
        (opcode & 0x7F)
    )

def encode_j_type(opcode: int, rd: int, imm: int) -> int:
    """Encode J-type instruction (JAL)"""
    imm_20 = (imm >> 20) & 0x1
    imm_10_1 = (imm >> 1) & 0x3FF
    imm_11 = (imm >> 11) & 0x1
    imm_19_12 = (imm >> 12) & 0xFF
    return _mask32(
        (imm_20 << 31) |
        (imm_10_1 << 21) |
        (imm_11 << 20) |
        (imm_19_12 << 12) |
        ((rd & 0x1F) << 7) |
        (opcode & 0x7F)
    )

# =============================================================================
# RV32I Instruction Set - Integer Computational
# =============================================================================

# R-type ALU operations
def ADD(rd, rs1, rs2):
    """rd = rs1 + rs2"""
    return encode_r_type(OP_OP, reg(rd), F3_ADD, reg(rs1), reg(rs2), F7_NORMAL)

def SUB(rd, rs1, rs2):
    """rd = rs1 - rs2"""
    return encode_r_type(OP_OP, reg(rd), F3_ADD, reg(rs1), reg(rs2), F7_ALT)

def AND(rd, rs1, rs2):
    """rd = rs1 & rs2"""
    return encode_r_type(OP_OP, reg(rd), F3_AND, reg(rs1), reg(rs2), F7_NORMAL)

def OR(rd, rs1, rs2):
    """rd = rs1 | rs2"""
    return encode_r_type(OP_OP, reg(rd), F3_OR, reg(rs1), reg(rs2), F7_NORMAL)

def XOR(rd, rs1, rs2):
    """rd = rs1 ^ rs2"""
    return encode_r_type(OP_OP, reg(rd), F3_XOR, reg(rs1), reg(rs2), F7_NORMAL)

def SLL(rd, rs1, rs2):
    """rd = rs1 << rs2[4:0]"""
    return encode_r_type(OP_OP, reg(rd), F3_SLL, reg(rs1), reg(rs2), F7_NORMAL)

def SRL(rd, rs1, rs2):
    """rd = rs1 >> rs2[4:0] (logical)"""
    return encode_r_type(OP_OP, reg(rd), F3_SRL, reg(rs1), reg(rs2), F7_NORMAL)

def SRA(rd, rs1, rs2):
    """rd = rs1 >> rs2[4:0] (arithmetic)"""
    return encode_r_type(OP_OP, reg(rd), F3_SRL, reg(rs1), reg(rs2), F7_ALT)

def SLT(rd, rs1, rs2):
    """rd = (rs1 < rs2) ? 1 : 0 (signed)"""
    return encode_r_type(OP_OP, reg(rd), F3_SLT, reg(rs1), reg(rs2), F7_NORMAL)

def SLTU(rd, rs1, rs2):
    """rd = (rs1 < rs2) ? 1 : 0 (unsigned)"""
    return encode_r_type(OP_OP, reg(rd), F3_SLTU, reg(rs1), reg(rs2), F7_NORMAL)

# I-type immediate operations
def ADDI(rd, rs1, imm):
    """rd = rs1 + imm"""
    return encode_i_type(OP_OP_IMM, reg(rd), F3_ADDI, reg(rs1), imm & 0xFFF)

def ANDI(rd, rs1, imm):
    """rd = rs1 & imm"""
    return encode_i_type(OP_OP_IMM, reg(rd), F3_ANDI, reg(rs1), imm & 0xFFF)

def ORI(rd, rs1, imm):
    """rd = rs1 | imm"""
    return encode_i_type(OP_OP_IMM, reg(rd), F3_ORI, reg(rs1), imm & 0xFFF)

def XORI(rd, rs1, imm):
    """rd = rs1 ^ imm"""
    return encode_i_type(OP_OP_IMM, reg(rd), F3_XORI, reg(rs1), imm & 0xFFF)

def SLTI(rd, rs1, imm):
    """rd = (rs1 < imm) ? 1 : 0 (signed)"""
    return encode_i_type(OP_OP_IMM, reg(rd), F3_SLTI, reg(rs1), imm & 0xFFF)

def SLTIU(rd, rs1, imm):
    """rd = (rs1 < imm) ? 1 : 0 (unsigned)"""
    return encode_i_type(OP_OP_IMM, reg(rd), F3_SLTIU, reg(rs1), imm & 0xFFF)

def SLLI(rd, rs1, shamt):
    """rd = rs1 << shamt (shamt is 5-bit)"""
    return encode_i_type(OP_OP_IMM, reg(rd), F3_SLLI, reg(rs1), shamt & 0x1F)

def SRLI(rd, rs1, shamt):
    """rd = rs1 >> shamt (logical, shamt is 5-bit)"""
    return encode_i_type(OP_OP_IMM, reg(rd), F3_SRLI, reg(rs1), shamt & 0x1F)

def SRAI(rd, rs1, shamt):
    """rd = rs1 >> shamt (arithmetic, shamt is 5-bit)"""
    return encode_i_type(OP_OP_IMM, reg(rd), F3_SRLI, reg(rs1), (shamt & 0x1F) | 0x400)

# Upper immediate
def LUI(rd, imm):
    """rd = imm << 12"""
    return encode_u_type(OP_LUI, reg(rd), (imm >> 12) & 0xFFFFF)

def AUIPC(rd, imm):
    """rd = PC + (imm << 12)"""
    return encode_u_type(OP_AUIPC, reg(rd), (imm >> 12) & 0xFFFFF)

# =============================================================================
# RV32I Instruction Set - Load/Store
# =============================================================================

def LB(rd, rs1, offset):
    """rd = sign_extend(mem[rs1 + offset][7:0])"""
    return encode_i_type(OP_LOAD, reg(rd), F3_LB, reg(rs1), offset & 0xFFF)

def LH(rd, rs1, offset):
    """rd = sign_extend(mem[rs1 + offset][15:0])"""
    return encode_i_type(OP_LOAD, reg(rd), F3_LH, reg(rs1), offset & 0xFFF)

def LW(rd, rs1, offset):
    """rd = mem[rs1 + offset]"""
    return encode_i_type(OP_LOAD, reg(rd), F3_LW, reg(rs1), offset & 0xFFF)

def LBU(rd, rs1, offset):
    """rd = zero_extend(mem[rs1 + offset][7:0])"""
    return encode_i_type(OP_LOAD, reg(rd), F3_LBU, reg(rs1), offset & 0xFFF)

def LHU(rd, rs1, offset):
    """rd = zero_extend(mem[rs1 + offset][15:0])"""
    return encode_i_type(OP_LOAD, reg(rd), F3_LHU, reg(rs1), offset & 0xFFF)

def SB(rs2, rs1, offset):
    """mem[rs1 + offset][7:0] = rs2[7:0]"""
    return encode_s_type(OP_STORE, F3_SB, reg(rs1), reg(rs2), offset & 0xFFF)

def SH(rs2, rs1, offset):
    """mem[rs1 + offset][15:0] = rs2[15:0]"""
    return encode_s_type(OP_STORE, F3_SH, reg(rs1), reg(rs2), offset & 0xFFF)

def SW(rs2, rs1, offset):
    """mem[rs1 + offset] = rs2"""
    return encode_s_type(OP_STORE, F3_SW, reg(rs1), reg(rs2), offset & 0xFFF)

# =============================================================================
# RV32I Instruction Set - Branch
# =============================================================================

def BEQ(rs1, rs2, offset):
    """if (rs1 == rs2) PC = PC + offset"""
    return encode_b_type(OP_BRANCH, F3_BEQ, reg(rs1), reg(rs2), offset & 0x1FFE)

def BNE(rs1, rs2, offset):
    """if (rs1 != rs2) PC = PC + offset"""
    return encode_b_type(OP_BRANCH, F3_BNE, reg(rs1), reg(rs2), offset & 0x1FFE)

def BLT(rs1, rs2, offset):
    """if (rs1 < rs2) PC = PC + offset (signed)"""
    return encode_b_type(OP_BRANCH, F3_BLT, reg(rs1), reg(rs2), offset & 0x1FFE)

def BGE(rs1, rs2, offset):
    """if (rs1 >= rs2) PC = PC + offset (signed)"""
    return encode_b_type(OP_BRANCH, F3_BGE, reg(rs1), reg(rs2), offset & 0x1FFE)

def BLTU(rs1, rs2, offset):
    """if (rs1 < rs2) PC = PC + offset (unsigned)"""
    return encode_b_type(OP_BRANCH, F3_BLTU, reg(rs1), reg(rs2), offset & 0x1FFE)

def BGEU(rs1, rs2, offset):
    """if (rs1 >= rs2) PC = PC + offset (unsigned)"""
    return encode_b_type(OP_BRANCH, F3_BGEU, reg(rs1), reg(rs2), offset & 0x1FFE)

# =============================================================================
# RV32I Instruction Set - Jump
# =============================================================================

def JAL(rd, offset):
    """rd = PC + 4; PC = PC + offset"""
    return encode_j_type(OP_JAL, reg(rd), offset & 0x1FFFFE)

def JALR(rd, rs1, offset):
    """rd = PC + 4; PC = (rs1 + offset) & ~1"""
    return encode_i_type(OP_JALR, reg(rd), 0, reg(rs1), offset & 0xFFF)

# =============================================================================
# RV32I Instruction Set - System
# =============================================================================

def ECALL():
    """System call"""
    return 0x00000073

def EBREAK():
    """Breakpoint"""
    return 0x00100073

def FENCE():
    """Memory fence (NOP in single-core)"""
    return 0x0000000F

# =============================================================================
# Pseudo-instructions (Common Assembly Idioms)
# =============================================================================

def NOP():
    """No operation (ADDI x0, x0, 0)"""
    return ADDI('x0', 'x0', 0)

def MV(rd, rs):
    """rd = rs (ADDI rd, rs, 0)"""
    return ADDI(rd, rs, 0)

def NOT(rd, rs):
    """rd = ~rs (XORI rd, rs, -1)"""
    return XORI(rd, rs, -1)

def NEG(rd, rs):
    """rd = -rs (SUB rd, x0, rs)"""
    return SUB(rd, 'x0', rs)

def LI(rd, imm):
    """Load immediate (LUI + ADDI for large values)
    Returns list of instructions for imm > 12 bits"""
    imm = imm & 0xFFFFFFFF
    if -2048 <= imm <= 2047:
        # Fits in 12-bit immediate
        return [ADDI(rd, 'x0', imm)]
    else:
        # Need LUI + ADDI
        upper = (imm + 0x800) >> 12  # Adjust for sign extension
        lower = imm & 0xFFF
        if lower & 0x800:  # Sign extend will happen
            lower = lower | 0xFFFFF000
        return [LUI(rd, upper << 12), ADDI(rd, rd, lower)]

def J(offset):
    """Unconditional jump (JAL x0, offset)"""
    return JAL('x0', offset)

def JR(rs):
    """Jump register (JALR x0, rs, 0)"""
    return JALR('x0', rs, 0)

def RET():
    """Return from function (JALR x0, ra, 0)"""
    return JALR('x0', 'ra', 0)
