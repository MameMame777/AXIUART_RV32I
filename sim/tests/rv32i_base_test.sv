`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// RV32I Base Test Class
//------------------------------------------------------------------------------
// Base class for all RV32I CPU tests
// Provides common setup: reset sequence, CPU start, environment
//
// Author: GitHub Copilot
// Date: 2026-01-02
//------------------------------------------------------------------------------

class rv32i_base_test extends uvm_test;
    
    `uvm_component_utils(rv32i_base_test)
    
    // Environment
    rv32i_env env;
    
    // Virtual interface
    virtual rv32i_tb_if vif;
    
    function new(string name = "rv32i_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Create environment
        env = rv32i_env::type_id::create("env", this);
        
        // Get virtual interface
        if (!uvm_config_db#(virtual rv32i_tb_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("RV32I_BASE_TEST", "Failed to get virtual interface from config DB")
        end
        
        `uvm_info("RV32I_BASE_TEST", "Base test built", UVM_MEDIUM)
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info("RV32I_BASE_TEST", "Starting base test run phase", UVM_LOW)
        
        // Apply reset sequence
        reset_sequence();
        
        // Start CPU
        start_cpu();
        
        `uvm_info("RV32I_BASE_TEST", "Base test run phase complete", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
    
    //--------------------------------------------------------------------------
    // Reset Sequence
    //--------------------------------------------------------------------------
    
    virtual task reset_sequence();
        `uvm_info("RV32I_BASE_TEST", "Applying reset sequence", UVM_MEDIUM)
        
        vif.rst_n = 0;
        vif.cpu_run = 0;
        vif.cpu_halt = 0;
        vif.cpu_step = 0;
        
        // Initialize debug signals
        vif.dbg_bp_enable = 4'b0000;
        vif.dbg_bp_addr[0] = 32'h0;
        vif.dbg_bp_addr[1] = 32'h0;
        vif.dbg_bp_addr[2] = 32'h0;
        vif.dbg_bp_addr[3] = 32'h0;
        vif.dbg_rf_addr = 5'h0;
        vif.dbg_trace_addr = 6'h0;
        vif.dbg_soft_reset = 1'b0;
        vif.dbg_mem_addr = 11'h0;
        vif.dbg_mem_wdata = 32'h0;
        vif.dbg_mem_we = 4'b0;
        vif.dbg_mem_re = 1'b0;
        
        repeat(5) @(posedge vif.clk);
        
        vif.rst_n = 1;
        
        repeat(2) @(posedge vif.clk);
        
        `uvm_info("RV32I_BASE_TEST", "Reset sequence complete", UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Start CPU
    //--------------------------------------------------------------------------
    
    virtual task start_cpu();
        `uvm_info("RV32I_BASE_TEST", "Starting CPU execution", UVM_MEDIUM)
        
        @(posedge vif.clk);
        vif.cpu_run = 1;
        
        @(posedge vif.clk);
        vif.cpu_run = 0;
        
        `uvm_info("RV32I_BASE_TEST", "CPU started", UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Halt CPU
    //--------------------------------------------------------------------------
    
    virtual task halt_cpu();
        `uvm_info("RV32I_BASE_TEST", "Halting CPU execution", UVM_MEDIUM)
        
        @(posedge vif.clk);
        vif.cpu_halt = 1;
        
        @(posedge vif.clk);
        vif.cpu_halt = 0;
        
        `uvm_info("RV32I_BASE_TEST", "CPU halted", UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Wait for Completion
    //--------------------------------------------------------------------------
    
    virtual task wait_for_completion(int max_cycles = 1000);
        int cycle_count = 0;
        `uvm_info("RV32I_BASE_TEST", $sformatf("Waiting for completion (max %0d cycles)", max_cycles), UVM_MEDIUM)
        
        while (cycle_count < max_cycles) begin
            @(posedge vif.clk);
            cycle_count++;
        end
        
        `uvm_info("RV32I_BASE_TEST", $sformatf("Wait complete after %0d cycles", cycle_count), UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Write Debug Memory
    //--------------------------------------------------------------------------
    
    virtual task write_debug_mem(input logic [10:0] addr, input logic [31:0] data);
        @(posedge vif.clk);
        vif.dbg_mem_addr = addr;
        vif.dbg_mem_wdata = data;
        vif.dbg_mem_we = 4'b1111;
        
        @(posedge vif.clk);
        vif.dbg_mem_we = 4'b0000;
        
        `uvm_info("RV32I_BASE_TEST", $sformatf("Wrote 0x%08h to memory address 0x%03h", data, addr), UVM_HIGH)
    endtask
    
    //--------------------------------------------------------------------------
    // Read Trace Buffer Entry
    //--------------------------------------------------------------------------
    
    virtual task read_trace_entry(input logic [5:0] entry_addr, 
                                   output logic [31:0] pc, 
                                   output logic [31:0] insn,
                                   output logic [31:0] rd_value,
                                   output logic [4:0] rd_addr);
        logic [127:0] trace_data;
        
        @(posedge vif.clk);
        vif.dbg_trace_addr = entry_addr;
        
        @(posedge vif.clk);
        trace_data = vif.dbg_trace_data;
        
        // Decode 128-bit trace entry
        pc = trace_data[127:96];
        insn = trace_data[95:64];
        rd_value = trace_data[63:32];
        rd_addr = trace_data[31:27];
        
        `uvm_info("RV32I_BASE_TEST", 
                  $sformatf("Trace[%02d]: PC=0x%08h, INSN=0x%08h, RD=x%0d, VAL=0x%08h",
                            entry_addr, pc, insn, rd_addr, rd_value), UVM_HIGH)
    endtask
    
    //--------------------------------------------------------------------------
    // Dump Trace Buffer
    //--------------------------------------------------------------------------
    
    virtual task dump_trace_buffer(input int num_entries = 10);
        logic [31:0] pc, insn, rd_value;
        logic [4:0] rd_addr;
        logic [5:0] write_ptr;
        logic [6:0] entry_count;
        
        `uvm_info("RV32I_BASE_TEST", "===== TRACE BUFFER DUMP =====", UVM_LOW)
        
        // Get trace status
        write_ptr = vif.dbg_trace_wptr;
        entry_count = vif.dbg_trace_count;
        
        `uvm_info("RV32I_BASE_TEST", $sformatf("Write Ptr: %0d, Entry Count: %0d", 
                  write_ptr, entry_count), UVM_LOW)
        
        // Read last N entries
        for (int i = 0; i < num_entries && i < entry_count; i++) begin
            logic [5:0] addr;
            if (write_ptr >= i) begin
                addr = write_ptr - i - 1;
            end else begin
                addr = 6'd64 - (i - write_ptr) - 1;
            end
            
            read_trace_entry(addr, pc, insn, rd_value, rd_addr);
        end
        
        `uvm_info("RV32I_BASE_TEST", "==============================", UVM_LOW)
    endtask
    
    //--------------------------------------------------------------------------
    // Set Hardware Breakpoint
    //--------------------------------------------------------------------------
    
    virtual task set_breakpoint(int bp_num, bit [31:0] addr);
        `uvm_info("RV32I_BASE_TEST", $sformatf("Setting breakpoint %0d at PC=0x%08X", bp_num, addr), UVM_MEDIUM)
        
        @(posedge vif.clk);
        
        // Set breakpoint address
        case (bp_num)
            0: vif.dbg_bp_addr[0] = addr;
            1: vif.dbg_bp_addr[1] = addr;
            2: vif.dbg_bp_addr[2] = addr;
            3: vif.dbg_bp_addr[3] = addr;
        endcase
        
        // Enable breakpoint
        vif.dbg_bp_enable[bp_num] = 1'b1;
        
        @(posedge vif.clk);
        
        `uvm_info("RV32I_BASE_TEST", $sformatf("Breakpoint %0d enabled", bp_num), UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Clear Hardware Breakpoint
    //--------------------------------------------------------------------------
    
    virtual task clear_breakpoint(int bp_num);
        `uvm_info("RV32I_BASE_TEST", $sformatf("Clearing breakpoint %0d", bp_num), UVM_MEDIUM)
        
        @(posedge vif.clk);
        vif.dbg_bp_enable[bp_num] = 1'b0;
        @(posedge vif.clk);
        
        `uvm_info("RV32I_BASE_TEST", $sformatf("Breakpoint %0d disabled", bp_num), UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Wait for CPU Break (EBREAK or Breakpoint)
    //--------------------------------------------------------------------------
    
    virtual task wait_for_cpu_break(int timeout_cycles);
        int cycle_count = 0;
        
        `uvm_info("RV32I_BASE_TEST", $sformatf("Waiting for CPU break (timeout=%0d cycles)", timeout_cycles), UVM_MEDIUM)
        
        while (cycle_count < timeout_cycles) begin
            @(posedge vif.clk);
            
            if (vif.cpu_halted && vif.cpu_break) begin
                `uvm_info("RV32I_BASE_TEST", $sformatf("CPU break detected at cycle %0d, PC=0x%08X", cycle_count, vif.pc_if), UVM_LOW)
                return;
            end
            
            cycle_count++;
        end
        
        `uvm_error("RV32I_BASE_TEST", $sformatf("Timeout waiting for CPU break (waited %0d cycles)", timeout_cycles))
    endtask
    
    virtual function void final_phase(uvm_phase phase);
        super.final_phase(phase);
        
        `uvm_info("RV32I_BASE_TEST", "===== Test Summary =====", UVM_LOW)
        `uvm_info("RV32I_BASE_TEST", $sformatf("Simulation Time: %0t", $time), UVM_LOW)
        `uvm_info("RV32I_BASE_TEST", "========================", UVM_LOW)
    endfunction
    
endclass
