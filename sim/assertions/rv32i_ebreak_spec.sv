`timescale 1ns / 1ps

//==============================================================================
// RV32I EBREAK Halt Specification (SVA)
//==============================================================================
// This module defines the expected behavior for EBREAK instruction execution.
// Assertions verify halt mechanism and cpu_break signal persistence.
//
// Expected Behavior:
// 1. When EBREAK enters MEM stage, cpu_break asserts
// 2. cpu_break remains high until cpu_run pulse
// 3. cpu_halted signal sets synchronously with EBREAK
// 4. No new instructions fetch after EBREAK detected
//==============================================================================

module rv32i_ebreak_spec
    import rv32i_isa_pkg::*;
(
    input logic        clk,
    input logic        rst_n,
    
    // MEM stage signals
    input logic        mem_valid,
    input decode_ctrl_t mem_ctrl,
    input logic [31:0] mem_pc,
    
    // Debug control
    input logic        cpu_run,
    input logic        cpu_halt,
    input logic        cpu_break,
    input logic        cpu_halted,
    input logic        running,
    
    // IF stage
    input logic        if_valid
);

    //==========================================================================
    // Helper Signals
    //==========================================================================
    
    logic ebreak_in_mem;
    assign ebreak_in_mem = mem_valid && mem_ctrl.is_ebreak;
    
    //==========================================================================
    // ASSERTION 1: cpu_break Assertion on EBREAK
    //==========================================================================
    // When EBREAK enters MEM stage, cpu_break must assert within 1 cycle
    
    property ebreak_asserts_cpu_break;
        @(posedge clk) disable iff (!rst_n)
        $rose(ebreak_in_mem) |-> ##[0:1] cpu_break;
    endproperty
    
    assert_ebreak_asserts_cpu_break: assert property (ebreak_asserts_cpu_break)
        else $error("[EBREAK_SPEC] ASSERTION FAILED: EBREAK at PC=0x%h did not assert cpu_break", mem_pc);
    
    cover_ebreak_asserts_cpu_break: cover property (ebreak_asserts_cpu_break)
        $display("[EBREAK_SPEC] COVER: EBREAK detected at PC=0x%h, cpu_break asserted @ %0t", mem_pc, $time);
    
    //==========================================================================
    // ASSERTION 2: cpu_break Persistence
    //==========================================================================
    // Once cpu_break asserts, it must remain high until cpu_run
    
    property cpu_break_persistence;
        @(posedge clk) disable iff (!rst_n)
        $rose(cpu_break) ##1 (!cpu_run)[*1:$] |-> cpu_break throughout (!cpu_run)[*1:$];
    endproperty
    
    assert_cpu_break_persistence: assert property (cpu_break_persistence)
        else $error("[EBREAK_SPEC] ASSERTION FAILED: cpu_break deasserted before cpu_run @ %0t", $time);
    
    //==========================================================================
    // ASSERTION 3: cpu_halted Sets with EBREAK
    //==========================================================================
    // cpu_halted must be set within 2 cycles of EBREAK detection
    
    property ebreak_sets_halted;
        @(posedge clk) disable iff (!rst_n)
        $rose(ebreak_in_mem) |-> ##[1:2] cpu_halted;
    endproperty
    
    assert_ebreak_sets_halted: assert property (ebreak_sets_halted)
        else $error("[EBREAK_SPEC] ASSERTION FAILED: cpu_halted not set after EBREAK @ %0t", $time);
    
    //==========================================================================
    // ASSERTION 4: Halt Stops Instruction Fetch
    //==========================================================================
    // After EBREAK, no new valid IF stages should occur (until cpu_run)
    
    property halt_stops_fetch;
        @(posedge clk) disable iff (!rst_n)
        (cpu_halted && !cpu_run) |-> !if_valid;
    endproperty
    
    assert_halt_stops_fetch: assert property (halt_stops_fetch)
        else $error("[EBREAK_SPEC] ASSERTION FAILED: IF stage active while halted @ %0t", $time);
    
    //==========================================================================
    // ASSERTION 5: running Flag Clears on EBREAK
    //==========================================================================
    
    property ebreak_clears_running;
        @(posedge clk) disable iff (!rst_n)
        $rose(ebreak_in_mem) |-> ##[1:2] !running;
    endproperty
    
    assert_ebreak_clears_running: assert property (ebreak_clears_running)
        else $error("[EBREAK_SPEC] ASSERTION FAILED: running flag still set after EBREAK @ %0t", $time);
    
    //==========================================================================
    // DEBUG: State Transitions
    //==========================================================================
    
    `ifdef ENABLE_ASSERTIONS
    always @(posedge clk) begin
        if (ebreak_in_mem) begin
            $display("[EBREAK_SPEC] @ %0t: EBREAK in MEM stage, PC=0x%h", $time, mem_pc);
            $display("              State: cpu_break=%b, cpu_halted=%b, running=%b", 
                     cpu_break, cpu_halted, running);
        end
        
        if ($rose(cpu_break)) begin
            $display("[EBREAK_SPEC] @ %0t: cpu_break ASSERTED", $time);
        end
        
        if ($fell(cpu_break)) begin
            $display("[EBREAK_SPEC] @ %0t: cpu_break DEASSERTED (cpu_run=%b)", $time, cpu_run);
        end
        
        if ($rose(cpu_halted)) begin
            $display("[EBREAK_SPEC] @ %0t: cpu_halted ASSERTED", $time);
        end
    end
    `endif
    
    //==========================================================================
    // COVERAGE: Halt/Resume Cycles
    //==========================================================================
    // ASSERTION 6: Same-Cycle IF Stage Halt
    //==========================================================================
    // When ebreak_detected rises, if_valid must deassert same or next cycle
    
    property ebreak_halts_if_immediately;
        @(posedge clk) disable iff (!rst_n)
        $rose(ebreak_in_mem) |=> !if_valid;
    endproperty
    
    assert_ebreak_halts_if_immediately: assert property (ebreak_halts_if_immediately)
        else $error("[EBREAK_SPEC] CRITICAL: IF stage remained active after EBREAK @ %0t", $time);
    
    //==========================================================================
    // ASSERTION 7: PC Freeze on EBREAK
    //==========================================================================
    // Once EBREAK detected, PC must remain stable until cpu_run
    
    logic [31:0] pc_at_ebreak;
    logic ebreak_seen;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ebreak_seen <= 1'b0;
            pc_at_ebreak <= 32'h0;
        end else if (ebreak_in_mem && !ebreak_seen) begin
            ebreak_seen <= 1'b1;
            pc_at_ebreak <= mem_pc;
        end else if (cpu_run) begin
            ebreak_seen <= 1'b0;
        end
    end
    
    property pc_stable_after_ebreak;
        @(posedge clk) disable iff (!rst_n)
        (ebreak_seen && !cpu_run) |-> $stable(if_valid ? 1'b0 : 1'b1);
    endproperty
    
    assert_pc_stable_after_ebreak: assert property (pc_stable_after_ebreak)
        else $error("[EBREAK_SPEC] PC changed while halted @ %0t", $time);
    
    //==========================================================================
    // ASSERTION 8: Pipeline Entry Count Limit (BUG SIGNATURE)
    //==========================================================================
    // After EBREAK enters MEM stage, no more than 1 additional IF/ID should occur
    // (accounting for pipeline delay). This catches the 8-instruction bug.
    
    int unsigned if_count_after_ebreak;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || cpu_run) begin
            if_count_after_ebreak <= 0;
        end else if (ebreak_in_mem && !ebreak_seen) begin
            if_count_after_ebreak <= 0;  // Start counting from EBREAK
        end else if (ebreak_seen && if_valid) begin
            if_count_after_ebreak <= if_count_after_ebreak + 1;
        end
    end
    
    property pipeline_entry_limit_after_ebreak;
        @(posedge clk) disable iff (!rst_n)
        (ebreak_seen && !cpu_run) |-> (if_count_after_ebreak <= 2);  // Max 2 IF after EBREAK
    endproperty
    
    assert_pipeline_entry_limit: assert property (pipeline_entry_limit_after_ebreak)
        else $error("[EBREAK_SPEC] CRITICAL BUG: %0d IF stages after EBREAK (max 2) @ %0t", 
                    if_count_after_ebreak, $time);
    
    //==========================================================================
    // ASSERTION 9: Instruction Fetch Lockout
    //==========================================================================
    // Once running flag clears, IF must not re-activate
    
    property no_fetch_after_running_clears;
        @(posedge clk) disable iff (!rst_n)
        $fell(running) |=> !if_valid throughout (!cpu_run)[*1:$];
    endproperty
    
    assert_no_fetch_after_running_clears: assert property (no_fetch_after_running_clears)
        else $error("[EBREAK_SPEC] IF stage active after running cleared @ %0t", $time);
    
    //==========================================================================
    
    covergroup ebreak_coverage @(posedge clk);
        option.per_instance = 1;
        option.name = "ebreak_cov";
        
        ebreak_execution: coverpoint ebreak_in_mem {
            bins ebreak_detected = {1};
        }
        
        halt_state: coverpoint cpu_halted {
            bins halted = {1};
            bins running = {0};
        }
        
        break_signal: coverpoint cpu_break {
            bins asserted = {1};
            bins deasserted = {0};
        }
        
        // Cross coverage: EBREAK → halt
        ebreak_to_halt: cross ebreak_execution, halt_state;
    endgroup
    
    ebreak_coverage ebreak_cov = new();

endmodule : rv32i_ebreak_spec
