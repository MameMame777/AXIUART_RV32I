`timescale 1ns / 1ps

//==============================================================================
// RV32I FAST Complex LED Pattern Test - High-Speed Simulation
//==============================================================================

class rv32i_led_fast_pattern_test extends rv32i_base_test;
    
    `uvm_component_utils(rv32i_led_fast_pattern_test)
    
    function new(string name = "rv32i_led_fast_pattern_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Disable scoreboard checks for pattern observation test
        uvm_config_db#(bit)::set(this, "env.scoreboard", "disable_checks", 1);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info("RV32I_FAST", "***** RV32I FAST Pattern Test *****", UVM_LOW)
        
        // Reset and halt
        reset_sequence();
        halt_cpu();
        
        // Load FAST pattern program
        load_complex_pattern_program_fast();
        
        // Apply soft reset to set PC to 0x000
        @(posedge vif.clk);
        vif.cb.dbg_soft_reset <= 1;
        @(posedge vif.clk);
        vif.cb.dbg_soft_reset <= 0;
        repeat(2) @(posedge vif.clk);
        `uvm_info("RV32I_FAST", "Applied soft reset - PC set to 0x000", UVM_LOW)
        
        // Start CPU
        `uvm_info("RV32I_FAST", "Starting CPU execution", UVM_MEDIUM)
        start_cpu();
        
        // Let it run for 100μs
        #100000ns;
        
        // Halt CPU
        halt_cpu();
        
        `uvm_info("RV32I_FAST", "***** Test Complete *****", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
    
    // Load fast pattern program - inline due to UVM scope
    virtual task load_complex_pattern_program_fast();
        `uvm_info("RV32I_FAST", "Loading 59-instruction FAST LED pattern program...", UVM_MEDIUM)
        `uvm_info("RV32I_FAST", "Mode: FAST SIMULATION - 1000 cycles/iteration", UVM_MEDIUM)
        
        `include "rv32i_complex_pattern_mem_fast.svh"
        
        `uvm_info("RV32I_FAST", "FAST pattern loaded successfully", UVM_MEDIUM)
        `uvm_info("RV32I_FAST", "Expect ~12-16 LED changes in 100μs simulation", UVM_MEDIUM)
    endtask

endclass


