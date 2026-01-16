`timescale 1ns / 1ps

class rv32i_reg_alu_test extends rv32i_base_test;
    `uvm_component_utils(rv32i_reg_alu_test)

    function new(string name = "rv32i_reg_alu_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Configure hex file for Test 2.1
        uvm_config_db#(string)::set(this, "*", "hex_file", 
            "e:/Nautilus/workspace/fpgawork/AXIUART_RV32I/sim/tests/rv32i_reg_alu_test.hex");
        
        // Expected instruction count: 2 CSR + 12 setup + 26 tests + 1 EBREAK = 41
        // Allow ±4 tolerance
        uvm_config_db#(int)::set(this, "*", "expected_insn_min", 37);
        uvm_config_db#(int)::set(this, "*", "expected_insn_max", 45);
        
        // Expected LED value (no LED activity)
        uvm_config_db#(int)::set(this, "*", "expected_led_value", 0);
        
        `uvm_info(get_type_name(), "Test 2.1: R-Type Register ALU Operations (ADD/SUB/SLT/SLTU/XOR/OR/AND)", UVM_LOW)
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), "=== Starting R-Type Register ALU Test ===", UVM_LOW)
        
        // Apply reset sequence (CRITICAL: User requested)
        reset_sequence();
        
        // Start CPU execution
        start_cpu();
        
        // Wait for CPU to hit EBREAK
        wait_for_cpu_break(10000);
        
        // Allow final register writes to settle
        #500ns;
        
        // Verify register contents
        verify_results();
        
        `uvm_info(get_type_name(), "=== R-Type Register ALU Test Complete ===", UVM_LOW)
        
        phase.drop_objection(this);
    endtask

    virtual function void verify_results();
        int errors = 0;
        logic [31:0] reg_val;
        
        `uvm_info(get_type_name(), "Verifying register results...", UVM_LOW)
        
        // ========== ADD Tests (Final values x1-x5) ==========
        `uvm_info(get_type_name(), "--- ADD Tests ---", UVM_LOW)
        
        // x1: After ADD then OR overwrite = 0xFFFFFFFF
        read_register(1, reg_val);
        if (reg_val !== 32'hFFFFFFFF) begin
            `uvm_error(get_type_name(), 
                $sformatf("x1 FAILED - Expected: 0xFFFFFFFF (OR overwrite), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x1 = 0xFFFFFFFF (OR: 0xFFFFFFFF | 0) PASS", UVM_LOW)
        end
        
        // x2: After ADD then OR overwrite = 0x00000064 (100)
        read_register(2, reg_val);
        if (reg_val !== 32'h00000064) begin
            `uvm_error(get_type_name(), 
                $sformatf("x2 FAILED - Expected: 0x00000064 (OR overwrite), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x2 = 0x00000064 (OR: 100 | 100) PASS", UVM_LOW)
        end
        
        // x3: After ADD then OR overwrite = 0x000000FF
        read_register(3, reg_val);
        if (reg_val !== 32'h000000FF) begin
            `uvm_error(get_type_name(), 
                $sformatf("x3 FAILED - Expected: 0x000000FF (OR overwrite), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x3 = 0x000000FF (OR: 0xF0 | 0x0F) PASS", UVM_LOW)
        end
        
        // x4: After ADD then AND overwrite = 0x00000000
        read_register(4, reg_val);
        if (reg_val !== 32'h00000000) begin
            `uvm_error(get_type_name(), 
                $sformatf("x4 FAILED - Expected: 0x00000000 (AND overwrite), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x4 = 0x00000000 (AND: 0xFFFFFFFF & 0) PASS", UVM_LOW)
        end
        
        // x5: After ADD then AND overwrite = 0x00000064 (100)
        read_register(5, reg_val);
        if (reg_val !== 32'h00000064) begin
            `uvm_error(get_type_name(), 
                $sformatf("x5 FAILED - Expected: 0x00000064 (AND overwrite), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x5 = 0x00000064 (AND: 100 & 100) PASS", UVM_LOW)
        end
        
        // ========== SUB Tests (Final values x6-x10) ==========
        `uvm_info(get_type_name(), "--- SUB Tests ---", UVM_LOW)
        
        // x6: After SUB then AND overwrite = 0x00000000
        read_register(6, reg_val);
        if (reg_val !== 32'h00000000) begin
            `uvm_error(get_type_name(), 
                $sformatf("x6 FAILED - Expected: 0x00000000 (AND overwrite), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x6 = 0x00000000 (AND: 0xF0 & 0x0F) PASS", UVM_LOW)
        end
        
        // x7: SUB result (not overwritten) = 0xFFFFFFCE (-50)
        read_register(7, reg_val);
        if (reg_val !== 32'hFFFFFFCE) begin
            `uvm_error(get_type_name(), 
                $sformatf("x7 FAILED - Expected: 0xFFFFFFCE (50 - 100 = -50), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x7 = 0xFFFFFFCE (SUB: 50 - 100 = -50) PASS", UVM_LOW)
        end
        
        // x8: SUB result = 0xFFFFFFFF (0 - 1 = -1)
        read_register(8, reg_val);
        if (reg_val !== 32'hFFFFFFFF) begin
            `uvm_error(get_type_name(), 
                $sformatf("x8 FAILED - Expected: 0xFFFFFFFF (0 - 1 = -1), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x8 = 0xFFFFFFFF (SUB: 0 - 1 = -1) PASS", UVM_LOW)
        end
        
        // x9: SUB result = 0x00000000 (100 - 100 = 0)
        read_register(9, reg_val);
        if (reg_val !== 32'h00000000) begin
            `uvm_error(get_type_name(), 
                $sformatf("x9 FAILED - Expected: 0x00000000 (100 - 100 = 0), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x9 = 0x00000000 (SUB: 100 - 100 = 0) PASS", UVM_LOW)
        end
        
        // x10: SUB result = 0x7FFFFFFF (0x80000000 - 1, underflow)
        read_register(10, reg_val);
        if (reg_val !== 32'h7FFFFFFF) begin
            `uvm_error(get_type_name(), 
                $sformatf("x10 FAILED - Expected: 0x7FFFFFFF (SUB underflow), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x10 = 0x7FFFFFFF (SUB: 0x80000000 - 1, underflow) PASS", UVM_LOW)
        end
        
        // ========== SLT Tests (x21-x23) ==========
        `uvm_info(get_type_name(), "--- SLT Tests (Signed) ---", UVM_LOW)
        
        // x21: SLT result = 1 (50 < 100)
        read_register(21, reg_val);
        if (reg_val !== 32'h00000001) begin
            `uvm_error(get_type_name(), 
                $sformatf("x21 FAILED - Expected: 0x00000001 (50 < 100), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x21 = 0x00000001 (SLT: 50 < 100) PASS", UVM_LOW)
        end
        
        // x22: SLT result = 0 (100 < -10 signed is false)
        read_register(22, reg_val);
        if (reg_val !== 32'h00000000) begin
            `uvm_error(get_type_name(), 
                $sformatf("x22 FAILED - Expected: 0x00000000 (100 < -10 signed is false), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x22 = 0x00000000 (SLT: 100 < -10 signed is false) PASS", UVM_LOW)
        end
        
        // x23: SLT result = 1 (-10 < 0)
        read_register(23, reg_val);
        if (reg_val !== 32'h00000001) begin
            `uvm_error(get_type_name(), 
                $sformatf("x23 FAILED - Expected: 0x00000001 (-10 < 0), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x23 = 0x00000001 (SLT: -10 < 0) PASS", UVM_LOW)
        end
        
        // ========== SLTU Tests (x24-x26) ==========
        `uvm_info(get_type_name(), "--- SLTU Tests (Unsigned) ---", UVM_LOW)
        
        // x24: SLTU result = 1 (50 <u 100)
        read_register(24, reg_val);
        if (reg_val !== 32'h00000001) begin
            `uvm_error(get_type_name(), 
                $sformatf("x24 FAILED - Expected: 0x00000001 (50 <u 100), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x24 = 0x00000001 (SLTU: 50 <u 100) PASS", UVM_LOW)
        end
        
        // x25: SLTU result = 0 (0xFFFFFFF6 <u 100 is false)
        read_register(25, reg_val);
        if (reg_val !== 32'h00000000) begin
            `uvm_error(get_type_name(), 
                $sformatf("x25 FAILED - Expected: 0x00000000 (0xFFFFFFF6 <u 100 is false), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x25 = 0x00000000 (SLTU: -10 <u 100 is false) PASS", UVM_LOW)
        end
        
        // x26: SLTU result = 1 (0 <u 1)
        read_register(26, reg_val);
        if (reg_val !== 32'h00000001) begin
            `uvm_error(get_type_name(), 
                $sformatf("x26 FAILED - Expected: 0x00000001 (0 <u 1), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x26 = 0x00000001 (SLTU: 0 <u 1) PASS", UVM_LOW)
        end
        
        // ========== XOR Tests (x27-x30) ==========
        `uvm_info(get_type_name(), "--- XOR Tests ---", UVM_LOW)
        
        // x27: XOR result = 0xFFFFFFFF (0xFFFFFFFF ^ 0)
        read_register(27, reg_val);
        if (reg_val !== 32'hFFFFFFFF) begin
            `uvm_error(get_type_name(), 
                $sformatf("x27 FAILED - Expected: 0xFFFFFFFF (XOR identity), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x27 = 0xFFFFFFFF (XOR: 0xFFFFFFFF ^ 0) PASS", UVM_LOW)
        end
        
        // x28: XOR result = 0 (100 ^ 100)
        read_register(28, reg_val);
        if (reg_val !== 32'h00000000) begin
            `uvm_error(get_type_name(), 
                $sformatf("x28 FAILED - Expected: 0x00000000 (XOR self = 0), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x28 = 0x00000000 (XOR: 100 ^ 100) PASS", UVM_LOW)
        end
        
        // x29: XOR result = 0xFF (0xF0 ^ 0x0F)
        read_register(29, reg_val);
        if (reg_val !== 32'h000000FF) begin
            `uvm_error(get_type_name(), 
                $sformatf("x29 FAILED - Expected: 0x000000FF (XOR mask merge), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x29 = 0x000000FF (XOR: 0xF0 ^ 0x0F) PASS", UVM_LOW)
        end
        
        // x30: XOR result = 0xFFFFFFFE (0xFFFFFFFF ^ 1)
        read_register(30, reg_val);
        if (reg_val !== 32'hFFFFFFFE) begin
            `uvm_error(get_type_name(), 
                $sformatf("x30 FAILED - Expected: 0xFFFFFFFE (XOR toggle), Got: 0x%08X", reg_val))
            errors++;
        end else begin
            `uvm_info(get_type_name(), "x30 = 0xFFFFFFFE (XOR: 0xFFFFFFFF ^ 1) PASS", UVM_LOW)
        end
        
        // ========== Summary ==========
        if (errors == 0) begin
            `uvm_info(get_type_name(), 
                "*** ALL 21 REGISTER VERIFICATIONS PASSED ***", UVM_LOW)
            `uvm_info(get_type_name(), 
                "R-type ALU operations (ADD/SUB/SLT/SLTU/XOR/OR/AND) working correctly", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("*** %0d REGISTER VERIFICATION(S) FAILED ***", errors))
        end
    endfunction

endclass
