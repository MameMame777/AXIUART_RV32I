`timescale 1ns / 1ps

//==============================================================================
// RV32I IF Stage Timing Assertions
//==============================================================================
// SystemVerilog Assertions for Instruction Fetch stage
// Verifies PC management, branch redirects, stall/flush behavior, and
// breakpoint detection according to rv32i_if_spec.md
//
// Bind this module to rv32i_if instance in rv32i_top:
//   bind rv32i_if rv32i_if_timing_spec u_if_assertions (.*);
//==============================================================================

module rv32i_if_timing_spec
    import rv32i_isa_pkg::*;
(
    input logic        clk,
    input logic        rst_n,
    
    // IF module signals (from binding)
    input logic [31:0] pc_current,
    input logic        if_valid,
    input logic        if_stall,
    input logic        if_flush,
    input logic        branch_taken,
    input logic [31:0] branch_target,
    input logic        exception_trap,
    input logic [31:0] trap_vector,
    input logic        mret_req,
    input logic [31:0] mret_pc,
    input logic [10:0] insn_ram_addr,
    input logic [3:0]  dbg_bp_enable,
    input logic [31:0] dbg_bp_addr[4],
    input logic [3:0]  dbg_bp_hit,
    input logic        cpu_break,
    input logic        running,
    input logic        bp_skip_once,
    input logic        bp_match,
    input logic [31:0] pc_next,
    input logic [31:0] pc_out,
    input logic        valid_out
);

    //==========================================================================
    // SPEC-IF-1: PC Sequential Increment
    //==========================================================================
    // When no redirects and not stalled, PC increments by 4
    
    property pc_sequential_increment;
        @(posedge clk) disable iff (!rst_n)
        (if_valid && !if_stall && !if_flush && !branch_taken && 
         !exception_trap && !mret_req && running)
        |-> (pc_next == pc_current + 32'd4);
    endproperty
    
    assert_pc_sequential: assert property (pc_sequential_increment)
        else $error("[SPEC-IF-1] PC sequential increment failed: pc_current=0x%08h, pc_next=0x%08h", 
                    pc_current, pc_next);
    
    //==========================================================================
    // SPEC-IF-2: Branch Redirect
    //==========================================================================
    // When branch taken, PC redirects to branch target
    
    property branch_redirect;
        @(posedge clk) disable iff (!rst_n)
        (branch_taken && !exception_trap && !mret_req)
        |-> (pc_next == branch_target);
    endproperty
    
    assert_branch_redirect: assert property (branch_redirect)
        else $error("[SPEC-IF-2] Branch redirect failed: branch_target=0x%08h, pc_next=0x%08h", 
                    branch_target, pc_next);
    
    //==========================================================================
    // SPEC-IF-3: Exception Trap Redirect (Highest Priority)
    //==========================================================================
    // Exception trap overrides all other PC sources
    
    property exception_trap_redirect;
        @(posedge clk) disable iff (!rst_n)
        (exception_trap)
        |-> (pc_next == trap_vector);
    endproperty
    
    assert_exception_trap: assert property (exception_trap_redirect)
        else $error("[SPEC-IF-3] Exception trap redirect failed: trap_vector=0x%08h, pc_next=0x%08h", 
                    trap_vector, pc_next);
    
    //==========================================================================
    // SPEC-IF-4: MRET Redirect
    //==========================================================================
    // MRET restores PC from mepc CSR
    
    property mret_redirect;
        @(posedge clk) disable iff (!rst_n)
        (mret_req && !exception_trap)
        |-> (pc_next == mret_pc);
    endproperty
    
    assert_mret_redirect: assert property (mret_redirect)
        else $error("[SPEC-IF-4] MRET redirect failed: mret_pc=0x%08h, pc_next=0x%08h", 
                    mret_pc, pc_next);
    
    //==========================================================================
    // SPEC-IF-5: Stall Holds PC
    //==========================================================================
    // When stalled, PC remains unchanged
    
    property stall_holds_pc;
        @(posedge clk) disable iff (!rst_n)
        (if_stall && !branch_taken && !exception_trap && !mret_req)
        |-> (pc_next == pc_current);
    endproperty
    
    assert_stall_holds_pc: assert property (stall_holds_pc)
        else $error("[SPEC-IF-5] Stall did not hold PC: pc_current=0x%08h, pc_next=0x%08h", 
                    pc_current, pc_next);
    
    //==========================================================================
    // SPEC-IF-6: Breakpoint Detection
    //==========================================================================
    // Breakpoint match when PC equals enabled breakpoint address
    
    property breakpoint_detection;
        logic bp_expected;
        @(posedge clk) disable iff (!rst_n)
        (running, 
         bp_expected = (dbg_bp_enable[0] && pc_current == dbg_bp_addr[0]) ||
                       (dbg_bp_enable[1] && pc_current == dbg_bp_addr[1]) ||
                       (dbg_bp_enable[2] && pc_current == dbg_bp_addr[2]) ||
                       (dbg_bp_enable[3] && pc_current == dbg_bp_addr[3]))
        |-> (bp_match == bp_expected);
    endproperty
    
    assert_breakpoint_detection: assert property (breakpoint_detection)
        else $error("[SPEC-IF-6] Breakpoint detection mismatch at PC=0x%08h", pc_current);
    
    //==========================================================================
    // SPEC-IF-7: RAM Address Generation
    //==========================================================================
    // Instruction RAM address is word address (PC[12:2])
    
    property ram_address_generation;
        @(posedge clk) disable iff (!rst_n)
        (if_valid)
        |-> (insn_ram_addr == pc_current[12:2]);
    endproperty
    
    assert_ram_address: assert property (ram_address_generation)
        else $error("[SPEC-IF-7] RAM address mismatch: pc_current=0x%08h, insn_ram_addr=0x%03h, expected=0x%03h", 
                    pc_current, insn_ram_addr, pc_current[12:2]);
    
    //==========================================================================
    // SPEC-IF-8: Flush Invalidates Output
    //==========================================================================
    // When flushed, valid_out must be 0
    
    property flush_invalidates;
        @(posedge clk) disable iff (!rst_n)
        (if_flush)
        |-> (valid_out == 1'b0);
    endproperty
    
    assert_flush_invalidates: assert property (flush_invalidates)
        else $error("[SPEC-IF-8] Flush did not invalidate output: valid_out=%b", valid_out);
    
    //==========================================================================
    // SPEC-IF-9: Breakpoint Hit Flags
    //==========================================================================
    // Individual breakpoint hit flags correctly reflect PC match
    
    property breakpoint_hit_flags;
        @(posedge clk) disable iff (!rst_n)
        (running && dbg_bp_enable[0] && pc_current == dbg_bp_addr[0])
        |-> (dbg_bp_hit[0] == 1'b1);
    endproperty
    
    assert_bp_hit_0: assert property (breakpoint_hit_flags)
        else $error("[SPEC-IF-9] Breakpoint 0 hit flag incorrect at PC=0x%08h", pc_current);
    
    //==========================================================================
    // Coverage: PC Update Sources
    //==========================================================================
    
    covergroup pc_update_cg @(posedge clk);
        option.per_instance = 1;
        option.name = "if_pc_update_coverage";
        
        pc_source: coverpoint {exception_trap, mret_req, branch_taken, if_stall} {
            bins sequential     = {4'b0000};
            bins branch         = {4'b0010};
            bins exception      = {4'b1000}, {4'b1010}, {4'b1100}, {4'b1110};  // Exception overrides all
            bins mret           = {4'b0100}, {4'b0110};  // MRET (no exception)
            bins stall          = {4'b0001}, {4'b0011}, {4'b0101}, {4'b0111};  // Any stall
        }
        
        breakpoint_coverage: coverpoint bp_match {
            bins no_breakpoint = {1'b0};
            bins breakpoint_hit = {1'b1};
        }
        
        flush_coverage: coverpoint if_flush {
            bins no_flush = {1'b0};
            bins flush_active = {1'b1};
        }
    endgroup
    
    pc_update_cg pc_update_inst = new();
    
    //==========================================================================
    // Functional Coverage: Breakpoint Combinations
    //==========================================================================
    
    covergroup bp_combination_cg @(posedge clk);
        option.per_instance = 1;
        option.name = "if_breakpoint_combination_coverage";
        
        bp0_en: coverpoint dbg_bp_enable[0];
        bp1_en: coverpoint dbg_bp_enable[1];
        bp2_en: coverpoint dbg_bp_enable[2];
        bp3_en: coverpoint dbg_bp_enable[3];
        
        bp_skip: coverpoint bp_skip_once {
            bins skip_inactive = {1'b0};
            bins skip_active = {1'b1};
        }
        
        // Cross coverage: breakpoint hit with skip
        bp_hit_with_skip: cross bp_match, bp_skip_once;
    endgroup
    
    bp_combination_cg bp_combination_inst = new();

endmodule : rv32i_if_timing_spec
