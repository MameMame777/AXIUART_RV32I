`timescale 1ns / 1ps

//==============================================================================
// Test 1.4: Shift Immediate Instructions (SLLI/SRLI/SRAI)
//==============================================================================
// Tests all three shift immediate instruction variants with comprehensive
// edge case coverage:
//   - SLLI: Shift Left Logical Immediate (overflow, max shift, boundary)
//   - SRLI: Shift Right Logical Immediate (zero-fill verification)
//   - SRAI: Shift Right Arithmetic Immediate (sign-extension verification)
//
// Critical verification: SRLI vs SRAI distinction on negative operands
//   x7 (SRLI): 0x80000000 >>u 16 = 0x00008000 (zero-fill)
//   x19 (SRAI): 0x80000000 >>s 8 = 0xFF800000 (sign-extend)
//
// Coverage: SLLI, SRLI, SRAI (3 new instructions)
// Author: GitHub Copilot
// Date: 2026-01-16
//==============================================================================

class rv32i_shift_imm_test extends rv32i_base_test;
    `uvm_component_utils(rv32i_shift_imm_test)
    
    function new(string name = "rv32i_shift_imm_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Configure expected instruction count (26 instructions total)
        // 2 CSR init + 8 setup + 5 SLLI + 5 SRLI + 5 SRAI + 1 EBREAK
        uvm_config_db#(int)::set(this, "*", "expected_insn_min", 24);
        uvm_config_db#(int)::set(this, "*", "expected_insn_max", 28);
        
        // No LED writes in this test
        uvm_config_db#(int)::set(this, "*", "expected_led_value", 0);
        
        `uvm_info(get_type_name(), 
                  "Shift Immediate Test Configuration:\n  Expected Instructions: 24-28\n  Verifying: SLLI, SRLI, SRAI with 15 test cases", 
                  UVM_LOW)
    endfunction : build_phase
    
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), "Starting shift immediate test", UVM_LOW)
        
        // CRITICAL: Initialize CPU with reset sequence
        reset_sequence();
        
        // Start CPU execution
        start_cpu();
        
        // Wait for CPU to complete (EBREAK)
        wait_for_cpu_break(5000);
        
        // Allow final register writes to settle
        #500ns;
        
        // Verify all results
        verify_results();
        
        phase.drop_objection(this);
    endtask : run_phase
    
    task verify_results();
        logic [31:0] actual_val;
        int error_count = 0;
        
        `uvm_info(get_type_name(), "=== Verifying Shift Immediate Test Results ===", UVM_LOW)
        
        // ========== SLLI Tests (x1-x5) ==========
        `uvm_info(get_type_name(), "--- SLLI Tests (Shift Left Logical) ---", UVM_LOW)
        
        // Test 1: x1 = 1 << 0 = 0x00000001 (identity)
        actual_val = rv32i_tb_top.dut.u_id.regfile[1];
        if (actual_val == 32'h00000001) begin
            `uvm_info(get_type_name(), "x1 (SLLI identity, 1<<0): PASS - 0x00000001", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("x1 FAILED - Expected: 0x00000001, Got: 0x%08X", actual_val))
            error_count++;
        end
        
        // Test 2: x2 = 1 << 8 = 0x00000100 (byte shift)
        actual_val = rv32i_tb_top.dut.u_id.regfile[2];
        if (actual_val == 32'h00000100) begin
            `uvm_info(get_type_name(), "x2 (SLLI byte shift, 1<<8): PASS - 0x00000100", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("x2 FAILED - Expected: 0x00000100, Got: 0x%08X", actual_val))
            error_count++;
        end
        
        // Test 3: x3 = 1 << 31 = 0x80000000 (max shift)
        actual_val = rv32i_tb_top.dut.u_id.regfile[3];
        if (actual_val == 32'h80000000) begin
            `uvm_info(get_type_name(), "x3 (SLLI max shift, 1<<31): PASS - 0x80000000", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("x3 FAILED - Expected: 0x80000000, Got: 0x%08X", actual_val))
            error_count++;
        end
        
        // Test 4: x4 = 0x12345678 << 4 = 0x23456780 (overflow)
        actual_val = rv32i_tb_top.dut.u_id.regfile[4];
        if (actual_val == 32'h23456780) begin
            `uvm_info(get_type_name(), "x4 (SLLI overflow, 0x12345678<<4): PASS - 0x23456780", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("x4 FAILED - Expected: 0x23456780, Got: 0x%08X", actual_val))
            error_count++;
        end
        
        // Test 5: x5 = 0x7FFFFFFF << 1 = 0xFFFFFFFE (boundary)
        actual_val = rv32i_tb_top.dut.u_id.regfile[5];
        if (actual_val == 32'hFFFFFFFE) begin
            `uvm_info(get_type_name(), "x5 (SLLI boundary, 0x7FFFFFFF<<1): PASS - 0xFFFFFFFE", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("x5 FAILED - Expected: 0xFFFFFFFE, Got: 0x%08X", actual_val))
            error_count++;
        end
        
        // ========== SRLI Tests (x6-x10) ==========
        `uvm_info(get_type_name(), "--- SRLI Tests (Shift Right Logical - Zero-fill) ---", UVM_LOW)
        
        // Test 6: x6 = 0xFFFFFFFF >>u 1 = 0x7FFFFFFF
        actual_val = rv32i_tb_top.dut.u_id.regfile[6];
        if (actual_val == 32'h7FFFFFFF) begin
            `uvm_info(get_type_name(), "x6 (SRLI zero-fill, 0xFFFFFFFF>>u1): PASS - 0x7FFFFFFF", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("x6 FAILED - Expected: 0x7FFFFFFF, Got: 0x%08X", actual_val))
            error_count++;
        end
        
        // Test 7: x7 = 0x80000000 >>u 16 = 0x00008000 (CRITICAL: zero-fill on negative)
        actual_val = rv32i_tb_top.dut.u_id.regfile[7];
        if (actual_val == 32'h00008000) begin
            `uvm_info(get_type_name(), "x7 (SRLI CRITICAL, 0x80000000>>u16): PASS - 0x00008000 (zero-fill)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("x7 FAILED - Expected: 0x00008000 (zero-fill), Got: 0x%08X", actual_val))
            error_count++;
        end
        
        // Test 8: x8 = 0x12345678 >>u 4 = 0x01234567
        actual_val = rv32i_tb_top.dut.u_id.regfile[8];
        if (actual_val == 32'h01234567) begin
            `uvm_info(get_type_name(), "x8 (SRLI nibble, 0x12345678>>u4): PASS - 0x01234567", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("x8 FAILED - Expected: 0x01234567, Got: 0x%08X", actual_val))
            error_count++;
        end
        
        // Test 9: x9 = 0xFFFFFFFF >>u 31 = 0x00000001
        actual_val = rv32i_tb_top.dut.u_id.regfile[9];
        if (actual_val == 32'h00000001) begin
            `uvm_info(get_type_name(), "x9 (SRLI max shift, 0xFFFFFFFF>>u31): PASS - 0x00000001", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("x9 FAILED - Expected: 0x00000001, Got: 0x%08X", actual_val))
            error_count++;
        end
        
        // Test 10: x10 = 1 >>u 0 = 0x00000001 (identity)
        actual_val = rv32i_tb_top.dut.u_id.regfile[10];
        if (actual_val == 32'h00000001) begin
            `uvm_info(get_type_name(), "x10 (SRLI identity, 1>>u0): PASS - 0x00000001", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("x10 FAILED - Expected: 0x00000001, Got: 0x%08X", actual_val))
            error_count++;
        end
        
        // ========== SRAI Tests (x17-x21) ==========
        `uvm_info(get_type_name(), "--- SRAI Tests (Shift Right Arithmetic - Sign-extend) ---", UVM_LOW)
        
        // Test 11: x17 = 0x12345678 >>s 4 = 0x01234567 (positive, same as SRLI)
        actual_val = rv32i_tb_top.dut.u_id.regfile[17];
        if (actual_val == 32'h01234567) begin
            `uvm_info(get_type_name(), "x17 (SRAI positive, 0x12345678>>s4): PASS - 0x01234567", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("x17 FAILED - Expected: 0x01234567, Got: 0x%08X", actual_val))
            error_count++;
        end
        
        // Test 12: x18 = 0xFFFFFFFE >>s 1 = 0xFFFFFFFF (sign-extend -2 to -1)
        actual_val = rv32i_tb_top.dut.u_id.regfile[18];
        if (actual_val == 32'hFFFFFFFF) begin
            `uvm_info(get_type_name(), "x18 (SRAI sign-extend, -2>>s1): PASS - 0xFFFFFFFF", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("x18 FAILED - Expected: 0xFFFFFFFF, Got: 0x%08X", actual_val))
            error_count++;
        end
        
        // Test 13: x19 = 0x80000000 >>s 8 = 0xFF800000 (CRITICAL: sign-extend on negative)
        actual_val = rv32i_tb_top.dut.u_id.regfile[19];
        if (actual_val == 32'hFF800000) begin
            `uvm_info(get_type_name(), "x19 (SRAI CRITICAL, 0x80000000>>s8): PASS - 0xFF800000 (sign-extend)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("x19 FAILED - Expected: 0xFF800000 (sign-extend), Got: 0x%08X", actual_val))
            error_count++;
        end
        
        // Test 14: x20 = 0x80000000 >>s 31 = 0xFFFFFFFF (max shift to all ones)
        actual_val = rv32i_tb_top.dut.u_id.regfile[20];
        if (actual_val == 32'hFFFFFFFF) begin
            `uvm_info(get_type_name(), "x20 (SRAI max shift, 0x80000000>>s31): PASS - 0xFFFFFFFF", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("x20 FAILED - Expected: 0xFFFFFFFF, Got: 0x%08X", actual_val))
            error_count++;
        end
        
        // Test 15: x21 = 0x7FFFFFFF >>s 1 = 0x3FFFFFFF (positive preserved)
        actual_val = rv32i_tb_top.dut.u_id.regfile[21];
        if (actual_val == 32'h3FFFFFFF) begin
            `uvm_info(get_type_name(), "x21 (SRAI positive preserved, 0x7FFFFFFF>>s1): PASS - 0x3FFFFFFF", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("x21 FAILED - Expected: 0x3FFFFFFF, Got: 0x%08X", actual_val))
            error_count++;
        end
        
        // ========== Summary ==========
        if (error_count == 0) begin
            `uvm_info(get_type_name(), "=== TEST 1.4: SHIFT IMMEDIATE - PASS ===", UVM_LOW)
            `uvm_info(get_type_name(), "All 15 shift tests passed successfully!", UVM_LOW)
            `uvm_info(get_type_name(), "  SLLI: 5/5 PASS (left shift with overflow handling)", UVM_LOW)
            `uvm_info(get_type_name(), "  SRLI: 5/5 PASS (logical right shift with zero-fill)", UVM_LOW)
            `uvm_info(get_type_name(), "  SRAI: 5/5 PASS (arithmetic right shift with sign-extend)", UVM_LOW)
            `uvm_info(get_type_name(), "CRITICAL DISTINCTION VERIFIED:", UVM_LOW)
            `uvm_info(get_type_name(), "  x7 (SRLI): 0x80000000>>u16 = 0x00008000 (zero-fill)", UVM_LOW)
            `uvm_info(get_type_name(), "  x19 (SRAI): 0x80000000>>s8 = 0xFF800000 (sign-extend)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("=== TEST 1.4: SHIFT IMMEDIATE - FAILED ===\n  Errors: %0d/15", error_count))
        end
    endtask : verify_results
    
endclass : rv32i_shift_imm_test
