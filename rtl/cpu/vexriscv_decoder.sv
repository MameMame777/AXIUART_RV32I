`timescale 1ns/1ps
//==============================================================================
// VexRiscv Instruction Decoder ROM
//
// Extracted from VexRiscv_GenSmallAndProductive.v (lines 960-2660)
// Original decoder ROM implements pattern matching for RV32I instruction set
//
// This module decodes 32-bit RISC-V instructions into control signals used
// throughout the CPU pipeline. The decoder uses a hierarchical pattern matching
// structure with 80+ intermediate signals organized into 4 levels.
//
// Main output: 25-bit packed control vector (_zz_decode_SRC_LESS_UNSIGNED)
//==============================================================================

module vexriscv_decoder
    import vexriscv_pkg::*;
(
    input  logic [31:0] decode_INSTRUCTION,
    
    // Packed ROM output
    output logic [24:0] decoder_output,
    
    // Individual control signals (unpacked from ROM output)
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
    // Intermediate Pattern Matching Signals
    //==========================================================================
    
    // Level 1 - Basic patterns
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_1;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_2;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_3;
    logic        _zz__zz_decode_SRC_LESS_UNSIGNED_4;
    logic [1:0]  _zz__zz_decode_SRC_LESS_UNSIGNED_5;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_6;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_7;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_9;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_10;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_11;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_12;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_14;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_15;
    
    // Level 2 - Combined patterns
    logic        _zz__zz_decode_SRC_LESS_UNSIGNED_8;
    logic        _zz__zz_decode_SRC_LESS_UNSIGNED_13;
    logic [18:0] _zz__zz_decode_SRC_LESS_UNSIGNED_16;
    logic        _zz__zz_decode_SRC_LESS_UNSIGNED_17;
    logic [1:0]  _zz__zz_decode_SRC_LESS_UNSIGNED_18;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_19;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_20;
    logic        _zz__zz_decode_SRC_LESS_UNSIGNED_21;
    logic        _zz__zz_decode_SRC_LESS_UNSIGNED_26;
    logic [14:0] _zz__zz_decode_SRC_LESS_UNSIGNED_27;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_22;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_23;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_24;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_25;
    
    // Level 3 - Higher order
    logic        _zz__zz_decode_SRC_LESS_UNSIGNED_28;
    logic [1:0]  _zz__zz_decode_SRC_LESS_UNSIGNED_29;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_30;
    logic [31:0] _zz__zz_decode_SRC_LESS_UNSIGNED_31;
    logic        _zz__zz_decode_SRC_LESS_UNSIGNED_32;
    
    // Top-level
    logic        _zz_decode_SRC_LESS_UNSIGNED_2;
    logic        _zz_decode_SRC_LESS_UNSIGNED_4;
    logic        _zz_decode_SRC_LESS_UNSIGNED_5;
    logic        _zz_decode_SRC_LESS_UNSIGNED_6;
    logic [24:0] _zz_decode_SRC_LESS_UNSIGNED;
    logic        when_RegFilePlugin_l63;
    
    //==========================================================================
    // Pattern Matching Logic (Original VexRiscv lines 965-1020)
    //==========================================================================
    
    assign _zz__zz_decode_SRC_LESS_UNSIGNED = (decode_INSTRUCTION & 32'h0000001c);
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_1 = 32'h00000004;
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_2 = (decode_INSTRUCTION & 32'h00000058);
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_3 = 32'h00000040;
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_4 = ((decode_INSTRUCTION & 32'h00007054) == 32'h00005010);
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_6 = 32'h40003054;
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_7 = 32'h00007054;
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_5 = {((decode_INSTRUCTION & _zz__zz_decode_SRC_LESS_UNSIGNED_6) == 32'h40001010),((decode_INSTRUCTION & _zz__zz_decode_SRC_LESS_UNSIGNED_7) == 32'h00001010)};
    
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_9 = (decode_INSTRUCTION & 32'h00000064);
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_10 = 32'h00000024;
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_11 = (decode_INSTRUCTION & 32'h00003054);
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_12 = 32'h00001010;
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_14 = (decode_INSTRUCTION & 32'h00001000);
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_15 = 32'h00001000;
    
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_8 = (|{(_zz__zz_decode_SRC_LESS_UNSIGNED_9 == _zz__zz_decode_SRC_LESS_UNSIGNED_10),(_zz__zz_decode_SRC_LESS_UNSIGNED_11 == _zz__zz_decode_SRC_LESS_UNSIGNED_12)});
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_13 = (|(_zz__zz_decode_SRC_LESS_UNSIGNED_14 == _zz__zz_decode_SRC_LESS_UNSIGNED_15));
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_17 = ((decode_INSTRUCTION & 32'h00003000) == 32'h00002000);
    
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_19 = 32'h00002010;
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_20 = 32'h00005000;
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_18 = {((decode_INSTRUCTION & _zz__zz_decode_SRC_LESS_UNSIGNED_19) == 32'h00002000),((decode_INSTRUCTION & _zz__zz_decode_SRC_LESS_UNSIGNED_20) == 32'h00001000)};
    
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_22 = (decode_INSTRUCTION & 32'h00006004);
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_23 = 32'h00006000;
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_24 = (decode_INSTRUCTION & 32'h00005004);
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_25 = 32'h00004000;
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_21 = (|{(_zz__zz_decode_SRC_LESS_UNSIGNED_22 == _zz__zz_decode_SRC_LESS_UNSIGNED_23),(_zz__zz_decode_SRC_LESS_UNSIGNED_24 == _zz__zz_decode_SRC_LESS_UNSIGNED_25)});
    
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_26 = (|_zz_decode_SRC_LESS_UNSIGNED_2);
    
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_28 = ((decode_INSTRUCTION & 32'h00003050) == 32'h00000050);
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_30 = 32'h00001050;
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_31 = 32'h00002050;
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_29 = {((decode_INSTRUCTION & _zz__zz_decode_SRC_LESS_UNSIGNED_30) == 32'h00001050),((decode_INSTRUCTION & _zz__zz_decode_SRC_LESS_UNSIGNED_31) == 32'h00002050)};
    
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_32 = (|((decode_INSTRUCTION & 32'h00000034) == 32'h00000020));
    
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_27 = {(|_zz__zz_decode_SRC_LESS_UNSIGNED_28),{(|_zz__zz_decode_SRC_LESS_UNSIGNED_29),{_zz__zz_decode_SRC_LESS_UNSIGNED_32,14'b00000000000000}}};
    
    assign _zz__zz_decode_SRC_LESS_UNSIGNED_16 = {(|_zz__zz_decode_SRC_LESS_UNSIGNED_17),{(|_zz__zz_decode_SRC_LESS_UNSIGNED_18),{_zz__zz_decode_SRC_LESS_UNSIGNED_21,{_zz__zz_decode_SRC_LESS_UNSIGNED_26,_zz__zz_decode_SRC_LESS_UNSIGNED_27}}}};
    
    //==========================================================================
    // Main Decoder ROM Output (Original VexRiscv line 2623)
    //==========================================================================
    
    assign _zz_decode_SRC_LESS_UNSIGNED_2 = ((decode_INSTRUCTION & 32'h00000058) == 32'h00000040);
    assign _zz_decode_SRC_LESS_UNSIGNED_4 = ((decode_INSTRUCTION & 32'h00000004) == 32'h00000004);
    assign _zz_decode_SRC_LESS_UNSIGNED_5 = ((decode_INSTRUCTION & 32'h00000050) == 32'h00000010);
    assign _zz_decode_SRC_LESS_UNSIGNED_6 = ((decode_INSTRUCTION & 32'h00000048) == 32'h00000048);
    
    assign _zz_decode_SRC_LESS_UNSIGNED = {(|{_zz_decode_SRC_LESS_UNSIGNED_6,(_zz__zz_decode_SRC_LESS_UNSIGNED == _zz__zz_decode_SRC_LESS_UNSIGNED_1)}),{(|(_zz__zz_decode_SRC_LESS_UNSIGNED_2 == _zz__zz_decode_SRC_LESS_UNSIGNED_3)),{(|_zz_decode_SRC_LESS_UNSIGNED_4),{(|_zz_decode_SRC_LESS_UNSIGNED_5),{_zz__zz_decode_SRC_LESS_UNSIGNED_8,{_zz__zz_decode_SRC_LESS_UNSIGNED_13,_zz__zz_decode_SRC_LESS_UNSIGNED_16}}}}}};
    
    //==========================================================================
    // Output Assignments (Original VexRiscv lines 2625-2643)
    //==========================================================================
    
    assign decoder_output = _zz_decode_SRC_LESS_UNSIGNED;
    
    // Unpack control signals from ROM output
    assign decode_SRC1_CTRL                = _zz_decode_SRC_LESS_UNSIGNED[1:0];
    assign decode_SRC_USE_SUB_LESS         = _zz_decode_SRC_LESS_UNSIGNED[2];
    assign decode_MEMORY_ENABLE            = _zz_decode_SRC_LESS_UNSIGNED[3];
    assign decode_RS1_USE                  = _zz_decode_SRC_LESS_UNSIGNED[4];
    assign decode_SRC2_CTRL                = _zz_decode_SRC_LESS_UNSIGNED[6:5];
    assign decode_BYPASSABLE_EXECUTE_STAGE = _zz_decode_SRC_LESS_UNSIGNED[8];
    assign decode_BYPASSABLE_MEMORY_STAGE  = _zz_decode_SRC_LESS_UNSIGNED[9];
    assign decode_MEMORY_STORE             = _zz_decode_SRC_LESS_UNSIGNED[10];
    assign decode_RS2_USE                  = _zz_decode_SRC_LESS_UNSIGNED[12];
    assign decode_IS_CSR                   = _zz_decode_SRC_LESS_UNSIGNED[13];
    assign decode_ENV_CTRL                 = _zz_decode_SRC_LESS_UNSIGNED[14];
    assign decode_ALU_CTRL                 = _zz_decode_SRC_LESS_UNSIGNED[16:15];
    assign decode_SRC_LESS_UNSIGNED        = _zz_decode_SRC_LESS_UNSIGNED[17];
    assign decode_ALU_BITWISE_CTRL         = _zz_decode_SRC_LESS_UNSIGNED[19:18];
    assign decode_SRC_ADD_ZERO             = _zz_decode_SRC_LESS_UNSIGNED[20];
    assign decode_SHIFT_CTRL               = _zz_decode_SRC_LESS_UNSIGNED[22:21];
    assign decode_BRANCH_CTRL              = _zz_decode_SRC_LESS_UNSIGNED[24:23];
    
    // REGFILE_WRITE_VALID with rd==0 override (Original VexRiscv lines 1836-1839, 2643)
    assign when_RegFilePlugin_l63 = (decode_INSTRUCTION[11:7] == 5'h0);
    assign decode_REGFILE_WRITE_VALID = when_RegFilePlugin_l63 ? 1'b0 : _zz_decode_SRC_LESS_UNSIGNED[7];

endmodule : vexriscv_decoder
