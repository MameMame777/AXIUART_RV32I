`timescale 1ns / 1ps

//==============================================================================
// TD4 CPU Fetch Specification (Executable Specification via SVA)
//==============================================================================
// This module defines the CORRECT fetch behavior as SystemVerilog Assertions.
// These assertions serve as the formal specification for CPU instruction fetch.
//
// Specification Rules:
// 1. Sequential Fetch: When PC=N, fetch from ram[N-1]
// 2. Branch Fetch: When branching to target T, fetch from ram[T-1]
// 3. Data Consistency: Fetched instruction must match RAM content at fetch address
//
// Purpose: Detect and verify fix for branch fetch addressing bug (BUG#10)
//==============================================================================

module td4cpu_fetch_spec (
    input  logic        clk,
    input  logic        rst,
    input  logic        running,
    input  logic [15:0] pc,
    input  logic [15:0] ram_addr_next,
    input  logic        ram_rd_en,
    input  logic        branch_pending,
    input  logic [15:0] branch_target_pending,
    input  logic [15:0] insn_fetched,
    input  logic [15:0] ram [0:65535]
);

    //==========================================================================
    // Local Variables for Specification
    //==========================================================================
    logic [15:0] captured_fetch_addr;
    logic [15:0] expected_insn_data;
    
    // Capture fetch address and expected data for verification
    always_ff @(posedge clk) begin
        if (ram_rd_en && !rst) begin
            captured_fetch_addr <= ram_addr_next;
            expected_insn_data  <= ram[ram_addr_next];
        end
    end

    //==========================================================================
    // SPEC 1: Sequential Fetch Address Specification
    //==========================================================================
    // When executing sequentially (no branch pending), the fetch address
    // MUST be (PC - 1) because PC has already been incremented.
    //
    // Example: PC=3 should fetch from ram[2]
    //==========================================================================
    property p_sequential_fetch_address;
        @(posedge clk) disable iff (rst || !running)
        (ram_rd_en && !branch_pending && pc > 0) 
        |-> (ram_addr_next == (pc - 16'd1));
    endproperty

    ast_sequential_fetch: assert property(p_sequential_fetch_address)
    else $error("[FETCH_SPEC_VIOLATION] Sequential fetch: PC=%0d should fetch from addr %0d, but ram_addr_next=%0d",
                pc, pc-1, ram_addr_next);

    //==========================================================================
    // SPEC 2: Branch Target Fetch Address Specification
    //==========================================================================
    // When branch is pending, the fetch address MUST be (target - 1).
    // This is consistent with sequential fetch behavior.
    //
    // Example: Branch to PC=5 should fetch from ram[4]
    //
    // CRITICAL: This assertion WILL FAIL with current CPU bug at line 862.
    // Expected violation: "[FETCH_BUG] Branch to PC=5 should fetch from addr 4, but ram_addr_next=5"
    //==========================================================================
    property p_branch_fetch_address;
        @(posedge clk) disable iff (rst || !running)
        (ram_rd_en && branch_pending && branch_target_pending > 0)
        |-> (ram_addr_next == (branch_target_pending - 16'd1));
    endproperty

    ast_branch_fetch: assert property(p_branch_fetch_address)
    else $error("[FETCH_BUG] Branch to PC=%0d should fetch from addr %0d, but ram_addr_next=%0d",
                branch_target_pending, branch_target_pending-1, ram_addr_next);

    //==========================================================================
    // SPEC 3: Fetch Data Correspondence
    //==========================================================================
    // The instruction fetched MUST match the RAM content at the fetch address.
    // This verifies that the addressing is working end-to-end.
    //==========================================================================
    property p_fetch_data_match;
        @(posedge clk) disable iff (rst)
        ($rose(insn_fetched !== 16'hxxxx) && captured_fetch_addr !== 16'hxxxx)
        |-> (insn_fetched == expected_insn_data);
    endproperty

    ast_fetch_data: assert property(p_fetch_data_match)
    else $error("[FETCH_DATA_MISMATCH] Fetched insn=0x%04h from addr %0d, but expected 0x%04h from ram[%0d]",
                insn_fetched, captured_fetch_addr, expected_insn_data, captured_fetch_addr);

    //==========================================================================
    // Coverage: Fetch Scenarios
    //==========================================================================
    covergroup cg_fetch_scenarios @(posedge clk);
        option.per_instance = 1;
        
        cp_fetch_type: coverpoint {branch_pending, ram_rd_en} {
            bins sequential = {2'b01};
            bins branch     = {2'b11};
            bins idle       = {2'b00};
        }
        
        cp_pc_range: coverpoint pc {
            bins low    = {[16'h0000:16'h000F]};
            bins mid    = {[16'h0010:16'h00FF]};
            bins high   = {[16'h0100:16'hFFFF]};
        }
    endgroup

    cg_fetch_scenarios cg_fetch = new();

    //==========================================================================
    // Debug Output (Optional)
    //==========================================================================
    always_ff @(posedge clk) begin
        if (ram_rd_en && !rst && running) begin
            if (branch_pending) begin
                $display("[FETCH_DEBUG] Branch fetch: target=%0d, fetch_addr=%0d (expected %0d), insn=0x%04h",
                         branch_target_pending, ram_addr_next, branch_target_pending-1, ram[ram_addr_next]);
            end else begin
                $display("[FETCH_DEBUG] Sequential fetch: PC=%0d, fetch_addr=%0d (expected %0d), insn=0x%04h",
                         pc, ram_addr_next, pc-1, ram[ram_addr_next]);
            end
        end
    end

endmodule

//==============================================================================
// Expected Behavior After Fix:
//==============================================================================
// Before Fix (BUG):
//   - ast_branch_fetch will FAIL
//   - Error: "[FETCH_BUG] Branch to PC=5 should fetch from addr 4, but ram_addr_next=5"
//
// After Fix (line 862: ram_addr_next <= branch_target_pending - 16'd1):
//   - All assertions PASS
//   - Debug output shows correct fetch addresses
//   - All branch tests pass with correct register values
//==============================================================================
