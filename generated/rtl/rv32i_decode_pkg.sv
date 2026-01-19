//
// RV32I Decode Package
// Auto-generated from VexRiscv RTL analysis
// Generated: 2026-01-17 19:42:57
// Source: vexriscv_reference/generated/VexRiscv.v
//
// DO NOT EDIT - Regenerate with: python tools/vexriscv_rtl_parser.py
//

`ifndef RV32I_DECODE_PKG_SV
`define RV32I_DECODE_PKG_SV

package rv32i_decode_pkg;

    // ============================================================
    // Instruction Opcodes (RV32I Base)
    // ============================================================
    
    localparam logic [6:0] OPCODE_LOAD      = 7'b0000011;
    localparam logic [6:0] OPCODE_STORE     = 7'b0100011;
    localparam logic [6:0] OPCODE_BRANCH    = 7'b1100011;
    localparam logic [6:0] OPCODE_JALR      = 7'b1100111;
    localparam logic [6:0] OPCODE_JAL       = 7'b1101111;
    localparam logic [6:0] OPCODE_OP_IMM    = 7'b0010011;
    localparam logic [6:0] OPCODE_OP        = 7'b0110011;
    localparam logic [6:0] OPCODE_AUIPC     = 7'b0010111;
    localparam logic [6:0] OPCODE_LUI       = 7'b0110111;
    localparam logic [6:0] OPCODE_SYSTEM    = 7'b1110011;
    
    // ============================================================
    // Function Codes
    // ============================================================
    
    // ALU funct3
    localparam logic [2:0] FUNCT3_ADD_SUB   = 3'b000;
    localparam logic [2:0] FUNCT3_SLL       = 3'b001;
    localparam logic [2:0] FUNCT3_SLT       = 3'b010;
    localparam logic [2:0] FUNCT3_SLTU      = 3'b011;
    localparam logic [2:0] FUNCT3_XOR       = 3'b100;
    localparam logic [2:0] FUNCT3_SRL_SRA   = 3'b101;
    localparam logic [2:0] FUNCT3_OR        = 3'b110;
    localparam logic [2:0] FUNCT3_AND       = 3'b111;
    
    // Load/Store funct3
    localparam logic [2:0] FUNCT3_LB_SB     = 3'b000;
    localparam logic [2:0] FUNCT3_LH_SH     = 3'b001;
    localparam logic [2:0] FUNCT3_LW_SW     = 3'b010;
    localparam logic [2:0] FUNCT3_LBU       = 3'b100;
    localparam logic [2:0] FUNCT3_LHU       = 3'b101;
    
    // Branch funct3
    localparam logic [2:0] FUNCT3_BEQ       = 3'b000;
    localparam logic [2:0] FUNCT3_BNE       = 3'b001;
    localparam logic [2:0] FUNCT3_BLT       = 3'b100;
    localparam logic [2:0] FUNCT3_BGE       = 3'b101;
    localparam logic [2:0] FUNCT3_BLTU      = 3'b110;
    localparam logic [2:0] FUNCT3_BGEU      = 3'b111;
    
    // CSR funct3
    localparam logic [2:0] FUNCT3_CSRRW     = 3'b001;
    localparam logic [2:0] FUNCT3_CSRRS     = 3'b010;
    localparam logic [2:0] FUNCT3_CSRRC     = 3'b011;
    localparam logic [2:0] FUNCT3_CSRRWI    = 3'b101;
    localparam logic [2:0] FUNCT3_CSRRSI    = 3'b110;
    localparam logic [2:0] FUNCT3_CSRRCI    = 3'b111;
    
    // funct7
    localparam logic [6:0] FUNCT7_NORMAL    = 7'b0000000;
    localparam logic [6:0] FUNCT7_ALTERNATE = 7'b0100000;  // SUB, SRA
    
    // ============================================================
    // CSR Addresses (Minimal set for VexRiscv GenSmallAndProductive)
    // ============================================================
    
    // Machine Information
    localparam logic [11:0] CSR_MVENDORID   = 12'hF11;
    localparam logic [11:0] CSR_MARCHID     = 12'hF12;
    localparam logic [11:0] CSR_MIMPID      = 12'hF13;
    localparam logic [11:0] CSR_MHARTID     = 12'hF14;
    
    // Machine Trap Setup
    localparam logic [11:0] CSR_MSTATUS     = 12'h300;
    localparam logic [11:0] CSR_MISA        = 12'h301;
    localparam logic [11:0] CSR_MIE         = 12'h304;
    localparam logic [11:0] CSR_MTVEC       = 12'h305;
    
    // Machine Trap Handling
    localparam logic [11:0] CSR_MSCRATCH    = 12'h340;
    localparam logic [11:0] CSR_MEPC        = 12'h341;
    localparam logic [11:0] CSR_MCAUSE      = 12'h342;
    localparam logic [11:0] CSR_MTVAL       = 12'h343;
    localparam logic [11:0] CSR_MIP         = 12'h344;
    
    // Machine Counter/Timers
    localparam logic [11:0] CSR_MCYCLE      = 12'hB00;
    localparam logic [11:0] CSR_MINSTRET    = 12'hB02;
    localparam logic [11:0] CSR_MCYCLEH     = 12'hB80;
    localparam logic [11:0] CSR_MINSTRETH   = 12'hB82;
    
    // ============================================================
    // Instruction Format Helpers
    // ============================================================
    
    function automatic logic [6:0] get_opcode(input logic [31:0] insn);
        return insn[6:0];
    endfunction
    
    function automatic logic [2:0] get_funct3(input logic [31:0] insn);
        return insn[14:12];
    endfunction
    
    function automatic logic [6:0] get_funct7(input logic [31:0] insn);
        return insn[31:25];
    endfunction
    
    function automatic logic [4:0] get_rd(input logic [31:0] insn);
        return insn[11:7];
    endfunction
    
    function automatic logic [4:0] get_rs1(input logic [31:0] insn);
        return insn[19:15];
    endfunction
    
    function automatic logic [4:0] get_rs2(input logic [31:0] insn);
        return insn[24:20];
    endfunction
    
    function automatic logic [11:0] get_imm_i(input logic [31:0] insn);
        return insn[31:20];
    endfunction
    
    function automatic logic [11:0] get_csr_addr(input logic [31:0] insn);
        return insn[31:20];
    endfunction

endpackage : rv32i_decode_pkg

`endif // RV32I_DECODE_PKG_SV
