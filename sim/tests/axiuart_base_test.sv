//------------------------------------------------------------------------------
// AXIUART Base Test
// Purpose: Foundation test class with common infrastructure
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

class axiuart_base_test extends uvm_test;
    `uvm_component_utils(axiuart_base_test)
    
    axiuart_env env;
    uvm_table_printer printer;
    bit test_pass = 1;
    
    function new(string name = "axiuart_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(int)::set(this, "*", "recording_detail", UVM_FULL);
        env = axiuart_env::type_id::create("env", this);
        printer = new();
        printer.knobs.depth = 3;
    endfunction
    
    function void end_of_elaboration_phase(uvm_phase phase);
        `uvm_info(get_type_name(),
            $sformatf("Printing test topology:\n%s", this.sprint(printer)), UVM_LOW)
    endfunction
    
    task run_phase(uvm_phase phase);
        phase.phase_done.set_drain_time(this, 50);
    endtask
    
    function void report_phase(uvm_phase phase);
        if(test_pass) begin
            `uvm_info(get_type_name(), "** UVM TEST PASSED **", UVM_NONE)
        end else begin
            `uvm_error(get_type_name(), "** UVM TEST FAIL **")
        end
    endfunction
endclass
