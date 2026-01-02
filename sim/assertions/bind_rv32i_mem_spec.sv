`timescale 1ns / 1ps
//==============================================================================
// Bind RV32I Memory Access Assertions to DUT
//
// This file binds the rv32i_mem_access_spec assertion module to the
// rv32i_core instance within the DUT hierarchy.
//
// Author: GitHub Copilot
// Date: 2026-01-03
//==============================================================================

bind rv32i_core rv32i_mem_access_spec u_rv32i_mem_spec (
    .clk(clk),
    .rst_n(rst_n),
    
    // CPU state
    .cpu_halted(cpu_halted),
    .cpu_running(state != STATE_HALT),  // Running when not in HALT state
    
    // Port A (CPU internal access)
    .ram_addr_if(ram_addr_if),
    .ram_addr_mem(ram_addr_mem),
    .ram_we_mem(ram_we_mem),
    .ram_wdata_mem(ram_wdata_mem),
    
    // Port B (Debug/external access)
    .dbg_mem_addr(dbg_mem_addr),
    .dbg_mem_wdata(dbg_mem_wdata),
    .dbg_mem_rdata(dbg_mem_rdata),
    .dbg_mem_we(dbg_mem_we),
    .dbg_mem_re(dbg_mem_re),
    
    // Register Block memory interface (connect via top-level hierarchy)
    // Note: These signals come from AXIUART_Top, not rv32i_core directly
    // Using default values here, will be overridden in testbench-specific bind
    .rv32i_mem_addr('0),
    .rv32i_mem_wdata('0),
    .rv32i_mem_rdata('0),
    .rv32i_mem_we('0),
    .rv32i_mem_re('0),
    .rv32i_mem_busy('0)
);
