`timescale 1ns / 1ps
//==============================================================================
// VexRiscv Jump Arbitration Specification
//==============================================================================
// Observer-only assertions for BranchPlugin and CsrPlugin jump interfaces.
// Checks: priority arbitration, flush signal propagation, and PC update.
// Bind target: VexRiscv
//==============================================================================

`ifdef ENABLE_ASSERTIONS

module vexriscv_jump_arbitration_spec (
    input logic clk,
    input logic reset,

    // Branch plugin jump interface (resolves in memory stage)
    input logic        BranchPlugin_jumpInterface_valid,
    input logic [31:0] BranchPlugin_jumpInterface_payload,

    // CSR plugin jump interface (MRET/trap entry, resolves in execute/writeBack)
    input logic        CsrPlugin_jumpInterface_valid,
    input logic [31:0] CsrPlugin_jumpInterface_payload,

    // Combined jump load (fed back to fetch PC)
    input logic        IBusSimplePlugin_jump_pcLoad_valid,
    input logic [31:0] IBusSimplePlugin_jump_pcLoad_payload,

    // Flush signals driven by branch/CSR jumps
    input logic        memory_arbitration_flushNext,
    input logic        execute_arbitration_flushNext,
    input logic        writeBack_arbitration_flushNext,

    // Fetch PC register (updated on jump)
    input logic [31:0] IBusSimplePlugin_fetchPc_pcReg
);

    // -------------------------------------------------------------------------
    // Check 1: Jump interface priority
    // When only Branch is valid, the combined output must use Branch target.
    // When only CSR is valid, the combined output must use CSR target.
    // -------------------------------------------------------------------------
    property p_branch_only_uses_branch_target;
        @(posedge clk) disable iff (reset)
        (BranchPlugin_jumpInterface_valid && !CsrPlugin_jumpInterface_valid)
        |-> (IBusSimplePlugin_jump_pcLoad_payload == BranchPlugin_jumpInterface_payload);
    endproperty

    a_branch_only_uses_branch_target: assert property (p_branch_only_uses_branch_target)
        else $error("[JUMP_ARB] Branch-only jump: pcLoad_payload=0x%08x != branch_target=0x%08x",
            IBusSimplePlugin_jump_pcLoad_payload, BranchPlugin_jumpInterface_payload);

    property p_csr_only_uses_csr_target;
        @(posedge clk) disable iff (reset)
        (!BranchPlugin_jumpInterface_valid && CsrPlugin_jumpInterface_valid)
        |-> (IBusSimplePlugin_jump_pcLoad_payload == CsrPlugin_jumpInterface_payload);
    endproperty

    a_csr_only_uses_csr_target: assert property (p_csr_only_uses_csr_target)
        else $error("[JUMP_ARB] CSR-only jump: pcLoad_payload=0x%08x != csr_target=0x%08x",
            IBusSimplePlugin_jump_pcLoad_payload, CsrPlugin_jumpInterface_payload);

    // When any jump is valid, the combined pcLoad must also be valid
    property p_any_jump_implies_pcload_valid;
        @(posedge clk) disable iff (reset)
        (BranchPlugin_jumpInterface_valid || CsrPlugin_jumpInterface_valid)
        |-> IBusSimplePlugin_jump_pcLoad_valid;
    endproperty

    a_any_jump_implies_pcload_valid: assert property (p_any_jump_implies_pcload_valid)
        else $error("[JUMP_ARB] jump interface valid but IBusSimplePlugin_jump_pcLoad_valid=0");

    // -------------------------------------------------------------------------
    // Check 2: Flush signal propagation
    // Branch jump (resolved in memory stage) flushes memory_flushNext so that
    // decode/execute stages are invalidated.
    // CSR jump (exception/MRET, resolved in writeBack stage) flushes
    // writeBack_arbitration_flushNext — which propagates to all earlier stages.
    // -------------------------------------------------------------------------
    property p_branch_jump_flushes_memory;
        @(posedge clk) disable iff (reset)
        BranchPlugin_jumpInterface_valid |-> memory_arbitration_flushNext;
    endproperty

    a_branch_jump_flushes_memory: assert property (p_branch_jump_flushes_memory)
        else $error("[JUMP_ARB] BranchPlugin jump valid but memory_arbitration_flushNext=0");

    property p_csr_jump_flushes_writeback;
        @(posedge clk) disable iff (reset)
        CsrPlugin_jumpInterface_valid |-> writeBack_arbitration_flushNext;
    endproperty

    a_csr_jump_flushes_writeback: assert property (p_csr_jump_flushes_writeback)
        else $error("[JUMP_ARB] CsrPlugin jump valid but writeBack_arbitration_flushNext=0");

    // -------------------------------------------------------------------------
    // Check 3: PC update after jump
    // When a jump load is valid, the fetch PC register is updated to the
    // jump target in the following clock cycle.
    // -------------------------------------------------------------------------
    property p_pc_updated_after_jump;
        @(posedge clk) disable iff (reset)
        IBusSimplePlugin_jump_pcLoad_valid
        |=> (IBusSimplePlugin_fetchPc_pcReg == $past(IBusSimplePlugin_jump_pcLoad_payload, 1));
    endproperty

    a_pc_updated_after_jump: assert property (p_pc_updated_after_jump)
        else $error("[JUMP_ARB] PC not updated after jump: pcReg=0x%08x expected=0x%08x",
            IBusSimplePlugin_fetchPc_pcReg, $past(IBusSimplePlugin_jump_pcLoad_payload, 1));

endmodule

`endif // ENABLE_ASSERTIONS
