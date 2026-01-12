`timescale 1ns / 1ps

//==============================================================================
// Bind WB Forwarding Assertions to rv32i_top
//==============================================================================
// Validates WB forwarding path correctness and catches timing skew bugs
//==============================================================================

bind rv32i_top rv32i_wb_forwarding_spec u_wb_forwarding_spec (
    .clk                 (clk),
    .rst                 (rst),
    .soft_reset_active   (soft_reset_active),
    
    // ID/EX pipeline register
    .id_ex_valid         (id_ex_reg.valid),
    .id_ex_insn          (id_ex_reg.insn),
    .id_ex_pc            (id_ex_reg.pc),
    .id_ex_rs1_addr      (id_ex_reg.ctrl.rs1_addr),
    .id_ex_rs2_addr      (id_ex_reg.ctrl.rs2_addr),
    .id_ex_forward_rs1   (id_ex_reg.forward_rs1),
    .id_ex_forward_rs2   (id_ex_reg.forward_rs2),
    
    // WB stage metadata (delayed)
    .wb_rd_addr_delayed  (wb_rd_addr_delayed),
    .wb_rf_wen_delayed   (wb_rf_wen_delayed),
    
    // WB stage current
    .wb_rd_addr_current  (mem_wb_reg.ctrl.rd_addr),
    .wb_rf_wen_current   (mem_wb_reg.ctrl.rf_wen),
    .wb_result_current   (wb_result),
    .wb_result_delayed   (wb_result_delayed),
    
    // EX stage forwarded operands
    .ex_rs1_forwarded    (ex_rs1_forwarded),
    .ex_rs2_forwarded    (ex_rs2_forwarded)
);
