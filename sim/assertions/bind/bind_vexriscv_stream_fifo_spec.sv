`timescale 1ns / 1ps
//==============================================================================
// Bind VexRiscv Stream FIFO Specification
// Binds to StreamFifoLowLatency (IBus response buffer instance inside VexRiscv)
//==============================================================================

`ifdef ENABLE_ASSERTIONS

bind StreamFifoLowLatency vexriscv_stream_fifo_spec u_vexriscv_stream_fifo_spec (
    .clk                      (clk),
    .reset                    (reset),
    .io_push_valid            (io_push_valid),
    .io_push_ready            (io_push_ready),
    .io_pop_valid             (io_pop_valid),
    .io_pop_ready             (io_pop_ready),
    .io_pop_payload_error     (io_pop_payload_error),
    .io_pop_payload_inst      (io_pop_payload_inst),
    .io_occupancy             (io_occupancy),
    .io_flush                 (io_flush)
);

`endif // ENABLE_ASSERTIONS
