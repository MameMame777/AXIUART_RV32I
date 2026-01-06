`timescale 1ns / 1ps

//==============================================================================
// RV32I EBREAK Simple Test
//==============================================================================
// Ultra-simple test to verify EBREAK instruction functionality.
// No breakpoints, no complex logic - just straight execution to EBREAK.
//
// Test Program (4 instructions):
//   0x0000: ADDI x1, x0, 1    (0x00100093) - x1 = 1
//   0x0004: ADDI x2, x0, 2    (0x00200113) - x2 = 2
//   0x0008: ADD  x3, x1, x2   (0x002081B3) - x3 = x1 + x2 = 3
//   0x000C: EBREAK            (0x00100073) - Stop here
//
// Expected Results:
//   - 4 instructions executed
//   - x1 = 1, x2 = 2, x3 = 3
//   - CPU halts at PC=0x000C with cpu_break asserted
//   - EBREAK count = 1
//
// This test isolates EBREAK functionality from hardware breakpoint logic.
//
// Author: GitHub Copilot
// Date: 2026-01-04
//==============================================================================

class rv32i_ebreak_simple_test extends rv32i_base_test;
    
    `uvm_component_utils(rv32i_ebreak_simple_test)
    
    function new(string name = "rv32i_ebreak_simple_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Configure for simple EBREAK test
        // Expect exactly 4 instructions
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_insn_min", 4);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_insn_max", 4);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_ebreak_count", 1);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_led_value", 32'h00000003);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info("RV32I_EBREAK_SIMPLE", "***** Starting RV32I Simple EBREAK Test *****", UVM_LOW)
        
        // Reset CPU and load program
        reset_sequence();
        halt_cpu();
        load_ebreak_simple_program();
        
        // Start CPU execution
        `uvm_info("RV32I_EBREAK_SIMPLE", "Starting CPU execution", UVM_MEDIUM)
        start_cpu();
        
        // Wait for EBREAK
        `uvm_info("RV32I_EBREAK_SIMPLE", "Waiting for EBREAK", UVM_MEDIUM)
        wait_for_cpu_break(1000);
        
        // Verify final state
        verify_final_state();
        
        // Verify trace buffer contents
        verify_trace_buffer();
        
        // Small delay before ending test
        #1000ns;
        
        `uvm_info("RV32I_EBREAK_SIMPLE", "***** RV32I Simple EBREAK Test Complete *****", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
    
    //--------------------------------------------------------------------------
    // Load Simple EBREAK Test Program
    //--------------------------------------------------------------------------
    
    virtual task load_ebreak_simple_program();
        `uvm_info("RV32I_EBREAK_SIMPLE", "Loading simple EBREAK test program", UVM_MEDIUM)
        
        // 4 instructions ending in EBREAK
        write_debug_mem(11'h000, 32'h00100093); // ADDI x1, x0, 1
        write_debug_mem(11'h001, 32'h00200113); // ADDI x2, x0, 2
        write_debug_mem(11'h002, 32'h002081B3); // ADD x3, x1, x2
        write_debug_mem(11'h003, 32'h00100073); // EBREAK
        
        `uvm_info("RV32I_EBREAK_SIMPLE", "Program loaded", UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Wait for CPU Break (EBREAK or Breakpoint)
    //--------------------------------------------------------------------------
    
    virtual task wait_for_cpu_break(int timeout_cycles);
        int cycle_count = 0;
        
        `uvm_info("RV32I_EBREAK_SIMPLE", $sformatf("Waiting for CPU break (timeout=%0d cycles)", timeout_cycles), UVM_MEDIUM)
        
        while (cycle_count < timeout_cycles) begin
            @(posedge vif.clk);
            
            if (vif.cpu_halted && vif.cpu_break) begin
                `uvm_info("RV32I_EBREAK_SIMPLE", $sformatf("CPU break detected at cycle %0d, PC=0x%08X", cycle_count, vif.pc_if), UVM_LOW)
                return;
            end
            
            cycle_count++;
        end
        
        `uvm_error("RV32I_EBREAK_SIMPLE", $sformatf("Timeout waiting for CPU break (waited %0d cycles)", timeout_cycles))
    endtask
    
    //--------------------------------------------------------------------------
    // Verify Final State
    //--------------------------------------------------------------------------
    
    virtual task verify_final_state();
        bit [31:0] pc_value;
        
        @(posedge vif.clk);
        pc_value = vif.pc_if;
        
        `uvm_info("RV32I_EBREAK_SIMPLE", "=== Final State Verification ===", UVM_MEDIUM)
        `uvm_info("RV32I_EBREAK_SIMPLE", $sformatf("PC = 0x%08X (expected 0x0000000C)", pc_value), UVM_MEDIUM)
        `uvm_info("RV32I_EBREAK_SIMPLE", $sformatf("cpu_break = %b (expected 1)", vif.cpu_break), UVM_MEDIUM)
        `uvm_info("RV32I_EBREAK_SIMPLE", $sformatf("cpu_halted = %b (expected 1)", vif.cpu_halted), UVM_MEDIUM)
        
        if (pc_value != 32'h0000000C) begin
            `uvm_error("RV32I_EBREAK_SIMPLE", $sformatf("PC mismatch: expected 0x0000000C, got 0x%08X", pc_value))
        end
        
        if (!vif.cpu_break) begin
            `uvm_error("RV32I_EBREAK_SIMPLE", "cpu_break not asserted")
        end
        
        if (!vif.cpu_halted) begin
            `uvm_error("RV32I_EBREAK_SIMPLE", "cpu_halted not asserted")
        end
        
        `uvm_info("RV32I_EBREAK_SIMPLE", "================================", UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Verify Trace Buffer (BUG DETECTION)
    //--------------------------------------------------------------------------
    
    virtual task verify_trace_buffer();
        logic [31:0] pc, insn, rd_value;
        logic [4:0] rd_addr;
        logic [6:0] entry_count;
        int bug_instruction_count = 0;
        
        @(posedge vif.clk);
        entry_count = vif.dbg_trace_count;
        
        `uvm_info("RV32I_EBREAK_SIMPLE", "=== TRACE BUFFER VERIFICATION ===", UVM_LOW)
        `uvm_info("RV32I_EBREAK_SIMPLE", $sformatf("Total entries logged: %0d (expect 4)", entry_count), UVM_LOW)
        
        // CRITICAL CHECK: Entry count must be 4, not 8
        if (entry_count != 4) begin
            `uvm_error("RV32I_EBREAK_SIMPLE", 
                       $sformatf("TRACE COUNT MISMATCH: Expected 4, got %0d (BUG SIGNATURE)", entry_count))
            bug_instruction_count = entry_count;
        end else begin
            `uvm_info("RV32I_EBREAK_SIMPLE", "PASS: Correct entry count (4 instructions)", UVM_LOW)
        end
        
        // Read and verify entries 0-7 (to catch bug)
        for (int i = 0; i < 8 && i < entry_count; i++) begin
            logic [5:0] idx;
            idx = i;
            read_trace_entry(idx, pc, insn, rd_value, rd_addr);
            
            `uvm_info("RV32I_EBREAK_SIMPLE", 
                      $sformatf("Entry[%0d]: PC=0x%08X, INSN=0x%08X", i, pc, insn), UVM_MEDIUM)
            
            // Expected PCs: 0x00, 0x04, 0x08, 0x0C
            // Bug signature: Additional entries at 0x10, 0x14, 0x18, 0x1C
            case (i)
                0: begin
                    if (pc != 32'h0000_0000) 
                        `uvm_error("TRACE", $sformatf("Entry 0: Expected PC=0x00, got 0x%08X", pc))
                end
                1: begin
                    if (pc != 32'h0000_0004) 
                        `uvm_error("TRACE", $sformatf("Entry 1: Expected PC=0x04, got 0x%08X", pc))
                end
                2: begin
                    if (pc != 32'h0000_0008) 
                        `uvm_error("TRACE", $sformatf("Entry 2: Expected PC=0x08, got 0x%08X", pc))
                end
                3: begin
                    if (pc != 32'h0000_000C) 
                        `uvm_error("TRACE", $sformatf("Entry 3: Expected PC=0x0C, got 0x%08X", pc))
                end
                default: begin
                    // These should NOT exist
                    `uvm_error("RV32I_EBREAK_SIMPLE", 
                               $sformatf("BUG DETECTED: Extra entry[%0d] at PC=0x%08X (should not exist)", i, pc))
                    
                    // Log specific bug signature addresses
                    if (pc == 32'h0000_0010 || pc == 32'h0000_0014 || pc == 32'h0000_0018 || pc == 32'h0000_001C) begin
                        `uvm_error("RV32I_EBREAK_SIMPLE", 
                                   $sformatf("CONFIRMED BUG: Instruction at 0x%08X executed after EBREAK", pc))
                    end
                end
            endcase
        end
        
        // Verify last entry is EBREAK at 0x0C
        if (entry_count >= 1) begin
            logic [5:0] last_idx;
            last_idx = entry_count - 1;
            read_trace_entry(last_idx, pc, insn, rd_value, rd_addr);
            if (pc != 32'h0000_000C) begin
                `uvm_error("RV32I_EBREAK_SIMPLE", 
                           $sformatf("Last entry PC=0x%08X, expected 0x0C (EBREAK location)", pc))
            end else begin
                `uvm_info("RV32I_EBREAK_SIMPLE", "PASS: Last entry is EBREAK at 0x0C", UVM_LOW)
            end
        end
        
        `uvm_info("RV32I_EBREAK_SIMPLE", "=================================", UVM_LOW)
    endtask
    
endclass
