`timescale 1ns / 1ps
//==============================================================================
// Bind RV32I ID Stage Assertions to DUT
//==============================================================================
// This file binds the rv32i_id_timing_spec assertion module to the
// rv32i_id instance within the DUT hierarchy (rv32i_top.u_id).
//==============================================================================

bind rv32i_id rv32i_id_timing_spec u_id_assertions (
    .clk(clk),
    .rst_n(rst_n),
    .pc_in(pc_in),
    .insn_in(insn_in),
    .valid_in(valid_in),
    .rf_wen(rf_wen),
    .rf_waddr(rf_waddr),
    .rf_wdata(rf_wdata),
    .csr_rdata(csr_rdata),
    .forward_rs1(forward_rs1),
    .forward_rs2(forward_rs2),
    .rs1_data_out(rs1_data_out),
    .rs2_data_out(rs2_data_out),
    .imm_out(imm_out),
    .ctrl_out(ctrl_out),
    .valid_out(valid_out),
    .csr_raddr(csr_raddr),
    .regfile(regfile),
    .rs1_addr(rs1_addr),
    .rs2_addr(rs2_addr)
);
