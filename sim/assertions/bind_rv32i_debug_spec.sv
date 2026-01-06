`timescale 1ns / 1ps

//==============================================================================
// Bind RV32I Debug Assertions to DUT
//==============================================================================
// This file binds assertion modules to rv32i_core for LED MMIO and EBREAK
// verification during simulation.
//==============================================================================

bind rv32i_top rv32i_mmio_led_spec u_led_spec (
    .clk              (clk),
    .rst_n            (rst_n),
    
    // MEM stage signals
    .mem_addr         (mem_addr),
    .mem_write        (ex_mem_reg.ctrl.mem_write),
    .mem_store_data   (ex_mem_reg.rs2_data),
    .mem_valid        (ex_mem_reg.valid),
    .mem_is_mmio      (mem_is_mmio),
    
    // LED register
    .led_reg          (led_reg),
    
    // Control
    .mem_ctrl         (ex_mem_reg.ctrl)
);

bind rv32i_top rv32i_ebreak_spec u_ebreak_spec (
    .clk              (clk),
    .rst_n            (rst_n),
    
    // MEM stage
    .mem_valid        (ex_mem_reg.valid),
    .mem_ctrl         (ex_mem_reg.ctrl),
    .mem_pc           (ex_mem_reg.pc),
    
    // Debug control
    .cpu_run          (cpu_run),
    .cpu_halt         (cpu_halt),
    .cpu_break        (cpu_break),
    .cpu_halted       (cpu_halted),
    .running          (running),
    
    // IF stage
    .if_valid         (if_id_reg.valid)
);
