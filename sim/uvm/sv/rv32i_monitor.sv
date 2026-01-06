`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// RV32I Monitor Class
//------------------------------------------------------------------------------
// Monitors the trace buffer interface and broadcasts executed instructions
//
// Author: GitHub Copilot
// Date: 2026-01-02
//------------------------------------------------------------------------------

class rv32i_monitor extends uvm_monitor;
    
    `uvm_component_utils(rv32i_monitor)
    
    // Virtual interface
    virtual rv32i_tb_if vif;
    
    // Analysis port
    uvm_analysis_port #(rv32i_transaction) analysis_port;
    
    // Statistics
    int instruction_count;
    
    function new(string name = "rv32i_monitor", uvm_component parent = null);
        super.new(name, parent);
        analysis_port = new("analysis_port", this);
        instruction_count = 0;
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(virtual rv32i_tb_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("RV32I_MONITOR", "Failed to get virtual interface from config DB")
        end
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        rv32i_transaction trans;
        
        `uvm_info("RV32I_MONITOR", "Monitor started", UVM_MEDIUM)
        
        forever begin
            // Wait for valid trace signal
            @(posedge vif.clk);
            
            if (vif.trace_valid) begin
                // Create transaction
                trans = rv32i_transaction::type_id::create("trans");
                
                // Capture trace data
                trans.pc        = vif.trace_pc;
                trans.insn      = vif.trace_insn;
                trans.rd_addr   = vif.trace_rd_addr;
                trans.rd_value  = vif.trace_rd_data;
                trans.timestamp = $time;
                
                // Increment instruction counter
                instruction_count++;
                
                // Broadcast transaction to scoreboard
                analysis_port.write(trans);
                
                `uvm_info("RV32I_MONITOR", 
                    $sformatf("Captured instruction #%0d: %s", instruction_count, trans.convert2string()),
                    UVM_HIGH)
            end
        end
    endtask
    
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("RV32I_MONITOR", 
            $sformatf("Total instructions monitored: %0d", instruction_count),
            UVM_LOW)
    endfunction
    
endclass
