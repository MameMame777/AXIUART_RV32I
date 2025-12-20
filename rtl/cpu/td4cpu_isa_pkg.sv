`timescale 1ns / 1ps

// TD4CPU ISA Package
//
// AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
// Generated from: td4cpu_isa.json
// Generation time: 2025-12-20T22:54:11.474281
//
// To regenerate:
//     python software/axiuart_driver/tools/gen_cpu_isa.py --in td4cpu_isa.json

package td4cpu_isa_pkg;

    // Opcodes
    localparam logic [3:0] OP_R_ALU = 4'h0;
    localparam logic [3:0] OP_LDI = 4'h1;
    localparam logic [3:0] OP_ADDI = 4'h2;
    localparam logic [3:0] OP_LD = 4'h3;
    localparam logic [3:0] OP_ST = 4'h4;
    localparam logic [3:0] OP_BR = 4'h5;
    localparam logic [3:0] OP_SYS = 4'h6;
    localparam logic [3:0] OP_STACK = 4'h7;
    localparam logic [3:0] OP_JMP16 = 4'hA;
    localparam logic [3:0] OP_CALL16 = 4'hB;

    // R-format funct codes
    localparam logic [5:0] FUNCT_ADD = 6'h00;
    localparam logic [5:0] FUNCT_SUB = 6'h01;
    localparam logic [5:0] FUNCT_AND = 6'h02;
    localparam logic [5:0] FUNCT_OR = 6'h03;
    localparam logic [5:0] FUNCT_XOR = 6'h04;
    localparam logic [5:0] FUNCT_CMP = 6'h05;
    localparam logic [5:0] FUNCT_SHL1 = 6'h06;
    localparam logic [5:0] FUNCT_SHR1 = 6'h07;
    localparam logic [5:0] FUNCT_MOV = 6'h08;

    // Branch conditions
    localparam logic [2:0] COND_AL = 3'd0;
    localparam logic [2:0] COND_Z = 3'd1;
    localparam logic [2:0] COND_NZ = 3'd2;
    localparam logic [2:0] COND_C = 3'd3;
    localparam logic [2:0] COND_NC = 3'd4;
    localparam logic [2:0] COND_N = 3'd5;
    localparam logic [2:0] COND_NN = 3'd6;

    // SYS sub-ops
    localparam logic [2:0] SYSOP_RET = 3'd0;
    localparam logic [2:0] SYSOP_BRK = 3'd1;

endpackage : td4cpu_isa_pkg
