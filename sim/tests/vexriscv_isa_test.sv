`timescale 1ns / 1ps

//==============================================================================
// VexRiscv ISA Test - Intermediate Base Class
//==============================================================================
// Base class for all VexRiscv upstream ISA tests (rv32ui-p-*, rv32ui-v-*, etc.)
// Inherits hex loading, tohost monitoring, and CPU control from vexriscv_base_test.
// Derived classes only need to specify hex_file_path.
//
// Pass/Fail Protocol:
//   - tohost = 1 → TEST PASSED
//   - tohost = other non-zero → TEST FAILED (error code)
//   - tohost = 0 → test still running (timeout → FAIL)
//
// Example usage:
//   class vexriscv_isa_add_test extends vexriscv_isa_test;
//       function void build_phase(uvm_phase phase);
//           hex_file_path = "sim/tests/isa_hex/rv32ui-p-add.hex";
//           super.build_phase(phase);
//       endfunction
//   endclass
//==============================================================================

class vexriscv_isa_test extends vexriscv_base_test;

    `uvm_component_utils(vexriscv_isa_test)

    function new(string name = "vexriscv_isa_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // ISA tests use tohost protocol (already default=1 in base, explicit for clarity)
        use_tohost_checking = 1;

        // ISA tests may take longer than unit tests (e.g., rv32ui-p-add takes ~1924 cycles)
        // Load/store tests with data sections need more cycles due to memory latency
        timeout_cycles = 50000;

        // Auto-start CPU after hex load (already default=1 in base)
        auto_start_cpu = 1;

        // Note: hex_file_path must be set by derived classes in their build_phase
        // BEFORE calling super.build_phase()
    endfunction

    // No run_phase override - use vexriscv_base_test's default sequence:
    //   1. reset_cpu()
    //   2. load_hex_file(hex_file_path, translate_addr=1)  // 0x80000000 → 0x00000000
    //   3. start_cpu()
    //   4. wait_for_tohost(timeout_cycles)  // Poll 0x00001000 for tohost value
    //   5. check_test_results()  // tohost=1 → PASS, tohost=other → FAIL with error code

endclass
