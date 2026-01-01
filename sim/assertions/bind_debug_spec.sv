`timescale 1ns / 1ps

//==============================================================================
// Bind Debug Memory Specification Assertions to CPU Core
//==============================================================================

bind td4cpu_core td4cpu_debug_mem_spec spec_checker (
    .clk(clk),
    .rst(rst),
    
    // Debug interface
    .dbg_mem_read_req(dbg_mem_read_req),
    .dbg_mem_write_req(dbg_mem_write_req),
    .dbg_mem_addr(dbg_mem_addr),
    .dbg_mem_wdata(dbg_mem_wdata),
    .dbg_mem_rdata(dbg_mem_rdata),
    .dbg_mem_err(dbg_mem_err),
    
    // CPU state
    .halted(halted),
    .running(running),
    
    // Internal signals
    .mem_busy_q(mem_busy_q),
    .ram_rd_en(ram_rd_en),
    .ram_wr_en(ram_wr_en),
    .ram_read_phase(ram_read_phase),
    .mem_data_valid(mem_data_valid),
    .ram_rd_data(ram_rd_data)
);
