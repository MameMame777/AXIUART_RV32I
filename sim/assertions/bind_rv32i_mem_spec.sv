`timescale 1ns / 1ps
//==============================================================================
// Bind RV32I MEM Stage Assertions to DUT
//==============================================================================
// This file binds the rv32i_mem_timing_spec assertion module to the
// rv32i_mem instance within the DUT hierarchy (rv32i_top.u_mem).
//==============================================================================

bind rv32i_mem rv32i_mem_timing_spec u_mem_assertions (
    .clk(clk),
    .rst_n(rst_n),
    .pc_in(pc_in),
    .insn_in(insn_in),
    .alu_result_in(alu_result_in),
    .rs2_data_in(rs2_data_in),
    .csr_rdata_in(csr_rdata_in),
    .ctrl_in(ctrl_in),
    .valid_in(valid_in),
    .data_ram_rdata(data_ram_rdata),
    .data_ram_addr(data_ram_addr),
    .data_ram_wdata(data_ram_wdata),
    .data_ram_we(data_ram_we),
    .mem_data(mem_data),
    .led_out(led_out),
    .exception_trap(exception_trap),
    .exception_pc(exception_pc),
    .exception_code(exception_code),
    .exception_tval(exception_tval)
);
