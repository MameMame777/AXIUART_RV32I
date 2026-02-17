`timescale 1ns / 1ps

//==============================================================================
// RV32I Exception Handler Test
//==============================================================================
// Comprehensive exception handler test covering EBREAK and ECALL.
// Tests:
// - EBREAK (mcause=3) - trap handler increments mepc and returns
// - ECALL (mcause=11) - trap handler writes tohost=1 for PASS
//
// Part of Issue #52: Exception and Interrupt Tests
//==============================================================================

import uvm_pkg::*;
import axiuart_pkg::*;

class rv32i_exception_handler_test extends vexriscv_base_test;

    `uvm_component_utils(rv32i_exception_handler_test)

    function new(string name = "rv32i_exception_handler_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Enable tohost checking - ECALL handler will write tohost=1
        use_tohost_checking = 1;
        timeout_cycles = 5000;
        auto_start_cpu = 0;  // Manual CPU control
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        `uvm_info(get_type_name(),
            {"========================================\n",
             "  RV32I Exception Handler Test\n",
             "  (EBREAK + ECALL)\n",
             "========================================"},
            UVM_LOW)

        // 1. Reset CPU
        reset_cpu();

        // 2. Load exception handler test program
        load_exception_handler_program();

        // 3. Start CPU
        start_cpu();

        // 4. Wait for test completion (tohost monitoring)
        wait_for_tohost(timeout_cycles);

        // 5. Check results
        check_test_results();

        // Halt CPU
        halt_cpu();

        phase.drop_objection(this);
    endtask

    // Load comprehensive exception handler test program
    // Program flow:
    //   1. Initialize mtvec to trap_handler
    //   2. Execute EBREAK → trap_handler (mcause=3) → skip EBREAK, MRET
    //   3. Execute ECALL → trap_handler (mcause=11) → write tohost=1, halt
    //
    // Memory layout:
    //   0x80000000: Main program (init, EBREAK, ECALL)
    //   0x80000100: Trap handler (dispatch based on mcause)
    virtual task load_exception_handler_program();
        `uvm_info(get_type_name(), "Loading exception handler test program", UVM_MEDIUM)

        //======================================================================
        // Main Program (0x80000000)
        //======================================================================

        // 0x80000000: LUI x31, 0x80000 → x31 = 0x80000000
        // Upper 20 bits of 0x80000100 = 0x80000
        write_memory_backdoor(32'h80000000, 32'h80000FB7);

        // 0x80000004: ADDI x31, x31, 0x100 → x31 = 0x80000100
        write_memory_backdoor(32'h80000004, 32'h100F8F93);

        // 0x80000008: CSRW mtvec, x31
        write_memory_backdoor(32'h80000008, 32'h305FB073);

        // 0x8000000C: NOP (pipeline delay)
        write_memory_backdoor(32'h8000000C, 32'h00000013);

        // 0x80000010: NOP
        write_memory_backdoor(32'h80000010, 32'h00000013);

        // 0x80000014: NOP
        write_memory_backdoor(32'h80000014, 32'h00000013);

        // 0x80000018: EBREAK (first exception - mcause=3)
        write_memory_backdoor(32'h80000018, 32'h00100073);

        // 0x8000001C: ECALL (second exception - mcause=11, writes tohost)
        write_memory_backdoor(32'h8000001C, 32'h00000073);

        // 0x80000020: JAL x0, 0 (infinite loop - should not reach)
        write_memory_backdoor(32'h80000020, 32'h0000006F);

        //======================================================================
        // Trap Handler (0x80000100)
        // Dispatch based on mcause:
        //   mcause=3  (EBREAK) → skip instruction, MRET
        //   mcause=11 (ECALL)  → write tohost=1, halt
        //   other              → write tohost=0xBAD, halt
        //======================================================================

        // 0x80000100: CSRR x5, mcause(0x342)
        write_memory_backdoor(32'h80000100, 32'h34202273);

        // 0x80000104: ANDI x6, x5, 0xFF (extract exception code)
        write_memory_backdoor(32'h80000104, 32'h0FF2F313);

        // 0x80000108: LI x7, 3 (EBREAK code)
        write_memory_backdoor(32'h80000108, 32'h00300393);

        // 0x8000010C: BEQ x6, x7, handle_ebreak (offset = +12 = 0x0C)
        // BEQ rs1=x6, rs2=x7, offset=12
        // offset[12:1] = 12 >> 1 = 6, encoded as: imm[12|10:5]=0, imm[4:1|11]=6
        write_memory_backdoor(32'h8000010C, 32'h00730663);

        // 0x80000110: LI x7, 11 (ECALL code)
        write_memory_backdoor(32'h80000110, 32'h00B00393);

        // 0x80000114: BEQ x6, x7, handle_ecall (offset = +20 = 0x14)
        write_memory_backdoor(32'h80000114, 32'h00730A63);

        // 0x80000118: J test_fail (offset = +40 = 0x28)
        write_memory_backdoor(32'h80000118, 32'h0280006F);

        //----------------------------------------------------------------------
        // handle_ebreak (0x8000011C):
        // Read mepc, add 4 (skip EBREAK), write back, MRET
        //----------------------------------------------------------------------

        // 0x8000011C: CSRR x5, mepc
        write_memory_backdoor(32'h8000011C, 32'h34102273);

        // 0x80000120: ADDI x5, x5, 4
        write_memory_backdoor(32'h80000120, 32'h00428293);

        // 0x80000124: CSRW mepc, x5
        write_memory_backdoor(32'h80000124, 32'h34129073);

        // 0x80000128: MRET
        write_memory_backdoor(32'h80000128, 32'h30200073);

        //----------------------------------------------------------------------
        // handle_ecall (0x8000012C):
        // Write tohost=1, then infinite loop (test PASS)
        //----------------------------------------------------------------------

        // 0x8000012C: LUI x10, 0x80001 → x10 = 0x80001000
        write_memory_backdoor(32'h8000012C, 32'h80001537);

        // 0x80000130: LI x11, 1
        write_memory_backdoor(32'h80000130, 32'h00100593);

        // 0x80000134: SW x11, 0(x10) → store 1 to 0x80001000 (tohost)
        write_memory_backdoor(32'h80000134, 32'h00B52023);

        // 0x80000138: JAL x0, 0 (infinite loop)
        write_memory_backdoor(32'h80000138, 32'h0000006F);

        //----------------------------------------------------------------------
        // test_fail (0x80000140):
        // Write tohost=0xBAD, then infinite loop (test FAIL)
        //----------------------------------------------------------------------

        // 0x80000140: LUI x10, 0x80001
        write_memory_backdoor(32'h80000140, 32'h80001537);

        // 0x80000144: LI x11, 0xBAD
        write_memory_backdoor(32'h80000144, 32'hBAD00593);

        // 0x80000148: SW x11, 0(x10)
        write_memory_backdoor(32'h80000148, 32'h00B52023);

        // 0x8000014C: JAL x0, 0
        write_memory_backdoor(32'h8000014C, 32'h0000006F);

        `uvm_info(get_type_name(), "Exception handler test program loaded successfully", UVM_MEDIUM)
    endtask

endclass : rv32i_exception_handler_test
