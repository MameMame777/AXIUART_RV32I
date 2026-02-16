`timescale 1ns / 1ps

//==============================================================================
// VexRiscv ISA Test - Intermediate Base Class
//==============================================================================

class vexriscv_isa_test extends vexriscv_base_test;

    `uvm_component_utils(vexriscv_isa_test)

    function new(string name = "vexriscv_isa_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        use_tohost_checking = 1;
        timeout_cycles = 50000;
        auto_start_cpu = 1;
    endfunction

endclass
