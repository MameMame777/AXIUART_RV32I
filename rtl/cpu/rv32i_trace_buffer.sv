`timescale 1ns / 1ps

//==============================================================================
// RV32I CPU Trace Buffer for Fast UVM Verification
//==============================================================================
// Captures executed instructions with PC, opcode, and result data
// Provides direct memory access for UVM testbench without UART overhead
// Updated from TD4CPU 16-bit version to RV32I 32-bit architecture
//
// Author: GitHub Copilot (RV32I Migration)
// Date: 2026-01-02
// License: MIT
//==============================================================================

module Rv32i_Trace_Buffer #(
    parameter DEPTH = 64  // Store last 64 instructions
)(
    input  logic        clk,
    input  logic        rst_n,
    
    // CPU signals to trace (32-bit RV32I)
    input  logic        insn_valid,      // Instruction executed (WB stage)
    input  logic [31:0] insn,            // Executed instruction
    input  logic [31:0] pc,              // Program counter (byte address)
    input  logic [4:0]  rd_addr,         // Destination register address
    input  logic [31:0] rd_value,        // Destination register value after writeback
    
    // UVM access interface (direct read, no protocol overhead)
    output logic [DEPTH-1:0][127:0] trace_buffer,  // Packed trace entries (128 bits each)
    output logic [$clog2(DEPTH)-1:0] write_ptr,    // Current write position
    output logic [$clog2(DEPTH)-1:0] entry_count   // Number of valid entries
);

    //==========================================================================
    // TRACE ENTRY STRUCTURE (128 bits total)
    //==========================================================================
    // [127:96] PC (32 bits)           - Program counter
    // [95:64]  Instruction (32 bits)  - Executed instruction
    // [63:32]  rd_value (32 bits)     - Result written to rd
    // [31:27]  rd_addr (5 bits)       - Destination register address
    // [26:0]   Reserved (27 bits)     - Reserved for future use
    
    typedef struct packed {
        logic [31:0] pc;           // [127:96] Program counter
        logic [31:0] insn;         // [95:64]  Instruction
        logic [31:0] rd_value;     // [63:32]  Result in rd
        logic [4:0]  rd_addr;      // [31:27]  Destination register
        logic [26:0] reserved;     // [26:0]   Reserved
    } trace_entry_t;
    
    //==========================================================================
    // TRACE BUFFER STORAGE
    //==========================================================================
    
    trace_entry_t buffer [DEPTH];
    
    // Write pointer and entry counter
    logic [$clog2(DEPTH)-1:0] wr_ptr;
    logic [$clog2(DEPTH)-1:0] count;
    
    //==========================================================================
    // TRACE CAPTURE LOGIC
    //==========================================================================
    // Capture trace on valid instruction execution (WB stage)
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            count  <= '0;
            for (int i = 0; i < DEPTH; i++) begin
                buffer[i] <= '0;
            end
        end else if (insn_valid) begin
            // Store trace entry
            buffer[wr_ptr].pc       <= pc;
            buffer[wr_ptr].insn     <= insn;
            buffer[wr_ptr].rd_value <= rd_value;
            buffer[wr_ptr].rd_addr  <= rd_addr;
            buffer[wr_ptr].reserved <= '0;
            
            // Update pointers (circular buffer)
            wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1;
            if (count < DEPTH) count <= count + 1;
        end
    end
    
    //==========================================================================
    // UVM INTERFACE - DIRECT BUFFER ACCESS
    //==========================================================================
    // Export buffer for UVM testbench direct memory access
    // No protocol overhead - read entire buffer in single transaction
    
    always_comb begin
        for (int i = 0; i < DEPTH; i++) begin
            trace_buffer[i] = buffer[i];
        end
        write_ptr   = wr_ptr;
        entry_count = count;
    end
    
    //==========================================================================
    // ASSERTIONS FOR VERIFICATION
    //==========================================================================
    
    // Check write pointer wraparound
    property p_write_ptr_range;
        @(posedge clk) disable iff (!rst_n)
        wr_ptr < DEPTH;
    endproperty
    assert property (p_write_ptr_range) else $error("Write pointer out of range");
    
    // Check entry count saturation
    property p_entry_count_saturate;
        @(posedge clk) disable iff (!rst_n)
        count <= DEPTH;
    endproperty
    assert property (p_entry_count_saturate) else $error("Entry count overflow");
    
    // Check trace capture on valid instruction
    property p_trace_capture;
        @(posedge clk) disable iff (!rst_n)
        insn_valid |=> (wr_ptr == $past(wr_ptr) + 1) || (wr_ptr == 0 && $past(wr_ptr) == DEPTH-1);
    endproperty
    assert property (p_trace_capture) else $warning("Trace capture pointer did not advance");

endmodule
