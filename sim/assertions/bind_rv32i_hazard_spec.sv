`timescale 1ns / 1ps
//==============================================================================
// Bind RV32I Hazard Detection Assertions to DUT
//==============================================================================
// This file binds the rv32i_hazard_timing_spec assertion module to the
// rv32i_hazard instance within the DUT hierarchy (rv32i_top.u_hazard).
//==============================================================================

bind rv32i_hazard rv32i_hazard_timing_spec u_hazard_assertions (
    .clk(clk),
    .rst_n(rst_n),
    .id_rs1_addr(id_rs1_addr),
    .id_rs2_addr(id_rs2_addr),
    .id_rs1_used(id_rs1_used),
    .id_rs2_used(id_rs2_used),
    .id_valid(id_valid),
    .ex_rd_addr(ex_rd_addr),
    .ex_rf_wen(ex_rf_wen),
    .ex_is_load(ex_is_load),
    .ex_valid(ex_valid),
    .mem_rd_addr(mem_rd_addr),
    .mem_rf_wen(mem_rf_wen),
    .mem_valid(mem_valid),
    .wb_rd_addr(wb_rd_addr_delayed),
    .wb_rf_wen(wb_rf_wen_delayed),
    .wb_valid(wb_valid_delayed),
    .branch_taken(branch_taken),
    .exception_trap(exception_trap),
    .mret_req(mret_req),
    .forward_rs1(forward_rs1_sel),
    .forward_rs2(forward_rs2_sel),
    .if_stall(if_stall),
    .id_stall(id_stall),
    .if_flush(if_flush),
    .id_flush(id_flush),
    .ex_flush(ex_flush),
    .load_use_stall(load_use_stall)
);
