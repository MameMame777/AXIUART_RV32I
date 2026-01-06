`timescale 1ns / 1ps
//==============================================================================
// Bind RV32I WB Stage Assertions to DUT
//==============================================================================
// This file binds the rv32i_wb_timing_spec assertion module to the
// rv32i_wb instance within the DUT hierarchy (rv32i_top.u_wb).
//==============================================================================

bind rv32i_wb rv32i_wb_timing_spec u_wb_assertions (
    .pc_in(pc_in),
    .insn_in(insn_in),
    .mem_data_in(mem_data_in),
    .alu_result_in(alu_result_in),
    .csr_rdata_in(csr_rdata_in),
    .ctrl_in(ctrl_in),
    .valid_in(valid_in),
    .rd_addr_in(rd_addr_in),
    .wb_result(wb_result),
    .rf_wen(rf_wen),
    .csr_waddr(csr_waddr),
    .csr_wdata(csr_wdata),
    .csr_wen(csr_wen)
);
