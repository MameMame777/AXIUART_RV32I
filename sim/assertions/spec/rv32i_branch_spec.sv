`timescale 1ns / 1ps

//==============================================================================
// RV32I Branch Operation Assertions
//==============================================================================
// Validates branch condition evaluation, operand forwarding, and decision logic
// for BEQ, BNE, BLT, BGE, BLTU, BGEU instructions.
//==============================================================================

module rv32i_branch_spec
    import rv32i_isa_pkg::*;
    import rv32i_pipeline_pkg::*;
(
    input logic         clk,
    input logic         rst,
    input logic         soft_reset_active,
    
    // ID/EX pipeline register
    input logic         id_ex_valid,
    input logic [31:0]  id_ex_insn,
    input logic [31:0]  id_ex_pc,
    input logic [4:0]   id_ex_rs1_addr,
    input logic [4:0]   id_ex_rs2_addr,
    input logic [1:0]   id_ex_forward_rs1,
    input logic [1:0]   id_ex_forward_rs2,
    input decode_ctrl_t id_ex_ctrl,
    
    // EX stage forwarded operands
    input logic [31:0]  ex_rs1_forwarded,
    input logic [31:0]  ex_rs2_forwarded,
    
    // Branch decision outputs
    input logic         ex_branch_taken,
    input logic [31:0]  ex_branch_target,
    
    // Branch condition signals
    input logic         branch_eq,
    input logic         branch_ne,
    input logic         branch_lt,
    input logic         branch_ge,
    input logic         branch_ltu,
    input logic         branch_geu
);

    //==========================================================================
    // Helper: Decode Branch Type
    //==========================================================================
    logic is_beq, is_bne, is_blt, is_bge, is_bltu, is_bgeu;
    
    assign is_beq  = id_ex_ctrl.is_branch && (id_ex_ctrl.branch_op == BR_EQ);
    assign is_bne  = id_ex_ctrl.is_branch && (id_ex_ctrl.branch_op == BR_NE);
    assign is_blt  = id_ex_ctrl.is_branch && (id_ex_ctrl.branch_op == BR_LT);
    assign is_bge  = id_ex_ctrl.is_branch && (id_ex_ctrl.branch_op == BR_GE);
    assign is_bltu = id_ex_ctrl.is_branch && (id_ex_ctrl.branch_op == BR_LTU);
    assign is_bgeu = id_ex_ctrl.is_branch && (id_ex_ctrl.branch_op == BR_GEU);
    
    //==========================================================================
    // Property: BEQ Logic Correctness
    //==========================================================================
    // BEQ should take when operands are equal, not take when different
    
    property p_beq_logic;
        logic [31:0] sampled_rs1, sampled_rs2;
        @(posedge clk) disable iff (rst || soft_reset_active)
        (id_ex_valid && is_beq, sampled_rs1 = ex_rs1_forwarded, sampled_rs2 = ex_rs2_forwarded) |->
        ((sampled_rs1 == sampled_rs2) == ex_branch_taken);
    endproperty
    
    assert_beq_logic: assert property (p_beq_logic)
        else $error("[BRANCH_BEQ] Logic error: PC=0x%08h insn=0x%08h rs1=0x%08h rs2=0x%08h eq=%b taken=%b",
                    id_ex_pc, id_ex_insn, ex_rs1_forwarded, ex_rs2_forwarded, branch_eq, ex_branch_taken);
    
    //==========================================================================
    // Property: BNE Logic Correctness
    //==========================================================================
    // BNE should take when operands are not equal, not take when equal
    
    property p_bne_logic;
        logic [31:0] sampled_rs1, sampled_rs2;
        @(posedge clk) disable iff (rst || soft_reset_active)
        (id_ex_valid && is_bne, sampled_rs1 = ex_rs1_forwarded, sampled_rs2 = ex_rs2_forwarded) |->
        ((sampled_rs1 != sampled_rs2) == ex_branch_taken);
    endproperty
    
    assert_bne_logic: assert property (p_bne_logic)
        else $error("[BRANCH_BNE] Logic error: PC=0x%08h insn=0x%08h rs1=0x%08h rs2=0x%08h ne=%b taken=%b",
                    id_ex_pc, id_ex_insn, ex_rs1_forwarded, ex_rs2_forwarded, branch_ne, ex_branch_taken);
    
    //==========================================================================
    // Property: BLT Logic Correctness
    //==========================================================================
    // BLT should take when rs1 < rs2 (signed), not take otherwise
    
    property p_blt_logic;
        logic [31:0] sampled_rs1, sampled_rs2;
        @(posedge clk) disable iff (rst || soft_reset_active)
        (id_ex_valid && is_blt, sampled_rs1 = ex_rs1_forwarded, sampled_rs2 = ex_rs2_forwarded) |->
        (($signed(sampled_rs1) < $signed(sampled_rs2)) == ex_branch_taken);
    endproperty
    
    assert_blt_logic: assert property (p_blt_logic)
        else $error("[BRANCH_BLT] Logic error: PC=0x%08h insn=0x%08h rs1=0x%08h rs2=0x%08h lt=%b taken=%b",
                    id_ex_pc, id_ex_insn, ex_rs1_forwarded, ex_rs2_forwarded, branch_lt, ex_branch_taken);
    
    //==========================================================================
    // Property: BGE Logic Correctness
    //==========================================================================
    // BGE should take when rs1 >= rs2 (signed), not take otherwise
    
    property p_bge_logic;
        logic [31:0] sampled_rs1, sampled_rs2;
        @(posedge clk) disable iff (rst || soft_reset_active)
        (id_ex_valid && is_bge, sampled_rs1 = ex_rs1_forwarded, sampled_rs2 = ex_rs2_forwarded) |->
        (($signed(sampled_rs1) >= $signed(sampled_rs2)) == ex_branch_taken);
    endproperty
    
    assert_bge_logic: assert property (p_bge_logic)
        else $error("[BRANCH_BGE] Logic error: PC=0x%08h insn=0x%08h rs1=0x%08h rs2=0x%08h ge=%b taken=%b",
                    id_ex_pc, id_ex_insn, ex_rs1_forwarded, ex_rs2_forwarded, branch_ge, ex_branch_taken);
    
    //==========================================================================
    // Property: BLTU Logic Correctness
    //==========================================================================
    // BLTU should take when rs1 < rs2 (unsigned), not take otherwise
    
    property p_bltu_logic;
        logic [31:0] sampled_rs1, sampled_rs2;
        @(posedge clk) disable iff (rst || soft_reset_active)
        (id_ex_valid && is_bltu, sampled_rs1 = ex_rs1_forwarded, sampled_rs2 = ex_rs2_forwarded) |->
        ((sampled_rs1 < sampled_rs2) == ex_branch_taken);
    endproperty
    
    assert_bltu_logic: assert property (p_bltu_logic)
        else $error("[BRANCH_BLTU] Logic error: PC=0x%08h insn=0x%08h rs1=0x%08h rs2=0x%08h ltu=%b taken=%b",
                    id_ex_pc, id_ex_insn, ex_rs1_forwarded, ex_rs2_forwarded, branch_ltu, ex_branch_taken);
    
    //==========================================================================
    // Property: BGEU Logic Correctness
    //==========================================================================
    // BGEU should take when rs1 >= rs2 (unsigned), not take otherwise
    
    property p_bgeu_logic;
        logic [31:0] sampled_rs1, sampled_rs2;
        @(posedge clk) disable iff (rst || soft_reset_active)
        (id_ex_valid && is_bgeu, sampled_rs1 = ex_rs1_forwarded, sampled_rs2 = ex_rs2_forwarded) |->
        ((sampled_rs1 >= sampled_rs2) == ex_branch_taken);
    endproperty
    
    assert_bgeu_logic: assert property (p_bgeu_logic)
        else $error("[BRANCH_BGEU] Logic error: PC=0x%08h insn=0x%08h rs1=0x%08h rs2=0x%08h geu=%b taken=%b",
                    id_ex_pc, id_ex_insn, ex_rs1_forwarded, ex_rs2_forwarded, branch_geu, ex_branch_taken);
    
    //==========================================================================
    // Property: Branch Operands Non-X When Valid
    //==========================================================================
    // Forwarded operands must not be X when branch executes
    
    property p_branch_operands_valid;
        @(posedge clk) disable iff (rst || soft_reset_active)
        (id_ex_valid && id_ex_ctrl.is_branch) |->
        (!$isunknown(ex_rs1_forwarded) && !$isunknown(ex_rs2_forwarded));
    endproperty
    
    assert_branch_operands_valid: assert property (p_branch_operands_valid)
        else $error("[BRANCH_OPERANDS] X-state detected: PC=0x%08h rs1=0x%08h rs2=0x%08h fwd_rs1=%b fwd_rs2=%b",
                    id_ex_pc, ex_rs1_forwarded, ex_rs2_forwarded, id_ex_forward_rs1, id_ex_forward_rs2);
    
    //==========================================================================
    // Property: Branch Target Alignment
    //==========================================================================
    // Branch targets must be 4-byte aligned (LSB = 0)
    
    property p_branch_target_aligned;
        @(posedge clk) disable iff (rst || soft_reset_active)
        (id_ex_valid && id_ex_ctrl.is_branch && ex_branch_taken) |->
        (ex_branch_target[1:0] == 2'b00);
    endproperty
    
    assert_branch_target_aligned: assert property (p_branch_target_aligned)
        else $error("[BRANCH_TARGET] Misaligned target: PC=0x%08h target=0x%08h",
                    id_ex_pc, ex_branch_target);
    
    //==========================================================================
    // Coverage: Track Branch Forwarding Scenarios
    //==========================================================================
    
    covergroup cg_branch_forwarding @(posedge clk);
        option.per_instance = 1;
        
        // Track which forwarding paths are used for branches
        cp_rs1_forward: coverpoint id_ex_forward_rs1 iff (id_ex_valid && id_ex_ctrl.is_branch) {
            bins no_forward  = {2'b00};
            bins ex_forward  = {2'b01};
            bins mem_forward = {2'b10};
            bins wb_forward  = {2'b11};
        }
        
        cp_rs2_forward: coverpoint id_ex_forward_rs2 iff (id_ex_valid && id_ex_ctrl.is_branch) {
            bins no_forward  = {2'b00};
            bins ex_forward  = {2'b01};
            bins mem_forward = {2'b10};
            bins wb_forward  = {2'b11};
        }
        
        // Track branch types
        cp_branch_type: coverpoint id_ex_ctrl.branch_op iff (id_ex_valid && id_ex_ctrl.is_branch) {
            bins beq  = {BR_EQ};
            bins bne  = {BR_NE};
            bins blt  = {BR_LT};
            bins bge  = {BR_GE};
            bins bltu = {BR_LTU};
            bins bgeu = {BR_GEU};
        }
        
        // Track taken vs not-taken
        cp_branch_taken: coverpoint ex_branch_taken iff (id_ex_valid && id_ex_ctrl.is_branch) {
            bins taken     = {1'b1};
            bins not_taken = {1'b0};
        }
        
        // Cross coverage: branch type with taken/not-taken
        cross cp_branch_type, cp_branch_taken;
        
        // Cross coverage: forwarding with branch decision
        cross cp_rs1_forward, cp_rs2_forward, cp_branch_taken;
    endgroup
    
    cg_branch_forwarding cg_inst = new();

endmodule : rv32i_branch_spec
