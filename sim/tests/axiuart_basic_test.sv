//------------------------------------------------------------------------------
// AXIUART Basic Test
// Purpose: Basic sanity test demonstrating simple sequence execution
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

class axiuart_basic_test extends axiuart_base_test;
    `uvm_component_utils(axiuart_basic_test)
    
    function new(string name = "axiuart_basic_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction
    
    task run_phase(uvm_phase phase);
        uart_basic_sequence seq;
        
        phase.raise_objection(this, "Starting basic test");
        `uvm_info(get_type_name(), "=== AXIUART Basic Test Started ===", UVM_LOW)
        
        seq = uart_basic_sequence::type_id::create("seq");
        seq.start(env.uart_agt.sequencer);
        
        #1000ns;
        
        `uvm_info(get_type_name(), "=== AXIUART Basic Test Completed ===", UVM_LOW)
        phase.drop_objection(this, "Basic test completed");
    endtask
endclass
