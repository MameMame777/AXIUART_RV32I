`timescale 1ns / 1ps

//==============================================================================
// RV32I Debug Memory Load Test
//==============================================================================
// This test verifies external memory loading via the debug memory interface.
// It bypasses the UART/AXI path and writes directly to the debug memory ports
// to verify the dual-port RAM functionality.
//
// Test Sequence:
// 1. Halt CPU (assert cpu_halt)
// 2. Load simple test program via debug memory interface
// 3. Start CPU (assert cpu_run)
// 4. Verify execution: instruction count, LED output, EBREAK detection
//
// Test Program (3 instructions):
//   0: ADDI x1, x0, 10   (0x00A00093) - Load 10 into x1
//   1: SW x1, 0x7C(x17)  (0x07C8AE23) - Store to LED address (MMIO)
//   2: EBREAK            (0x00100073) - Halt
//
// Expected Results:
//   - 5-6 instructions executed (3 program + 2-3 pipeline drain)
//   - LED value = 10 (0xA)
//   - EBREAK detected
//   - CPU halted
//
// Future Enhancement: Replace direct DUT access with proper UART frame
// encoding via AXI4-Lite agent once full UVM infrastructure is available.
//
// Author: GitHub Copilot
// Date: 2026-01-03
//==============================================================================

class rv32i_debug_load_test extends rv32i_base_test;
    
    `uvm_component_utils(rv32i_debug_load_test)
    
    function new(string name = "rv32i_debug_load_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Configure scoreboard for debug load test expectations
        // 3 instructions + 2-3 pipeline drain = 5-6 instructions
        // LED value = 10 (0xA) from loaded program
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_insn_min", 5);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_insn_max", 6);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_led_value", 'hA);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_ebreak_count", 1);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info("RV32I_DEBUG_LOAD", "***** Starting RV32I Debug Load Test *****", UVM_LOW)
        
        // Apply reset sequence
        reset_sequence();
        
        // Halt CPU before loading program
        halt_cpu();
        
        // Load test program via debug memory interface
        load_test_program();
        
        // Verify CPU is still halted
        verify_halted();
        
        // Start CPU and wait for completion
        start_cpu();
        
        // Wait for EBREAK or timeout
        wait_for_completion();
        
        `uvm_info("RV32I_DEBUG_LOAD", "***** RV32I Debug Load Test Complete *****", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
    
    //--------------------------------------------------------------------------
    // Halt CPU
    //--------------------------------------------------------------------------
    
    virtual task halt_cpu();
        `uvm_info("RV32I_DEBUG_LOAD", "Halting CPU for memory loading", UVM_MEDIUM)
        
        @(posedge vif.clk);
        vif.cpu_halt = 1;
        
        // Wait for CPU to enter halted state
        wait(vif.cpu_halted == 1);
        
        @(posedge vif.clk);
        vif.cpu_halt = 0;
        
        `uvm_info("RV32I_DEBUG_LOAD", "CPU halted", UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Load Test Program via Debug Memory Interface
    //--------------------------------------------------------------------------
    
    virtual task load_test_program();
        `uvm_info("RV32I_DEBUG_LOAD", "Loading test program via debug memory interface", UVM_MEDIUM)
        
        // Simple 3-instruction program:
        // 0x0000: ADDI x1, x0, 10    (0x00A00093)
        // 0x0004: SW x1, 0x7C(x17)   (0x07C8AE23)  // Write to LED MMIO
        // 0x0008: EBREAK             (0x00100073)
        
        // NOTE: Direct DUT access used here for simplicity
        // Production version should use Register_Block CPU_MEM_* registers
        // via proper AXI4-Lite transaction sequences
        
        write_debug_mem(11'h000, 32'h00A00093);  // ADDI x1, x0, 10
        write_debug_mem(11'h001, 32'h07C8AE23);  // SW x1, 0x7C(x17)
        write_debug_mem(11'h002, 32'h00100073);  // EBREAK
        
        `uvm_info("RV32I_DEBUG_LOAD", "Test program loaded (3 instructions)", UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Write Debug Memory (Direct DUT Access)
    //--------------------------------------------------------------------------
    
    virtual task write_debug_mem(logic [10:0] word_addr, logic [31:0] data);
        `uvm_info("RV32I_DEBUG_LOAD", 
                  $sformatf("Debug write: addr=0x%03h, data=0x%08h", word_addr, data), 
                  UVM_HIGH)
        
        @(posedge vif.clk);
        
        // Access DUT internal signals directly (testbench privilege)
        // In production, this would be Register_Block writes:
        //   1. Write addr to CPU_MEM_ADDR (0x1228)
        //   2. Write data to CPU_MEM_WDATA (0x122C)
        //   3. Write 0x3F to CPU_MEM_CTRL (0x1234) - write_req + full word
        //   4. Poll CPU_MEM_CTRL[6] until busy clears
        
        force rv32i_tb_top.dut.dbg_mem_addr = word_addr;
        force rv32i_tb_top.dut.dbg_mem_wdata = data;
        force rv32i_tb_top.dut.dbg_mem_we = 4'b1111;  // Full word write
        
        @(posedge vif.clk);
        
        release rv32i_tb_top.dut.dbg_mem_addr;
        release rv32i_tb_top.dut.dbg_mem_wdata;
        release rv32i_tb_top.dut.dbg_mem_we;
        
        @(posedge vif.clk);
    endtask
    
    //--------------------------------------------------------------------------
    // Verify CPU Halted
    //--------------------------------------------------------------------------
    
    virtual task verify_halted();
        if (vif.cpu_halted !== 1'b1) begin
            `uvm_error("RV32I_DEBUG_LOAD", "CPU not in halted state after load")
        end else begin
            `uvm_info("RV32I_DEBUG_LOAD", "CPU halted state verified", UVM_MEDIUM)
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Wait for Completion
    //--------------------------------------------------------------------------
    
    virtual task wait_for_completion();
        int timeout_cycles = 100;
        int cycle_count = 0;
        
        `uvm_info("RV32I_DEBUG_LOAD", "Waiting for CPU completion", UVM_MEDIUM)
        
        fork
            begin
                // Wait for EBREAK (cpu_break assertion)
                wait(vif.cpu_break == 1);
                `uvm_info("RV32I_DEBUG_LOAD", "EBREAK detected", UVM_MEDIUM)
            end
            begin
                // Timeout watchdog
                repeat(timeout_cycles) @(posedge vif.clk);
                `uvm_error("RV32I_DEBUG_LOAD", 
                          $sformatf("Timeout: CPU did not complete after %0d cycles", timeout_cycles))
            end
        join_any
        disable fork;
        
        // Allow pipeline to drain
        repeat(5) @(posedge vif.clk);
        
        `uvm_info("RV32I_DEBUG_LOAD", 
                  $sformatf("Test completed after %0d cycles", cycle_count), 
                  UVM_LOW)
    endtask
    
endclass
