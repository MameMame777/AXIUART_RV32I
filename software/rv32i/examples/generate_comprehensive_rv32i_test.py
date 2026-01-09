#!/usr/bin/env python3
"""
Generate Comprehensive RV32I Test - All 40 Instructions with Interdependencies

Creates a test program that exercises all RV32I base instructions in an
interdependent chain where each instruction's result is used by subsequent
instructions. Includes exception handler with MRET.

Memory Layout:
- 0x000-0x1FF: Main program (128 instructions max)
- 0x200-0x220: Exception handler (16 instructions)
- 0x400-0x500: Data area for load/store tests (256 bytes)

Output:
- rv32i_comprehensive_test.hex: Hex file for UVM test
- rv32i_comprehensive_map.json: Instruction map with expected results
"""

import sys
import json
sys.path.insert(0, '..')

from encoder import RV32IInstructionEncoder

# CSR addresses
CSR_MTVEC = 0x305
CSR_MEPC = 0x341
CSR_MCAUSE = 0x342
CSR_MTVAL = 0x343

def generate_comprehensive_test():
    """Generate all 40 RV32I instructions with interdependencies"""
    enc = RV32IInstructionEncoder()
    instructions = []
    instruction_map = []
    
    def add_insn(insn, name, operands="", expected_reg=None, expected_val=None, comment=""):
        """Helper to add instruction with metadata"""
        addr = len(instructions) * 4
        instructions.append(insn)
        entry = {
            "address": f"0x{addr:03X}",
            "encoding": f"0x{insn:08X}",
            "name": name,
            "operands": operands,
            "comment": comment
        }
        if expected_reg is not None:
            entry["expected_register"] = f"x{expected_reg}"
            entry["expected_value"] = f"0x{expected_val:08X}" if isinstance(expected_val, int) else expected_val
        instruction_map.append(entry)
        return addr
    
    # =========================================================================
    # PART 1: CSR INITIALIZATION (mtvec = 0x200 for exception handler)
    # =========================================================================
    add_insn(enc.addi(31, 0, 0x200 & 0x7FF), "ADDI", "x31, x0, 0x200", 31, 0x200, 
             "Set handler address (lower 11 bits)")
    add_insn(enc.csrrw(0, CSR_MTVEC, 31), "CSRRW", "x0, mtvec, x31", None, None,
             "mtvec = 0x200 (4 cycle latency)")
    
    # =========================================================================
    # PART 2: IMMEDIATE LOADS (base values for subsequent operations)
    # =========================================================================
    add_insn(enc.addi(1, 0, 10), "ADDI", "x1, x0, 10", 1, 10, "x1 = 10")
    add_insn(enc.addi(2, 0, 20), "ADDI", "x2, x0, 20", 2, 20, "x2 = 20")
    add_insn(enc.lui(3, 0x12345), "LUI", "x3, 0x12345", 3, 0x12345000, "x3 = 0x12345000")
    
    # =========================================================================
    # PART 3: R-TYPE ALU OPERATIONS (using previous results)
    # =========================================================================
    add_insn(enc.add(4, 1, 2), "ADD", "x4, x1, x2", 4, 30, "x4 = 10 + 20 = 30")
    add_insn(enc.sub(5, 4, 1), "SUB", "x5, x4, x1", 5, 20, "x5 = 30 - 10 = 20")
    add_insn(enc.slt(6, 1, 2), "SLT", "x6, x1, x2", 6, 1, "x6 = (10 < 20) = 1")
    add_insn(enc.sltu(7, 2, 1), "SLTU", "x7, x2, x1", 7, 0, "x7 = (20 < 10) unsigned = 0")
    add_insn(enc.and_(8, 4, 5), "AND", "x8, x4, x5", 8, 20, "x8 = 30 & 20 = 20")
    add_insn(enc.or_(9, 1, 2), "OR", "x9, x1, x2", 9, 30, "x9 = 10 | 20 = 30")
    add_insn(enc.xor(10, 4, 5), "XOR", "x10, x4, x5", 10, 10, "x10 = 30 ^ 20 = 10")
    add_insn(enc.sll(11, 1, 6), "SLL", "x11, x1, x6", 11, 20, "x11 = 10 << 1 = 20")
    add_insn(enc.srl(12, 4, 6), "SRL", "x12, x4, x6", 12, 15, "x12 = 30 >> 1 = 15")
    add_insn(enc.sra(13, 12, 6), "SRA", "x13, x12, x6", 13, 7, "x13 = 15 >>> 1 = 7")
    
    # =========================================================================
    # PART 4: I-TYPE ALU OPERATIONS (using R-type results)
    # =========================================================================
    add_insn(enc.addi(14, 4, 100), "ADDI", "x14, x4, 100", 14, 130, "x14 = 30 + 100 = 130")
    add_insn(enc.slti(15, 14, 200), "SLTI", "x15, x14, 200", 15, 1, "x15 = (130 < 200) = 1")
    add_insn(enc.sltiu(16, 14, 100), "SLTIU", "x16, x14, 100", 16, 0, "x16 = (130 < 100) unsigned = 0")
    add_insn(enc.andi(17, 14, 0xFF), "ANDI", "x17, x14, 0xFF", 17, 130, "x17 = 130 & 0xFF = 130")
    add_insn(enc.ori(18, 17, 0x100), "ORI", "x18, x17, 0x100", 18, 0x182, "x18 = 130 | 0x100 = 0x182")
    add_insn(enc.xori(19, 18, 0x0FF), "XORI", "x19, x18, 0xFF", 19, 0x17D, "x19 = 0x182 ^ 0xFF = 0x17D")
    add_insn(enc.slli(20, 5, 3), "SLLI", "x20, x5, 3", 20, 160, "x20 = 20 << 3 = 160")
    add_insn(enc.srli(21, 20, 2), "SRLI", "x21, x20, 2", 21, 40, "x21 = 160 >> 2 = 40")
    add_insn(enc.srai(22, 14, 1), "SRAI", "x22, x14, 1", 22, 65, "x22 = 130 >>> 1 = 65")
    
    # =========================================================================
    # PART 5: MEMORY ADDRESS PREPARATION
    # =========================================================================
    add_insn(enc.lui(23, 0), "LUI", "x23, 0", 23, 0, "x23 = 0x0 (RAM base)")
    add_insn(enc.addi(23, 23, 0x400), "ADDI", "x23, x23, 0x400", 23, 0x400, "x23 = 0x400 (data area)")
    add_insn(enc.auipc(24, 0), "AUIPC", "x24, 0", 24, None, "x24 = PC + 0 (PC-relative)")
    
    # =========================================================================
    # PART 6: STORE OPERATIONS (write test data to memory)
    # =========================================================================
    add_insn(enc.sw(4, 0, 23), "SW", "x4, 0(x23)", None, None, "MEM[0x400] = x4 (30)")
    add_insn(enc.sh(5, 4, 23), "SH", "x5, 4(x23)", None, None, "MEM[0x404] = x5[15:0] (20)")
    add_insn(enc.sb(1, 8, 23), "SB", "x1, 8(x23)", None, None, "MEM[0x408] = x1[7:0] (10)")
    
    # =========================================================================
    # PART 7: LOAD OPERATIONS (read back test data)
    # =========================================================================
    add_insn(enc.lw(25, 23, 0), "LW", "x25, 0(x23)", 25, 30, "x25 = MEM[0x400] = 30")
    add_insn(enc.lh(26, 23, 4), "LH", "x26, 4(x23)", 26, 20, "x26 = sign_ext(MEM[0x404][15:0]) = 20")
    add_insn(enc.lhu(27, 23, 4), "LHU", "x27, 4(x23)", 27, 20, "x27 = zero_ext(MEM[0x404][15:0]) = 20")
    add_insn(enc.lb(28, 23, 8), "LB", "x28, 8(x23)", 28, 10, "x28 = sign_ext(MEM[0x408][7:0]) = 10")
    add_insn(enc.lbu(29, 23, 8), "LBU", "x29, 8(x23)", 29, 10, "x29 = zero_ext(MEM[0x408][7:0]) = 10")
    
    # =========================================================================
    # PART 8: BRANCH OPERATIONS (test all 6 branch conditions)
    # =========================================================================
    # BEQ: x1 == x1 (taken)
    beq_target = (len(instructions) + 2) * 4
    add_insn(enc.beq(1, 1, 8), "BEQ", "x1, x1, +8", None, None, "Branch if x1 == x1 (TAKEN)")
    add_insn(enc.addi(30, 0, 99), "ADDI", "x30, x0, 99", None, None, "SKIPPED (branch taken)")
    # BEQ target
    add_insn(enc.addi(30, 0, 1), "ADDI", "x30, x0, 1", 30, 1, "x30 = 1 (BEQ passed)")
    
    # BNE: x1 != x2 (taken)
    add_insn(enc.bne(1, 2, 8), "BNE", "x1, x2, +8", None, None, "Branch if x1 != x2 (TAKEN)")
    add_insn(enc.addi(30, 30, 99), "ADDI", "x30, x30, 99", None, None, "SKIPPED")
    add_insn(enc.addi(30, 30, 1), "ADDI", "x30, x30, 1", 30, 2, "x30 = 2 (BNE passed)")
    
    # BLT: x1 < x2 (taken, 10 < 20)
    add_insn(enc.blt(1, 2, 8), "BLT", "x1, x2, +8", None, None, "Branch if x1 < x2 (TAKEN)")
    add_insn(enc.addi(30, 30, 99), "ADDI", "x30, x30, 99", None, None, "SKIPPED")
    add_insn(enc.addi(30, 30, 1), "ADDI", "x30, x30, 1", 30, 3, "x30 = 3 (BLT passed)")
    
    # BGE: x2 >= x1 (taken, 20 >= 10)
    add_insn(enc.bge(2, 1, 8), "BGE", "x2, x1, +8", None, None, "Branch if x2 >= x1 (TAKEN)")
    add_insn(enc.addi(30, 30, 99), "ADDI", "x30, x30, 99", None, None, "SKIPPED")
    add_insn(enc.addi(30, 30, 1), "ADDI", "x30, x30, 1", 30, 4, "x30 = 4 (BGE passed)")
    
    # BLTU: x1 < x2 unsigned (taken)
    add_insn(enc.bltu(1, 2, 8), "BLTU", "x1, x2, +8", None, None, "Branch if x1 < x2 unsigned (TAKEN)")
    add_insn(enc.addi(30, 30, 99), "ADDI", "x30, x30, 99", None, None, "SKIPPED")
    add_insn(enc.addi(30, 30, 1), "ADDI", "x30, x30, 1", 30, 5, "x30 = 5 (BLTU passed)")
    
    # BGEU: x2 >= x1 unsigned (taken)
    add_insn(enc.bgeu(2, 1, 8), "BGEU", "x2, x1, +8", None, None, "Branch if x2 >= x1 unsigned (TAKEN)")
    add_insn(enc.addi(30, 30, 99), "ADDI", "x30, x30, 99", None, None, "SKIPPED")
    add_insn(enc.addi(30, 30, 1), "ADDI", "x30, x30, 1", 30, 6, "x30 = 6 (BGEU passed)")
    
    # =========================================================================
    # PART 9: JUMP OPERATIONS
    # =========================================================================
    # JAL: Jump and link
    jal_return = (len(instructions) + 1) * 4
    jal_target = jal_return + 8
    add_insn(enc.jal(1, 8), "JAL", "x1, +8", 1, jal_return + 4, "x1 = PC+4, jump to target")
    add_insn(enc.addi(30, 30, 99), "ADDI", "x30, x30, 99", None, None, "SKIPPED (JAL)")
    # JAL target
    add_insn(enc.addi(30, 30, 10), "ADDI", "x30, x30, 10", 30, 16, "x30 = 16 (JAL passed)")
    
    # JALR: Jump and link register (return using x1)
    jalr_target_pc = (len(instructions) + 2) * 4
    add_insn(enc.addi(2, 0, jalr_target_pc & 0x7FF), "ADDI", "x2, x0, target", 2, jalr_target_pc, 
             f"x2 = 0x{jalr_target_pc:03X} (JALR target)")
    add_insn(enc.jalr(3, 2, 0), "JALR", "x3, 0(x2)", 3, None, "x3 = PC+4, jump to x2")
    add_insn(enc.addi(30, 30, 99), "ADDI", "x30, x30, 99", None, None, "SKIPPED (JALR)")
    # JALR target
    add_insn(enc.addi(30, 30, 20), "ADDI", "x30, x30, 20", 30, 36, "x30 = 36 (JALR passed)")
    
    # =========================================================================
    # PART 10: CSR OPERATIONS (read/write/set/clear)
    # =========================================================================
    # Wait 4+ cycles after mtvec write before using CSRs
    add_insn(enc.addi(0, 0, 0), "ADDI", "x0, x0, 0", None, None, "NOP (CSR timing)")
    add_insn(enc.addi(0, 0, 0), "ADDI", "x0, x0, 0", None, None, "NOP (CSR timing)")
    add_insn(enc.addi(0, 0, 0), "ADDI", "x0, x0, 0", None, None, "NOP (CSR timing)")
    
    # CSRRS: Set bits in mcause (test register)
    add_insn(enc.addi(10, 0, 0x5), "ADDI", "x10, x0, 0x5", 10, 5, "x10 = 5 (bits to set)")
    add_insn(enc.csrrs(11, CSR_MCAUSE, 10), "CSRRS", "x11, mcause, x10", 11, None, "Set bits in mcause")
    
    # CSRRC: Clear bits in mcause
    add_insn(enc.addi(12, 0, 0x3), "ADDI", "x12, x0, 0x3", 12, 3, "x12 = 3 (bits to clear)")
    add_insn(enc.csrrc(13, CSR_MCAUSE, 12), "CSRRC", "x13, mcause, x12", 13, None, "Clear bits in mcause")
    
    # CSRRWI: Write immediate to mtval
    add_insn(enc.csrrwi(14, CSR_MTVAL, 0x1F), "CSRRWI", "x14, mtval, 0x1F", 14, None, "mtval = 0x1F")
    
    # CSRRSI: Set bits immediate
    add_insn(enc.csrrsi(15, CSR_MTVAL, 0x10), "CSRRSI", "x15, mtval, 0x10", 15, None, "Set bit 4 in mtval")
    
    # CSRRCI: Clear bits immediate
    add_insn(enc.csrrci(16, CSR_MTVAL, 0x0F), "CSRRCI", "x16, mtval, 0x0F", 16, None, "Clear lower bits in mtval")
    
    # =========================================================================
    # PART 11: FENCE (treated as NOP)
    # =========================================================================
    add_insn(enc.fence(), "FENCE", "", None, None, "Memory fence (NOP in this impl)")
    
    # =========================================================================
    # PART 12: ECALL (trigger exception handler)
    # =========================================================================
    ecall_pc = len(instructions) * 4
    add_insn(enc.ecall(), "ECALL", "", None, None, f"Call exception handler at 0x200")
    
    # Return point after ECALL (handler returns here via MRET)
    add_insn(enc.addi(30, 30, 100), "ADDI", "x30, x30, 100", 30, 136, "x30 = 136 (after ECALL)")
    
    # =========================================================================
    # PART 13: WRITE LED AND EBREAK
    # =========================================================================
    add_insn(enc.lui(17, 0x4), "LUI", "x17, 0x4", 17, 0x4000, "x17 = 0x4000")
    add_insn(enc.addi(17, 17, 0x7C), "ADDI", "x17, x17, 0x7C", 17, 0x407C, "x17 = 0x407C (LED)")
    add_insn(enc.sw(30, 0, 17), "SW", "x30, 0(x17)", None, None, "LED = x30")
    add_insn(enc.ebreak(), "EBREAK", "", None, None, "Stop CPU")
    
    # =========================================================================
    # PAD TO 0x200 (exception handler base)
    # =========================================================================
    current_addr = len(instructions) * 4
    handler_addr = 0x200
    padding_words = (handler_addr - current_addr) // 4
    for _ in range(padding_words):
        instructions.append(0x00000000)  # NOP (invalid instruction, won't execute)
    
    # =========================================================================
    # EXCEPTION HANDLER @ 0x200
    # =========================================================================
    # Note: mepc already points to the instruction after ECALL (hardware adds +4)
    # Handler must save/restore registers without clobbering any used by test
    # Use x1 (ra) as scratch - set to 0x400 base, then use small offsets
    handler_start = len(instructions)
    add_insn(enc.lui(1, 0), "LUI", "x1, 0", 1, 0, "x1 = 0x0")
    add_insn(enc.addi(1, 1, 0x400), "ADDI", "x1, x1, 0x400", 1, 0x400, "x1 = 0x400 (scratch memory base)")
    add_insn(enc.sw(10, 0, 1), "SW", "x10, 0(x1)", None, 0x400, "Save x10 to 0x400")
    add_insn(enc.sw(11, 4, 1), "SW", "x11, 4(x1)", None, 0x404, "Save x11 to 0x404")
    add_insn(enc.csrrs(10, CSR_MEPC, 0), "CSRRS", "x10, mepc, x0", 10, None, "x10 = mepc (return address)")
    add_insn(enc.csrrs(11, CSR_MCAUSE, 0), "CSRRS", "x11, mcause, x0", 11, None, "x11 = mcause (exception cause)")
    add_insn(enc.lw(10, 1, 0), "LW", "x10, 0(x1)", 10, None, "Restore x10 from 0x400")
    add_insn(enc.lw(11, 1, 4), "LW", "x11, 4(x1)", 11, None, "Restore x11 from 0x404")
    add_insn(enc.mret(), "MRET", "", None, None, "Return from exception (PC = mepc)")
    
    return instructions, instruction_map

