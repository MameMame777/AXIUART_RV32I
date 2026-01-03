`timescale 1ns / 1ps
//==============================================================================
// Bind RV32I Data Hazard & Forwarding Assertions to DUT
//
// This file binds the rv32i_data_hazard_spec assertion module to the
// rv32i_core instance within the DUT hierarchy to verify forwarding logic
// correctness and RAW hazard handling.
//
// Author: GitHub Copilot
// Date: 2026-01-03
//==============================================================================

bind rv32i_core rv32i_data_hazard_spec u_rv32i_hazard_spec (
    .clk(clk),
    .rst_n(rst_n),
    
    // ID stage (register read)
    .id_rs1_addr(if_id_reg.ctrl.rs1_addr),
    .id_rs2_addr(if_id_reg.ctrl.rs2_addr),
    .id_valid(if_id_reg.valid),
    
    // EX stage (ALU operation)
    .ex_rs1_forwarded(ex_rs1_forwarded),
    .ex_rs2_forwarded(ex_rs2_forwarded),
    .ex_alu_result(ex_alu_result),
    .ex_rd_addr(id_ex_reg.ctrl.rd_addr),
    .ex_rf_wen(id_ex_reg.ctrl.rf_wen),
    .ex_valid(id_ex_reg.valid),
    
    // MEM stage (memory access)
    .mem_alu_result(ex_mem_reg.alu_result),
    .mem_rs2_data(ex_mem_reg.rs2_data),
    .mem_rd_addr(ex_mem_reg.ctrl.rd_addr),
    .mem_rf_wen(ex_mem_reg.ctrl.rf_wen),
    .mem_valid(ex_mem_reg.valid),
    
    // WB stage (writeback)
    .wb_result(mem_wb_reg.result),
    .wb_rd_addr(mem_wb_reg.rd_addr),
    .wb_rf_wen(mem_wb_reg.rf_wen),
    .wb_valid(mem_wb_reg.valid),
    
    // Register file
    .regfile(regfile),
    
    // Forwarding control (optimized logic)
    .forward_rs1(forward_rs1),
    .forward_rs2(forward_rs2)
);
