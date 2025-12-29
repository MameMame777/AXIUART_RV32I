r"""
TD4CPU ISA

AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
Generated from: td4cpu_isa.json
Generation time: 2025-12-29T19:43:44.228331

To regenerate:
    python software/axiuart_driver/tools/gen_cpu_isa.py --in td4cpu_isa.json
"""

WORD_MASK = 0xFFFF

# Opcodes
OP_R_ALU = 0x0
OP_LDI = 0x1
OP_ADDI = 0x2
OP_LD = 0x3
OP_ST = 0x4
OP_BR = 0x5
OP_SYS = 0x6
OP_STACK = 0x7
OP_JMP16 = 0xA
OP_CALL16 = 0xB

# R funct
FUNCT_ADD = 0x00
FUNCT_SUB = 0x01
FUNCT_AND = 0x02
FUNCT_OR = 0x03
FUNCT_XOR = 0x04
FUNCT_CMP = 0x05
FUNCT_SHL1 = 0x06
FUNCT_SHR1 = 0x07
FUNCT_MOV = 0x08

# Cond
COND_AL = 0
COND_Z = 1
COND_NZ = 2
COND_C = 3
COND_NC = 4
COND_N = 5
COND_NN = 6

# SYS subops
SYSOP_RET = 0
SYSOP_BRK = 1

def _mask16(x: int) -> int:
    return x & WORD_MASK

def encode_R(op: int, rd: int, rs: int, funct: int) -> int:
    return _mask16((op << 12) | ((rd & 7) << 9) | ((rs & 7) << 6) | (funct & 0x3F))

def encode_I(op: int, rd: int, imm9: int) -> int:
    return _mask16((op << 12) | ((rd & 7) << 9) | (imm9 & 0x1FF))

def encode_M(op: int, rD: int, rB: int, off6: int) -> int:
    return _mask16((op << 12) | ((rD & 7) << 9) | ((rB & 7) << 6) | (off6 & 0x3F))

def encode_B(op: int, cond: int, off9: int) -> int:
    return _mask16((op << 12) | ((cond & 7) << 9) | (off9 & 0x1FF))

def encode_S(op: int, r: int, dir_: int) -> int:
    return _mask16((op << 12) | ((r & 7) << 9) | ((dir_ & 1) << 8))

def encode_SYS(op: int, sysop: int) -> int:
    return _mask16((op << 12) | (sysop & 7))

# Convenience wrappers (word0 only for X-format)
def ADD(rd: int, rs: int) -> int: return encode_R(OP_R_ALU, rd, rs, FUNCT_ADD)
def SUB(rd: int, rs: int) -> int: return encode_R(OP_R_ALU, rd, rs, FUNCT_SUB)
def AND_(rd: int, rs: int) -> int: return encode_R(OP_R_ALU, rd, rs, FUNCT_AND)
def OR_(rd: int, rs: int) -> int: return encode_R(OP_R_ALU, rd, rs, FUNCT_OR)
def XOR(rd: int, rs: int) -> int: return encode_R(OP_R_ALU, rd, rs, FUNCT_XOR)
def CMP(rd: int, rs: int) -> int: return encode_R(OP_R_ALU, rd, rs, FUNCT_CMP)
def SHL1(rd: int) -> int: return encode_R(OP_R_ALU, rd, 0, FUNCT_SHL1)
def SHR1(rd: int) -> int: return encode_R(OP_R_ALU, rd, 0, FUNCT_SHR1)
def MOV(rd: int, rs: int) -> int: return encode_R(OP_R_ALU, rd, rs, FUNCT_MOV)
def LDI(rd: int, imm9: int) -> int: return encode_I(OP_LDI, rd, imm9)
def ADDI(rd: int, imm9: int) -> int: return encode_I(OP_ADDI, rd, imm9)
def LD(rD: int, rB: int, off6: int) -> int: return encode_M(OP_LD, rD, rB, off6)
def ST(rD: int, rB: int, off6: int) -> int: return encode_M(OP_ST, rD, rB, off6)
def BR(cond: int, off9: int) -> int: return encode_B(OP_BR, cond, off9)
def RET() -> int: return encode_SYS(OP_SYS, SYSOP_RET)
def BRK() -> int: return encode_SYS(OP_SYS, SYSOP_BRK)
def PUSH(r: int) -> int: return encode_S(OP_STACK, r, 0)
def POP(r: int) -> int: return encode_S(OP_STACK, r, 1)
def JMP16_WORD0() -> int: return _mask16(OP_JMP16 << 12)
def CALL16_WORD0() -> int: return _mask16(OP_CALL16 << 12)
