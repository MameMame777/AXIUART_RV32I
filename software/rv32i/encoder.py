"""RV32I Instruction Encoder

Provides bit-field encoding for RV32I base instruction set.
Pure computation module with no external dependencies.

Usage:
    encoder = RV32IInstructionEncoder()
    insn = encoder.addi(rd=10, rs1=0, imm=42)  # x10 = x0 + 42
    print(f"0x{insn:08x}")  # 0x02a00513
"""


class RV32IInstructionEncoder:
    """Encodes RV32I instructions into 32-bit machine code"""
    
    def __init__(self):
        pass
    
    # Helper methods for bit field encoding
    def _sign_extend(self, value, bits):
        """Sign extend a value to bits"""
        sign_bit = 1 << (bits - 1)
        return (value & (sign_bit - 1)) - (value & sign_bit)
    
    def _encode_r_type(self, opcode, rd, funct3, rs1, rs2, funct7):
        """Encode R-type instruction"""
        return ((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | \
               ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
               ((rd & 0x1F) << 7) | (opcode & 0x7F)
    
    def _encode_i_type(self, opcode, rd, funct3, rs1, imm):
        """Encode I-type instruction"""
        return ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | \
               ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)
    
    def _encode_s_type(self, opcode, funct3, rs1, rs2, imm):
        """Encode S-type instruction"""
        imm11_5 = (imm >> 5) & 0x7F
        imm4_0 = imm & 0x1F
        return (imm11_5 << 25) | ((rs2 & 0x1F) << 20) | \
               ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
               (imm4_0 << 7) | (opcode & 0x7F)
    
    def _encode_b_type(self, opcode, funct3, rs1, rs2, offset):
        """Encode B-type instruction
        B-type format: imm[12|10:5] rs2 rs1 funct3 imm[4:1|11] opcode
        Offset is in bytes, must be even (LSB=0)
        """
        # Sign-extend to 13 bits and mask
        offset_13bit = offset & 0x1FFF
        imm12 = (offset_13bit >> 12) & 0x1
        imm10_5 = (offset_13bit >> 5) & 0x3F
        imm4_1 = (offset_13bit >> 1) & 0xF
        imm11 = (offset_13bit >> 11) & 0x1
        return (imm12 << 31) | (imm10_5 << 25) | ((rs2 & 0x1F) << 20) | \
               ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
               (imm4_1 << 8) | (imm11 << 7) | (opcode & 0x7F)
    
    def _encode_u_type(self, opcode, rd, imm):
        """Encode U-type instruction"""
        return (imm << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)
    
    def _encode_j_type(self, opcode, rd, offset):
        """Encode J-type instruction"""
        imm20 = (offset >> 20) & 0x1
        imm10_1 = (offset >> 1) & 0x3FF
        imm11 = (offset >> 11) & 0x1
        imm19_12 = (offset >> 12) & 0xFF
        return (imm20 << 31) | (imm19_12 << 12) | (imm11 << 20) | \
               (imm10_1 << 21) | ((rd & 0x1F) << 7) | (opcode & 0x7F)
    
    # R-type instructions (OP: 0x33)
    def add(self, rd, rs1, rs2):
        """ADD rd, rs1, rs2 - Add"""
        return self._encode_r_type(0x33, rd, 0x0, rs1, rs2, 0x00)
    
    def sub(self, rd, rs1, rs2):
        """SUB rd, rs1, rs2 - Subtract"""
        return self._encode_r_type(0x33, rd, 0x0, rs1, rs2, 0x20)
    
    def sll(self, rd, rs1, rs2):
        """SLL rd, rs1, rs2 - Shift left logical"""
        return self._encode_r_type(0x33, rd, 0x1, rs1, rs2, 0x00)
    
    def slt(self, rd, rs1, rs2):
        """SLT rd, rs1, rs2 - Set less than"""
        return self._encode_r_type(0x33, rd, 0x2, rs1, rs2, 0x00)
    
    def sltu(self, rd, rs1, rs2):
        """SLTU rd, rs1, rs2 - Set less than unsigned"""
        return self._encode_r_type(0x33, rd, 0x3, rs1, rs2, 0x00)
    
    def xor(self, rd, rs1, rs2):
        """XOR rd, rs1, rs2 - XOR"""
        return self._encode_r_type(0x33, rd, 0x4, rs1, rs2, 0x00)
    
    def srl(self, rd, rs1, rs2):
        """SRL rd, rs1, rs2 - Shift right logical"""
        return self._encode_r_type(0x33, rd, 0x5, rs1, rs2, 0x00)
    
    def sra(self, rd, rs1, rs2):
        """SRA rd, rs1, rs2 - Shift right arithmetic"""
        return self._encode_r_type(0x33, rd, 0x5, rs1, rs2, 0x20)
    
    def or_(self, rd, rs1, rs2):
        """OR rd, rs1, rs2 - OR"""
        return self._encode_r_type(0x33, rd, 0x6, rs1, rs2, 0x00)
    
    def and_(self, rd, rs1, rs2):
        """AND rd, rs1, rs2 - AND"""
        return self._encode_r_type(0x33, rd, 0x7, rs1, rs2, 0x00)
    
    # I-type instructions (OP-IMM: 0x13)
    def addi(self, rd, rs1, imm):
        """ADDI rd, rs1, imm - Add immediate"""
        return self._encode_i_type(0x13, rd, 0x0, rs1, imm & 0xFFF)
    
    def slti(self, rd, rs1, imm):
        """SLTI rd, rs1, imm - Set less than immediate"""
        return self._encode_i_type(0x13, rd, 0x2, rs1, imm & 0xFFF)
    
    def sltiu(self, rd, rs1, imm):
        """SLTIU rd, rs1, imm - Set less than immediate unsigned"""
        return self._encode_i_type(0x13, rd, 0x3, rs1, imm & 0xFFF)
    
    def xori(self, rd, rs1, imm):
        """XORI rd, rs1, imm - XOR immediate"""
        return self._encode_i_type(0x13, rd, 0x4, rs1, imm & 0xFFF)
    
    def ori(self, rd, rs1, imm):
        """ORI rd, rs1, imm - OR immediate"""
        return self._encode_i_type(0x13, rd, 0x6, rs1, imm & 0xFFF)
    
    def andi(self, rd, rs1, imm):
        """ANDI rd, rs1, imm - AND immediate"""
        return self._encode_i_type(0x13, rd, 0x7, rs1, imm & 0xFFF)
    
    def slli(self, rd, rs1, shamt):
        """SLLI rd, rs1, shamt - Shift left logical immediate"""
        return self._encode_i_type(0x13, rd, 0x1, rs1, shamt & 0x1F)
    
    def srli(self, rd, rs1, shamt):
        """SRLI rd, rs1, shamt - Shift right logical immediate"""
        return self._encode_i_type(0x13, rd, 0x5, rs1, shamt & 0x1F)
    
    def srai(self, rd, rs1, shamt):
        """SRAI rd, rs1, shamt - Shift right arithmetic immediate"""
        return self._encode_i_type(0x13, rd, 0x5, rs1, (shamt & 0x1F) | 0x400)
    
    # Load instructions (LOAD: 0x03)
    def lb(self, rd, rs1, imm):
        """LB rd, imm(rs1) - Load byte"""
        return self._encode_i_type(0x03, rd, 0x0, rs1, imm & 0xFFF)
    
    def lh(self, rd, rs1, imm):
        """LH rd, imm(rs1) - Load halfword"""
        return self._encode_i_type(0x03, rd, 0x1, rs1, imm & 0xFFF)
    
    def lw(self, rd, rs1, imm):
        """LW rd, imm(rs1) - Load word"""
        return self._encode_i_type(0x03, rd, 0x2, rs1, imm & 0xFFF)
    
    def lbu(self, rd, rs1, imm):
        """LBU rd, imm(rs1) - Load byte unsigned"""
        return self._encode_i_type(0x03, rd, 0x4, rs1, imm & 0xFFF)
    
    def lhu(self, rd, rs1, imm):
        """LHU rd, imm(rs1) - Load halfword unsigned"""
        return self._encode_i_type(0x03, rd, 0x5, rs1, imm & 0xFFF)
    
    # Store instructions (STORE: 0x23)
    def sb(self, rs2, imm, rs1):
        """SB rs2, imm(rs1) - Store byte"""
        return self._encode_s_type(0x23, 0x0, rs1, rs2, imm & 0xFFF)
    
    def sh(self, rs2, imm, rs1):
        """SH rs2, imm(rs1) - Store halfword"""
        return self._encode_s_type(0x23, 0x1, rs1, rs2, imm & 0xFFF)
    
    def sw(self, rs2, imm, rs1):
        """SW rs2, imm(rs1) - Store word"""
        return self._encode_s_type(0x23, 0x2, rs1, rs2, imm & 0xFFF)
    
    # Branch instructions (BRANCH: 0x63)
    def beq(self, rs1, rs2, offset):
        """BEQ rs1, rs2, offset - Branch if equal"""
        return self._encode_b_type(0x63, 0x0, rs1, rs2, offset & 0x1FFF)
    
    def bne(self, rs1, rs2, offset):
        """BNE rs1, rs2, offset - Branch if not equal"""
        return self._encode_b_type(0x63, 0x1, rs1, rs2, offset & 0x1FFF)
    
    def blt(self, rs1, rs2, offset):
        """BLT rs1, rs2, offset - Branch if less than"""
        return self._encode_b_type(0x63, 0x4, rs1, rs2, offset & 0x1FFF)
    
    def bge(self, rs1, rs2, offset):
        """BGE rs1, rs2, offset - Branch if greater or equal"""
        return self._encode_b_type(0x63, 0x5, rs1, rs2, offset & 0x1FFF)
    
    def bltu(self, rs1, rs2, offset):
        """BLTU rs1, rs2, offset - Branch if less than unsigned"""
        return self._encode_b_type(0x63, 0x6, rs1, rs2, offset & 0x1FFF)
    
    def bgeu(self, rs1, rs2, offset):
        """BGEU rs1, rs2, offset - Branch if greater or equal unsigned"""
        return self._encode_b_type(0x63, 0x7, rs1, rs2, offset & 0x1FFF)
    
    # Upper immediate instructions
    def lui(self, rd, imm):
        """LUI rd, imm - Load upper immediate (imm is upper 20 bits)"""
        return self._encode_u_type(0x37, rd, imm & 0xFFFFF)
    
    def auipc(self, rd, imm):
        """AUIPC rd, imm - Add upper immediate to PC"""
        return self._encode_u_type(0x17, rd, imm & 0xFFFFF)
    
    # Jump instructions
    def jal(self, rd, offset):
        """JAL rd, offset - Jump and link"""
        return self._encode_j_type(0x6F, rd, offset & 0x1FFFFF)
    
    def jalr(self, rd, rs1, imm):
        """JALR rd, rs1, imm - Jump and link register"""
        return self._encode_i_type(0x67, rd, 0x0, rs1, imm & 0xFFF)
    
    # System instructions (SYSTEM: 0x73)
    def ebreak(self):
        """EBREAK - Environment break"""
        return 0x00100073
    
    def ecall(self):
        """ECALL - Environment call"""
        return 0x00000073
    
    def mret(self):
        """MRET - Machine return from trap"""
        return 0x30200073
    
    def fence(self):
        """FENCE - Fence instruction (treated as NOP in this implementation)"""
        return 0x0000000F
    
    # CSR instructions (SYSTEM: 0x73)
    def csrrw(self, rd, csr, rs1):
        """CSRRW rd, csr, rs1 - CSR read/write"""
        return self._encode_i_type(0x73, rd, 0x1, rs1, csr & 0xFFF)
    
    def csrrs(self, rd, csr, rs1):
        """CSRRS rd, csr, rs1 - CSR read and set bits"""
        return self._encode_i_type(0x73, rd, 0x2, rs1, csr & 0xFFF)
    
    def csrrc(self, rd, csr, rs1):
        """CSRRC rd, csr, rs1 - CSR read and clear bits"""
        return self._encode_i_type(0x73, rd, 0x3, rs1, csr & 0xFFF)
    
    def csrrwi(self, rd, csr, imm):
        """CSRRWI rd, csr, imm - CSR read/write immediate"""
        return self._encode_i_type(0x73, rd, 0x5, imm & 0x1F, csr & 0xFFF)
    
    def csrrsi(self, rd, csr, imm):
        """CSRRSI rd, csr, imm - CSR read and set bits immediate"""
        return self._encode_i_type(0x73, rd, 0x6, imm & 0x1F, csr & 0xFFF)
    
    def csrrci(self, rd, csr, imm):
        """CSRRCI rd, csr, imm - CSR read and clear bits immediate"""
        return self._encode_i_type(0x73, rd, 0x7, imm & 0x1F, csr & 0xFFF)
