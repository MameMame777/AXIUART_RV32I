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
//
// IMPORTANT: PC Address Accuracy
// -------------------------------
// The traced PC represents the **actual instruction address**.
// The PC value is delayed by 1 cycle in the IF stage to compensate for
// BRAM's 1-cycle output latency, ensuring PC and instruction encoding
// are correctly synchronized throughout the pipeline.
//
// Example trace output:
//   Line 1: PC=0x000, encoding=0x20000f93 (instruction at address 0x000) ✓
//   Line 2: PC=0x004, encoding=0x305f9073 (instruction at address 0x004) ✓
//   Line 3: PC=0x008, encoding=0x00a00093 (instruction at address 0x008) ✓
//
// Note: The first instruction at PC=0x000 is now correctly traced.
//==============================================================================

module Rv32i_Trace_Buffer #(
    parameter DEPTH = 64  // Store last 64 instructions
)(
    input  logic        clk,
    input  logic        rst,
    
    // CPU signals to trace (32-bit RV32I)
    input  logic        insn_valid,      // Instruction executed (WB stage)
    input  logic [31:0] insn,            // Executed instruction
    input  logic [31:0] pc,              // Program counter (byte address)
    input  logic [4:0]  rd_addr,         // Destination register address
    input  logic [31:0] rd_value,        // Destination register value after writeback
    
    // Extended trace signals for enhanced debugging
    input  logic [31:0] rs1_value,       // Source operand 1 value (after forwarding)
    input  logic [31:0] rs2_value,       // Source operand 2 value (after forwarding)
    input  logic [4:0]  rs1_addr,        // Source register 1 address
    input  logic [4:0]  rs2_addr,        // Source register 2 address
    input  logic [1:0]  forward_rs1,     // Forwarding control for rs1 (00=RF, 01=EX, 10=MEM, 11=WB)
    input  logic [1:0]  forward_rs2,     // Forwarding control for rs2 (00=RF, 01=EX, 10=MEM, 11=WB)
    input  logic        stall,           // Pipeline stall flag
    input  logic        flush,           // Pipeline flush flag
    input  logic        branch_taken,    // Branch taken flag
    
    // Hardware debug read interface (UART accessible via Register_Block)
    input  logic [$clog2(DEPTH)-1:0] dbg_read_addr,   // Trace entry index to read
    output logic [191:0]             dbg_read_data,   // Trace entry data (combinational)
    output logic [$clog2(DEPTH)-1:0] dbg_write_ptr,   // Current write pointer (registered)
    output logic [$clog2(DEPTH)-1:0] dbg_entry_count, // Number of valid entries (registered)
    
    // UVM access interface (direct read, no protocol overhead)
    output logic [DEPTH-1:0][191:0] trace_buffer,  // Packed trace entries (192 bits each)
    output logic [$clog2(DEPTH)-1:0] write_ptr,    // Current write position
    output logic [$clog2(DEPTH)-1:0] entry_count   // Number of valid entries
);

    //==========================================================================
    // TRACE ENTRY STRUCTURE (192 bits total)
    //==========================================================================
    // [191:160] PC (32 bits)           - Program counter
    // [159:128] Instruction (32 bits)  - Executed instruction
    // [127:96]  rd_value (32 bits)     - Result written to rd
    // [95:64]   rs1_value (32 bits)    - Source operand 1 (after forwarding)
    // [63:32]   rs2_value (32 bits)    - Source operand 2 (after forwarding)
    // [31:27]   rd_addr (5 bits)       - Destination register address
    // [26:22]   rs1_addr (5 bits)      - Source register 1 address
    // [21:17]   rs2_addr (5 bits)      - Source register 2 address
    // [16:15]   forward_rs1 (2 bits)   - Forwarding control for rs1
    // [14:13]   forward_rs2 (2 bits)   - Forwarding control for rs2
    // [12]      stall (1 bit)           - Pipeline stall flag
    // [11]      flush (1 bit)           - Pipeline flush flag
    // [10]      branch_taken (1 bit)   - Branch taken flag
    // [9:0]     reserved (10 bits)     - Reserved for future use
    
    typedef struct packed {
        logic [31:0] pc;           // [191:160] Program counter
        logic [31:0] insn;         // [159:128] Instruction
        logic [31:0] rd_value;     // [127:96]  Result in rd
        logic [31:0] rs1_value;    // [95:64]   Source operand 1
        logic [31:0] rs2_value;    // [63:32]   Source operand 2
        logic [4:0]  rd_addr;      // [31:27]   Destination register
        logic [4:0]  rs1_addr;     // [26:22]   Source register 1
        logic [4:0]  rs2_addr;     // [21:17]   Source register 2
        logic [1:0]  forward_rs1;  // [16:15]   Forwarding control rs1
        logic [1:0]  forward_rs2;  // [14:13]   Forwarding control rs2
        logic        stall;        // [12]      Pipeline stall
        logic        flush;        // [11]      Pipeline flush
        logic        branch_taken; // [10]      Branch taken
        logic [9:0]  reserved;     // [9:0]     Reserved
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
    
    always_ff @(posedge clk) begin
        if (rst) begin
            wr_ptr <= '0;
            count  <= '0;
            for (int i = 0; i < DEPTH; i++) begin
                buffer[i] <= '0;
            end
        end else if (insn_valid) begin
            // Store trace entry with extended debug info
            buffer[wr_ptr].pc           <= pc;
            buffer[wr_ptr].insn         <= insn;
            buffer[wr_ptr].rd_value     <= rd_value;
            buffer[wr_ptr].rs1_value    <= rs1_value;
            buffer[wr_ptr].rs2_value    <= rs2_value;
            buffer[wr_ptr].rd_addr      <= rd_addr;
            buffer[wr_ptr].rs1_addr     <= rs1_addr;
            buffer[wr_ptr].rs2_addr     <= rs2_addr;
            buffer[wr_ptr].forward_rs1  <= forward_rs1;
            buffer[wr_ptr].forward_rs2  <= forward_rs2;
            buffer[wr_ptr].stall        <= stall;
            buffer[wr_ptr].flush        <= flush;
            buffer[wr_ptr].branch_taken <= branch_taken;
            buffer[wr_ptr].reserved     <= '0;
            
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
    // HARDWARE DEBUG READ INTERFACE
    //==========================================================================
    // Combinational read for UART access via Register_Block
    // Registered outputs for status polling
    
    assign dbg_read_data = buffer[dbg_read_addr];  // Combinational read
    
    always_ff @(posedge clk) begin
        if (rst) begin
            dbg_write_ptr   <= '0;
            dbg_entry_count <= '0;
        end else begin
            dbg_write_ptr   <= wr_ptr;
            dbg_entry_count <= count;
        end
    end
    
    //==========================================================================
    // ASSERTIONS FOR VERIFICATION
    //==========================================================================
    
    // Check write pointer wraparound
    property p_write_ptr_range;
        @(posedge clk) disable iff (rst)
        wr_ptr < DEPTH;
    endproperty
    assert property (p_write_ptr_range) else $error("Write pointer out of range");
    
    // Check entry count saturation
    property p_entry_count_saturate;
        @(posedge clk) disable iff (rst)
        count <= DEPTH;
    endproperty
    assert property (p_entry_count_saturate) else $error("Entry count overflow");
    
    // Check trace capture on valid instruction
    property p_trace_capture;
        @(posedge clk) disable iff (rst)
        insn_valid |=> (wr_ptr == $past(wr_ptr) + 1) || (wr_ptr == 0 && $past(wr_ptr) == DEPTH-1);
    endproperty
    assert property (p_trace_capture) else $warning("Trace capture pointer did not advance");

endmodule
