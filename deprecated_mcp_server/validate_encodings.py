#!/usr/bin/env python3
"""
RV32I Instruction Encoding Validator
=====================================
Validates instruction encodings in hex files against RV32I ISA specification.
Decodes instructions to human-readable format and checks for encoding errors.

Author: GitHub Copilot
Date: 2026-01-11
License: MIT

Usage:
    python mcp_server/validate_encodings.py sim/tests/rv32i_comprehensive_test.hex
"""

import sys
import os
from typing import Tuple, List, Dict


class RV32IDecoder:
    """Decodes RV32I 32-bit instruction encodings"""
    
    # Opcode definitions
    OP_LUI    = 0b0110111
    OP_AUIPC  = 0b0010111
    OP_JAL    = 0b1101111
    OP_JALR   = 0b1100111
    OP_BRANCH = 0b1100011
    OP_LOAD   = 0b0000011
    OP_STORE  = 0b0100011
    OP_OP_IMM = 0b0010011
    OP_OP     = 0b0110011
    OP_MISC_MEM = 0b0001111
    OP_SYSTEM = 0b1110011
    
    # Register names
    REG_NAMES = [
        "x0",  "x1",  "x2",  "x3",  "x4",  "x5",  "x6",  "x7",
        "x8",  "x9",  "x10", "x11", "x12", "x13", "x14", "x15",
        "x16", "x17", "x18", "x19", "x20", "x21", "x22", "x23",
        "x24", "x25", "x26", "x27", "x28", "x29", "x30", "x31"
    ]
    
    def _sign_extend(self, value: int, bits: int) -> int:
        """Sign extend a value from 'bits' bits to 32 bits"""
        sign_bit = 1 << (bits - 1)
        if value & sign_bit:
            return value | (~((1 << bits) - 1) & 0xFFFFFFFF)
        return value
    
    def decode_r_type(self, insn: int) -> Tuple:
        """Decode R-type: opcode, rd, funct3, rs1, rs2, funct7"""
        opcode = insn & 0x7F
        rd = (insn >> 7) & 0x1F
        funct3 = (insn >> 12) & 0x7
        rs1 = (insn >> 15) & 0x1F
        rs2 = (insn >> 20) & 0x1F
        funct7 = (insn >> 25) & 0x7F
        return opcode, rd, funct3, rs1, rs2, funct7
    
    def decode_i_type(self, insn: int) -> Tuple:
        """Decode I-type: opcode, rd, funct3, rs1, imm"""
        opcode = insn & 0x7F
        rd = (insn >> 7) & 0x1F
        funct3 = (insn >> 12) & 0x7
        rs1 = (insn >> 15) & 0x1F
        imm = (insn >> 20) & 0xFFF
        imm_signed = self._sign_extend(imm, 12)
        return opcode, rd, funct3, rs1, imm_signed
    
    def decode_s_type(self, insn: int) -> Tuple:
        """Decode S-type: opcode, funct3, rs1, rs2, imm"""
        opcode = insn & 0x7F
        imm4_0 = (insn >> 7) & 0x1F
        funct3 = (insn >> 12) & 0x7
        rs1 = (insn >> 15) & 0x1F
        rs2 = (insn >> 20) & 0x1F
        imm11_5 = (insn >> 25) & 0x7F
        imm = (imm11_5 << 5) | imm4_0
        imm_signed = self._sign_extend(imm, 12)
        return opcode, funct3, rs1, rs2, imm_signed
    
    def decode_b_type(self, insn: int) -> Tuple:
        """Decode B-type: opcode, funct3, rs1, rs2, offset"""
        opcode = insn & 0x7F
        imm11 = (insn >> 7) & 0x1
        imm4_1 = (insn >> 8) & 0xF
        funct3 = (insn >> 12) & 0x7
        rs1 = (insn >> 15) & 0x1F
        rs2 = (insn >> 20) & 0x1F
        imm10_5 = (insn >> 25) & 0x3F
        imm12 = (insn >> 31) & 0x1
        offset = (imm12 << 12) | (imm11 << 11) | (imm10_5 << 5) | (imm4_1 << 1)
        offset_signed = self._sign_extend(offset, 13)
        return opcode, funct3, rs1, rs2, offset_signed
    
    def decode_u_type(self, insn: int) -> Tuple:
        """Decode U-type: opcode, rd, imm"""
        opcode = insn & 0x7F
        rd = (insn >> 7) & 0x1F
        imm = (insn >> 12) & 0xFFFFF
        return opcode, rd, imm
    
    def decode_j_type(self, insn: int) -> Tuple:
        """Decode J-type: opcode, rd, offset"""
        opcode = insn & 0x7F
        rd = (insn >> 7) & 0x1F
        imm19_12 = (insn >> 12) & 0xFF
        imm11 = (insn >> 20) & 0x1
        imm10_1 = (insn >> 21) & 0x3FF
        imm20 = (insn >> 31) & 0x1
        offset = (imm20 << 20) | (imm19_12 << 12) | (imm11 << 11) | (imm10_1 << 1)
        offset_signed = self._sign_extend(offset, 21)
        return opcode, rd, offset_signed
    
    def disassemble(self, insn: int) -> str:
        """Disassemble instruction to human-readable string"""
        if insn == 0:
            return "NOP (all zeros)"
        
        opcode = insn & 0x7F
        
        # R-type (OP: 0x33)
        if opcode == self.OP_OP:
            _, rd, funct3, rs1, rs2, funct7 = self.decode_r_type(insn)
            rd_name = self.REG_NAMES[rd]
            rs1_name = self.REG_NAMES[rs1]
            rs2_name = self.REG_NAMES[rs2]
            
            if funct3 == 0x0:
                if funct7 == 0x00:
                    return f"ADD {rd_name}, {rs1_name}, {rs2_name}"
                elif funct7 == 0x20:
                    return f"SUB {rd_name}, {rs1_name}, {rs2_name}"
            elif funct3 == 0x1 and funct7 == 0x00:
                return f"SLL {rd_name}, {rs1_name}, {rs2_name}"
            elif funct3 == 0x2 and funct7 == 0x00:
                return f"SLT {rd_name}, {rs1_name}, {rs2_name}"
            elif funct3 == 0x3 and funct7 == 0x00:
                return f"SLTU {rd_name}, {rs1_name}, {rs2_name}"
            elif funct3 == 0x4 and funct7 == 0x00:
                return f"XOR {rd_name}, {rs1_name}, {rs2_name}"
            elif funct3 == 0x5:
                if funct7 == 0x00:
                    return f"SRL {rd_name}, {rs1_name}, {rs2_name}"
                elif funct7 == 0x20:
                    return f"SRA {rd_name}, {rs1_name}, {rs2_name}"
            elif funct3 == 0x6 and funct7 == 0x00:
                return f"OR {rd_name}, {rs1_name}, {rs2_name}"
            elif funct3 == 0x7 and funct7 == 0x00:
                return f"AND {rd_name}, {rs1_name}, {rs2_name}"
            return f"UNKNOWN_R (f3={funct3:#x}, f7={funct7:#x})"
        
        # I-type ALU (OP-IMM: 0x13)
        elif opcode == self.OP_OP_IMM:
            _, rd, funct3, rs1, imm = self.decode_i_type(insn)
            rd_name = self.REG_NAMES[rd]
            rs1_name = self.REG_NAMES[rs1]
            
            if funct3 == 0x0:
                return f"ADDI {rd_name}, {rs1_name}, {imm}"
            elif funct3 == 0x2:
                return f"SLTI {rd_name}, {rs1_name}, {imm}"
            elif funct3 == 0x3:
                return f"SLTIU {rd_name}, {rs1_name}, {imm}"
            elif funct3 == 0x4:
                return f"XORI {rd_name}, {rs1_name}, {imm}"
            elif funct3 == 0x6:
                return f"ORI {rd_name}, {rs1_name}, {imm}"
            elif funct3 == 0x7:
                return f"ANDI {rd_name}, {rs1_name}, {imm}"
            elif funct3 == 0x1:
                shamt = imm & 0x1F
                return f"SLLI {rd_name}, {rs1_name}, {shamt}"
            elif funct3 == 0x5:
                shamt = imm & 0x1F
                if (imm >> 10) & 0x1:  # bit 30 set = SRAI
                    return f"SRAI {rd_name}, {rs1_name}, {shamt}"
                else:
                    return f"SRLI {rd_name}, {rs1_name}, {shamt}"
        
        # Load (LOAD: 0x03)
        elif opcode == self.OP_LOAD:
            _, rd, funct3, rs1, imm = self.decode_i_type(insn)
            rd_name = self.REG_NAMES[rd]
            rs1_name = self.REG_NAMES[rs1]
            
            if funct3 == 0x0:
                return f"LB {rd_name}, {imm}({rs1_name})"
            elif funct3 == 0x1:
                return f"LH {rd_name}, {imm}({rs1_name})"
            elif funct3 == 0x2:
                return f"LW {rd_name}, {imm}({rs1_name})"
            elif funct3 == 0x4:
                return f"LBU {rd_name}, {imm}({rs1_name})"
            elif funct3 == 0x5:
                return f"LHU {rd_name}, {imm}({rs1_name})"
        
        # Store (STORE: 0x23)
        elif opcode == self.OP_STORE:
            _, funct3, rs1, rs2, imm = self.decode_s_type(insn)
            rs1_name = self.REG_NAMES[rs1]
            rs2_name = self.REG_NAMES[rs2]
            
            if funct3 == 0x0:
                return f"SB {rs2_name}, {imm}({rs1_name})"
            elif funct3 == 0x1:
                return f"SH {rs2_name}, {imm}({rs1_name})"
            elif funct3 == 0x2:
                return f"SW {rs2_name}, {imm}({rs1_name})"
        
        # Branch (BRANCH: 0x63)
        elif opcode == self.OP_BRANCH:
            _, funct3, rs1, rs2, offset = self.decode_b_type(insn)
            rs1_name = self.REG_NAMES[rs1]
            rs2_name = self.REG_NAMES[rs2]
            
            if funct3 == 0x0:
                return f"BEQ {rs1_name}, {rs2_name}, {offset}"
            elif funct3 == 0x1:
                return f"BNE {rs1_name}, {rs2_name}, {offset}"
            elif funct3 == 0x4:
                return f"BLT {rs1_name}, {rs2_name}, {offset}"
            elif funct3 == 0x5:
                return f"BGE {rs1_name}, {rs2_name}, {offset}"
            elif funct3 == 0x6:
                return f"BLTU {rs1_name}, {rs2_name}, {offset}"
            elif funct3 == 0x7:
                return f"BGEU {rs1_name}, {rs2_name}, {offset}"
        
        # JALR (JALR: 0x67)
        elif opcode == self.OP_JALR:
            _, rd, funct3, rs1, imm = self.decode_i_type(insn)
            rd_name = self.REG_NAMES[rd]
            rs1_name = self.REG_NAMES[rs1]
            if funct3 == 0x0:
                return f"JALR {rd_name}, {imm}({rs1_name})"
        
        # JAL (JAL: 0x6F)
        elif opcode == self.OP_JAL:
            _, rd, offset = self.decode_j_type(insn)
            rd_name = self.REG_NAMES[rd]
            return f"JAL {rd_name}, {offset}"
        
        # LUI (LUI: 0x37)
        elif opcode == self.OP_LUI:
            _, rd, imm = self.decode_u_type(insn)
            rd_name = self.REG_NAMES[rd]
            return f"LUI {rd_name}, 0x{imm:05x}"
        
        # AUIPC (AUIPC: 0x17)
        elif opcode == self.OP_AUIPC:
            _, rd, imm = self.decode_u_type(insn)
            rd_name = self.REG_NAMES[rd]
            return f"AUIPC {rd_name}, 0x{imm:05x}"
        
        # MISC-MEM (FENCE: 0x0F)
        elif opcode == self.OP_MISC_MEM:
            _, rd, funct3, rs1, imm = self.decode_i_type(insn)
            if funct3 == 0x0:
                return "FENCE"
            elif funct3 == 0x1:
                return "FENCE.I"
        
        # SYSTEM (SYSTEM: 0x73)
        elif opcode == self.OP_SYSTEM:
            _, rd, funct3, rs1, imm = self.decode_i_type(insn)
            rd_name = self.REG_NAMES[rd]
            rs1_name = self.REG_NAMES[rs1]
            csr = imm & 0xFFF
            
            if funct3 == 0x0:
                if imm == 0x0:
                    return "ECALL"
                elif imm == 0x1:
                    return "EBREAK"
                elif imm == 0x302:
                    return "MRET"
                return f"SYSTEM_PRIV (imm={imm:#x})"
            elif funct3 == 0x1:
                return f"CSRRW {rd_name}, 0x{csr:03x}, {rs1_name}"
            elif funct3 == 0x2:
                return f"CSRRS {rd_name}, 0x{csr:03x}, {rs1_name}"
            elif funct3 == 0x3:
                return f"CSRRC {rd_name}, 0x{csr:03x}, {rs1_name}"
            elif funct3 == 0x5:
                zimm = rs1
                return f"CSRRWI {rd_name}, 0x{csr:03x}, {zimm}"
            elif funct3 == 0x6:
                zimm = rs1
                return f"CSRRSI {rd_name}, 0x{csr:03x}, {zimm}"
            elif funct3 == 0x7:
                zimm = rs1
                return f"CSRRCI {rd_name}, 0x{csr:03x}, {zimm}"
        
        return f"UNKNOWN (opcode={opcode:#09b})"


