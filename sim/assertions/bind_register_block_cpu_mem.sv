`timescale 1ns / 1ps

//==============================================================================
// Bind Register_Block CPU Memory Assertions
//==============================================================================
// This file binds the CPU memory debug interface assertion module to
// the Register_Block instance in AXIUART_Top
//==============================================================================

bind Register_Block register_block_cpu_mem_assertions #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .BASEADDR(BASE_ADDR)
) u_cpu_mem_assertions (
    .clk(clk),
    .rst_n(rst_n),
    
    // AXI4-Lite Write Interface
    .axi_awaddr(axi.awaddr),
    .axi_awvalid(axi.awvalid),
    .axi_awready(axi.awready),
    .axi_wdata(axi.wdata),
    .axi_wstrb(axi.wstrb),
    .axi_wvalid(axi.wvalid),
    .axi_wready(axi.wready),
    
    // CPU Memory Debug Interface
    .rv32i_mem_addr(rv32i_mem_addr),
    .rv32i_mem_wdata(rv32i_mem_wdata),
    .rv32i_mem_rdata(rv32i_mem_rdata),
    .rv32i_mem_we(rv32i_mem_we),
    .rv32i_mem_re(rv32i_mem_re),
    .rv32i_mem_busy(rv32i_mem_busy),
    
    // Internal registers
    .cpu_mem_addr_reg(cpu_mem_addr_reg),
    .cpu_mem_wdata_reg(cpu_mem_wdata_reg),
    .cpu_mem_rdata_reg(cpu_mem_rdata_reg),
    .cpu_mem_ctrl_reg(cpu_mem_ctrl_reg)
);
