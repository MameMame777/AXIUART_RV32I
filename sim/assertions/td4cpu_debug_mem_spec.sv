`timescale 1ns / 1ps

//==============================================================================
// TD4 CPU Debug Memory Access Specification (SVA)
//==============================================================================
// Purpose: Formal specification of debug memory read/write timing requirements
// This module defines the REQUIRED behavior as executable assertions
// Created: 2026-01-01 - BUG#7 Resolution
//==============================================================================

module td4cpu_debug_mem_spec (
    input wire clk,
    input wire rst,
    
    // Debug interface
    input wire dbg_mem_read_req,
    input wire dbg_mem_write_req,
    input wire [15:0] dbg_mem_addr,
    input wire [15:0] dbg_mem_wdata,
    input wire [15:0] dbg_mem_rdata,
    input wire dbg_mem_err,
    
    // CPU state
    input wire halted,
    input wire running,
    
    // Internal signals (for verification)
    input wire mem_busy_q,
    input wire ram_rd_en,
    input wire ram_wr_en,
    input wire ram_read_phase,
    input wire mem_data_valid,
    input wire [15:0] ram_rd_data
);

    //==========================================================================
    // SPEC 1: Debug Memory Read Sequence Timing
    //==========================================================================
    // Requirement: RAM read requires 3-cycle sequence when halted
    // Cycle N:   Request arrives → set mem_busy_q=1, ram_rd_en=1, ram_read_phase=1
    // Cycle N+1: Hold ram_rd_en=1, transition ram_read_phase=0
    // Cycle N+2: Capture data, clear ram_rd_en, set mem_data_valid=1
    // Cycle N+3: Clear mem_busy_q and mem_data_valid
    
    sequence debug_read_request;
        (halted && !running && dbg_mem_read_req && !mem_busy_q);
    endsequence
    
    sequence debug_read_cycle1_setup;
        (mem_busy_q && ram_rd_en && ram_read_phase);
    endsequence
    
    sequence debug_read_cycle2_hold;
        (mem_busy_q && ram_rd_en && !ram_read_phase);
    endsequence
    
    sequence debug_read_cycle3_capture;
        (mem_busy_q && !ram_rd_en && mem_data_valid);
    endsequence
    
    sequence debug_read_cycle4_complete;
        (!mem_busy_q && !mem_data_valid && !ram_rd_en);
    endsequence
    
    // ASSERTION: Full read sequence must complete in 4 cycles
    // NOTE: This check is informational - use $error not $fatal to allow debugging
    property p_debug_read_4cycle_sequence;
        @(posedge clk) disable iff (rst)
        debug_read_request |=> 
            debug_read_cycle1_setup ##1
            debug_read_cycle2_hold ##1
            debug_read_cycle3_capture ##1
            debug_read_cycle4_complete;
    endproperty
    
    assert_debug_read_sequence: assert property (p_debug_read_4cycle_sequence)
        else $error("[SPEC_INFO] Debug read sequence did not follow exact 4-cycle protocol");
    
    //==========================================================================
    // SPEC 2: ram_rd_en Must Stay High During Active Read
    //==========================================================================
    // Requirement: Once ram_rd_en is asserted for debug read, it MUST stay
    //              high until data capture in Cycle N+2
    
    property p_ram_rd_en_hold_during_read;
        @(posedge clk) disable iff (rst)
        (mem_busy_q && ram_rd_en && ram_read_phase) |=> 
            ram_rd_en throughout ((!ram_read_phase) [->1]);
    endproperty
    
    assert_ram_rd_en_stable: assert property (p_ram_rd_en_hold_during_read)
        else $fatal(1, "[SPEC_FATAL] ram_rd_en cleared prematurely during debug read - CRITICAL TIMING VIOLATION");
    
    //==========================================================================
    // SPEC 3: mem_busy_q Must Protect Entire Sequence
    //==========================================================================
    // Requirement: mem_busy_q MUST remain high for full 3-cycle read sequence
    //              (Cycles N+1, N+2, N+3) and only clear in Cycle N+4
    
    property p_mem_busy_q_protection;
        @(posedge clk) disable iff (rst)
        (debug_read_request ##1 mem_busy_q) |->
            mem_busy_q [*3];  // Must stay high for 3 consecutive cycles
    endproperty
    
    assert_mem_busy_q_hold: assert property (p_mem_busy_q_protection)
        else $fatal(1, "[SPEC_FATAL] mem_busy_q cleared too early during debug read - CRITICAL TIMING VIOLATION");
    
    //==========================================================================
    // SPEC 4: Data Capture Timing
    //==========================================================================
    // Requirement: Data must be captured exactly in Cycle N+2 when
    //              ram_read_phase=0 and ram_rd_en=1
    
    property p_data_capture_timing;
        @(posedge clk) disable iff (rst)
        (mem_busy_q && !ram_read_phase && ram_rd_en) |=>
            (mem_data_valid && !ram_rd_en);
    endproperty
    
    assert_data_capture: assert property (p_data_capture_timing)
        else $error("[SPEC_INFO] Data not captured at expected cycle");
    
    //==========================================================================
    // SPEC 5: No Premature ram_rd_en Clear (CRITICAL)
    //==========================================================================
    // Requirement: ram_rd_en must NOT be cleared while mem_busy_q is active
    //              EXCEPT in the data capture cycle (ram_read_phase=0)
    //              This is the CRITICAL invariant that BUG#7 violated
    
    property p_no_ram_rd_en_clear_during_busy;
        @(posedge clk) disable iff (rst)
        (mem_busy_q && ram_rd_en && ram_read_phase) |=> 
            (mem_busy_q |-> ram_rd_en);  // If busy still active AND still in read phase, rd_en must stay high
    endproperty
    
    assert_ram_rd_en_protected: assert property (p_no_ram_rd_en_clear_during_busy)
        else $fatal(1, "[SPEC_FATAL] CRITICAL: ram_rd_en cleared prematurely during RAM access phase");
    
    //==========================================================================
    // SPEC 6: Debug Read Only When Halted
    //==========================================================================
    // Requirement: Debug memory operations only allowed when CPU is halted
    
    property p_debug_only_when_halted;
        @(posedge clk) disable iff (rst)
        (dbg_mem_read_req || dbg_mem_write_req) |-> (halted && !running);
    endproperty
    
    assert_debug_halted_only: assert property (p_debug_only_when_halted)
        else $error("[SPEC_INFO] Debug memory access attempted while CPU running");
    
    //==========================================================================
    // SPEC 7: Mutually Exclusive Operations
    //==========================================================================
    // Requirement: Read and write requests must not occur simultaneously
    
    property p_read_write_mutex;
        @(posedge clk) disable iff (rst)
        not (dbg_mem_read_req && dbg_mem_write_req);
    endproperty
    
    assert_mutex: assert property (p_read_write_mutex)
        else $fatal(1, "[SPEC_FATAL] Simultaneous read and write request - PROTOCOL VIOLATION");
    
    //==========================================================================
    // SPEC 8: mem_data_valid Clear Timing
    //==========================================================================
    // Requirement: mem_data_valid clears in same cycle as mem_busy_q
    
    property p_data_valid_clear_with_busy;
        @(posedge clk) disable iff (rst)
        ($fell(mem_busy_q) && $past(mem_data_valid)) |-> !mem_data_valid;
    endproperty
    
    assert_data_valid_clear: assert property (p_data_valid_clear_with_busy)
        else $error("[SPEC] mem_data_valid did not clear with mem_busy_q");
    
    //==========================================================================
    // Coverage: Verify All States Exercised
    //==========================================================================
    
    covergroup cg_debug_read_states @(posedge clk);
        option.per_instance = 1;
        option.name = "debug_read_coverage";
        
        cp_cycle1: coverpoint (mem_busy_q && ram_rd_en && ram_read_phase) {
            bins cycle1 = {1};
        }
        cp_cycle2: coverpoint (mem_busy_q && ram_rd_en && !ram_read_phase) {
            bins cycle2 = {1};
        }
        cp_cycle3: coverpoint (mem_busy_q && !ram_rd_en && mem_data_valid) {
            bins cycle3 = {1};
        }
        cp_cycle4: coverpoint (!mem_busy_q && !mem_data_valid) {
            bins cycle4 = {1};
        }
        
        // Cross coverage: Verify full sequence exercised
        cx_full_sequence: cross cp_cycle1, cp_cycle2, cp_cycle3, cp_cycle4;
    endgroup
    
    cg_debug_read_states cg_inst = new();
    
    //==========================================================================
    // Helper: Detect sequence violations for debugging
    //==========================================================================
    
    logic [2:0] sequence_state;
    logic is_read_request, is_cycle1, is_cycle2, is_cycle3, is_cycle4;
    
    assign is_read_request = halted && !running && dbg_mem_read_req && !mem_busy_q;
    assign is_cycle1 = mem_busy_q && ram_rd_en && ram_read_phase;
    assign is_cycle2 = mem_busy_q && ram_rd_en && !ram_read_phase;
    assign is_cycle3 = mem_busy_q && !ram_rd_en && mem_data_valid;
    assign is_cycle4 = !mem_busy_q && !mem_data_valid && !ram_rd_en;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sequence_state <= 3'd0;
        end else begin
            case (sequence_state)
                3'd0: if (is_read_request) sequence_state <= 3'd1;
                3'd1: if (is_cycle1) sequence_state <= 3'd2;
                      else sequence_state <= 3'd0;  // Abort on violation
                3'd2: if (is_cycle2) sequence_state <= 3'd3;
                      else sequence_state <= 3'd0;
                3'd3: if (is_cycle3) sequence_state <= 3'd4;
                      else sequence_state <= 3'd0;
                3'd4: if (is_cycle4) sequence_state <= 3'd0;
                      else sequence_state <= 3'd0;
                default: sequence_state <= 3'd0;
            endcase
        end
    end

endmodule

//==============================================================================
// Bind Statement - Add to testbench or compile list
//==============================================================================
// bind td4cpu_core td4cpu_debug_mem_spec spec_checker (
//     .clk(clk),
//     .rst(rst),
//     .dbg_mem_read_req(dbg_mem_read_req),
//     .dbg_mem_write_req(dbg_mem_write_req),
//     .dbg_mem_addr(dbg_mem_addr),
//     .dbg_mem_wdata(dbg_mem_wdata),
//     .dbg_mem_rdata(dbg_mem_rdata),
//     .dbg_mem_err(dbg_mem_err),
//     .halted(halted),
//     .running(running),
//     .mem_busy_q(mem_busy_q),
//     .ram_rd_en(ram_rd_en),
//     .ram_wr_en(ram_wr_en),
//     .ram_read_phase(ram_read_phase),
//     .mem_data_valid(mem_data_valid),
//     .ram_rd_data(ram_rd_data)
// );
