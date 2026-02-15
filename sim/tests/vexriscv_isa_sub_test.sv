`timescale 1ns / 1ps

//==============================================================================
// VexRiscv ISA Test: rv32ui-p-sub
//==============================================================================
// Tests SUB instruction compliance using upstream VexRiscv ISA test hex file.
// Pass/Fail via tohost protocol (tohost=1 → PASS).
//==============================================================================

class vexriscv_isa_sub_test extends vexriscv_isa_test;

    `uvm_component_utils(vexriscv_isa_sub_test)

    function new(string name = "vexriscv_isa_sub_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        hex_file_path = "sim/tests/isa_hex/rv32ui-p-sub.hex";
        super.build_phase(phase);
    endfunction

endclass
