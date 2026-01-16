`timescale 1ns / 1ps

class rv32i_reg_shift_test extends rv32i_base_test;
    `uvm_component_utils(rv32i_reg_shift_test)

    function new(string name = "rv32i_reg_shift_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Configure hex file for Test 2.3
        uvm_config_db#(string)::set(this, "*", "hex_file", 
            "e:/Nautilus/workspace/fpgawork/AXIUART_RV32I/sim/tests/rv32i_reg_shift_test.hex");
        
        // Expected instruction count: 2 CSR + 14 setup + 18 tests + 1 EBREAK = 35
        // Allow ±4 tolerance
        uvm_config_db#(int)::set(this, "*", "expected_insn_min", 31);
        uvm_config_db#(int)::set(this, "*", "expected_insn_max", 39);
        
        // Expected LED value (no LED activity)
        uvm_config_db#(int)::set(this, "*", "expected_led_value", 0);
        
        `uvm_info(get_type_name(), "Test 2.3: R-Type Register Shift Operations (SLL/SRL/SRA)", UVM_LOW)
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), "=== Starting R-Type Register Shift Test ===", UVM_LOW)
        
        // Apply reset sequence
        reset_sequence();
        
        // Start CPU execution
        start_cpu();
        
        // Wait for CPU to hit EBREAK
        wait_for_cpu_break(10000);
        
        // Allow final register writes to settle
        #500ns;
        
        // Verify register contents
        verify_results();
        
        `uvm_info(get_type_name(), "=== R-Type Register Shift Test Complete ===", UVM_LOW)
        
        phase.drop_objection(this);
    endtask

    virtual function void verify_results();
        int errors = 0;
        logic [31:0] reg_val;
        
        `uvm_info(get_type_name(), "Verifying register results...", UVM_LOW)
        
        // ========== SLL Tests (x1-x6) ==========
        `uvm_info(get_type_name(), "--- SLL Tests (Shift Left Logical) ---", UVM_LOW)
        
        // x1: Identity (1 << 0 = 1)
        read_register(1, reg_val);
        if (reg_val !== 32'h00000001) begin
            `uvm_error(get_type_name(), 
                $sformatf("x1 FAILED - Expected: 0x00000001 (identity), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x1 = 0x00000001 (SLL: 1 << 0, identity) PASS", UVM_LOW)
        end
        
        // x2: Shift by 1
        read_register(2, reg_val);
        if (reg_val !== 32'h00000002) begin
            `uvm_error(get_type_name(), 
                $sformatf("x2 FAILED - Expected: 0x00000002 (1 << 1), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x2 = 0x00000002 (SLL: 1 << 1) PASS", UVM_LOW)
        end
        
        // x3: Byte shift
        read_register(3, reg_val);
        if (reg_val !== 32'h00000100) begin
            `uvm_error(get_type_name(), 
                $sformatf("x3 FAILED - Expected: 0x00000100 (1 << 8), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x3 = 0x00000100 (SLL: 1 << 8) PASS", UVM_LOW)
        end
        
        // x4: Max shift
        read_register(4, reg_val);
        if (reg_val !== 32'h80000000) begin
            `uvm_error(get_type_name(), 
                $sformatf("x4 FAILED - Expected: 0x80000000 (1 << 31), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x4 = 0x80000000 (SLL: 1 << 31, max shift) PASS", UVM_LOW)
        end
        
        // x5: Overflow
        read_register(5, reg_val);
        if (reg_val !== 32'h23456780) begin
            `uvm_error(get_type_name(), 
                $sformatf("x5 FAILED - Expected: 0x23456780 (overflow), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x5 = 0x23456780 (SLL: complex overflow) PASS", UVM_LOW)
        end
        
        // x6: Shift amount masking (32 & 0x1F = 0)
        read_register(6, reg_val);
        if (reg_val !== 32'h00000001) begin
            `uvm_error(get_type_name(), 
                $sformatf("x6 FAILED - Expected: 0x00000001 (masked), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x6 = 0x00000001 (SLL: shift amount masked) PASS", UVM_LOW)
        end
        
        // ========== SRL Tests (x7-x10, x15-x16) ==========
        `uvm_info(get_type_name(), "--- SRL Tests (Shift Right Logical - Zero-fill) ---", UVM_LOW)
        
        // x7: Zero-fill from all ones
        read_register(7, reg_val);
        if (reg_val !== 32'h7FFFFFFF) begin
            `uvm_error(get_type_name(), 
                $sformatf("x7 FAILED - Expected: 0x7FFFFFFF (zero-fill), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x7 = 0x7FFFFFFF (SRL: 0xFFFFFFFF >> 1, zero-fill) PASS", UVM_LOW)
        end
        
        // x8: CRITICAL - Zero-fill on sign bit
        read_register(8, reg_val);
        if (reg_val !== 32'h00008000) begin
            `uvm_error(get_type_name(), 
                $sformatf("x8 FAILED - Expected: 0x00008000 (CRITICAL zero-fill), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x8 = 0x00008000 (SRL: 0x80000000 >> 16, CRITICAL zero-fill) PASS", UVM_LOW)
        end
        
        // x9: Complex pattern
        read_register(9, reg_val);
        if (reg_val !== 32'h01234567) begin
            `uvm_error(get_type_name(), 
                $sformatf("x9 FAILED - Expected: 0x01234567, Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x9 = 0x01234567 (SRL: complex pattern) PASS", UVM_LOW)
        end
        
        // x10: Max shift
        read_register(10, reg_val);
        if (reg_val !== 32'h00000001) begin
            `uvm_error(get_type_name(), 
                $sformatf("x10 FAILED - Expected: 0x00000001 (max shift), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x10 = 0x00000001 (SRL: max shift) PASS", UVM_LOW)
        end
        
        // x15: Identity
        read_register(15, reg_val);
        if (reg_val !== 32'h00000001) begin
            `uvm_error(get_type_name(), 
                $sformatf("x15 FAILED - Expected: 0x00000001 (identity), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x15 = 0x00000001 (SRL: identity) PASS", UVM_LOW)
        end
        
        // x16: Shift amount masking
        read_register(16, reg_val);
        if (reg_val !== 32'hFFFFFFFF) begin
            `uvm_error(get_type_name(), 
                $sformatf("x16 FAILED - Expected: 0xFFFFFFFF (masked), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x16 = 0xFFFFFFFF (SRL: shift amount masked) PASS", UVM_LOW)
        end
        
        // ========== SRA Tests (x17-x22) ==========
        `uvm_info(get_type_name(), "--- SRA Tests (Shift Right Arithmetic - Sign-extend) ---", UVM_LOW)
        
        // x17: Positive (same as SRL)
        read_register(17, reg_val);
        if (reg_val !== 32'h01234567) begin
            `uvm_error(get_type_name(), 
                $sformatf("x17 FAILED - Expected: 0x01234567 (positive), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x17 = 0x01234567 (SRA: positive, same as SRL) PASS", UVM_LOW)
        end
        
        // x18: Sign-extend -1
        read_register(18, reg_val);
        if (reg_val !== 32'hFFFFFFFF) begin
            `uvm_error(get_type_name(), 
                $sformatf("x18 FAILED - Expected: 0xFFFFFFFF (sign-extend), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x18 = 0xFFFFFFFF (SRA: -1 >> 1, sign-extend) PASS", UVM_LOW)
        end
        
        // x19: CRITICAL - Sign-extend on sign bit
        read_register(19, reg_val);
        if (reg_val !== 32'hFFFF8000) begin
            `uvm_error(get_type_name(), 
                $sformatf("x19 FAILED - Expected: 0xFFFF8000 (CRITICAL sign-extend), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x19 = 0xFFFF8000 (SRA: 0x80000000 >> 16, CRITICAL sign-extend) PASS", UVM_LOW)
        end
        
        // x20: Partial sign-extend
        read_register(20, reg_val);
        if (reg_val !== 32'hFF800000) begin
            `uvm_error(get_type_name(), 
                $sformatf("x20 FAILED - Expected: 0xFF800000, Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x20 = 0xFF800000 (SRA: 0x80000000 >> 8) PASS", UVM_LOW)
        end
        
        // x21: Max shift (all ones)
        read_register(21, reg_val);
        if (reg_val !== 32'hFFFFFFFF) begin
            `uvm_error(get_type_name(), 
                $sformatf("x21 FAILED - Expected: 0xFFFFFFFF (max shift), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x21 = 0xFFFFFFFF (SRA: max shift to all ones) PASS", UVM_LOW)
        end
        
        // x22: Identity
        read_register(22, reg_val);
        if (reg_val !== 32'h12345678) begin
            `uvm_error(get_type_name(), 
                $sformatf("x22 FAILED - Expected: 0x12345678 (identity), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x22 = 0x12345678 (SRA: identity) PASS", UVM_LOW)
        end
        
        // ========== Summary ==========
        if (errors == 0) begin
            `uvm_info(get_type_name(), 
                "*** ALL 18 REGISTER VERIFICATIONS PASSED ***", UVM_LOW)
            `uvm_info(get_type_name(), 
                "R-type shift operations (SLL/SRL/SRA) working correctly", UVM_LOW)
            `uvm_info(get_type_name(), 
                "CRITICAL: SRL/SRA distinction verified (x8 vs x19)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("*** %0d REGISTER VERIFICATION(S) FAILED ***", errors))
        end
    endfunction

endclass
