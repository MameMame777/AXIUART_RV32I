`timescale 1ns/1ps
//==============================================================================
// StreamFifo Modules for VexRiscv
//
// Low-latency single-entry FIFO for instruction fetch response buffering
// Extracted from VexRiscv_GenSmallAndProductive.v (lines 3661-3801)
//==============================================================================

//==============================================================================
// StreamFifoLowLatency
// Wrapper around StreamFifo providing low-latency interface
//==============================================================================

module StreamFifoLowLatency (
    input  logic        io_push_valid,
    output logic        io_push_ready,
    input  logic        io_push_payload_error,
    input  logic [31:0] io_push_payload_inst,
    output logic        io_pop_valid,
    input  logic        io_pop_ready,
    output logic        io_pop_payload_error,
    output logic [31:0] io_pop_payload_inst,
    input  logic        io_flush,
    output logic [0:0]  io_occupancy,
    output logic [0:0]  io_availability,
    input  logic        clk,
    input  logic        reset
);

    logic        fifo_io_push_ready;
    logic        fifo_io_pop_valid;
    logic        fifo_io_pop_payload_error;
    logic [31:0] fifo_io_pop_payload_inst;
    logic [0:0]  fifo_io_occupancy;
    logic [0:0]  fifo_io_availability;

    StreamFifo fifo (
        .io_push_valid         (io_push_valid),
        .io_push_ready         (fifo_io_push_ready),
        .io_push_payload_error (io_push_payload_error),
        .io_push_payload_inst  (io_push_payload_inst),
        .io_pop_valid          (fifo_io_pop_valid),
        .io_pop_ready          (io_pop_ready),
        .io_pop_payload_error  (fifo_io_pop_payload_error),
        .io_pop_payload_inst   (fifo_io_pop_payload_inst),
        .io_flush              (io_flush),
        .io_occupancy          (fifo_io_occupancy),
        .io_availability       (fifo_io_availability),
        .clk                   (clk),
        .reset                 (reset)
    );

    assign io_push_ready = fifo_io_push_ready;
    assign io_pop_valid = fifo_io_pop_valid;
    assign io_pop_payload_error = fifo_io_pop_payload_error;
    assign io_pop_payload_inst = fifo_io_pop_payload_inst;
    assign io_occupancy = fifo_io_occupancy;
    assign io_availability = fifo_io_availability;

endmodule : StreamFifoLowLatency

//==============================================================================
// StreamFifo
// Single-entry FIFO with bypass path for zero-latency operation
//==============================================================================

module StreamFifo (
    input  logic        io_push_valid,
    output logic        io_push_ready,
    input  logic        io_push_payload_error,
    input  logic [31:0] io_push_payload_inst,
    output logic        io_pop_valid,
    input  logic        io_pop_ready,
    output logic        io_pop_payload_error,
    output logic [31:0] io_pop_payload_inst,
    input  logic        io_flush,
    output logic [0:0]  io_occupancy,
    output logic [0:0]  io_availability,
    input  logic        clk,
    input  logic        reset
);

    //==========================================================================
    // Internal Signals
    //==========================================================================
    
    logic        oneStage_doFlush;
    logic        oneStage_buffer_valid;
    logic        oneStage_buffer_ready;
    logic        oneStage_buffer_payload_error;
    logic [31:0] oneStage_buffer_payload_inst;
    
    logic        io_push_rValid;
    logic        io_push_rData_error;
    logic [31:0] io_push_rData_inst;
    
    logic        when_Stream_l477;
    logic        when_Stream_l1432;

    //==========================================================================
    // Flush Logic
    //==========================================================================
    
    always_comb begin
        oneStage_doFlush = io_flush;
        if (when_Stream_l1432) begin
            if (io_pop_ready) begin
                oneStage_doFlush = 1'b1;
            end
        end
    end

    //==========================================================================
    // Push Ready Logic
    //==========================================================================
    
    always_comb begin
        io_push_ready = oneStage_buffer_ready;
        if (when_Stream_l477) begin
            io_push_ready = 1'b1;
        end
    end

    assign when_Stream_l477 = (!oneStage_buffer_valid);
    
    //==========================================================================
    // Buffer State
    //==========================================================================
    
    assign oneStage_buffer_valid = io_push_rValid;
    assign oneStage_buffer_payload_error = io_push_rData_error;
    assign oneStage_buffer_payload_inst = io_push_rData_inst;
    
    //==========================================================================
    // Pop Valid Logic (with bypass)
    //==========================================================================
    
    always_comb begin
        io_pop_valid = oneStage_buffer_valid;
        if (when_Stream_l1432) begin
            io_pop_valid = io_push_valid;
        end
    end

    assign oneStage_buffer_ready = io_pop_ready;
    
    //==========================================================================
    // Pop Payload Logic (with bypass)
    //==========================================================================
    
    always_comb begin
        io_pop_payload_error = oneStage_buffer_payload_error;
        if (when_Stream_l1432) begin
            io_pop_payload_error = io_push_payload_error;
        end
    end

    always_comb begin
        io_pop_payload_inst = oneStage_buffer_payload_inst;
        if (when_Stream_l1432) begin
            io_pop_payload_inst = io_push_payload_inst;
        end
    end

    //==========================================================================
    // Occupancy Status
    //==========================================================================
    
    assign io_occupancy = oneStage_buffer_valid;
    assign io_availability = (!oneStage_buffer_valid);
    assign when_Stream_l1432 = (!oneStage_buffer_valid);
    
    //==========================================================================
    // Sequential Logic - Valid Register
    //==========================================================================
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            io_push_rValid <= 1'b0;
        end else begin
            if (io_push_ready) begin
                io_push_rValid <= io_push_valid;
            end
            if (oneStage_doFlush) begin
                io_push_rValid <= 1'b0;
            end
        end
    end

    //==========================================================================
    // Sequential Logic - Data Registers
    //==========================================================================
    
    always_ff @(posedge clk) begin
        if (io_push_ready) begin
            io_push_rData_error <= io_push_payload_error;
            io_push_rData_inst <= io_push_payload_inst;
        end
    end

endmodule : StreamFifo
