`timescale 1ns / 1ps
//==============================================================================
// VexRiscv Pipeline Arbitration Specification
//==============================================================================
// Observer-only assertions for pipeline stage arbitration invariants.
// Checks valid propagation, stuck consistency, isFiring, and flush propagation.
// Bind target: VexRiscv
//==============================================================================

`ifdef ENABLE_ASSERTIONS

module vexriscv_pipeline_arbitration_spec (
    input logic clk,
    input logic reset,

    // Decode stage arbitration
    input logic decode_arbitration_isValid,
    input logic decode_arbitration_isStuck,
    input logic decode_arbitration_isStuckByOthers,
    input logic decode_arbitration_isFlushed,
    input logic decode_arbitration_isMoving,
    input logic decode_arbitration_isFiring,
    input logic decode_arbitration_haltItself,
    input logic decode_arbitration_flushNext,

    // Execute stage arbitration
    input logic execute_arbitration_isValid,
    input logic execute_arbitration_isStuck,
    input logic execute_arbitration_isStuckByOthers,
    input logic execute_arbitration_isFlushed,
    input logic execute_arbitration_isMoving,
    input logic execute_arbitration_isFiring,
    input logic execute_arbitration_haltItself,
    input logic execute_arbitration_flushNext,

    // Memory stage arbitration
    input logic memory_arbitration_isValid,
    input logic memory_arbitration_isStuck,
    input logic memory_arbitration_isFlushed,
    input logic memory_arbitration_isMoving,
    input logic memory_arbitration_isFiring,
    input logic memory_arbitration_haltItself,
    input logic memory_arbitration_flushNext,

    // WriteBack stage arbitration
    input logic writeBack_arbitration_isValid,
    input logic writeBack_arbitration_isStuck,
    input logic writeBack_arbitration_isFlushed,
    input logic writeBack_arbitration_isMoving,
    input logic writeBack_arbitration_isFiring
);

    // -------------------------------------------------------------------------
    // Check 1: Valid propagation
    // isFiring implies isValid must be true (can only fire if valid instruction)
    // -------------------------------------------------------------------------
    property p_decode_firing_implies_valid;
        @(posedge clk) disable iff (reset)
        decode_arbitration_isFiring |-> decode_arbitration_isValid;
    endproperty

    a_decode_firing_implies_valid: assert property (p_decode_firing_implies_valid)
        else $error("[PIPE_ARB] decode: isFiring but isValid=0");

    property p_execute_firing_implies_valid;
        @(posedge clk) disable iff (reset)
        execute_arbitration_isFiring |-> execute_arbitration_isValid;
    endproperty

    a_execute_firing_implies_valid: assert property (p_execute_firing_implies_valid)
        else $error("[PIPE_ARB] execute: isFiring but isValid=0");

    property p_memory_firing_implies_valid;
        @(posedge clk) disable iff (reset)
        memory_arbitration_isFiring |-> memory_arbitration_isValid;
    endproperty

    a_memory_firing_implies_valid: assert property (p_memory_firing_implies_valid)
        else $error("[PIPE_ARB] memory: isFiring but isValid=0");

    property p_writeback_firing_implies_valid;
        @(posedge clk) disable iff (reset)
        writeBack_arbitration_isFiring |-> writeBack_arbitration_isValid;
    endproperty

    a_writeback_firing_implies_valid: assert property (p_writeback_firing_implies_valid)
        else $error("[PIPE_ARB] writeBack: isFiring but isValid=0");

    // -------------------------------------------------------------------------
    // Check 2: isStuck == (haltItself || isStuckByOthers)
    // When stuck, at least one halt cause must exist
    // When not stuck, no halt causes exist
    // -------------------------------------------------------------------------
    property p_decode_stuck_cause;
        @(posedge clk) disable iff (reset)
        decode_arbitration_isStuck |-> (decode_arbitration_haltItself || decode_arbitration_isStuckByOthers);
    endproperty

    a_decode_stuck_cause: assert property (p_decode_stuck_cause)
        else $error("[PIPE_ARB] decode: isStuck without halt cause (haltItself=%0b, isStuckByOthers=%0b)",
            decode_arbitration_haltItself, decode_arbitration_isStuckByOthers);

    property p_decode_not_stuck_no_cause;
        @(posedge clk) disable iff (reset)
        !decode_arbitration_isStuck |-> (!decode_arbitration_haltItself && !decode_arbitration_isStuckByOthers);
    endproperty

    a_decode_not_stuck_no_cause: assert property (p_decode_not_stuck_no_cause)
        else $error("[PIPE_ARB] decode: !isStuck but halt cause exists (haltItself=%0b, isStuckByOthers=%0b)",
            decode_arbitration_haltItself, decode_arbitration_isStuckByOthers);

    // -------------------------------------------------------------------------
    // Check 3: isFiring == (isValid && isMoving)
    // Triple equivalence for decode stage (representative check)
    // -------------------------------------------------------------------------
    property p_decode_firing_eq_valid_moving;
        @(posedge clk) disable iff (reset)
        decode_arbitration_isFiring |-> (decode_arbitration_isValid && decode_arbitration_isMoving);
    endproperty

    a_decode_firing_eq_valid_moving: assert property (p_decode_firing_eq_valid_moving)
        else $error("[PIPE_ARB] decode: isFiring=1 but isValid=%0b or isMoving=%0b",
            decode_arbitration_isValid, decode_arbitration_isMoving);

    property p_decode_valid_moving_eq_firing;
        @(posedge clk) disable iff (reset)
        (decode_arbitration_isValid && decode_arbitration_isMoving) |-> decode_arbitration_isFiring;
    endproperty

    a_decode_valid_moving_eq_firing: assert property (p_decode_valid_moving_eq_firing)
        else $error("[PIPE_ARB] decode: isValid && isMoving but isFiring=0");

    // -------------------------------------------------------------------------
    // Check 4: Flush signal propagation
    // When a downstream stage asserts flushNext, upstream stages become flushed
    // (combinational, same-cycle relationship)
    // -------------------------------------------------------------------------
    property p_execute_flushNext_flushes_decode;
        @(posedge clk) disable iff (reset)
        execute_arbitration_flushNext |-> decode_arbitration_isFlushed;
    endproperty

    a_execute_flushNext_flushes_decode: assert property (p_execute_flushNext_flushes_decode)
        else $error("[PIPE_ARB] execute flushNext asserted but decode_isFlushed=0");

    property p_memory_flushNext_flushes_execute;
        @(posedge clk) disable iff (reset)
        memory_arbitration_flushNext |-> execute_arbitration_isFlushed;
    endproperty

    a_memory_flushNext_flushes_execute: assert property (p_memory_flushNext_flushes_execute)
        else $error("[PIPE_ARB] memory flushNext asserted but execute_isFlushed=0");

    property p_memory_flushNext_flushes_decode;
        @(posedge clk) disable iff (reset)
        memory_arbitration_flushNext |-> decode_arbitration_isFlushed;
    endproperty

    a_memory_flushNext_flushes_decode: assert property (p_memory_flushNext_flushes_decode)
        else $error("[PIPE_ARB] memory flushNext asserted but decode_isFlushed=0");

endmodule

`endif // ENABLE_ASSERTIONS
