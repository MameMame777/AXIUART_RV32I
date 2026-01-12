`timescale 1ns / 1ps

//==============================================================================
// Memory Protection Assertion Binding
//==============================================================================
// Binds rv32i_mem_protect_spec to rv32i_top for non-invasive verification
//==============================================================================

bind rv32i_top rv32i_mem_protect_spec u_mem_protect (
    .clk             (clk),
    .rst             (rst),
    
    // Port B signals
    .ram_ena_b       (ram_ena_b),
    .ram_addr_b      (ram_addr_b),
    .ram_we_b        (ram_we_b),
    .ram_wdata_b     (ram_wdata_b),
    
    // CPU state
    .cpu_halted      (cpu_halted),
    .ex_mem_pc       (ex_mem_reg.pc)
);
