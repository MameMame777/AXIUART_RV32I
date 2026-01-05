`timescale 1ns / 1ps

//==============================================================================
// RV32I WB Forwarding Timing Test
//==============================================================================
// CRITICAL: Verifies the wb_result_fwd registered signal fix (2026/1/5)
//
// This test validates the timing fix documented in docs/cpu/06_wb_stage.md:
// - Initial bug: wb_result combinational signal changed when WB advanced
// - Fix: wb_result_fwd registered to hold previous cycle's value
//
// Test Scenario (Original Bug Case):
//   Cycle N:   ADDI x27, x0, 7    in WB → wb_result = 0x7
//   Cycle N+1: LUI  x15, 0x4000   in WB → wb_result = 0x4000000
//              SW   x27, 0(x15)   in EX → needs x27 forwarding
//
// Expected (After Fix):
//   EX stage receives wb_result_fwd = 0x7 (correct)
//
// Bug (Before Fix):
//   EX stage receives wb_result = 0x4000000 (wrong - stale data)
//
// Test Program:
//   0x0000: ADDI x27, x0, 7         # x27 = 7
//   0x0004: LUI  x15, 0x4000        # x15 = 0x40000000
//   0x0008: SW   x27, 0x7C(x15)     # mem[0x4000007C] = x27 (LED register)
//   0x000C: ADDI x1, x0, 0xAA       # Marker: x1 = 0xAA
//   0x0010: EBREAK                  # Halt
//
// Verification Points:
//   1. x27 = 0x00000007 (ADDI result preserved)
//   2. x15 = 0x40000000 (LUI result)
//   3. LED output = 0x7 (SW used correct x27 value via wb_result_fwd)
//   4. x1 = 0xAA (execution continued correctly)
//
// Author: GitHub Copilot
// Date: 2026-01-05
//==============================================================================

class rv32i_wb_forward_timing_test extends rv32i_base_test;
    
    `uvm_component_utils(rv32i_wb_forward_timing_test)
    
    function new(string name = "rv32i_wb_forward_timing_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Configure scoreboard expectations for this specific test
        // This test has 5 instructions but pipeline overhead causes 9 WB cycles
        // Allow 5-12 to account for pipeline flush, bubbles, and debug overhead
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_insn_min", 5);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_insn_max", 12);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_led_value", 32'h7);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_ebreak_count", 1);
        
        `uvm_info("WB_FORWARD_TIMING", "WB forwarding timing test configured (5-12 instructions expected)", UVM_MEDIUM)
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info("WB_FORWARD_TIMING", "========================================", UVM_LOW)
        `uvm_info("WB_FORWARD_TIMING", "Starting WB Forwarding Timing Test", UVM_LOW)
        `uvm_info("WB_FORWARD_TIMING", "Verifying wb_result_fwd fix (2026/1/5)", UVM_LOW)
        `uvm_info("WB_FORWARD_TIMING", "========================================", UVM_LOW)
        
        // Reset CPU first (following standard test pattern)
        reset_sequence();
        halt_cpu();
        
        // Load test program
        load_wb_forward_program();
        
        // Start CPU
        `uvm_info("WB_FORWARD_TIMING", "Starting CPU execution", UVM_MEDIUM)
        start_cpu();
        
        // Wait for CPU to complete (EBREAK)
        wait_for_cpu_break(3000);
        
        // Halt CPU to read final state
        halt_cpu();
        #100ns;
        
        // Verify results
        verify_wb_forward_results();
        
        // Verify timing behavior through trace buffer
        verify_trace_timing();
        
        #1000ns;
        
        `uvm_info("WB_FORWARD_TIMING", "========================================", UVM_LOW)
        `uvm_info("WB_FORWARD_TIMING", "WB Forwarding Timing Test Complete", UVM_LOW)
        `uvm_info("WB_FORWARD_TIMING", "========================================", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
    
    //--------------------------------------------------------------------------
    // Load Test Program
    //--------------------------------------------------------------------------
    
    virtual task load_wb_forward_program();
        `uvm_info("WB_FORWARD_TIMING", "Loading WB forwarding test program", UVM_MEDIUM)
        
        // Test program:
        // 0x0000: ADDI x27, x0, 7         # x27 = 7 (0x00700D93)
        // 0x0004: LUI  x15, 0x4           # x15 = 0x00004000 (0x000047B7)
        // 0x0008: SW   x27, 0x7C(x15)     # mem[0x0000407C] = x27 (LED address) (0x07B7AE23)
        // 0x000C: ADDI x1, x0, 0xAA       # x1 = 0xAA (0x0AA00093)
        // 0x0010: EBREAK                  # Halt (0x00100073)
        
        write_debug_mem(11'h000, 32'h00700D93); // ADDI x27, x0, 7
        write_debug_mem(11'h001, 32'h000047B7); // LUI  x15, 0x4 → x15 = 0x00004000
        write_debug_mem(11'h002, 32'h07B7AE23); // SW   x27, 0x7C(x15) → LED[0x407C] = x27
        write_debug_mem(11'h003, 32'h0AA00093); // ADDI x1, x0, 0xAA
        write_debug_mem(11'h004, 32'h00100073); // EBREAK
        
        `uvm_info("WB_FORWARD_TIMING", "Program loaded:", UVM_MEDIUM)
        `uvm_info("WB_FORWARD_TIMING", "  0x0000: ADDI x27, x0, 7", UVM_MEDIUM)
        `uvm_info("WB_FORWARD_TIMING", "  0x0004: LUI  x15, 0x4 (x15 = 0x4000)", UVM_MEDIUM)
        `uvm_info("WB_FORWARD_TIMING", "  0x0008: SW   x27, 0x7C(x15)  <- Store to LED (0x407C)", UVM_MEDIUM)
        `uvm_info("WB_FORWARD_TIMING", "  0x000C: ADDI x1, x0, 0xAA", UVM_MEDIUM)
        `uvm_info("WB_FORWARD_TIMING", "  0x0010: EBREAK", UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Verify WB Forwarding Results
    //--------------------------------------------------------------------------
    
    virtual task verify_wb_forward_results();
        bit [31:0] x27_value, x15_value, x1_value;
        bit [31:0] led_value;
        
        `uvm_info("WB_FORWARD_TIMING", "=========================================", UVM_LOW)
        `uvm_info("WB_FORWARD_TIMING", "Verifying WB Forwarding Results", UVM_LOW)
        `uvm_info("WB_FORWARD_TIMING", "=========================================", UVM_LOW)
        
        // Read x27 (should be 7 from ADDI)
        read_register(5'd27, x27_value);
        `uvm_info("WB_FORWARD_TIMING", $sformatf("x27 = 0x%08X (expected 0x00000007)", x27_value), UVM_LOW)
        
        if (x27_value != 32'h00000007) begin
            `uvm_error("WB_FORWARD_TIMING", $sformatf("x27 mismatch: expected 0x00000007, got 0x%08X", x27_value))
        end else begin
            `uvm_info("WB_FORWARD_TIMING", "PASS: x27 correct", UVM_LOW)
        end
        
        // Read x15 (should be 0x00004000 from LUI x15, 0x4)
        read_register(5'd15, x15_value);
        `uvm_info("WB_FORWARD_TIMING", $sformatf("x15 = 0x%08X (expected 0x00004000)", x15_value), UVM_LOW)
        
        if (x15_value != 32'h00004000) begin
            `uvm_error("WB_FORWARD_TIMING", $sformatf("x15 mismatch: expected 0x00004000, got 0x%08X", x15_value))
        end else begin
            `uvm_info("WB_FORWARD_TIMING", "PASS: x15 correct", UVM_LOW)
        end
        
        // Read x1 (marker - should be 0xAA)
        read_register(5'd1, x1_value);
        `uvm_info("WB_FORWARD_TIMING", $sformatf("x1 = 0x%08X (expected 0x000000AA)", x1_value), UVM_LOW)
        
        if (x1_value != 32'h000000AA) begin
            `uvm_error("WB_FORWARD_TIMING", $sformatf("x1 mismatch: expected 0x000000AA, got 0x%08X", x1_value))
        end else begin
            `uvm_info("WB_FORWARD_TIMING", "PASS: x1 correct (execution continued)", UVM_LOW)
        end
        
        // Check LED output (critical - should be 7, not 0x4000000)
        @(posedge vif.clk);
        led_value = {28'h0, vif.led_reg};
        `uvm_info("WB_FORWARD_TIMING", $sformatf("LED = 0x%X (expected 0x7)", led_value), UVM_LOW)
        
        if (led_value != 32'h7) begin
            `uvm_error("WB_FORWARD_TIMING", $sformatf("LED mismatch: expected 0x7, got 0x%X", led_value))
            `uvm_error("WB_FORWARD_TIMING", "CRITICAL: SW used wrong value - wb_result_fwd may not be working!")
            `uvm_error("WB_FORWARD_TIMING", "This indicates the WB forwarding timing fix is not applied correctly")
        end else begin
            `uvm_info("WB_FORWARD_TIMING", "PASS: LED correct - wb_result_fwd working!", UVM_LOW)
            `uvm_info("WB_FORWARD_TIMING", "✓ SW instruction used x27=0x7 via wb_result_fwd", UVM_LOW)
            `uvm_info("WB_FORWARD_TIMING", "✓ WB forwarding timing fix verified", UVM_LOW)
        end
        
        `uvm_info("WB_FORWARD_TIMING", "=========================================", UVM_LOW)
    endtask
    
    //--------------------------------------------------------------------------
    // Verify Trace Timing
    //--------------------------------------------------------------------------
    
    virtual task verify_trace_timing();
        logic [31:0] pc, insn;
        logic [31:0] rd_value;
        logic [4:0] rd_addr;
        logic [6:0] entry_count;
        int addi_x27_found = 0;
        int lui_x15_found = 0;
        int sw_x27_found = 0;
        
        `uvm_info("WB_FORWARD_TIMING", "=========================================", UVM_LOW)
        `uvm_info("WB_FORWARD_TIMING", "Analyzing Trace Buffer (Timing)", UVM_LOW)
        `uvm_info("WB_FORWARD_TIMING", "=========================================", UVM_LOW)
        
        @(posedge vif.clk);
        entry_count = vif.dbg_trace_count;
        
        `uvm_info("WB_FORWARD_TIMING", $sformatf("Trace entries: %0d", entry_count), UVM_MEDIUM)
        
        for (int i = 0; i < entry_count; i++) begin
            read_trace_entry(i, pc, insn, rd_value, rd_addr);
            
            case (insn)
                32'h00700D93: begin // ADDI x27, x0, 7
                    addi_x27_found = 1;
                    `uvm_info("WB_FORWARD_TIMING", $sformatf("[%0d] PC=0x%08X: ADDI x27, x0, 7 → x27=0x%08X", 
                              i, pc, rd_value), UVM_MEDIUM)
                    if (rd_value != 32'h00000007) begin
                        `uvm_error("WB_FORWARD_TIMING", "ADDI x27 produced wrong value")
                    end
                end
                
                32'h000047B7: begin // LUI x15, 0x4
                    lui_x15_found = 1;
                    `uvm_info("WB_FORWARD_TIMING", $sformatf("[%0d] PC=0x%08X: LUI x15, 0x4 → x15=0x%08X", 
                              i, pc, rd_value), UVM_MEDIUM)
                    if (rd_value != 32'h00004000) begin
                        `uvm_error("WB_FORWARD_TIMING", "LUI x15 produced wrong value")
                    end
                end
                
                32'h07B7AE23: begin // SW x27, 0x7C(x15)
                    sw_x27_found = 1;
                    `uvm_info("WB_FORWARD_TIMING", $sformatf("[%0d] PC=0x%08X: SW x27, 0x7C(x15) - Critical forwarding point", 
                              i, pc), UVM_MEDIUM)
                    `uvm_info("WB_FORWARD_TIMING", "  → This instruction must use wb_result_fwd for x27", UVM_MEDIUM)
                end
                
                32'h0AA00093: begin // ADDI x1, x0, 0xAA
                    `uvm_info("WB_FORWARD_TIMING", $sformatf("[%0d] PC=0x%08X: ADDI x1, x0, 0xAA → x1=0x%08X", 
                              i, pc, rd_value), UVM_MEDIUM)
                end
            endcase
        end
        
        // Verify critical instructions were traced
        if (!addi_x27_found) begin
            `uvm_error("WB_FORWARD_TIMING", "ADDI x27 not found in trace")
        end
        
        if (!lui_x15_found) begin
            `uvm_error("WB_FORWARD_TIMING", "LUI x15 not found in trace")
        end
        
        if (!sw_x27_found) begin
            `uvm_error("WB_FORWARD_TIMING", "SW x27 not found in trace")
        end
        
        if (addi_x27_found && lui_x15_found && sw_x27_found) begin
            `uvm_info("WB_FORWARD_TIMING", "✓ All critical instructions traced correctly", UVM_LOW)
        end
        
        `uvm_info("WB_FORWARD_TIMING", "=========================================", UVM_LOW)
    endtask
    
endclass
