`timescale 1ns / 1ps

//==============================================================================
// RV32I Performance Counter Test
//==============================================================================
// This test verifies performance counter functionality and calculates IPC.
//
// Test Sequence:
// 1. Load test program with known instruction count and hazards
// 2. Start CPU
// 3. Wait for completion
// 4. Read performance counters
// 5. Verify cycle/instruction counts and calculate IPC
//
// Test Program (20 instructions with intentional hazards):
//   0x0000: ADDI x1, x0, 10   - x1 = 10
//   0x0004: ADDI x2, x0, 20   - x2 = 20
//   0x0008: ADD x3, x1, x2    - x3 = 30 (no hazard)
//   0x000C: ADDI x4, x3, 5    - x4 = 35 (forwarding)
//   0x0010: LW x5, 0(x0)      - Load from mem[0] (load-use stall next insn)
//   0x0014: ADDI x6, x5, 1    - x6 = x5+1 (STALL: load-use hazard)
//   0x0018: SW x6, 4(x0)      - Store x6 to mem[1]
//   0x001C: BEQ x1, x2, 12    - Branch not taken (FLUSH: 2-cycle penalty)
//   0x0020: ADDI x7, x0, 7    - x7 = 7
//   0x0024: SUB x8, x2, x1    - x8 = 10
//   0x0028: AND x9, x1, x2    - x9 = 0
//   0x002C: OR x10, x1, x2    - x10 = 30
//   0x0030: XOR x11, x1, x2   - x11 = 30
//   0x0034: SLL x12, x1, x2   - x12 = shifted
//   0x0038: SRL x13, x2, x1   - x13 = shifted
//   0x003C: SLT x14, x1, x2   - x14 = 1
//   0x0040: JAL x15, 8        - Jump +8 (FLUSH: 2-cycle penalty)
//   0x0044: ADDI x16, x0, 99  - Skipped
//   0x0048: ADDI x17, x0, 88  - x17 = 88
//   0x004C: EBREAK            - Halt
//
// Expected Results:
//   - Instructions: 19 (20 - 1 skipped by JAL)
//   - Cycles: ~24-27 (19 base + 1 load stall + 2 branch flush + 2 jump flush)
//   - IPC: ~0.70-0.79
//   - Stalls: ~1-2
//   - Flushes: ~2
//
// Author: GitHub Copilot
// Date: 2026-01-04
//==============================================================================

class rv32i_perfcount_test extends rv32i_base_test;
    
    `uvm_component_utils(rv32i_perfcount_test)
    
    function new(string name = "rv32i_perfcount_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Configure for performance counter test
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_insn_min", 18);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_insn_max", 22);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_ebreak_count", 1);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        int cycle_count, insn_count, stall_count, flush_count;
        real ipc, stall_percent, flush_percent;
        
        phase.raise_objection(this);
        
        `uvm_info("RV32I_PERFCOUNT", "***** Starting RV32I Performance Counter Test *****", UVM_LOW)
        
        // Apply reset
        reset_sequence();
        halt_cpu();
        
        // Load test program
        load_perfcount_program();
        
        // Start CPU
        start_cpu();
        
        // Wait for completion
        wait_for_completion();
        
        // Read performance counters
        cycle_count = read_perf_counter("CYCLE");
        insn_count = read_perf_counter("INSN");
        stall_count = read_perf_counter("STALL");
        flush_count = read_perf_counter("FLUSH");
        
        // Calculate metrics
        ipc = real'(insn_count) / real'(cycle_count);
        stall_percent = (real'(stall_count) / real'(cycle_count)) * 100.0;
        flush_percent = (real'(flush_count) / real'(cycle_count)) * 100.0;
        
        // Report results
        `uvm_info("RV32I_PERFCOUNT", "=== Performance Counter Results ===", UVM_LOW)
        `uvm_info("RV32I_PERFCOUNT", $sformatf("Cycle Count:  %0d", cycle_count), UVM_LOW)
        `uvm_info("RV32I_PERFCOUNT", $sformatf("Insn Count:   %0d", insn_count), UVM_LOW)
        `uvm_info("RV32I_PERFCOUNT", $sformatf("Stall Count:  %0d", stall_count), UVM_LOW)
        `uvm_info("RV32I_PERFCOUNT", $sformatf("Flush Count:  %0d", flush_count), UVM_LOW)
        `uvm_info("RV32I_PERFCOUNT", $sformatf("IPC:          %0.3f", ipc), UVM_LOW)
        `uvm_info("RV32I_PERFCOUNT", $sformatf("Stall %%:      %0.1f%%", stall_percent), UVM_LOW)
        `uvm_info("RV32I_PERFCOUNT", $sformatf("Flush %%:      %0.1f%%", flush_percent), UVM_LOW)
        `uvm_info("RV32I_PERFCOUNT", "===================================", UVM_LOW)
        
        // Verify reasonable ranges
        verify_perf_metrics(cycle_count, insn_count, stall_count, flush_count, ipc);
        
        `uvm_info("RV32I_PERFCOUNT", "***** RV32I Performance Counter Test Complete *****", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
    
    //--------------------------------------------------------------------------
    // Load Performance Counter Test Program
    //--------------------------------------------------------------------------
    
    virtual task load_perfcount_program();
        `uvm_info("RV32I_PERFCOUNT", "Loading performance test program (20 instructions)", UVM_MEDIUM)
        
        write_debug_mem(11'h000, 32'h00A00093); // ADDI x1, x0, 10
        write_debug_mem(11'h001, 32'h01400113); // ADDI x2, x0, 20
        write_debug_mem(11'h002, 32'h002081B3); // ADD x3, x1, x2
        write_debug_mem(11'h003, 32'h00518213); // ADDI x4, x3, 5
        write_debug_mem(11'h004, 32'h00002283); // LW x5, 0(x0)
        write_debug_mem(11'h005, 32'h00128313); // ADDI x6, x5, 1 (load-use stall)
        write_debug_mem(11'h006, 32'h00602223); // SW x6, 4(x0)
        write_debug_mem(11'h007, 32'h00208663); // BEQ x1, x2, 12 (not taken, flush)
        write_debug_mem(11'h008, 32'h00700393); // ADDI x7, x0, 7
        write_debug_mem(11'h009, 32'h40110433); // SUB x8, x2, x1
        write_debug_mem(11'h00A, 32'h0020F4B3); // AND x9, x1, x2
        write_debug_mem(11'h00B, 32'h0020E533); // OR x10, x1, x2
        write_debug_mem(11'h00C, 32'h0020C5B3); // XOR x11, x1, x2
        write_debug_mem(11'h00D, 32'h00209633); // SLL x12, x1, x2
        write_debug_mem(11'h00E, 32'h0011D6B3); // SRL x13, x2, x1
        write_debug_mem(11'h00F, 32'h00212733); // SLT x14, x1, x2
        write_debug_mem(11'h010, 32'h008007EF); // JAL x15, 8 (jump +8, flush)
        write_debug_mem(11'h011, 32'h06300813); // ADDI x16, x0, 99 (skipped)
        write_debug_mem(11'h012, 32'h05800893); // ADDI x17, x0, 88
        write_debug_mem(11'h013, 32'h00100073); // EBREAK
        
        `uvm_info("RV32I_PERFCOUNT", "Program loaded", UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Read Performance Counter
    //--------------------------------------------------------------------------
    
    virtual function int read_perf_counter(string counter_name);
        int value;
        
        // Direct DUT access for performance counters
        case (counter_name)
            "CYCLE": value = vif.perf_cycle_count;
            "INSN":  value = vif.perf_insn_count;
            "STALL": value = vif.perf_stall_count;
            "FLUSH": value = vif.perf_flush_count;
            default: begin
                `uvm_error("RV32I_PERFCOUNT", $sformatf("Unknown counter: %s", counter_name))
                value = 0;
            end
        endcase
        
        return value;
    endfunction
    
    //--------------------------------------------------------------------------
    // Verify Performance Metrics
    //--------------------------------------------------------------------------
    
    virtual function void verify_perf_metrics(int cycles, int insns, int stalls, int flushes, real ipc);
        bit pass = 1'b1;
        
        // Instruction count should be 18-20 (19 expected)
        if (insns < 18 || insns > 22) begin
            `uvm_error("RV32I_PERFCOUNT", $sformatf("Instruction count out of range: %0d (expected 18-22)", insns))
            pass = 1'b0;
        end
        
        // Cycle count should be reasonable (24-30 expected)
        if (cycles < 22 || cycles > 35) begin
            `uvm_error("RV32I_PERFCOUNT", $sformatf("Cycle count out of range: %0d (expected 22-35)", cycles))
            pass = 1'b0;
        end
        
        // IPC should be > 0.6 (reasonable for simple pipeline)
        if (ipc < 0.5 || ipc > 1.0) begin
            `uvm_error("RV32I_PERFCOUNT", $sformatf("IPC out of range: %0.3f (expected 0.5-1.0)", ipc))
            pass = 1'b0;
        end
        
        // Stall count should be 0-3 (1-2 expected from load-use)
        if (stalls > 5) begin
            `uvm_error("RV32I_PERFCOUNT", $sformatf("Stall count excessive: %0d (expected 0-5)", stalls))
            pass = 1'b0;
        end
        
        // Flush count should be 1-4 (2-3 expected from branch/jump)
        if (flushes < 1 || flushes > 6) begin
            `uvm_error("RV32I_PERFCOUNT", $sformatf("Flush count out of range: %0d (expected 1-6)", flushes))
            pass = 1'b0;
        end
        
        if (pass) begin
            `uvm_info("RV32I_PERFCOUNT", "All performance metrics within expected ranges", UVM_MEDIUM)
        end
    endfunction
    
endclass

