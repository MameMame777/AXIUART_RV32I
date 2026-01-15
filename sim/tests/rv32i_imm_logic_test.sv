//-----------------------------------------------------------------------------
// File: rv32i_imm_logic_test.sv
// Description: Test 1.3 - Immediate Arithmetic/Logic Instructions
//              Tests SLTI, SLTIU, XORI, ORI, ANDI
// Date: 2026-01-16
//-----------------------------------------------------------------------------

`include "uvm_macros.svh"

class rv32i_imm_logic_test extends rv32i_base_test;
    
    `uvm_component_utils(rv32i_imm_logic_test)
    
    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "rv32i_imm_logic_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new
    
    //-------------------------------------------------------------------------
    // Build Phase
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Configure expected instruction count (16 instructions total)
        // 2 CSR init + 3 setup + 10 test + 1 EBREAK
        uvm_config_db#(int)::set(this, "*", "expected_insn_min", 14);
        uvm_config_db#(int)::set(this, "*", "expected_insn_max", 18);
        
        // No LED writes in this test
        uvm_config_db#(int)::set(this, "*", "expected_led_value", 0);
        
        `uvm_info(get_type_name(), 
                  "Immediate Arithmetic/Logic Test Configuration:\n  Expected Instructions: 14-18", 
                  UVM_LOW)
    endfunction : build_phase
    
    //-------------------------------------------------------------------------
    // Run Phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), "Starting immediate arithmetic/logic test", UVM_LOW)
        
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
    endtask : run_phase
    
    //-------------------------------------------------------------------------
    // Verify Test Results
    //-------------------------------------------------------------------------
    task verify_results();
        logic [31:0] x1, x2, x3, x4, x5, x6, x7, x8, x9, x10;
        
        `uvm_info(get_type_name(), "=== Verifying Immediate Arithmetic/Logic Test Results ===", UVM_LOW)
        
        // Read register values from interface
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
        
        // Check x1: SLTI (10 < 20) = 1
        if (x1 !== 32'h00000001) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x1 (SLTI 10 < 20) mismatch: got 0x%08X, expected 0x00000001", x1))
        end else begin
            `uvm_info(get_type_name(), "x1 (SLTI 10 < 20): PASS - 0x00000001", UVM_LOW)
        end
        
        // Check x2: SLTI (10 < -5) = 0 (signed comparison)
        if (x2 !== 32'h00000000) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x2 (SLTI 10 < -5) mismatch: got 0x%08X, expected 0x00000000", x2))
        end else begin
            `uvm_info(get_type_name(), "x2 (SLTI 10 < -5, signed): PASS - 0x00000000", UVM_LOW)
        end
        
        // Check x3: SLTI (-5 < 0) = 1
        if (x3 !== 32'h00000001) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x3 (SLTI -5 < 0) mismatch: got 0x%08X, expected 0x00000001", x3))
        end else begin
            `uvm_info(get_type_name(), "x3 (SLTI -5 < 0): PASS - 0x00000001", UVM_LOW)
        end
        
        // Check x4: SLTIU (10 < 20) = 1
        if (x4 !== 32'h00000001) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x4 (SLTIU 10 < 20) mismatch: got 0x%08X, expected 0x00000001", x4))
        end else begin
            `uvm_info(get_type_name(), "x4 (SLTIU 10 < 20): PASS - 0x00000001", UVM_LOW)
        end
        
        // Check x5: SLTIU (10 < 0xFFFFFFFF) = 1 (unsigned)
        if (x5 !== 32'h00000001) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x5 (SLTIU unsigned) mismatch: got 0x%08X, expected 0x00000001", x5))
        end else begin
            `uvm_info(get_type_name(), "x5 (SLTIU 10 < 0xFFFFFFFF): PASS - 0x00000001", UVM_LOW)
        end
        
        // Check x6: XORI (0x0F0 ^ 0x0FF) = 0x00F
        if (x6 !== 32'h0000000F) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x6 (XORI) mismatch: got 0x%08X, expected 0x0000000F", x6))
        end else begin
            `uvm_info(get_type_name(), "x6 (XORI 0x0F0 ^ 0x0FF): PASS - 0x0000000F", UVM_LOW)
        end
        
        // Check x7: XORI (0x0F0 ^ -1) = 0xFFFFFF0F (bitwise NOT)
        if (x7 !== 32'hFFFFFF0F) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x7 (XORI NOT) mismatch: got 0x%08X, expected 0xFFFFFF0F", x7))
        end else begin
            `uvm_info(get_type_name(), "x7 (XORI bitwise NOT): PASS - 0xFFFFFF0F", UVM_LOW)
        end
        
        // Check x8: ORI (0x0F0 | 0x00F) = 0x0FF
        if (x8 !== 32'h000000FF) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x8 (ORI) mismatch: got 0x%08X, expected 0x000000FF", x8))
        end else begin
            `uvm_info(get_type_name(), "x8 (ORI 0x0F0 | 0x00F): PASS - 0x000000FF", UVM_LOW)
        end
        
        // Check x9: ANDI (0x0F0 & 0x0F0) = 0x0F0
        if (x9 !== 32'h000000F0) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x9 (ANDI) mismatch: got 0x%08X, expected 0x000000F0", x9))
        end else begin
            `uvm_info(get_type_name(), "x9 (ANDI 0x0F0 & 0x0F0): PASS - 0x000000F0", UVM_LOW)
        end
        
        // Check x10: ANDI (0x0F0 & 0x00F) = 0x000
        if (x10 !== 32'h00000000) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x10 (ANDI mask) mismatch: got 0x%08X, expected 0x00000000", x10))
        end else begin
            `uvm_info(get_type_name(), "x10 (ANDI 0x0F0 & 0x00F): PASS - 0x00000000", UVM_LOW)
        end
        
        `uvm_info(get_type_name(), "=== TEST 1.3: IMMEDIATE ARITHMETIC/LOGIC - PASS ===", UVM_LOW)
        
    endtask : verify_results
    
endclass : rv32i_imm_logic_test