def write_hex_file(instructions, filename):
    """Write instructions to hex file"""
    with open(filename, 'w') as f:
        for insn in instructions:
            f.write(f"{insn:08x}\n")

def write_map_file(instruction_map, filename):
    """Write instruction map to JSON"""
    output = {
        "test_name": "RV32I Comprehensive Test",
        "description": "All 40 RV32I base instructions with interdependencies",
        "total_instructions": len(instruction_map),
        "memory_layout": {
            "main_program": "0x000-0x1FF",
            "exception_handler": "0x200-0x220",
            "data_area": "0x400-0x500"
        },
        "instructions": instruction_map
    }
    with open(filename, 'w') as f:
        json.dump(output, f, indent=2)

if __name__ == "__main__":
    print("Generating comprehensive RV32I test...")
    instructions, instruction_map = generate_comprehensive_test()
    
    # Output paths (from software/rv32i/examples/ to workspace root sim/tests/)
    hex_file = "../../../sim/tests/rv32i_comprehensive_test.hex"
    map_file = "../../../sim/tests/rv32i_comprehensive_map.json"
    
    write_hex_file(instructions, hex_file)
    write_map_file(instruction_map, map_file)
    
    print(f"Generated {len(instructions)} instructions")
    print(f"Hex file: {hex_file}")
    print(f"Map file: {map_file}")
    print(f"Main program: {len([i for i in instruction_map if int(i['address'], 16) < 0x200])} instructions")
    print(f"Handler: {len([i for i in instruction_map if int(i['address'], 16) >= 0x200])} instructions")
    print("\nDone!")
