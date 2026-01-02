`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// RV32I Basic Test Class
//------------------------------------------------------------------------------
// Basic functional test for RV32I CPU
// Runs built-in test program and waits for completion (EBREAK)
//
// Author: GitHub Copilot
// Date: 2026-01-02
//------------------------------------------------------------------------------

class rv32i_basic_test extends rv32i_base_test;
    
    `uvm_component_utils(rv32i_basic_test)
    
    // Timeout parameter
    localparam int TIMEOUT_CYCLES = 10000;  // 100us at 100MHz
    
    function new(string name = "rv32i_basic_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        int cycle_count;
        
        phase.raise_objection(this);
        
        `uvm_info("RV32I_BASIC_TEST", "***** Starting RV32I Basic Test *****", UVM_LOW)
        
        // Call base class reset and start
        super.run_phase(phase);
        
        // Wait for CPU to complete execution (cpu_break) or timeout
        `uvm_info("RV32I_BASIC_TEST", "Waiting for CPU completion (cpu_break or timeout)", UVM_MEDIUM)
        
        cycle_count = 0;
        fork
            begin
                // Wait for cpu_break signal
                @(posedge vif.cpu_break);
                `uvm_info("RV32I_BASIC_TEST", "CPU break detected", UVM_MEDIUM)
            end
            begin
                // Timeout watchdog
                while (cycle_count < TIMEOUT_CYCLES && !vif.cpu_break) begin
                    @(posedge vif.clk);
                    cycle_count++;
                end
                
                if (cycle_count >= TIMEOUT_CYCLES) begin
                    `uvm_error("RV32I_BASIC_TEST", 
                        $sformatf("Timeout: CPU did not complete after %0d cycles", TIMEOUT_CYCLES))
                end
            end
        join_any
        disable fork;
        
        // Verify CPU halted status
        if (vif.cpu_halted) begin
            `uvm_info("RV32I_BASIC_TEST", "CPU halted status confirmed", UVM_MEDIUM)
        end else begin
            `uvm_warning("RV32I_BASIC_TEST", "CPU not in halted state")
        end
        
        // Allow some cycles for final monitoring
        repeat(10) @(posedge vif.clk);
        
        `uvm_info("RV32I_BASIC_TEST", 
            $sformatf("Test completed after %0d cycles", cycle_count), UVM_LOW)
        `uvm_info("RV32I_BASIC_TEST", "***** RV32I Basic Test Complete *****", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
    
endclass
