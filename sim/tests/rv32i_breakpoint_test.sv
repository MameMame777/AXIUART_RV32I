`timescale 1ns / 1ps

//==============================================================================
// RV32I Hardware Breakpoint Test
//==============================================================================
// This test verifies hardware breakpoint functionality.
//
// Test Sequence:
// 1. Load test program with loop structure
// 2. Set hardware breakpoint at loop entry (PC=0x0010)
// 3. Start CPU
// 4. Verify CPU halts at breakpoint with bp_hit flag set
// 5. Clear breakpoint and continue execution
//
// Test Program (8 instructions):
//   0x0000: ADDI x1, x0, 0    (0x00000093) - x1 = 0
//   0x0004: ADDI x2, x0, 5    (0x00500113) - x2 = 5 (loop counter)
//   0x0008: ADDI x3, x0, 0    (0x00000193) - x3 = 0 (accumulator)
//   0x000C: BEQ x1, x2, 20    (0x01208A63) - if x1==x2, jump to 0x0020
//   0x0010: ADDI x3, x3, 1    (0x00118193) - x3++ (BREAKPOINT HERE)
//   0x0014: ADDI x1, x1, 1    (0x00108093) - x1++
//   0x0018: JAL x0, -16       (0xFF1FF06F) - jump to 0x000C
//   0x001C: EBREAK            (0x00100073) - Should not reach
//   0x0020: EBREAK            (0x00100073) - Loop exit
//
// Expected Results:
//   - CPU halts at PC=0x0010 on first loop iteration
//   - dbg_bp_hit[0] = 1
//   - After clear and continue: CPU halts at PC=0x0020 (EBREAK)
//
// Author: GitHub Copilot
// Date: 2026-01-04
//==============================================================================

class rv32i_breakpoint_test extends rv32i_base_test;
    
    `uvm_component_utils(rv32i_breakpoint_test)
    
    function new(string name = "rv32i_breakpoint_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Configure for breakpoint test
        // Will hit breakpoint multiple times before final EBREAK
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_insn_min", 10);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_insn_max", 40);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_ebreak_count", 1);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info("RV32I_BREAKPOINT", "***** Starting RV32I Hardware Breakpoint Test *****", UVM_LOW)
        
        // Apply reset
        reset_sequence();
        halt_cpu();
        
        // Load test program
        load_breakpoint_program();
        
        // Set breakpoint at loop body entry (PC=0x0010)
        set_breakpoint(0, 32'h0000_0010);
        
        // Start CPU
        start_cpu();
        
        // Wait for breakpoint hit
        wait_for_breakpoint_hit(0);
        
        // Verify PC is at breakpoint
        verify_pc_at_breakpoint(32'h0000_0010);
        
        // Clear breakpoint and continue
        clear_breakpoint(0);
        
        // Resume execution
        start_cpu();
        
        // Wait for EBREAK at loop exit
        wait_for_completion();
        
        // Dump trace buffer to see PC history
        `uvm_info("RV32I_BREAKPOINT", "Dumping trace buffer for analysis", UVM_LOW)
        dump_trace_buffer(15);  // Show last 15 instructions
        
        `uvm_info("RV32I_BREAKPOINT", "***** RV32I Hardware Breakpoint Test Complete *****", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
    
    //--------------------------------------------------------------------------
    // Load Breakpoint Test Program
    //--------------------------------------------------------------------------
    
    virtual task load_breakpoint_program();
        `uvm_info("RV32I_BREAKPOINT", "Loading breakpoint test program", UVM_MEDIUM)
        
        // Program with loop structure for breakpoint testing
        write_debug_mem(11'h000, 32'h00000093); // ADDI x1, x0, 0
        write_debug_mem(11'h001, 32'h00500113); // ADDI x2, x0, 5
        write_debug_mem(11'h002, 32'h00000193); // ADDI x3, x0, 0
        write_debug_mem(11'h003, 32'h01208A63); // BEQ x1, x2, 20
        write_debug_mem(11'h004, 32'h00118193); // ADDI x3, x3, 1 (breakpoint target)
        write_debug_mem(11'h005, 32'h00108093); // ADDI x1, x1, 1
        write_debug_mem(11'h006, 32'hFF1FF06F); // JAL x0, -16
        write_debug_mem(11'h007, 32'h00100073); // EBREAK (unreachable)
        write_debug_mem(11'h008, 32'h00100073); // EBREAK (loop exit)
        
        `uvm_info("RV32I_BREAKPOINT", "Program loaded", UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Set Hardware Breakpoint
    //--------------------------------------------------------------------------
    
    virtual task set_breakpoint(int bp_num, bit [31:0] addr);
        `uvm_info("RV32I_BREAKPOINT", $sformatf("Setting breakpoint %0d at PC=0x%08X", bp_num, addr), UVM_MEDIUM)
        
        @(posedge vif.clk);
        
        // Set breakpoint address
        case (bp_num)
            0: vif.dbg_bp_addr[0] = addr;
            1: vif.dbg_bp_addr[1] = addr;
            2: vif.dbg_bp_addr[2] = addr;
            3: vif.dbg_bp_addr[3] = addr;
        endcase
        
        // Enable breakpoint
        vif.dbg_bp_enable[bp_num] = 1'b1;
        
        @(posedge vif.clk);
        
        `uvm_info("RV32I_BREAKPOINT", $sformatf("Breakpoint %0d enabled", bp_num), UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Clear Hardware Breakpoint
    //--------------------------------------------------------------------------
    
    virtual task clear_breakpoint(int bp_num);
        `uvm_info("RV32I_BREAKPOINT", $sformatf("Clearing breakpoint %0d", bp_num), UVM_MEDIUM)
        
        @(posedge vif.clk);
        vif.dbg_bp_enable[bp_num] = 1'b0;
        @(posedge vif.clk);
        
        `uvm_info("RV32I_BREAKPOINT", $sformatf("Breakpoint %0d disabled", bp_num), UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Wait for Breakpoint Hit
    //--------------------------------------------------------------------------
    
    virtual task wait_for_breakpoint_hit(int bp_num);
        int timeout_cycles = 1000;
        int cycle_count = 0;
        
        `uvm_info("RV32I_BREAKPOINT", $sformatf("Waiting for breakpoint %0d hit", bp_num), UVM_MEDIUM)
        
        while (cycle_count < timeout_cycles) begin
            @(posedge vif.clk);
            
            if (vif.dbg_bp_hit[bp_num] && vif.cpu_halted) begin
                `uvm_info("RV32I_BREAKPOINT", $sformatf("Breakpoint %0d hit at cycle %0d", bp_num, cycle_count), UVM_LOW)
                return;
            end
            
            cycle_count++;
        end
        
        `uvm_error("RV32I_BREAKPOINT", $sformatf("Timeout waiting for breakpoint %0d (waited %0d cycles)", bp_num, timeout_cycles))
    endtask
    
    //--------------------------------------------------------------------------
    // Verify PC at Breakpoint
    //--------------------------------------------------------------------------
    
    virtual task verify_pc_at_breakpoint(bit [31:0] expected_pc);
        bit [31:0] actual_pc;
        
        @(posedge vif.clk);
        
        // Access PC from DUT (hierarchical path)
        actual_pc = vif.pc_if;
        
        if (actual_pc == expected_pc) begin
            `uvm_info("RV32I_BREAKPOINT", $sformatf("PC verified at 0x%08X", actual_pc), UVM_MEDIUM)
        end else begin
            `uvm_error("RV32I_BREAKPOINT", $sformatf("PC mismatch: expected=0x%08X, actual=0x%08X", expected_pc, actual_pc))
        end
    endtask
    
endclass

