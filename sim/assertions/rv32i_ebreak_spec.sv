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
