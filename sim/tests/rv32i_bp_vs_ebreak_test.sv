`timescale 1ns / 1ps

//==============================================================================
// RV32I Breakpoint vs EBREAK Comparison Test
//==============================================================================
// This test compares hardware breakpoint and EBREAK instruction behavior.
// Both should halt cleanly without executing extra instructions.
//
// Test Strategy:
//   Run 1: Hardware breakpoint at 0x08 → Expect 3 instructions (0x00, 0x04, 0x08)
//   Run 2: EBREAK at 0x0C → Expect 4 instructions (0x00, 0x04, 0x08, 0x0C)
//
// BUG DETECTION:
//   If EBREAK run logs 8 instructions instead of 4, bug is confirmed.
//
// Author: GitHub Copilot
// Date: 2026-01-04
//==============================================================================

class rv32i_bp_vs_ebreak_test extends rv32i_base_test;
    
    `uvm_component_utils(rv32i_bp_vs_ebreak_test)
    
    int bp_trace_count;
    int ebreak_trace_count;
    logic [31:0] bp_last_pc;
    logic [31:0] ebreak_last_pc;
    
    function new(string name = "rv32i_bp_vs_ebreak_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info("BP_VS_EBREAK", "***** Breakpoint vs EBREAK Comparison Test *****", UVM_LOW)
        
        // RUN 1: Hardware Breakpoint at 0x08
        `uvm_info("BP_VS_EBREAK", "=== RUN 1: Hardware Breakpoint Test ===", UVM_LOW)
        run_hardware_breakpoint_test();
        
        #2000ns;
        
        // RUN 2: EBREAK at 0x0C
        `uvm_info("BP_VS_EBREAK", "=== RUN 2: EBREAK Instruction Test ===", UVM_LOW)
        run_ebreak_instruction_test();
        
        #2000ns;
        
        // Compare results
        compare_results();
        
        `uvm_info("BP_VS_EBREAK", "***** Comparison Test Complete *****", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
    
    //--------------------------------------------------------------------------
    // Run 1: Hardware Breakpoint Test
    //--------------------------------------------------------------------------
    
    virtual task run_hardware_breakpoint_test();
        logic [31:0] pc, insn, rd_value;
        logic [4:0] rd_addr;
        
        reset_sequence();
        halt_cpu();
        
        // Load 4-instruction program (NO EBREAK)
        `uvm_info("BP_VS_EBREAK", "Loading program with NOP at position 3", UVM_MEDIUM)
        write_debug_mem(11'h000, 32'h00100093); // ADDI x1, x0, 1
        write_debug_mem(11'h001, 32'h00200113); // ADDI x2, x0, 2
        write_debug_mem(11'h002, 32'h002081B3); // ADD x3, x1, x2
        write_debug_mem(11'h003, 32'h00000013); // NOP (ADDI x0, x0, 0)
        
        // Set hardware breakpoint at 0x08 (3rd instruction)
        `uvm_info("BP_VS_EBREAK", "Setting hardware breakpoint at PC=0x08", UVM_MEDIUM)
        set_breakpoint(0, 32'h0000_0008);
        
        start_cpu();
        wait_for_cpu_break(500);
        
        // Capture trace count
        @(posedge vif.clk);
        bp_trace_count = vif.dbg_trace_count;
        
        // Read last PC
        if (bp_trace_count > 0) begin
            read_trace_entry((bp_trace_count - 1)[5:0], pc, insn, rd_value, rd_addr);
            bp_last_pc = pc;
        end else begin
            bp_last_pc = 32'hDEAD_BEEF;
        end
        
        `uvm_info("BP_VS_EBREAK", $sformatf("HW Breakpoint: %0d instructions, Last PC=0x%08X", 
                  bp_trace_count, bp_last_pc), UVM_LOW)
        
        // Dump trace buffer for analysis
        dump_trace_buffer(bp_trace_count < 10 ? bp_trace_count : 10);
        
        // Clear breakpoint
        clear_breakpoint(0);
        halt_cpu();
    endtask
    
    //--------------------------------------------------------------------------
    // Run 2: EBREAK Instruction Test
    //--------------------------------------------------------------------------
    
    virtual task run_ebreak_instruction_test();
        logic [31:0] pc, insn, rd_value;
        logic [4:0] rd_addr;
        
        reset_sequence();
        halt_cpu();
        
        // Load same program with EBREAK
        `uvm_info("BP_VS_EBREAK", "Loading program with EBREAK at position 3", UVM_MEDIUM)
        write_debug_mem(11'h000, 32'h00100093); // ADDI x1, x0, 1
        write_debug_mem(11'h001, 32'h00200113); // ADDI x2, x0, 2
        write_debug_mem(11'h002, 32'h002081B3); // ADD x3, x1, x2
        write_debug_mem(11'h003, 32'h00100073); // EBREAK
        
        start_cpu();
        wait_for_cpu_break(500);
        
        // Capture trace count
        @(posedge vif.clk);
        ebreak_trace_count = vif.dbg_trace_count;
        
        // Read last PC
        if (ebreak_trace_count > 0) begin
            read_trace_entry((ebreak_trace_count - 1)[5:0], pc, insn, rd_value, rd_addr);
            ebreak_last_pc = pc;
        end else begin
            ebreak_last_pc = 32'hDEAD_BEEF;
        end
        
        `uvm_info("BP_VS_EBREAK", $sformatf("EBREAK: %0d instructions, Last PC=0x%08X", 
                  ebreak_trace_count, ebreak_last_pc), UVM_LOW)
        
        // Dump trace buffer for analysis
        dump_trace_buffer(ebreak_trace_count < 10 ? ebreak_trace_count : 10);
        
        halt_cpu();
    endtask
    
    //--------------------------------------------------------------------------
    // Compare Results
    //--------------------------------------------------------------------------
    
    virtual task compare_results();
        `uvm_info("BP_VS_EBREAK", "=== COMPARISON RESULTS ===", UVM_LOW)
        `uvm_info("BP_VS_EBREAK", $sformatf("HW Breakpoint: %0d instructions (expected 3)", bp_trace_count), UVM_LOW)
        `uvm_info("BP_VS_EBREAK", $sformatf("EBREAK:        %0d instructions (expected 4)", ebreak_trace_count), UVM_LOW)
        
        // Check hardware breakpoint
        if (bp_trace_count != 3) begin
            `uvm_error("BP_VS_EBREAK", 
                       $sformatf("HW Breakpoint trace count mismatch: Expected 3, got %0d", bp_trace_count))
        end else begin
            `uvm_info("BP_VS_EBREAK", "PASS: HW Breakpoint trace count correct", UVM_LOW)
        end
        
        // Check EBREAK
        if (ebreak_trace_count != 4) begin
            `uvm_error("BP_VS_EBREAK", 
                       $sformatf("EBREAK trace count mismatch: Expected 4, got %0d", ebreak_trace_count))
            if (ebreak_trace_count == 8) begin
                `uvm_error("BP_VS_EBREAK", 
                           "*** EBREAK BUG CONFIRMED: 8 instructions instead of 4 (double execution) ***")
            end
        end else begin
            `uvm_info("BP_VS_EBREAK", "PASS: EBREAK trace count correct", UVM_LOW)
        end
        
        // Verify last PCs
        if (bp_last_pc != 32'h0000_0008) begin
            `uvm_error("BP_VS_EBREAK", $sformatf("HW Breakpoint last PC: Expected 0x08, got 0x%08X", bp_last_pc))
        end
        
        if (ebreak_last_pc != 32'h0000_000C) begin
            `uvm_error("BP_VS_EBREAK", $sformatf("EBREAK last PC: Expected 0x0C, got 0x%08X", ebreak_last_pc))
        end
        
        // Summary
        `uvm_info("BP_VS_EBREAK", "==========================", UVM_LOW)
        
        if (bp_trace_count == 3 && ebreak_trace_count == 4) begin
            `uvm_info("BP_VS_EBREAK", "*** ALL CHECKS PASSED - Both mechanisms work correctly ***", UVM_LOW)
        end else if (bp_trace_count == 3 && ebreak_trace_count == 8) begin
            `uvm_error("BP_VS_EBREAK", "HW Breakpoint works, but EBREAK has timing bug (8 vs 4 instructions)")
        end else begin
            `uvm_error("BP_VS_EBREAK", "Unexpected results - both mechanisms may have issues")
        end
    endtask
    
endclass
