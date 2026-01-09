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
    
    // CSV Trace logging
    int trace_file;
    string trace_filename;
    bit trace_enabled;
    int max_trace_lines;
    
    function new(string name = "rv32i_monitor", uvm_component parent = null);
        super.new(name, parent);
        analysis_port = new("analysis_port", this);
        instruction_count = 0;
        trace_enabled = 0;
        max_trace_lines = 10000;
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(virtual rv32i_tb_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("RV32I_MONITOR", "Failed to get virtual interface from config DB")
        end
        
        // Check if trace logging is enabled
        if (uvm_config_db#(string)::get(this, "", "trace_filename", trace_filename)) begin
            trace_enabled = 1;
            trace_file = $fopen(trace_filename, "w");
            if (trace_file == 0) begin
                `uvm_error("RV32I_MONITOR", $sformatf("Failed to open trace file: %s", trace_filename))
                trace_enabled = 0;
            end else begin
                // Write CSV header
                $fdisplay(trace_file, "#,PC,Encoding,Instruction,Operands,rd,rd_value,Time_ps");
                `uvm_info("RV32I_MONITOR", 
                         $sformatf("Trace logging enabled: %s (max %0d lines)", trace_filename, max_trace_lines), 
                         UVM_LOW)
            end
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
                
                // Write to CSV trace file (limited to max_trace_lines)
                if (trace_enabled && instruction_count <= max_trace_lines) begin
                    string insn_name = trans.decode_instruction();
                    string operands = trans.get_operands();
                    $fdisplay(trace_file, "%0d,0x%08h,0x%08h,%s,\"%s\",x%0d,0x%08h,%0t",
                             instruction_count,
                             trans.pc,
                             trans.insn,
                             insn_name,
                             operands,
                             trans.rd_addr,
                             trans.rd_value,
                             trans.timestamp);
                    $fflush(trace_file);
                end
                
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
    
    virtual function void final_phase(uvm_phase phase);
        super.final_phase(phase);
        if (trace_enabled && trace_file != 0) begin
            $fclose(trace_file);
            `uvm_info("RV32I_MONITOR", 
                     $sformatf("Trace log closed: %0d instructions recorded", 
                              (instruction_count < max_trace_lines) ? instruction_count : max_trace_lines),
                     UVM_LOW)
        end
    endfunction
    
endclass
