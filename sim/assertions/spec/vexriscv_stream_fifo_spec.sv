`timescale 1ns / 1ps
//==============================================================================
// VexRiscv Stream FIFO Specification
//==============================================================================
// Observer-only assertions for StreamFifoLowLatency (IBus response buffer).
// Checks: valid/ready handshake, hold requirement, and data stability when stalled.
// Bind target: StreamFifoLowLatency
//==============================================================================

`ifdef ENABLE_ASSERTIONS

module vexriscv_stream_fifo_spec (
    input logic clk,
    input logic reset,

    // Push side
    input logic        io_push_valid,
    input logic        io_push_ready,

    // Pop side
    input logic        io_pop_valid,
    input logic        io_pop_ready,
    input logic        io_pop_payload_error,
    input logic [31:0] io_pop_payload_inst,

    // FIFO status
    input logic        io_occupancy,   // 1-bit: 0=empty, 1=full (depth-1 FIFO)
    input logic        io_flush
);

    // -------------------------------------------------------------------------
    // Check 1: Valid/ready handshake – backpressure implies FIFO is occupied
    // When the FIFO cannot accept a push (push_ready=0), it must be full.
    // -------------------------------------------------------------------------
    property p_backpressure_implies_full;
        @(posedge clk) disable iff (reset)
        (io_push_valid && !io_push_ready) |-> io_occupancy;
    endproperty

    a_backpressure_implies_full: assert property (p_backpressure_implies_full)
        else $error("[STREAM_FIFO] push stalled (valid=1, ready=0) but occupancy=0");

    // When FIFO is empty (not occupied), it must accept pushes (ready=1)
    property p_empty_implies_push_ready;
        @(posedge clk) disable iff (reset)
        !io_occupancy |-> io_push_ready;
    endproperty

    a_empty_implies_push_ready: assert property (p_empty_implies_push_ready)
        else $error("[STREAM_FIFO] FIFO not occupied but push_ready=0");

    // -------------------------------------------------------------------------
    // Check 2: Hold requirement – when pop is stalled, pop_valid must be held
    // If the downstream consumer is not ready (!pop_ready), the FIFO must
    // keep pop_valid asserted until the consumer accepts.
    // -------------------------------------------------------------------------
    property p_pop_valid_held_when_stalled;
        @(posedge clk) disable iff (reset)
        (io_pop_valid && !io_pop_ready && !io_flush) |=> io_pop_valid;
    endproperty

    a_pop_valid_held_when_stalled: assert property (p_pop_valid_held_when_stalled)
        else $error("[STREAM_FIFO] pop_valid dropped while stalled (pop_ready=0, flush=0)");

    // -------------------------------------------------------------------------
    // Check 3: Data stability – output data must not change while stalled
    // When pop is valid but not accepted, both error and instruction fields
    // must remain stable until the handshake completes.
    // -------------------------------------------------------------------------
    property p_pop_data_stable_when_stalled;
        @(posedge clk) disable iff (reset)
        (io_pop_valid && !io_pop_ready && !io_flush)
        |=> $stable({io_pop_payload_error, io_pop_payload_inst});
    endproperty

    a_pop_data_stable_when_stalled: assert property (p_pop_data_stable_when_stalled)
        else $error("[STREAM_FIFO] pop data changed while stalled (pop_ready=0, flush=0)");

endmodule

`endif // ENABLE_ASSERTIONS
