//------------------------------------------------------------------------------
// AXIUART Reset Test
// Purpose: Demonstrates DUT reset capability and post-reset behavior
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

class axiuart_reset_test extends axiuart_base_test;
    `uvm_component_utils(axiuart_reset_test)
    
    function new(string name = "axiuart_reset_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction
    
    task run_phase(uvm_phase phase);
        uart_reset_sequence reset_seq;
        uart_basic_sequence basic_seq;
        
        phase.raise_objection(this, "Starting reset test");
        `uvm_info(get_type_name(), "=== AXIUART Reset Test Started ===", UVM_LOW)
        
        // Execute reset
        reset_seq = uart_reset_sequence::type_id::create("reset_seq");
        reset_seq.reset_cycles = 200; // Custom reset duration
        reset_seq.start(env.uart_agt.sequencer);
        
        // Run basic sequence after reset
        basic_seq = uart_basic_sequence::type_id::create("basic_seq");
        basic_seq.start(env.uart_agt.sequencer);
        
        #1000ns;
        
        `uvm_info(get_type_name(), "=== AXIUART Reset Test Completed ===", UVM_LOW)
        phase.drop_objection(this, "Reset test completed");
    endtask
endclass
