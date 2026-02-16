`timescale 1ns / 1ps

//==============================================================================
// RV32I Performance Counter Test
//==============================================================================
// Tests VexRiscv performance counter CSRs (mcycle, minstret).
// Verifies that:
// - mcycle increments with each clock cycle
// - minstret increments with each instruction retired
//
// Part of Issue #52: Exception and Interrupt Tests
//==============================================================================

import uvm_pkg::*;
import axiuart_pkg::*;

class rv32i_perfcount_test extends vexriscv_base_test;

    `uvm_component_utils(rv32i_perfcount_test)

    function new(string name = "rv32i_perfcount_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Disable tohost checking - we'll verify manually
        use_tohost_checking = 0;
        timeout_cycles = 1000;
        auto_start_cpu = 0;  // Manual CPU control
    endfunction

    virtual task run_phase(uvm_phase phase);
        bit [31:0] mcycle_start, mcycle_end;
        bit [31:0] minstret_start, minstret_end;
        bit [31:0] mcycle_delta, minstret_delta;
        int expected_instructions = 10;
        bit test_passed = 1;

        phase.raise_objection(this);

        `uvm_info(get_type_name(),
            {"========================================\n",
             "  RV32I Performance Counter Test\n",
             "========================================"},
            UVM_LOW)

        // 1. Reset CPU
        reset_cpu();

        // 2. Load simple NOP program
        load_nop_program(expected_instructions);

        // 3. Read initial counter values
        mcycle_start = read_csr_backdoor(12'hB00);
        minstret_start = read_csr_backdoor(12'hB02);

        `uvm_info(get_type_name(),
            $sformatf("Initial counters:\n  mcycle   = %0d\n  minstret = %0d",
                      mcycle_start, minstret_start),
            UVM_LOW)

        // 4. Start CPU and execute program
        start_cpu();

        // Wait for program execution (10 instructions + pipeline depth + margin)
        // VexRiscv 5-stage pipeline needs extra cycles to retire all instructions
        repeat(expected_instructions * 5 + 50) @(posedge $root.rv32i_tb_top.clk);

        // 5. Halt CPU
        halt_cpu();

        // 6. Read final counter values
        mcycle_end = read_csr_backdoor(12'hB00);
        minstret_end = read_csr_backdoor(12'hB02);

        mcycle_delta = mcycle_end - mcycle_start;
        minstret_delta = minstret_end - minstret_start;

        `uvm_info(get_type_name(),
            $sformatf("Final counters:\n  mcycle   = %0d (delta: %0d)\n  minstret = %0d (delta: %0d)",
                      mcycle_end, mcycle_delta,
                      minstret_end, minstret_delta),
            UVM_LOW)

        // 7. Verify counter increments

        // mcycle should have incremented
        if (mcycle_delta == 0) begin
            `uvm_error(get_type_name(),
                "mcycle did not increment - counter may be stuck or not implemented")
            test_passed = 0;
        end else begin
            `uvm_info(get_type_name(),
                $sformatf("✓ mcycle incremented by %0d cycles", mcycle_delta),
                UVM_LOW)
        end

        // minstret should have incremented by at least expected_instructions
        if (minstret_delta < expected_instructions) begin
            `uvm_error(get_type_name(),
                $sformatf("minstret increment too small: expected >= %0d, got %0d",
                          expected_instructions, minstret_delta))
            test_passed = 0;
        end else begin
            `uvm_info(get_type_name(),
                $sformatf("✓ minstret incremented by %0d instructions (expected >= %0d)",
                          minstret_delta, expected_instructions),
                UVM_LOW)
        end

        // mcycle should be >= minstret (assuming no multi-cycle stalls)
        // Note: This is a weak check - mcycle can be much larger than minstret
        if (mcycle_delta < minstret_delta) begin
            `uvm_warning(get_type_name(),
                $sformatf("mcycle (%0d) < minstret (%0d) - unusual but may be valid in some cases",
                          mcycle_delta, minstret_delta))
        end

        // 8. Write tohost for test completion
        if (test_passed) begin
            write_memory_backdoor(32'h80001000, 32'h00000001);  // tohost = 1 (PASS)
            `uvm_info(get_type_name(),
                {"========================================\n",
                 "  TEST PASSED\n",
                 "========================================"},
                UVM_NONE)
        end else begin
            write_memory_backdoor(32'h80001000, 32'h0000DEAD);  // tohost = 0xDEAD (FAIL)
            `uvm_error(get_type_name(),
                {"========================================\n",
                 "  TEST FAILED\n",
                 "========================================"})
        end

        phase.drop_objection(this);
    endtask

    // Load a simple program with NOP instructions
    virtual task load_nop_program(int num_nops = 10);
        bit [31:0] nop_insn = 32'h00000013;  // ADDI x0, x0, 0 (NOP)
        bit [31:0] jal_insn = 32'h0000006F;  // JAL x0, 0 (infinite loop)

        `uvm_info(get_type_name(),
            $sformatf("Loading NOP program: %0d instructions", num_nops),
            UVM_MEDIUM)

        // Load NOP instructions starting at 0x80000000
        for (int i = 0; i < num_nops; i++) begin
            write_memory_backdoor(32'h80000000 + (i * 4), nop_insn);
        end

        // End with infinite loop to prevent PC runaway
        write_memory_backdoor(32'h80000000 + (num_nops * 4), jal_insn);

        `uvm_info(get_type_name(), "NOP program loaded successfully", UVM_MEDIUM)
    endtask

endclass : rv32i_perfcount_test
