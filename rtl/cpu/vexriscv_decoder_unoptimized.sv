`timescale 1ns/1ps
//==============================================================================
// VexRiscv Instruction Decoder - Unoptimized (Case Statement Based)
//
// Generated from SpinalHDL GenSmallAndProductive configuration with stupidDecoder=true
// This decoder uses explicit case statements instead of ROM optimization
// Fixes: I-type ALU instruction decoding (REGFILE_WRITE_VALID and SRC2_CTRL)
//
// SpinalHDL Version: 1.13.0
// Generator: GenSmallAndProductive_UnoptimizedDecoder.scala
// Generated: 2026-01-19
//==============================================================================

module vexriscv_decoder_unoptimized
    import vexriscv_pkg::*;
(
    input  logic [31:0] decode_INSTRUCTION,
    
    // Individual control signals
    output logic [1:0]  decode_SRC1_CTRL,
    output logic        decode_SRC_USE_SUB_LESS,
    output logic        decode_MEMORY_ENABLE,
    output logic        decode_RS1_USE,
    output logic [1:0]  decode_SRC2_CTRL,
    output logic        decode_REGFILE_WRITE_VALID,
    output logic        decode_BYPASSABLE_EXECUTE_STAGE,
    output logic        decode_BYPASSABLE_MEMORY_STAGE,
    output logic        decode_MEMORY_STORE,
    output logic        decode_RS2_USE,
    output logic        decode_IS_CSR,
    output logic        decode_ENV_CTRL,
    output logic [1:0]  decode_ALU_CTRL,
    output logic        decode_SRC_LESS_UNSIGNED,
    output logic [1:0]  decode_ALU_BITWISE_CTRL,
    output logic        decode_SRC_ADD_ZERO,
    output logic [1:0]  decode_SHIFT_CTRL,
    output logic [1:0]  decode_BRANCH_CTRL
);

    //==========================================================================
    // Instruction Pattern Matching Conditions (from SpinalHDL generation)
    //==========================================================================
    
    logic when_Decoder_l112_0;   // LB
    logic when_Decoder_l112_1;   // LH
    logic when_Decoder_l112_2;   // LW
    logic when_Decoder_l112_3;   // LBU
    logic when_Decoder_l112_4;   // LHU
    logic when_Decoder_l112_5;   // SB
    logic when_Decoder_l112_6;   // SH
    logic when_Decoder_l112_7;   // SW
    logic when_Decoder_l112_8;   // CSRRW
    logic when_Decoder_l112_9;   // CSRRS
    logic when_Decoder_l112_10;  // CSRRC
    logic when_Decoder_l112_11;  // CSRRWI
    logic when_Decoder_l112_12;  // CSRRSI
    logic when_Decoder_l112_13;  // CSRRCI
    logic when_Decoder_l112_14;  // MRET
    logic when_Decoder_l112_15;  // SRET
    logic when_Decoder_l112_16;  // ADD
    logic when_Decoder_l112_17;  // SUB
    logic when_Decoder_l112_18;  // SLT
    logic when_Decoder_l112_19;  // SLTU
    logic when_Decoder_l112_20;  // XOR
    logic when_Decoder_l112_21;  // OR
    logic when_Decoder_l112_22;  // AND
    logic when_Decoder_l112_23;  // ADDI
    logic when_Decoder_l112_24;  // SLTI
    logic when_Decoder_l112_25;  // SLTIU
    logic when_Decoder_l112_26;  // XORI
    logic when_Decoder_l112_27;  // ORI
    logic when_Decoder_l112_28;  // ANDI
    logic when_Decoder_l112_29;  // LUI
    logic when_Decoder_l112_30;  // AUIPC
    logic when_Decoder_l112_31;  // SLL
    logic when_Decoder_l112_32;  // SRL
    logic when_Decoder_l112_33;  // SRA
    logic when_Decoder_l112_34;  // SLLI
    logic when_Decoder_l112_35;  // SRLI
    logic when_Decoder_l112_36;  // SRAI
    logic when_Decoder_l112_37;  // JAL
    logic when_Decoder_l112_38;  // JALR
    logic when_Decoder_l112_39;  // BEQ
    logic when_Decoder_l112_40;  // BNE
    logic when_Decoder_l112_41;  // BLT
    logic when_Decoder_l112_42;  // BGE
    logic when_Decoder_l112_43;  // BLTU
    logic when_Decoder_l112_44;  // BGEU

    // Pattern matching assignments
    assign when_Decoder_l112_0  = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00000003);  // LB
    assign when_Decoder_l112_1  = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00001003);  // LH
    assign when_Decoder_l112_2  = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00002003);  // LW
    assign when_Decoder_l112_3  = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00004003);  // LBU
    assign when_Decoder_l112_4  = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00005003);  // LHU
    assign when_Decoder_l112_5  = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00000023);  // SB
    assign when_Decoder_l112_6  = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00001023);  // SH
    assign when_Decoder_l112_7  = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00002023);  // SW
    assign when_Decoder_l112_8  = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00001073);  // CSRRW
    assign when_Decoder_l112_9  = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00002073);  // CSRRS
    assign when_Decoder_l112_10 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00003073);  // CSRRC
    assign when_Decoder_l112_11 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00005073);  // CSRRWI
    assign when_Decoder_l112_12 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00006073);  // CSRRSI
    assign when_Decoder_l112_13 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00007073);  // CSRRCI
    assign when_Decoder_l112_14 = ((decode_INSTRUCTION & 32'hffffffff) == 32'h30200073);  // MRET
    assign when_Decoder_l112_15 = ((decode_INSTRUCTION & 32'hffffffff) == 32'h10200073);  // SRET
    assign when_Decoder_l112_16 = ((decode_INSTRUCTION & 32'hfe00707f) == 32'h00000033);  // ADD
    assign when_Decoder_l112_17 = ((decode_INSTRUCTION & 32'hfe00707f) == 32'h40000033);  // SUB
    assign when_Decoder_l112_18 = ((decode_INSTRUCTION & 32'hfe00707f) == 32'h00002033);  // SLT
    assign when_Decoder_l112_19 = ((decode_INSTRUCTION & 32'hfe00707f) == 32'h00003033);  // SLTU
    assign when_Decoder_l112_20 = ((decode_INSTRUCTION & 32'hfe00707f) == 32'h00004033);  // XOR
    assign when_Decoder_l112_21 = ((decode_INSTRUCTION & 32'hfe00707f) == 32'h00006033);  // OR
    assign when_Decoder_l112_22 = ((decode_INSTRUCTION & 32'hfe00707f) == 32'h00007033);  // AND
    assign when_Decoder_l112_23 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00000013);  // ADDI
    assign when_Decoder_l112_24 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00002013);  // SLTI
    assign when_Decoder_l112_25 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00003013);  // SLTIU
    assign when_Decoder_l112_26 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00004013);  // XORI
    assign when_Decoder_l112_27 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00006013);  // ORI
    assign when_Decoder_l112_28 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00007013);  // ANDI
    assign when_Decoder_l112_29 = ((decode_INSTRUCTION & 32'h0000007f) == 32'h00000037);  // LUI
    assign when_Decoder_l112_30 = ((decode_INSTRUCTION & 32'h0000007f) == 32'h00000017);  // AUIPC
    assign when_Decoder_l112_31 = ((decode_INSTRUCTION & 32'hfe00707f) == 32'h00001033);  // SLL
    assign when_Decoder_l112_32 = ((decode_INSTRUCTION & 32'hfe00707f) == 32'h00005033);  // SRL
    assign when_Decoder_l112_33 = ((decode_INSTRUCTION & 32'hfe00707f) == 32'h40005033);  // SRA
    assign when_Decoder_l112_34 = ((decode_INSTRUCTION & 32'hfe00707f) == 32'h00001013);  // SLLI
    assign when_Decoder_l112_35 = ((decode_INSTRUCTION & 32'hfe00707f) == 32'h00005013);  // SRLI
    assign when_Decoder_l112_36 = ((decode_INSTRUCTION & 32'hfe00707f) == 32'h40005013);  // SRAI
    assign when_Decoder_l112_37 = ((decode_INSTRUCTION & 32'h0000007f) == 32'h0000006f);  // JAL
    assign when_Decoder_l112_38 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00000067);  // JALR
    assign when_Decoder_l112_39 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00000063);  // BEQ
    assign when_Decoder_l112_40 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00001063);  // BNE
    assign when_Decoder_l112_41 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00004063);  // BLT
    assign when_Decoder_l112_42 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00005063);  // BGE
    assign when_Decoder_l112_43 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00006063);  // BLTU
    assign when_Decoder_l112_44 = ((decode_INSTRUCTION & 32'h0000707f) == 32'h00007063);  // BGEU

    //==========================================================================
    // Control Signal Decoding (Unoptimized, from SpinalHDL generation)
    //==========================================================================
    
    // SRC2_CTRL Decode
    always_comb begin
        decode_SRC2_CTRL = 2'bxx;  // Default undefined
        if (when_Decoder_l112_0)  decode_SRC2_CTRL = SRC2_IMI;   // LB
        if (when_Decoder_l112_1)  decode_SRC2_CTRL = SRC2_IMI;   // LH
        if (when_Decoder_l112_2)  decode_SRC2_CTRL = SRC2_IMI;   // LW
        if (when_Decoder_l112_3)  decode_SRC2_CTRL = SRC2_IMI;   // LBU
        if (when_Decoder_l112_4)  decode_SRC2_CTRL = SRC2_IMI;   // LHU
        if (when_Decoder_l112_5)  decode_SRC2_CTRL = SRC2_IMS;   // SB
        if (when_Decoder_l112_6)  decode_SRC2_CTRL = SRC2_IMS;   // SH
        if (when_Decoder_l112_7)  decode_SRC2_CTRL = SRC2_IMS;   // SW
        if (when_Decoder_l112_16) decode_SRC2_CTRL = SRC2_RS;    // ADD
        if (when_Decoder_l112_17) decode_SRC2_CTRL = SRC2_RS;    // SUB
        if (when_Decoder_l112_18) decode_SRC2_CTRL = SRC2_RS;    // SLT
        if (when_Decoder_l112_19) decode_SRC2_CTRL = SRC2_RS;    // SLTU
        if (when_Decoder_l112_20) decode_SRC2_CTRL = SRC2_RS;    // XOR
        if (when_Decoder_l112_21) decode_SRC2_CTRL = SRC2_RS;    // OR
        if (when_Decoder_l112_22) decode_SRC2_CTRL = SRC2_RS;    // AND
        if (when_Decoder_l112_23) decode_SRC2_CTRL = SRC2_IMI;   // ADDI ← KEY FIX!
        if (when_Decoder_l112_24) decode_SRC2_CTRL = SRC2_IMI;   // SLTI ← KEY FIX!
        if (when_Decoder_l112_25) decode_SRC2_CTRL = SRC2_IMI;   // SLTIU ← KEY FIX!
        if (when_Decoder_l112_26) decode_SRC2_CTRL = SRC2_IMI;   // XORI ← KEY FIX!
        if (when_Decoder_l112_27) decode_SRC2_CTRL = SRC2_IMI;   // ORI ← KEY FIX!
        if (when_Decoder_l112_28) decode_SRC2_CTRL = SRC2_IMI;   // ANDI ← KEY FIX!
        if (when_Decoder_l112_30) decode_SRC2_CTRL = SRC2_PC;    // AUIPC
        if (when_Decoder_l112_31) decode_SRC2_CTRL = SRC2_RS;    // SLL
        if (when_Decoder_l112_32) decode_SRC2_CTRL = SRC2_RS;    // SRL
        if (when_Decoder_l112_33) decode_SRC2_CTRL = SRC2_RS;    // SRA
        if (when_Decoder_l112_34) decode_SRC2_CTRL = SRC2_IMI;   // SLLI ← KEY FIX!
        if (when_Decoder_l112_35) decode_SRC2_CTRL = SRC2_IMI;   // SRLI ← KEY FIX!
        if (when_Decoder_l112_36) decode_SRC2_CTRL = SRC2_IMI;   // SRAI ← KEY FIX!
        if (when_Decoder_l112_37) decode_SRC2_CTRL = SRC2_PC;    // JAL
        if (when_Decoder_l112_38) decode_SRC2_CTRL = SRC2_PC;    // JALR
        if (when_Decoder_l112_39) decode_SRC2_CTRL = SRC2_RS;    // BEQ
        if (when_Decoder_l112_40) decode_SRC2_CTRL = SRC2_RS;    // BNE
        if (when_Decoder_l112_41) decode_SRC2_CTRL = SRC2_RS;    // BLT
        if (when_Decoder_l112_42) decode_SRC2_CTRL = SRC2_RS;    // BGE
        if (when_Decoder_l112_43) decode_SRC2_CTRL = SRC2_RS;    // BLTU
        if (when_Decoder_l112_44) decode_SRC2_CTRL = SRC2_RS;    // BGEU
    end

    // REGFILE_WRITE_VALID Decode
    always_comb begin
        decode_REGFILE_WRITE_VALID = 1'b0;  // Default no write
        if (when_Decoder_l112_0)  decode_REGFILE_WRITE_VALID = 1'b1;  // LB
        if (when_Decoder_l112_1)  decode_REGFILE_WRITE_VALID = 1'b1;  // LH
        if (when_Decoder_l112_2)  decode_REGFILE_WRITE_VALID = 1'b1;  // LW
        if (when_Decoder_l112_3)  decode_REGFILE_WRITE_VALID = 1'b1;  // LBU
        if (when_Decoder_l112_4)  decode_REGFILE_WRITE_VALID = 1'b1;  // LHU
        if (when_Decoder_l112_8)  decode_REGFILE_WRITE_VALID = 1'b1;  // CSRRW
        if (when_Decoder_l112_9)  decode_REGFILE_WRITE_VALID = 1'b1;  // CSRRS
        if (when_Decoder_l112_10) decode_REGFILE_WRITE_VALID = 1'b1;  // CSRRC
        if (when_Decoder_l112_11) decode_REGFILE_WRITE_VALID = 1'b1;  // CSRRWI
        if (when_Decoder_l112_12) decode_REGFILE_WRITE_VALID = 1'b1;  // CSRRSI
        if (when_Decoder_l112_13) decode_REGFILE_WRITE_VALID = 1'b1;  // CSRRCI
        if (when_Decoder_l112_16) decode_REGFILE_WRITE_VALID = 1'b1;  // ADD
        if (when_Decoder_l112_17) decode_REGFILE_WRITE_VALID = 1'b1;  // SUB
        if (when_Decoder_l112_18) decode_REGFILE_WRITE_VALID = 1'b1;  // SLT
        if (when_Decoder_l112_19) decode_REGFILE_WRITE_VALID = 1'b1;  // SLTU
        if (when_Decoder_l112_20) decode_REGFILE_WRITE_VALID = 1'b1;  // XOR
        if (when_Decoder_l112_21) decode_REGFILE_WRITE_VALID = 1'b1;  // OR
        if (when_Decoder_l112_22) decode_REGFILE_WRITE_VALID = 1'b1;  // AND
        if (when_Decoder_l112_23) decode_REGFILE_WRITE_VALID = 1'b1;  // ADDI ← KEY FIX!
        if (when_Decoder_l112_24) decode_REGFILE_WRITE_VALID = 1'b1;  // SLTI ← KEY FIX!
        if (when_Decoder_l112_25) decode_REGFILE_WRITE_VALID = 1'b1;  // SLTIU ← KEY FIX!
        if (when_Decoder_l112_26) decode_REGFILE_WRITE_VALID = 1'b1;  // XORI ← KEY FIX!
        if (when_Decoder_l112_27) decode_REGFILE_WRITE_VALID = 1'b1;  // ORI ← KEY FIX!
        if (when_Decoder_l112_28) decode_REGFILE_WRITE_VALID = 1'b1;  // ANDI ← KEY FIX!
        if (when_Decoder_l112_29) decode_REGFILE_WRITE_VALID = 1'b1;  // LUI
        if (when_Decoder_l112_30) decode_REGFILE_WRITE_VALID = 1'b1;  // AUIPC
        if (when_Decoder_l112_31) decode_REGFILE_WRITE_VALID = 1'b1;  // SLL
        if (when_Decoder_l112_32) decode_REGFILE_WRITE_VALID = 1'b1;  // SRL
        if (when_Decoder_l112_33) decode_REGFILE_WRITE_VALID = 1'b1;  // SRA
        if (when_Decoder_l112_34) decode_REGFILE_WRITE_VALID = 1'b1;  // SLLI ← KEY FIX!
        if (when_Decoder_l112_35) decode_REGFILE_WRITE_VALID = 1'b1;  // SRLI ← KEY FIX!
        if (when_Decoder_l112_36) decode_REGFILE_WRITE_VALID = 1'b1;  // SRAI ← KEY FIX!
        if (when_Decoder_l112_37) decode_REGFILE_WRITE_VALID = 1'b1;  // JAL
        if (when_Decoder_l112_38) decode_REGFILE_WRITE_VALID = 1'b1;  // JALR
    end

    // RS1_USE Decode
    always_comb begin
        decode_RS1_USE = 1'b0;
        if (when_Decoder_l112_0)  decode_RS1_USE = 1'b1;  // LB
        if (when_Decoder_l112_1)  decode_RS1_USE = 1'b1;  // LH
        if (when_Decoder_l112_2)  decode_RS1_USE = 1'b1;  // LW
        if (when_Decoder_l112_3)  decode_RS1_USE = 1'b1;  // LBU
        if (when_Decoder_l112_4)  decode_RS1_USE = 1'b1;  // LHU
        if (when_Decoder_l112_5)  decode_RS1_USE = 1'b1;  // SB
        if (when_Decoder_l112_6)  decode_RS1_USE = 1'b1;  // SH
        if (when_Decoder_l112_7)  decode_RS1_USE = 1'b1;  // SW
        if (when_Decoder_l112_8)  decode_RS1_USE = 1'b1;  // CSRRW
        if (when_Decoder_l112_9)  decode_RS1_USE = 1'b1;  // CSRRS
        if (when_Decoder_l112_10) decode_RS1_USE = 1'b1;  // CSRRC
        if (when_Decoder_l112_16) decode_RS1_USE = 1'b1;  // ADD
        if (when_Decoder_l112_17) decode_RS1_USE = 1'b1;  // SUB
        if (when_Decoder_l112_18) decode_RS1_USE = 1'b1;  // SLT
        if (when_Decoder_l112_19) decode_RS1_USE = 1'b1;  // SLTU
        if (when_Decoder_l112_20) decode_RS1_USE = 1'b1;  // XOR
        if (when_Decoder_l112_21) decode_RS1_USE = 1'b1;  // OR
        if (when_Decoder_l112_22) decode_RS1_USE = 1'b1;  // AND
        if (when_Decoder_l112_23) decode_RS1_USE = 1'b1;  // ADDI
        if (when_Decoder_l112_24) decode_RS1_USE = 1'b1;  // SLTI
        if (when_Decoder_l112_25) decode_RS1_USE = 1'b1;  // SLTIU
        if (when_Decoder_l112_26) decode_RS1_USE = 1'b1;  // XORI
        if (when_Decoder_l112_27) decode_RS1_USE = 1'b1;  // ORI
        if (when_Decoder_l112_28) decode_RS1_USE = 1'b1;  // ANDI
        if (when_Decoder_l112_31) decode_RS1_USE = 1'b1;  // SLL
        if (when_Decoder_l112_32) decode_RS1_USE = 1'b1;  // SRL
        if (when_Decoder_l112_33) decode_RS1_USE = 1'b1;  // SRA
        if (when_Decoder_l112_34) decode_RS1_USE = 1'b1;  // SLLI
        if (when_Decoder_l112_35) decode_RS1_USE = 1'b1;  // SRLI
        if (when_Decoder_l112_36) decode_RS1_USE = 1'b1;  // SRAI
        if (when_Decoder_l112_38) decode_RS1_USE = 1'b1;  // JALR
        if (when_Decoder_l112_39) decode_RS1_USE = 1'b1;  // BEQ
        if (when_Decoder_l112_40) decode_RS1_USE = 1'b1;  // BNE
        if (when_Decoder_l112_41) decode_RS1_USE = 1'b1;  // BLT
        if (when_Decoder_l112_42) decode_RS1_USE = 1'b1;  // BGE
        if (when_Decoder_l112_43) decode_RS1_USE = 1'b1;  // BLTU
        if (when_Decoder_l112_44) decode_RS1_USE = 1'b1;  // BGEU
    end

    // RS2_USE Decode
    always_comb begin
        decode_RS2_USE = 1'b0;
        if (when_Decoder_l112_5)  decode_RS2_USE = 1'b1;  // SB
        if (when_Decoder_l112_6)  decode_RS2_USE = 1'b1;  // SH
        if (when_Decoder_l112_7)  decode_RS2_USE = 1'b1;  // SW
        if (when_Decoder_l112_16) decode_RS2_USE = 1'b1;  // ADD
        if (when_Decoder_l112_17) decode_RS2_USE = 1'b1;  // SUB
        if (when_Decoder_l112_18) decode_RS2_USE = 1'b1;  // SLT
        if (when_Decoder_l112_19) decode_RS2_USE = 1'b1;  // SLTU
        if (when_Decoder_l112_20) decode_RS2_USE = 1'b1;  // XOR
        if (when_Decoder_l112_21) decode_RS2_USE = 1'b1;  // OR
        if (when_Decoder_l112_22) decode_RS2_USE = 1'b1;  // AND
        if (when_Decoder_l112_31) decode_RS2_USE = 1'b1;  // SLL
        if (when_Decoder_l112_32) decode_RS2_USE = 1'b1;  // SRL
        if (when_Decoder_l112_33) decode_RS2_USE = 1'b1;  // SRA
        if (when_Decoder_l112_39) decode_RS2_USE = 1'b1;  // BEQ
        if (when_Decoder_l112_40) decode_RS2_USE = 1'b1;  // BNE
        if (when_Decoder_l112_41) decode_RS2_USE = 1'b1;  // BLT
        if (when_Decoder_l112_42) decode_RS2_USE = 1'b1;  // BGE
        if (when_Decoder_l112_43) decode_RS2_USE = 1'b1;  // BLTU
        if (when_Decoder_l112_44) decode_RS2_USE = 1'b1;  // BGEU
    end

    //==========================================================================
    // SRC1_CTRL Decode
    //==========================================================================
    always_comb begin
        decode_SRC1_CTRL = 2'b00;  // Default: RS (register source)
        if (when_Decoder_l112_29) decode_SRC1_CTRL = 2'b01;  // LUI: IMU (upper immediate)
        if (when_Decoder_l112_30) decode_SRC1_CTRL = 2'b10;  // AUIPC: PC_INCREMENT
        if (when_Decoder_l112_37) decode_SRC1_CTRL = 2'b10;  // JAL: PC_INCREMENT
        if (when_Decoder_l112_38) decode_SRC1_CTRL = 2'b10;  // JALR: PC_INCREMENT
    end

    //==========================================================================
    // ALU_CTRL Decode
    //==========================================================================
    always_comb begin
        decode_ALU_CTRL = 2'b00;  // Default: ADD_SUB
        if (when_Decoder_l112_16) decode_ALU_CTRL = 2'b00;  // ADD: ADD_SUB
        if (when_Decoder_l112_17) decode_ALU_CTRL = 2'b00;  // SUB: ADD_SUB
        if (when_Decoder_l112_18) decode_ALU_CTRL = 2'b01;  // SLT: SLT_SLTU
        if (when_Decoder_l112_19) decode_ALU_CTRL = 2'b01;  // SLTU: SLT_SLTU
        if (when_Decoder_l112_20) decode_ALU_CTRL = 2'b10;  // XOR: BITWISE
        if (when_Decoder_l112_21) decode_ALU_CTRL = 2'b10;  // OR: BITWISE
        if (when_Decoder_l112_22) decode_ALU_CTRL = 2'b10;  // AND: BITWISE
        if (when_Decoder_l112_23) decode_ALU_CTRL = 2'b00;  // ADDI: ADD_SUB
        if (when_Decoder_l112_24) decode_ALU_CTRL = 2'b01;  // SLTI: SLT_SLTU
        if (when_Decoder_l112_25) decode_ALU_CTRL = 2'b01;  // SLTIU: SLT_SLTU
        if (when_Decoder_l112_26) decode_ALU_CTRL = 2'b10;  // XORI: BITWISE
        if (when_Decoder_l112_27) decode_ALU_CTRL = 2'b10;  // ORI: BITWISE
        if (when_Decoder_l112_28) decode_ALU_CTRL = 2'b10;  // ANDI: BITWISE
        if (when_Decoder_l112_29) decode_ALU_CTRL = 2'b00;  // LUI: ADD_SUB
        if (when_Decoder_l112_30) decode_ALU_CTRL = 2'b00;  // AUIPC: ADD_SUB
        if (when_Decoder_l112_31) decode_ALU_CTRL = 2'b00;  // SLL: ADD_SUB
        if (when_Decoder_l112_32) decode_ALU_CTRL = 2'b00;  // SRL: ADD_SUB
        if (when_Decoder_l112_33) decode_ALU_CTRL = 2'b00;  // SRA: ADD_SUB
        if (when_Decoder_l112_34) decode_ALU_CTRL = 2'b00;  // SLLI: ADD_SUB
        if (when_Decoder_l112_35) decode_ALU_CTRL = 2'b00;  // SRLI: ADD_SUB
        if (when_Decoder_l112_36) decode_ALU_CTRL = 2'b00;  // SRAI: ADD_SUB
        if (when_Decoder_l112_37) decode_ALU_CTRL = 2'b00;  // JAL: ADD_SUB
        if (when_Decoder_l112_38) decode_ALU_CTRL = 2'b00;  // JALR: ADD_SUB
    end

    //==========================================================================
    // ALU_BITWISE_CTRL Decode
    //==========================================================================
    always_comb begin
        decode_ALU_BITWISE_CTRL = 2'b00;  // Default: XOR
        if (when_Decoder_l112_20) decode_ALU_BITWISE_CTRL = 2'b00;  // XOR: XOR
        if (when_Decoder_l112_21) decode_ALU_BITWISE_CTRL = 2'b01;  // OR: OR
        if (when_Decoder_l112_22) decode_ALU_BITWISE_CTRL = 2'b10;  // AND: AND
        if (when_Decoder_l112_26) decode_ALU_BITWISE_CTRL = 2'b00;  // XORI: XOR
        if (when_Decoder_l112_27) decode_ALU_BITWISE_CTRL = 2'b01;  // ORI: OR
        if (when_Decoder_l112_28) decode_ALU_BITWISE_CTRL = 2'b10;  // ANDI: AND
    end

    //==========================================================================
    // SHIFT_CTRL Decode
    //==========================================================================
    always_comb begin
        decode_SHIFT_CTRL = 2'b00;  // Default: DISABLE
        if (when_Decoder_l112_31) decode_SHIFT_CTRL = 2'b01;  // SLL: SLL
        if (when_Decoder_l112_32) decode_SHIFT_CTRL = 2'b10;  // SRL: SRL
        if (when_Decoder_l112_33) decode_SHIFT_CTRL = 2'b11;  // SRA: SRA
        if (when_Decoder_l112_34) decode_SHIFT_CTRL = 2'b01;  // SLLI: SLL
        if (when_Decoder_l112_35) decode_SHIFT_CTRL = 2'b10;  // SRLI: SRL
        if (when_Decoder_l112_36) decode_SHIFT_CTRL = 2'b11;  // SRAI: SRA
    end

    //==========================================================================
    // BRANCH_CTRL Decode
    //==========================================================================
    always_comb begin
        decode_BRANCH_CTRL = 2'b00;  // Default: INC (no branch)
        if (when_Decoder_l112_37) decode_BRANCH_CTRL = 2'b10;  // JAL: JAL
        if (when_Decoder_l112_38) decode_BRANCH_CTRL = 2'b11;  // JALR: JALR
        if (when_Decoder_l112_39) decode_BRANCH_CTRL = 2'b01;  // BEQ: B (branch)
        if (when_Decoder_l112_40) decode_BRANCH_CTRL = 2'b01;  // BNE: B
        if (when_Decoder_l112_41) decode_BRANCH_CTRL = 2'b01;  // BLT: B
        if (when_Decoder_l112_42) decode_BRANCH_CTRL = 2'b01;  // BGE: B
        if (when_Decoder_l112_43) decode_BRANCH_CTRL = 2'b01;  // BLTU: B
        if (when_Decoder_l112_44) decode_BRANCH_CTRL = 2'b01;  // BGEU: B
    end

    //==========================================================================
    // SRC_LESS_UNSIGNED Decode
    //==========================================================================
    always_comb begin
        decode_SRC_LESS_UNSIGNED = 1'b0;  // Default: signed comparison
        if (when_Decoder_l112_19) decode_SRC_LESS_UNSIGNED = 1'b1;  // SLTU: unsigned
        if (when_Decoder_l112_25) decode_SRC_LESS_UNSIGNED = 1'b1;  // SLTIU: unsigned
        if (when_Decoder_l112_43) decode_SRC_LESS_UNSIGNED = 1'b1;  // BLTU: unsigned
        if (when_Decoder_l112_44) decode_SRC_LESS_UNSIGNED = 1'b1;  // BGEU: unsigned
    end

    //==========================================================================
    // SRC_USE_SUB_LESS Decode
    //==========================================================================
    always_comb begin
        decode_SRC_USE_SUB_LESS = 1'b0;  // Default: no subtraction/comparison
        if (when_Decoder_l112_17) decode_SRC_USE_SUB_LESS = 1'b1;  // SUB
        if (when_Decoder_l112_18) decode_SRC_USE_SUB_LESS = 1'b1;  // SLT
        if (when_Decoder_l112_19) decode_SRC_USE_SUB_LESS = 1'b1;  // SLTU
        if (when_Decoder_l112_24) decode_SRC_USE_SUB_LESS = 1'b1;  // SLTI
        if (when_Decoder_l112_25) decode_SRC_USE_SUB_LESS = 1'b1;  // SLTIU
        if (when_Decoder_l112_39) decode_SRC_USE_SUB_LESS = 1'b1;  // BEQ
        if (when_Decoder_l112_40) decode_SRC_USE_SUB_LESS = 1'b1;  // BNE
        if (when_Decoder_l112_41) decode_SRC_USE_SUB_LESS = 1'b1;  // BLT
        if (when_Decoder_l112_42) decode_SRC_USE_SUB_LESS = 1'b1;  // BGE
        if (when_Decoder_l112_43) decode_SRC_USE_SUB_LESS = 1'b1;  // BLTU
        if (when_Decoder_l112_44) decode_SRC_USE_SUB_LESS = 1'b1;  // BGEU
    end

    //==========================================================================
    // SRC_ADD_ZERO Decode
    //==========================================================================
    always_comb begin
        decode_SRC_ADD_ZERO = 1'b0;  // Default: use SRC2
        if (when_Decoder_l112_29) decode_SRC_ADD_ZERO = 1'b1;  // LUI: add zero (pass immediate)
        if (when_Decoder_l112_31) decode_SRC_ADD_ZERO = 1'b1;  // SLL: shifter mode
        if (when_Decoder_l112_32) decode_SRC_ADD_ZERO = 1'b1;  // SRL: shifter mode
        if (when_Decoder_l112_33) decode_SRC_ADD_ZERO = 1'b1;  // SRA: shifter mode
        if (when_Decoder_l112_34) decode_SRC_ADD_ZERO = 1'b1;  // SLLI: shifter mode
        if (when_Decoder_l112_35) decode_SRC_ADD_ZERO = 1'b1;  // SRLI: shifter mode
        if (when_Decoder_l112_36) decode_SRC_ADD_ZERO = 1'b1;  // SRAI: shifter mode
    end

    //==========================================================================
    // BYPASSABLE_EXECUTE_STAGE Decode
    //==========================================================================
    always_comb begin
        decode_BYPASSABLE_EXECUTE_STAGE = 1'b0;  // Default: not bypassable (load instructions)
        // All non-load instructions can bypass Execute stage
        if (when_Decoder_l112_16) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // ADD
        if (when_Decoder_l112_17) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // SUB
        if (when_Decoder_l112_18) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // SLT
        if (when_Decoder_l112_19) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // SLTU
        if (when_Decoder_l112_20) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // XOR
        if (when_Decoder_l112_21) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // OR
        if (when_Decoder_l112_22) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // AND
        if (when_Decoder_l112_23) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // ADDI
        if (when_Decoder_l112_24) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // SLTI
        if (when_Decoder_l112_25) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // SLTIU
        if (when_Decoder_l112_26) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // XORI
        if (when_Decoder_l112_27) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // ORI
        if (when_Decoder_l112_28) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // ANDI
        if (when_Decoder_l112_29) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // LUI
        if (when_Decoder_l112_30) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // AUIPC
        if (when_Decoder_l112_31) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // SLL
        if (when_Decoder_l112_32) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // SRL
        if (when_Decoder_l112_33) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // SRA
        if (when_Decoder_l112_34) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // SLLI
        if (when_Decoder_l112_35) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // SRLI
        if (when_Decoder_l112_36) decode_BYPASSABLE_EXECUTE_STAGE = 1'b1;  // SRAI
    end

    //==========================================================================
    // BYPASSABLE_MEMORY_STAGE Decode
    //==========================================================================
    always_comb begin
        decode_BYPASSABLE_MEMORY_STAGE = 1'b0;  // Default: not bypassable
        // ALU and shift instructions can bypass Memory stage
        if (when_Decoder_l112_16) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // ADD
        if (when_Decoder_l112_17) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // SUB
        if (when_Decoder_l112_18) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // SLT
        if (when_Decoder_l112_19) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // SLTU
        if (when_Decoder_l112_20) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // XOR
        if (when_Decoder_l112_21) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // OR
        if (when_Decoder_l112_22) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // AND
        if (when_Decoder_l112_23) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // ADDI
        if (when_Decoder_l112_24) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // SLTI
        if (when_Decoder_l112_25) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // SLTIU
        if (when_Decoder_l112_26) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // XORI
        if (when_Decoder_l112_27) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // ORI
        if (when_Decoder_l112_28) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // ANDI
        if (when_Decoder_l112_29) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // LUI
        if (when_Decoder_l112_30) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // AUIPC
        if (when_Decoder_l112_31) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // SLL
        if (when_Decoder_l112_32) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // SRL
        if (when_Decoder_l112_33) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // SRA
        if (when_Decoder_l112_34) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // SLLI
        if (when_Decoder_l112_35) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // SRLI
        if (when_Decoder_l112_36) decode_BYPASSABLE_MEMORY_STAGE = 1'b1;  // SRAI
    end

    //==========================================================================
    // Simple Control Signals (already implemented)
    //==========================================================================
    assign decode_MEMORY_ENABLE = when_Decoder_l112_0 | when_Decoder_l112_1 | when_Decoder_l112_2 | 
                                   when_Decoder_l112_3 | when_Decoder_l112_4 | when_Decoder_l112_5 | 
                                   when_Decoder_l112_6 | when_Decoder_l112_7;
    assign decode_MEMORY_STORE = when_Decoder_l112_5 | when_Decoder_l112_6 | when_Decoder_l112_7;
    assign decode_IS_CSR = when_Decoder_l112_8 | when_Decoder_l112_9 | when_Decoder_l112_10 | 
                           when_Decoder_l112_11 | when_Decoder_l112_12 | when_Decoder_l112_13;
    assign decode_ENV_CTRL = when_Decoder_l112_14 | when_Decoder_l112_15;  // MRET/SRET

endmodule
