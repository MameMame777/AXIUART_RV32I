`timescale 1ns / 1ps
//==============================================================================
// Bind RV32I EX Stage Assertions to DUT
//==============================================================================
// This file binds the rv32i_ex_timing_spec assertion module to the
// rv32i_ex instance within the DUT hierarchy (rv32i_top.u_ex).
//==============================================================================

bind rv32i_ex rv32i_ex_timing_spec u_ex_assertions (
    .pc_in(pc_in),
    .insn_in(insn_in),
    .rs1_data_in(rs1_data_in),
    .rs2_data_in(rs2_data_in),
    .imm_in(imm_in),
    .csr_rdata_in(csr_rdata_in),
    .forward_rs1(forward_rs1),
    .forward_rs2(forward_rs2),
    .ctrl_in(ctrl_in),
    .valid_in(valid_in),
    .ex_forward_data(ex_forward_data),
    .mem_forward_data(mem_forward_data),
    .wb_forward_data(wb_forward_data),
    .alu_result(alu_result),
    .rs2_forwarded_out(rs2_forwarded_out),
    .branch_taken(branch_taken),
    .branch_target(branch_target),
    .valid_out(valid_out)
);
