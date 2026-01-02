`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// RV32I Environment Class
//------------------------------------------------------------------------------
// Top-level UVM environment for RV32I CPU verification
// Contains monitor and scoreboard components
//
// Author: GitHub Copilot
// Date: 2026-01-02
//------------------------------------------------------------------------------

class rv32i_env extends uvm_env;
    
    `uvm_component_utils(rv32i_env)
    
    // Components
    rv32i_monitor    monitor;
    rv32i_scoreboard scoreboard;
    
    function new(string name = "rv32i_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Create components
        monitor = rv32i_monitor::type_id::create("monitor", this);
        scoreboard = rv32i_scoreboard::type_id::create("scoreboard", this);
        
        `uvm_info("RV32I_ENV", "Environment built", UVM_MEDIUM)
    endfunction
    
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        // Connect monitor to scoreboard
        monitor.analysis_port.connect(scoreboard.analysis_export);
        
        `uvm_info("RV32I_ENV", "Monitor connected to scoreboard", UVM_MEDIUM)
    endfunction
    
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        `uvm_info("RV32I_ENV", "Environment elaboration complete", UVM_LOW)
    endfunction
    
endclass
