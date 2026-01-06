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
    logic        cpu_step;
    logic        cpu_halted;
    logic        cpu_break;
    
    // Hardware breakpoint interface
    logic [3:0]  dbg_bp_enable;
    logic [31:0] dbg_bp_addr[0:3];
    logic [3:0]  dbg_bp_hit;
    
    // Performance counters
    logic [31:0] perf_cycle_count;
    logic [31:0] perf_insn_count;
    logic [31:0] perf_stall_count;
    logic [31:0] perf_flush_count;
    
    // Register file snapshot
    logic [4:0]  dbg_rf_addr;
    logic [31:0] dbg_rf_rdata;
    
    // Trace buffer interface
    logic [5:0]  dbg_trace_addr;
    logic [127:0] dbg_trace_data;
    logic [5:0]  dbg_trace_wptr;
    logic [5:0]  dbg_trace_count;
    
    // Software reset
    logic        dbg_soft_reset;
    logic        dbg_reset_done;
    
    // LED output
    logic [3:0]  led_reg;
    
    // Trace buffer interface (UVM direct access)
    logic        trace_valid;
    logic [31:0] trace_pc;
    logic [31:0] trace_insn;
    logic [4:0]  trace_rd_addr;
    logic [31:0] trace_rd_data;
    
    // Debug memory interface (for test program loading)
    logic [10:0] dbg_mem_addr;
    logic [31:0] dbg_mem_wdata;
    logic [31:0] dbg_mem_rdata;
    logic [3:0]  dbg_mem_we;
    logic        dbg_mem_re;
    
    // Internal PC signal (for verification)
    logic [31:0] pc_if;
    
    // Clocking block with explicit timing to avoid X-value propagation
    clocking cb @(posedge clk);
        default input #1step output #0;
        output rst_n;
        output cpu_run;
        output cpu_halt;
        output cpu_step;
        output dbg_bp_enable;
        output dbg_bp_addr;
        output dbg_rf_addr;
        output dbg_trace_addr;
        output dbg_soft_reset;
        output dbg_mem_addr;
        output dbg_mem_wdata;
        output dbg_mem_we;
        output dbg_mem_re;
        input  cpu_halted;
        input  cpu_break;
        input  dbg_bp_hit;
        input  perf_cycle_count;
        input  perf_insn_count;
        input  perf_stall_count;
        input  perf_flush_count;
        input  dbg_rf_rdata;
        input  dbg_trace_data;
        input  dbg_trace_wptr;
        input  dbg_trace_count;
        input  dbg_reset_done;
        input  led_reg;
        input  trace_valid;
        input  trace_pc;
        input  trace_insn;
        input  trace_rd_addr;
        input  trace_rd_data;
        input  dbg_mem_rdata;
        input  pc_if;
    endclocking
    
    // Initial block to prevent X-value propagation
    // All output signals must have defined values before first clock edge
    initial begin
        rst_n = 0;
        cpu_run = 0;
        cpu_halt = 0;
        cpu_step = 0;
        dbg_bp_enable = 4'b0000;
        dbg_bp_addr[0] = 32'h0;
        dbg_bp_addr[1] = 32'h0;
        dbg_bp_addr[2] = 32'h0;
        dbg_bp_addr[3] = 32'h0;
        dbg_rf_addr = 5'h0;
        dbg_trace_addr = 6'h0;
        dbg_soft_reset = 1'b0;
        dbg_mem_addr = 11'h0;
        dbg_mem_wdata = 32'h0;
        dbg_mem_we = 4'b0;
        dbg_mem_re = 1'b0;
    end
    
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
    // DUT INSTANTIATION - RV32I TOP (Modular Pipeline Architecture)
    //==========================================================================
    
    rv32i_top dut (
        .clk(clk),
        .rst_n(tb_if.rst_n),
        
        // Control
        .cpu_run(tb_if.cpu_run),
        .cpu_halt(tb_if.cpu_halt),
        .cpu_step(tb_if.cpu_step),
        .cpu_halted(tb_if.cpu_halted),
        .cpu_break(tb_if.cpu_break),
        
        // Debug memory interface
        .dbg_mem_addr(tb_if.dbg_mem_addr),
        .dbg_mem_wdata(tb_if.dbg_mem_wdata),
        .dbg_mem_rdata(tb_if.dbg_mem_rdata),
        .dbg_mem_we(tb_if.dbg_mem_we),
        .dbg_mem_re(tb_if.dbg_mem_re),
        
        // Hardware breakpoints
        .dbg_bp_enable(tb_if.dbg_bp_enable),
        .dbg_bp_addr(tb_if.dbg_bp_addr),
        .dbg_bp_hit(tb_if.dbg_bp_hit),
        
        // Performance counters
        .perf_cycle_count(tb_if.perf_cycle_count),
        .perf_insn_count(tb_if.perf_insn_count),
        .perf_stall_count(tb_if.perf_stall_count),
        .perf_flush_count(tb_if.perf_flush_count),
        
        // Register file snapshot
        .dbg_rf_addr(tb_if.dbg_rf_addr),
        .dbg_rf_rdata(tb_if.dbg_rf_rdata),
        
        // Trace buffer
        .dbg_trace_addr(tb_if.dbg_trace_addr),
        .dbg_trace_data(tb_if.dbg_trace_data),
        .dbg_trace_wptr(tb_if.dbg_trace_wptr),
        .dbg_trace_count(tb_if.dbg_trace_count),
        
        // Software reset
        .dbg_soft_reset(tb_if.dbg_soft_reset),
        .dbg_reset_done(tb_if.dbg_reset_done),
        
        // LED output
        .led_out(tb_if.led_reg),
        
        // Trace outputs (UVM direct access)
        .trace_valid(tb_if.trace_valid),
        .trace_pc(tb_if.trace_pc),
        .trace_insn(tb_if.trace_insn),
        .trace_rd_addr(tb_if.trace_rd_addr),
        .trace_rd_data(tb_if.trace_rd_data)
    );
    
    // Expose internal PC for verification
    assign tb_if.pc_if = dut.if_pc_current;
    
    //==========================================================================
    // UVM CONFIGURATION AND TEST START
    //==========================================================================
    
    initial begin
        string test_name;
        string hex_file;
        
        // Set virtual interface in config DB
        uvm_config_db#(virtual rv32i_tb_if)::set(null, "*", "vif", tb_if);
        
        // Load CPU test program from hex file ONLY if test doesn't use debug writes
        // Tests that load code via debug interface (exception handler, minimal tests) skip this
        if ($value$plusargs("UVM_TESTNAME=%s", test_name)) begin
            if (test_name != "rv32i_exception_handler_test" && 
                test_name != "rv32i_minimal_led_test" &&
                test_name != "rv32i_bne_loop_test") begin
                // Try to load test-specific hex file first
                hex_file = {"../../tests/", test_name, ".hex"};
                if ($fopen(hex_file, "r")) begin
                    $readmemh(hex_file, dut.ram);
                    $display("[TB] Loaded %s for test: %s", hex_file, test_name);
                end else begin
                    // Fall back to default
                    $readmemh("../../tests/rv32i_ram_init.hex", dut.ram);
                    $display("[TB] Loaded rv32i_ram_init.hex for test: %s (test-specific hex not found)", test_name);
                end
            end else begin
                $display("[TB] Skipping readmemh - test %s uses debug writes", test_name);
            end
        end else begin
            // Default: load hex file
            $readmemh("../../tests/rv32i_ram_init.hex", dut.ram);
            $display("[TB] Loaded rv32i_ram_init.hex (no UVM_TESTNAME)");
        end
        
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