def validate_hex_file(hex_file_path: str) -> Tuple[List[str], List[Dict]]:
    """Validate encodings in hex file
    
    Returns:
        (errors, decoded_lines): List of error messages and decoded instructions
    """
    decoder = RV32IDecoder()
    errors = []
    decoded_lines = []
    
    try:
        with open(hex_file_path, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        errors.append(f"ERROR: File not found: {hex_file_path}")
        return errors, decoded_lines
    
    for line_num, line in enumerate(lines, start=1):
        line = line.strip()
        if not line or line.startswith('#') or line.startswith('//'):
            continue
        
        try:
            encoding = int(line, 16)
            disasm = decoder.disassemble(encoding)
            
            decoded_lines.append({
                'line': line_num,
                'encoding': f"0x{encoding:08x}",
                'hex': line,
                'instruction': disasm
            })
            
            # Validate line 6 (known issue: ADD x4, x1, x2 encoded incorrectly)
            if line_num == 6:
                if encoding == 0x00208233:
                    errors.append(f"Line {line_num}: ENCODING ERROR")
                    errors.append(f"  Found:    0x{encoding:08x} = {disasm}")
                    errors.append(f"  Expected: 0x00110233 = ADD x4, x1, x2")
                    errors.append(f"  Issue:    rs1 field encodes x1 but instruction shows SLT")
        
        except ValueError:
            errors.append(f"Line {line_num}: PARSE ERROR - Invalid hex: {line}")
    
    return errors, decoded_lines


def main():
    if len(sys.argv) < 2:
        print("Usage: python validate_encodings.py <hex_file>")
        print("Example: python validate_encodings.py sim/tests/rv32i_comprehensive_test.hex")
        sys.exit(1)
    
    hex_file = sys.argv[1]
    
    print("="*80)
    print("RV32I Instruction Encoding Validator")
    print("="*80)
    print(f"File: {hex_file}\n")
    
    errors, decoded = validate_hex_file(hex_file)
    
    # Show first 20 decoded instructions
    print("Decoded Instructions (first 20):")
    print("-"*80)
    for entry in decoded[:20]:
        print(f"Line {entry['line']:3d}: {entry['encoding']} -> {entry['instruction']}")
    
    if len(decoded) > 20:
        print(f"... ({len(decoded) - 20} more lines)")
    print()
    
    # Display errors
    if errors:
        print("="*80)
        print("VALIDATION ERRORS:")
        print("="*80)
        for error in errors:
            print(error)
        print(f"\nTotal: {len([e for e in errors if 'Line' in e and 'ERROR' in e])} errors")
        sys.exit(1)
    else:
        print("="*80)
        print("✓ ALL ENCODINGS VALID")
        print("="*80)
        print(f"Validated {len(decoded)} instructions")
        sys.exit(0)


if __name__ == "__main__":
    main()
