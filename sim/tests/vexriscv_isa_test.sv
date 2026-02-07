`timescale 1ns / 1ps

//==============================================================================
// VexRiscv ISA Test Class (Parameterized)
//==============================================================================
// Base class for all VexRiscv upstream ISA tests (Stage 2).
// Loads an Intel HEX file, starts the CPU, and monitors tohost for pass/fail.
//
// Usage:
//   +UVM_TESTNAME=vexriscv_isa_test +HEX_FILE=sim/tests/isa_hex/rv32ui-p-add.hex
//
// Or derive a named class that sets hex_file_path in build_phase.
//
// Pass/Fail Protocol:
//   tohost (0x00001000) == 1  → TEST PASSED
//   tohost (0x00001000) != 1  → TEST FAILED (value encodes error info)
//==============================================================================

class vexriscv_isa_test extends vexriscv_base_test;

    `uvm_component_utils(vexriscv_isa_test)

    function new(string name = "vexriscv_isa_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // ISA tests always use tohost checking
        use_tohost_checking = 1;

        // Generous timeout for complex ISA test programs
        // rv32ui-p-add needs ~12500 fetches; allow 200K cycles for margin
        timeout_cycles = 200000;

        // Auto-start CPU after loading hex file
        auto_start_cpu = 1;

        // Verify hex file is specified
        if (hex_file_path == "") begin
            `uvm_fatal(get_type_name(),
                "No hex file specified. Use +HEX_FILE=<path> or set via uvm_config_db")
        end

        `uvm_info(get_type_name(),
            $sformatf("VexRiscv ISA Test: %s (timeout=%0d cycles)",
                      hex_file_path, timeout_cycles),
            UVM_LOW)
    endfunction

    // run_phase inherited from vexriscv_base_test:
    //   reset_cpu() → load_hex_file() → start_cpu() → wait_for_tohost() → check_test_results()

endclass
