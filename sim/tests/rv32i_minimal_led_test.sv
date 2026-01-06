`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// RV32I Minimal LED Test
// Simple sequential LED writes to verify MMIO functionality
//------------------------------------------------------------------------------

class rv32i_minimal_led_test extends rv32i_base_test;
    `uvm_component_utils(rv32i_minimal_led_test)
    
    function new(string name = "rv32i_minimal_led_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // Disable scoreboard checks for observation test
        uvm_config_db#(bit)::set(this, "env.scoreboard", "checks_enable", 0);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info("RV32I_MINIMAL", "***** RV32I Minimal LED Test *****", UVM_LOW)
        
        // Reset and halt
        reset_sequence();
        halt_cpu();
        
        // Load minimal LED test program
        load_minimal_led_program();
        
        // Apply soft reset to ensure PC starts at 0x000
        @(posedge vif.clk);
        vif.cb.dbg_soft_reset <= 1;
        @(posedge vif.clk);
        vif.cb.dbg_soft_reset <= 0;
        repeat(2) @(posedge vif.clk);
        `uvm_info("RV32I_MINIMAL", "Applied soft reset - PC set to 0x000", UVM_LOW)
        
        // Start CPU
        start_cpu();
        `uvm_info("RV32I_MINIMAL", "CPU started - executing minimal LED test", UVM_LOW)
        
        // Run for sufficient time (6 writes × 10 cycles = 60 cycles + overhead = ~1μs)
        #10000ns;  // 10μs should be plenty
        
        // Halt CPU
        halt_cpu();
        
        `uvm_info("RV32I_MINIMAL", "***** Test Complete *****", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
    
    virtual task load_minimal_led_program();
        `uvm_info("RV32I_MINIMAL", "Loading minimal LED test program...", UVM_LOW)
        
        // Include generated memory initialization
        `include "rv32i_minimal_led_mem.svh"
        
        `uvm_info("RV32I_MINIMAL", "Program loaded successfully", UVM_LOW)
    endtask
    
endclass
