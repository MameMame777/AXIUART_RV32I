`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// Test 1.2: Upper Immediate Instructions Test
//
// Tests LUI and AUIPC instructions:
// - LUI: Load Upper Immediate (20-bit immediate to upper 20 bits)
// - AUIPC: Add Upper Immediate to PC (PC-relative addressing)
//
// Expected Results:
//   x1  = 0x12345000 (LUI 0x12345)
//   x2  = 0xABCDE000 (LUI 0xABCDE)
//   x3  = 0xFFFFF000 (LUI 0xFFFFF)
//   x4  = 0x00001014 (AUIPC at PC=0x14, offset=0x1000)
//   x5  = 0x7FFFF018 (AUIPC at PC=0x18, offset=0x7FFFF000)
//   x6  = 0x12345678 (LUI + ADDI combination)
//   x7  = 0x00000020 (AUIPC at PC=0x20, offset=0)
//   x8  = 0x00000010 (x7 - 0x10 via ADDI)
//   x9  = 0x00000000 (LUI 0x00000)
//   x10 = 0x0000002C (AUIPC at PC=0x2C, offset=0)
//------------------------------------------------------------------------------

class rv32i_upper_imm_test extends rv32i_base_test;
    `uvm_component_utils(rv32i_upper_imm_test)
    
    function new(string name = "rv32i_upper_imm_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Configure test-specific parameters
        uvm_config_db#(int)::set(this, "*", "expected_insn_min", 10);
        uvm_config_db#(int)::set(this, "*", "expected_insn_max", 20);
        
        `uvm_info(get_type_name(), 
                  "Upper Immediate Test Configuration:\n  Expected Instructions: 10-20", 
                  UVM_LOW)
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), "Starting upper immediate instruction test", UVM_LOW)
        
        // Reset and start CPU
        reset_sequence();
        start_cpu();
        
        // Wait for CPU to complete
        wait_for_cpu_break(5000);
        
        // Allow time for final writes
        #500ns;
        
        // Verify results
        verify_results();
        
        phase.drop_objection(this);
    endtask
    
    virtual task verify_results();
        logic [31:0] x1, x2, x3, x4, x5, x6, x7, x8, x9, x10;
        int error_count = 0;
        
        `uvm_info(get_type_name(), "=== Verifying Upper Immediate Test Results ===", UVM_LOW)
        
        // Read register values
        x1  = rv32i_tb_top.dut.u_id.regfile[1];
        x2  = rv32i_tb_top.dut.u_id.regfile[2];
        x3  = rv32i_tb_top.dut.u_id.regfile[3];
        x4  = rv32i_tb_top.dut.u_id.regfile[4];
        x5  = rv32i_tb_top.dut.u_id.regfile[5];
        x6  = rv32i_tb_top.dut.u_id.regfile[6];
        x7  = rv32i_tb_top.dut.u_id.regfile[7];
        x8  = rv32i_tb_top.dut.u_id.regfile[8];
        x9  = rv32i_tb_top.dut.u_id.regfile[9];
        x10 = rv32i_tb_top.dut.u_id.regfile[10];
        
        // Check x1: LUI 0x12345
        if (x1 !== 32'h12345000) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x1 (LUI 0x12345) mismatch: Expected=0x12345000, Actual=0x%08h", x1))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x1 (LUI 0x12345): PASS - 0x12345000", UVM_LOW)
        end
        
        // Check x2: LUI 0xABCDE
        if (x2 !== 32'hABCDE000) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x2 (LUI 0xABCDE) mismatch: Expected=0xABCDE000, Actual=0x%08h", x2))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x2 (LUI 0xABCDE): PASS - 0xABCDE000", UVM_LOW)
        end
        
        // Check x3: LUI 0xFFFFF
        if (x3 !== 32'hFFFFF000) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x3 (LUI 0xFFFFF) mismatch: Expected=0xFFFFF000, Actual=0x%08h", x3))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x3 (LUI 0xFFFFF): PASS - 0xFFFFF000", UVM_LOW)
        end
        
        // Check x4: AUIPC at PC=0x14
        if (x4 !== 32'h00001014) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x4 (AUIPC) mismatch: Expected=0x00001014, Actual=0x%08h", x4))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x4 (AUIPC): PASS - 0x00001014", UVM_LOW)
        end
        
        // Check x5: AUIPC at PC=0x18
        if (x5 !== 32'h7FFFF018) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x5 (AUIPC large offset) mismatch: Expected=0x7FFFF018, Actual=0x%08h", x5))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x5 (AUIPC large offset): PASS - 0x7FFFF018", UVM_LOW)
        end
        
        // Check x6: LUI + ADDI combination
        if (x6 !== 32'h12345678) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x6 (LUI+ADDI) mismatch: Expected=0x12345678, Actual=0x%08h", x6))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x6 (LUI+ADDI combination): PASS - 0x12345678", UVM_LOW)
        end
        
        // Check x7: AUIPC at PC=0x20
        if (x7 !== 32'h00000020) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x7 (AUIPC zero offset) mismatch: Expected=0x00000020, Actual=0x%08h", x7))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x7 (AUIPC zero offset): PASS - 0x00000020", UVM_LOW)
        end
        
        // Check x8: PC-relative calculation
        if (x8 !== 32'h00000010) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x8 (PC-relative calc) mismatch: Expected=0x00000010, Actual=0x%08h", x8))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x8 (PC-relative calc): PASS - 0x00000010", UVM_LOW)
        end
        
        // Check x9: LUI 0
        if (x9 !== 32'h00000000) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x9 (LUI 0) mismatch: Expected=0x00000000, Actual=0x%08h", x9))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x9 (LUI 0): PASS - 0x00000000", UVM_LOW)
        end
        
        // Check x10: AUIPC at PC=0x2C
        if (x10 !== 32'h0000002C) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x10 (AUIPC at PC=0x2C) mismatch: Expected=0x0000002C, Actual=0x%08h", x10))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x10 (AUIPC at PC=0x2C): PASS - 0x0000002C", UVM_LOW)
        end
        
        // Summary
        if (error_count == 0) begin
            `uvm_info(get_type_name(), "=== TEST 1.2: UPPER IMMEDIATE - PASS ===", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), 
                       $sformatf("=== UPPER IMMEDIATE TESTS FAILED: %0d errors ===", error_count))
        end
    endtask
    
endclass
