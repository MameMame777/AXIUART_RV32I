`timescale 1ns / 1ps

//==============================================================================
// Bind Branch Assertions to rv32i_top
//==============================================================================
// Validates branch operation correctness at EX stage via rv32i_top hierarchy
//==============================================================================

bind rv32i_top rv32i_branch_spec u_branch_spec (
    .clk                 (clk),
    .rst                 (rst),
    .soft_reset_active   (soft_reset_active),
    
    // ID/EX pipeline register inputs (from top level)
    .id_ex_valid         (id_ex_reg.valid),
    .id_ex_insn          (id_ex_reg.insn),
    .id_ex_pc            (id_ex_reg.pc),
    .id_ex_rs1_addr      (id_ex_reg.ctrl.rs1_addr),
    .id_ex_rs2_addr      (id_ex_reg.ctrl.rs2_addr),
    .id_ex_forward_rs1   (id_ex_reg.forward_rs1),
    .id_ex_forward_rs2   (id_ex_reg.forward_rs2),
    .id_ex_ctrl          (id_ex_reg.ctrl),
    
    // EX stage forwarded operands (from EX module)
    .ex_rs1_forwarded    (ex_rs1_forwarded),
    .ex_rs2_forwarded    (ex_rs2_forwarded),
    
    // Branch decision outputs (from EX module)
    .ex_branch_taken     (ex_branch_taken),
    .ex_branch_target    (ex_branch_target),
    
    // Branch condition signals (from EX module internals)
    .branch_eq           (u_ex.branch_eq),
    .branch_ne           (u_ex.branch_ne),
    .branch_lt           (u_ex.branch_lt),
    .branch_ge           (u_ex.branch_ge),
    .branch_ltu          (u_ex.branch_ltu),
    .branch_geu          (u_ex.branch_geu)
);
