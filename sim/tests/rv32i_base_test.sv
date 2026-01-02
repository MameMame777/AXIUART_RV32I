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
    
    virtual function void final_phase(uvm_phase phase);
        super.final_phase(phase);
        
        `uvm_info("RV32I_BASE_TEST", "===== Test Summary =====", UVM_LOW)
        `uvm_info("RV32I_BASE_TEST", $sformatf("Simulation Time: %0t", $time), UVM_LOW)
        `uvm_info("RV32I_BASE_TEST", "========================", UVM_LOW)
    endfunction
    
endclass
