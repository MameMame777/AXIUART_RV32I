`timescale 1ns / 1ps

//==============================================================================
// Bind Statement: RV32I EBREAK Debug Assertions
//==============================================================================
// Binds enhanced EBREAK diagnostic assertions to rv32i_top
// These assertions track EBREAK through all pipeline stages and detect
// where the instruction may be lost or invalidated.
//==============================================================================

bind rv32i_top rv32i_ebreak_debug_spec u_ebreak_debug_assertions (
    .clk             (clk),
    .rst_n           (rst_n),
    
    // IF Stage
    .if_valid        (if_valid),
    .if_pc           (if_pc_out),
    .if_insn         (if_insn_out),
    
    // ID Stage
    .id_valid        (id_valid),
    .id_pc           (id_pc_out),
    .id_insn         (id_insn_out),
    .id_ctrl         (id_ctrl),
    
    // EX Stage
    .ex_valid        (id_ex_reg.valid),
    .ex_pc           (id_ex_reg.pc),
    .ex_ctrl         (id_ex_reg.ctrl),
    
    // MEM Stage
    .mem_valid       (ex_mem_reg.valid),
    .mem_pc          (ex_mem_reg.pc),
    .mem_ctrl        (ex_mem_reg.ctrl),
    
    // WB Stage
    .wb_valid        (mem_wb_reg.valid),
    .wb_pc           (mem_wb_reg.pc),
    
    // Control
    .cpu_break       (cpu_break),
    .cpu_halted      (cpu_halted),
    .running         (running),
    
    // Hazard signals
    .if_stall        (if_stall),
    .id_stall        (id_stall),
    .if_flush        (if_flush),
    .id_flush        (id_flush),
    .ex_flush        (ex_flush)
);
