`timescale 1ns / 1ps

//==============================================================================
// RV32I CPU Testbench Top Module - UVM Compatible
//==============================================================================
// UVM-based testbench for RV32I core verification
// Provides interface to DUT and launches UVM test
//
// Author: GitHub Copilot (RV32I Migration)
// Date: 2026-01-02
//==============================================================================

// Import UVM
import uvm_pkg::*;
`include "uvm_macros.svh"

// Include RV32I test package (AXIUART style)
`include "rv32i_test_pkg.sv"

//==============================================================================
// Interface Definition
//==============================================================================

interface rv32i_tb_if (input logic clk);
    
    // Reset
    logic        rst_n;
    
    // CPU control
    logic        cpu_run;
    logic        cpu_halt;
    logic        cpu_halted;
    logic        cpu_break;
    
    // LED output
    logic [3:0]  led_reg;
    
    // Trace buffer interface
    logic        trace_valid;
    logic [31:0] trace_pc;
    logic [31:0] trace_insn;
    logic [4:0]  trace_rd_addr;
    logic [31:0] trace_rd_data;
    
    // Clocking block
    clocking cb @(posedge clk);
        output rst_n;
        output cpu_run;
        output cpu_halt;
        input  cpu_halted;
        input  cpu_break;
        input  led_reg;
        input  trace_valid;
        input  trace_pc;
        input  trace_insn;
        input  trace_rd_addr;
        input  trace_rd_data;
    endclocking
    
endinterface

//==============================================================================
// Testbench Top Module
//==============================================================================

module rv32i_tb_top;
    
    parameter CLK_PERIOD = 10;  // 100 MHz
    
    //==========================================================================
    // CLOCK GENERATION
    //==========================================================================
    
    logic clk;
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //==========================================================================
    // INTERFACE INSTANTIATION
    //==========================================================================
    
    rv32i_tb_if tb_if(clk);
    
    //==========================================================================
    // DUT INSTANTIATION - RV32I CORE
    //==========================================================================
    
    rv32i_core dut (
        .clk(clk),
        .rst_n(tb_if.rst_n),
        
        // Control
        .cpu_run(tb_if.cpu_run),
        .cpu_halt(tb_if.cpu_halt),
        .cpu_halted(tb_if.cpu_halted),
        .cpu_break(tb_if.cpu_break),
        
        // LED output
        .led_out(tb_if.led_reg),
        
        // Trace outputs
        .trace_valid(tb_if.trace_valid),
        .trace_pc(tb_if.trace_pc),
        .trace_insn(tb_if.trace_insn),
        .trace_rd_addr(tb_if.trace_rd_addr),
        .trace_rd_data(tb_if.trace_rd_data)
    );
    
    //==========================================================================
    // UVM CONFIGURATION AND TEST START
    //==========================================================================
    
    initial begin
        // Load CPU test program from hex file (for simple CPU tests)
        // For UART-driven tests, this will be skipped and memory loaded via AXI
        $readmemh("../../tests/rv32i_ram_init.hex", dut.ram);
        
        // Set virtual interface in config DB
        uvm_config_db#(virtual rv32i_tb_if)::set(null, "*", "vif", tb_if);
        
        // Enable waveform dumping
        $dumpfile("rv32i_test.mxd");
        $dumpvars(0, rv32i_tb_top);
        
        // Start UVM test
        run_test();
    end
    
    //==========================================================================
    // TIMEOUT WATCHDOG
    //==========================================================================
    
    initial begin
        #1ms;
        $display("*** FATAL: Simulation timeout after 1ms ***");
        $finish;
    end
    
endmodule
