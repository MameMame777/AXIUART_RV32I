`timescale 1ns/1ps
//==============================================================================
// VexRiscv BranchPlugin Module
//
// Branch resolution and control flow:
// - Branch condition evaluation (BEQ, BNE, BLT, BGE, BLTU, BGEU)
// - Jump target calculation (JAL, JALR)
// - Branch misalignment detection
// - Branch resolution interface
//
// Extracted from VexRiscv_GenSmallAndProductive.v
// Original lines: ~708-730, 2880-3000 (distributed across file)
//==============================================================================

module vexriscv_branch
    import vexriscv_pkg::*;
(
    input  logic        clk,
    input  logic        reset,
    
    // Execute stage inputs
    input  logic        execute_arbitration_isValid,
    input  logic [31:0] execute_PC,
    input  logic [31:0] execute_INSTRUCTION,
    input  logic [1:0]  execute_BRANCH_CTRL,
    input  logic        execute_PREDICTION_HAD_BRANCHED1,
    input  logic [31:0] execute_RS1,
    input  logic [31:0] execute_SRC1,
    input  logic [31:0] execute_SRC2,
    input  logic        execute_SRC_LESS,
    
    // Branch outputs
    output logic        BranchPlugin_jumpInterface_valid,
    output logic [31:0] BranchPlugin_jumpInterface_payload,
    output logic        execute_BRANCH_DO,
    output logic [31:0] execute_BRANCH_CALC
);

    //==========================================================================
    // Internal Signals
    //==========================================================================
    
    logic        execute_BranchPlugin_eq;
    logic        execute_BRANCH_COND_RESULT;
    logic        execute_BranchPlugin_missAlignedTarget;
    logic [31:0] execute_BranchPlugin_branch_src1;
    logic [31:0] execute_BranchPlugin_branch_src2;
    logic [31:0] execute_BranchPlugin_branchAdder;
    
    // Immediate extraction signals
    logic        imm_j_sign;
    logic [19:0] imm_j_bits;
    logic        imm_i_sign;
    logic [10:0] imm_i_bits;
    logic        imm_b_sign;
    logic [18:0] imm_b_bits;
    
    //==========================================================================
    // Branch Condition Evaluation
    //==========================================================================
    
    assign execute_BranchPlugin_eq = (execute_SRC1 == execute_SRC2);
    
    always_comb begin
        case (execute_INSTRUCTION[14:12])
            3'b000: begin // BEQ
                execute_BRANCH_COND_RESULT = execute_BranchPlugin_eq;
            end
            3'b001: begin // BNE
                execute_BRANCH_COND_RESULT = (!execute_BranchPlugin_eq);
            end
            3'b101: begin // BGE
                execute_BRANCH_COND_RESULT = (!execute_SRC_LESS);
            end
            3'b111: begin // BGEU
                execute_BRANCH_COND_RESULT = (!execute_SRC_LESS);
            end
            default: begin // BLT, BLTU
                execute_BRANCH_COND_RESULT = execute_SRC_LESS;
            end
        endcase
    end
    
    //==========================================================================
    // Branch Source Selection
    //==========================================================================
    
    always_comb begin
        case (execute_BRANCH_CTRL)
            2'b00: begin // No branch
                execute_BranchPlugin_branch_src1 = execute_PC;
                execute_BranchPlugin_branch_src2 = 32'h4;
            end
            2'b01: begin // Conditional branch (B-type)
                execute_BranchPlugin_branch_src1 = execute_PC;
                // Extract B-immediate: [31:25|11:7] -> [12|10:5|4:1|11]
                imm_b_sign = execute_INSTRUCTION[31];
                imm_b_bits = {execute_INSTRUCTION[7], execute_INSTRUCTION[30:25], execute_INSTRUCTION[11:8]};
                execute_BranchPlugin_branch_src2 = {{19{imm_b_sign}}, imm_b_bits, 1'b0};
            end
            2'b10: begin // JAL (J-type)
                execute_BranchPlugin_branch_src1 = execute_PC;
                // Extract J-immediate: [31:12] -> [20|10:1|11|19:12]
                imm_j_sign = execute_INSTRUCTION[31];
                imm_j_bits = {execute_INSTRUCTION[19:12], execute_INSTRUCTION[20], execute_INSTRUCTION[30:21]};
                execute_BranchPlugin_branch_src2 = {{11{imm_j_sign}}, imm_j_bits, 1'b0};
            end
            2'b11: begin // JALR (I-type)
                execute_BranchPlugin_branch_src1 = execute_RS1;
                // Extract I-immediate: [31:20]
                imm_i_sign = execute_INSTRUCTION[31];
                imm_i_bits = execute_INSTRUCTION[30:20];
                execute_BranchPlugin_branch_src2 = {{20{imm_i_sign}}, imm_i_bits, 1'b0};
            end
        endcase
    end
    
    //==========================================================================
    // Branch Target Calculation
    //==========================================================================
    
    assign execute_BranchPlugin_branchAdder = execute_BranchPlugin_branch_src1 + execute_BranchPlugin_branch_src2;
    assign execute_BRANCH_CALC = {execute_BranchPlugin_branchAdder[31:1], 1'b0};
    
    //==========================================================================
    // Misalignment Detection
    //==========================================================================
    
    assign execute_BranchPlugin_missAlignedTarget = (execute_BranchPlugin_branchAdder[1:0] != 2'b00);
    
    //==========================================================================
    // Branch Decision
    //==========================================================================
    
    always_comb begin
        execute_BRANCH_DO = 1'b0;
        
        case (execute_BRANCH_CTRL)
            2'b01: begin // Conditional branch
                if (execute_PREDICTION_HAD_BRANCHED1 != execute_BRANCH_COND_RESULT) begin
                    execute_BRANCH_DO = 1'b1;
                end
            end
            2'b10, 2'b11: begin // JAL, JALR
                execute_BRANCH_DO = 1'b1;
            end
            default: begin
                execute_BRANCH_DO = 1'b0;
            end
        endcase
        
        if (execute_BranchPlugin_missAlignedTarget) begin
            execute_BRANCH_DO = 1'b1;
        end
    end
    
    //==========================================================================
    // Jump Interface
    //==========================================================================
    
    assign BranchPlugin_jumpInterface_valid = (execute_arbitration_isValid && execute_BRANCH_DO);
    assign BranchPlugin_jumpInterface_payload = execute_BRANCH_CALC;

endmodule : vexriscv_branch
