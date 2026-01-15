/**
 * Test 1.1: Basic Immediate Instructions Test
 * 
 * Purpose: Verify register file write and forwarding with ADDI instructions
 * Priority: CRITICAL - This test validates the fix for Issue #1
 * 
 * Issue #1 Background:
 *   - PC=0x08 ADDI x10, x0, 0x400 was decoded with rd_addr=0 instead of rd_addr=10
 *   - This caused all subsequent tests to fail due to incorrect register values
 * 
 * Test Strategy:
 *   1. Use simple ADDI instructions with x0 source (no dependencies)
 *   2. Test positive and negative immediates
 *   3. Test register forwarding with dependent ADDI instruction
 *   4. Verify register writes by checking final register values
 * 
 * Expected Results:
 *   - x1 = 0x0000000A (10)
 *   - x2 = 0x00000014 (20)
 *   - x3 = 0xFFFFFFFB (-5, sign-extended)
 *   - x4 = 0x0000006E (110 = 10 + 100)
 */

`timescale 1ns / 1ps

class rv32i_basic_imm_test extends rv32i_base_test;
    `uvm_component_utils(rv32i_basic_imm_test)

    function new(string name = "rv32i_basic_imm_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Override expected instruction range
        uvm_config_db#(int)::set(this, "*", "expected_insn_min", 4);
        uvm_config_db#(int)::set(this, "*", "expected_insn_max", 10);
        // No LED writes expected
        uvm_config_db#(int)::set(this, "*", "expected_led_value", 0);
        
        `uvm_info(get_type_name(), "Building Basic Immediate Test", UVM_MEDIUM)
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        `uvm_info(get_type_name(), " Test 1.1: Basic Immediate Instructions", UVM_LOW)
        `uvm_info(get_type_name(), " Issue #1 Fix Verification", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        // Apply reset and start CPU (from base test)
        reset_sequence();
        start_cpu();
        
        // Wait for test completion (EBREAK or timeout)
        wait_for_cpu_break(1000); // 1000 cycle timeout (short test)
        
        // Give time for final register writes
        #500ns;
        
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        `uvm_info(get_type_name(), " Verifying Register Values", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        // Check register values
        check_register_values();
        
        phase.drop_objection(this);
        
        `uvm_info(get_type_name(), "Basic Immediate Test Completed", UVM_LOW)
    endtask

    virtual task check_register_values();
        logic [31:0] x1_value, x2_value, x3_value, x4_value;
        int errors = 0;
        
        // Read register values from DUT
        x1_value = rv32i_tb_top.dut.u_id.regfile[1];
        x2_value = rv32i_tb_top.dut.u_id.regfile[2];
        x3_value = rv32i_tb_top.dut.u_id.regfile[3];
        x4_value = rv32i_tb_top.dut.u_id.regfile[4];
        
        // Check x1 = 10
        `uvm_info(get_type_name(), $sformatf("x1 = 0x%08h (expect 0x0000000A)", x1_value), UVM_LOW)
        if (x1_value !== 32'h0000000A) begin
            `uvm_error(get_type_name(), 
                $sformatf("x1 mismatch: expected 0x0000000A, got 0x%08h", x1_value))
            errors++;
        end
        
        // Check x2 = 20
        `uvm_info(get_type_name(), $sformatf("x2 = 0x%08h (expect 0x00000014)", x2_value), UVM_LOW)
        if (x2_value !== 32'h00000014) begin
            `uvm_error(get_type_name(), 
                $sformatf("x2 mismatch: expected 0x00000014, got 0x%08h", x2_value))
            errors++;
        end
        
        // Check x3 = -5 (0xFFFFFFFB)
        `uvm_info(get_type_name(), $sformatf("x3 = 0x%08h (expect 0xFFFFFFFB)", x3_value), UVM_LOW)
        if (x3_value !== 32'hFFFFFFFB) begin
            `uvm_error(get_type_name(), 
                $sformatf("x3 mismatch: expected 0xFFFFFFFB, got 0x%08h", x3_value))
            errors++;
        end
        
        // Check x4 = 110 (0x0000006E)
        `uvm_info(get_type_name(), $sformatf("x4 = 0x%08h (expect 0x0000006E)", x4_value), UVM_LOW)
        if (x4_value !== 32'h0000006E) begin
            `uvm_error(get_type_name(), 
                $sformatf("x4 mismatch: expected 0x0000006E, got 0x%08h", x4_value))
            errors++;
        end
        
        // Summary
        if (errors == 0) begin
            `uvm_info(get_type_name(), 
                "========================================", UVM_LOW)
            `uvm_info(get_type_name(), 
                "   TEST 1.1: BASIC IMMEDIATE - PASS", UVM_LOW)
            `uvm_info(get_type_name(), 
                "   Issue #1 FIX VERIFIED", UVM_LOW)
            `uvm_info(get_type_name(), 
                "========================================", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("TEST FAILED with %0d errors", errors))
        end
    endtask

endclass
