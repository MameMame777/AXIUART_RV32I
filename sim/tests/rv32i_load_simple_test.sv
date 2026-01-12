`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// RV32I LOAD Instruction Simple Test
//
// Tests all LOAD variants:
// - LW (Load Word)
// - LH (Load Halfword - sign extended)
// - LHU (Load Halfword Unsigned - zero extended)
// - LB (Load Byte - sign extended)
// - LBU (Load Byte Unsigned - zero extended)
// - Negative offset tests
// - Critical: Load-to-use hazard test
//
// Expected Results:
//   x16 = 0x12345678 (LW)
//   x17 = 0xFFFFCCDD (LH sign-extended)
//   x18 = 0x0000CCDD (LHU zero-extended)
//   x19 = 0x00000044 (LB positive)
//   x20 = 0x00000044 (LBU positive)
//   x21 = 0xFFFFFFCC (LB negative sign-extended)
//   x22 = 0x000000CC (LBU negative zero-extended)
//   x23 = 0xFFEEDDCC (LW negative offset)
//   x24 = 0x12345678 (hazard test load)
//   x25 = 0x2468ACF0 (hazard test: x24 + x24)
//   LED = 0x2468ACF0
//------------------------------------------------------------------------------

class rv32i_load_simple_test extends rv32i_base_test;
    `uvm_component_utils(rv32i_load_simple_test)
    
    function new(string name = "rv32i_load_simple_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Configure test-specific parameters
        uvm_config_db#(int)::set(this, "*", "expected_insn_min", 30);
        uvm_config_db#(int)::set(this, "*", "expected_insn_max", 50);
        uvm_config_db#(int)::set(this, "*", "expected_led_value", 32'h2468ACF0);
        
        `uvm_info(get_type_name(), 
                  "LOAD Simple Test Configuration:\n  Expected Instructions: 30-50\n  Expected LED: 0x2468ACF0", 
                  UVM_LOW)
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), "Starting LOAD instruction test", UVM_LOW)
        
        // CRITICAL: Reset sequence as required by user
        reset_sequence();
        
        // CRITICAL: Start CPU as required by user
        start_cpu();
        
        // Wait for CPU to complete execution
        wait_for_cpu_break(10000);
        
        // Allow time for final writes to propagate
        #500ns;
        
        // Verify all results
        verify_results();
        
        phase.drop_objection(this);
    endtask
    
    virtual task verify_results();
        logic [31:0] x16, x17, x18, x19, x20, x21, x22, x23, x24, x25;
        logic [31:0] led_value;
        int error_count = 0;
        
        `uvm_info(get_type_name(), "=== Verifying LOAD Test Results ===", UVM_LOW)
        
        // Read register values from DUT (regfile is in u_id module)
        x16 = rv32i_tb_top.dut.u_id.regfile[16];
        x17 = rv32i_tb_top.dut.u_id.regfile[17];
        x18 = rv32i_tb_top.dut.u_id.regfile[18];
        x19 = rv32i_tb_top.dut.u_id.regfile[19];
        x20 = rv32i_tb_top.dut.u_id.regfile[20];
        x21 = rv32i_tb_top.dut.u_id.regfile[21];
        x22 = rv32i_tb_top.dut.u_id.regfile[22];
        x23 = rv32i_tb_top.dut.u_id.regfile[23];
        x24 = rv32i_tb_top.dut.u_id.regfile[24];
        x25 = rv32i_tb_top.dut.u_id.regfile[25];
        led_value = rv32i_tb_top.tb_if.led_reg;
        
        // Check x16: LW test (Load Word)
        if (x16 !== 32'h12345678) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x16 (LW) mismatch: Expected=0x12345678, Actual=0x%08h", x16))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x16 (LW): PASS - 0x12345678", UVM_LOW)
        end
        
        // Check x17: LH test (Load Halfword sign-extended)
        if (x17 !== 32'hFFFFCCDD) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x17 (LH) mismatch: Expected=0xFFFFCCDD, Actual=0x%08h", x17))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x17 (LH sign-extended): PASS - 0xFFFFCCDD", UVM_LOW)
        end
        
        // Check x18: LHU test (Load Halfword Unsigned zero-extended)
        if (x18 !== 32'h0000CCDD) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x18 (LHU) mismatch: Expected=0x0000CCDD, Actual=0x%08h", x18))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x18 (LHU zero-extended): PASS - 0x0000CCDD", UVM_LOW)
        end
        
        // Check x19: LB test (Load Byte positive sign-extended)
        if (x19 !== 32'h00000044) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x19 (LB positive) mismatch: Expected=0x00000044, Actual=0x%08h", x19))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x19 (LB positive): PASS - 0x00000044", UVM_LOW)
        end
        
        // Check x20: LBU test (Load Byte Unsigned)
        if (x20 !== 32'h00000044) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x20 (LBU) mismatch: Expected=0x00000044, Actual=0x%08h", x20))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x20 (LBU): PASS - 0x00000044", UVM_LOW)
        end
        
        // Check x21: LB test (Load Byte negative sign-extended)
        if (x21 !== 32'hFFFFFFCC) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x21 (LB negative) mismatch: Expected=0xFFFFFFCC, Actual=0x%08h", x21))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x21 (LB negative sign-extended): PASS - 0xFFFFFFCC", UVM_LOW)
        end
        
        // Check x22: LBU test (Load Byte Unsigned negative)
        if (x22 !== 32'h000000CC) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x22 (LBU negative) mismatch: Expected=0x000000CC, Actual=0x%08h", x22))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x22 (LBU negative): PASS - 0x000000CC", UVM_LOW)
        end
        
        // Check x23: LW with negative offset
        if (x23 !== 32'hFFEEDDCC) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x23 (LW negative offset) mismatch: Expected=0xFFEEDDCC, Actual=0x%08h", x23))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x23 (LW negative offset): PASS - 0xFFEEDDCC", UVM_LOW)
        end
        
        // Check x24: Load-to-use hazard test (loaded value)
        if (x24 !== 32'h12345678) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x24 (hazard load) mismatch: Expected=0x12345678, Actual=0x%08h", x24))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x24 (hazard test load): PASS - 0x12345678", UVM_LOW)
        end
        
        // Check x25: Load-to-use hazard test (ADD result) - CRITICAL TEST
        if (x25 !== 32'h2468ACF0) begin
            `uvm_error(get_type_name(), 
                       $sformatf("x25 (hazard result) mismatch: Expected=0x2468ACF0, Actual=0x%08h\n" +
                                "*** LOAD-TO-USE HAZARD DETECTION FAILURE ***\n" +
                                "This indicates the hazard unit is not properly stalling the pipeline\n" +
                                "when a LOAD instruction is immediately followed by an instruction\n" +
                                "that uses the loaded value.", x25))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "x25 (hazard test result): PASS - 0x2468ACF0", UVM_LOW)
        end
        
        // Check LED register
        if (led_value !== 32'h2468ACF0) begin
            `uvm_error(get_type_name(), 
                       $sformatf("LED mismatch: Expected=0x2468ACF0, Actual=0x%08h", led_value))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "LED: PASS - 0x2468ACF0", UVM_LOW)
        end
        
        // Summary
        if (error_count == 0) begin
            `uvm_info(get_type_name(), 
                      {"=== ALL LOAD TESTS PASSED ===\n",
                       "  LW: PASS\n",
                       "  LH (sign-extended): PASS\n",
                       "  LHU (zero-extended): PASS\n",
                       "  LB (positive): PASS\n",
                       "  LBU: PASS\n",
                       "  LB (negative sign-extended): PASS\n",
                       "  LBU (negative): PASS\n",
                       "  LW (negative offset): PASS\n",
                       "  Load-to-use hazard: PASS\n",
                       "  LED: PASS"}, 
                      UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), 
                       $sformatf("=== LOAD TESTS FAILED: %0d errors ===", error_count))
        end
    endtask
    
endclass
