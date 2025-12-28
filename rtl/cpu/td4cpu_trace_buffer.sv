`timescale 1ns / 1ps

// CPU Trace Buffer for fast UVM verification
// Captures CPU execution results without UART overhead
module Td4cpu_Trace_Buffer #(
    parameter DEPTH = 64  // Store last 64 operations
)(
    input  logic        clk,
    input  logic        rstn,
    
    // CPU signals to trace
    input  logic        insn_valid,      // Instruction executed
    input  logic [15:0] insn,            // Executed instruction
    input  logic [15:0] pc,              // Program counter
    input  logic [15:0] reg_rd_value,    // Destination register value after execute
    input  logic [15:0] reg_rs_value,    // Source register value
    input  logic        flag_z,          // Zero flag
    input  logic        flag_n,          // Negative flag
    input  logic        flag_c,          // Carry flag
    
    // UVM access interface (direct read, no protocol overhead)
    output logic [DEPTH-1:0][79:0] trace_buffer,  // Packed trace entries
    output logic [$clog2(DEPTH)-1:0] write_ptr,   // Current write position
    output logic [$clog2(DEPTH)-1:0] entry_count  // Number of valid entries
);

    // Trace entry structure (80 bits total)
    typedef struct packed {
        logic [15:0] pc;           // [79:64] Program counter
        logic [15:0] insn;         // [63:48] Instruction
        logic [15:0] rd_value;     // [47:32] Result in rd
        logic [15:0] rs_value;     // [31:16] Value in rs
        logic        flag_z;       // [2]     Zero flag
        logic        flag_n;       // [1]     Negative flag
        logic        flag_c;       // [0]     Carry flag
        logic [12:0] reserved;     // [15:3]  Reserved
    } trace_entry_t;
    
    // Trace buffer storage
    trace_entry_t buffer [DEPTH];
    
    // Write pointer and entry counter
    logic [$clog2(DEPTH)-1:0] wr_ptr;
    logic [$clog2(DEPTH)-1:0] count;
    
    // Capture trace on valid instruction execution
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            wr_ptr <= '0;
            count  <= '0;
            for (int i = 0; i < DEPTH; i++) begin
                buffer[i] <= '0;
            end
        end else if (insn_valid) begin
            // Store trace entry
            buffer[wr_ptr].pc       <= pc;
            buffer[wr_ptr].insn     <= insn;
            buffer[wr_ptr].rd_value <= reg_rd_value;
            buffer[wr_ptr].rs_value <= rs_value;
            buffer[wr_ptr].flag_z   <= flag_z;
            buffer[wr_ptr].flag_n   <= flag_n;
            buffer[wr_ptr].flag_c   <= flag_c;
            buffer[wr_ptr].reserved <= '0;
            
            // Update pointers
            wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1;
            if (count < DEPTH) count <= count + 1;
        end
    end
    
    // Export buffer for UVM direct access
    always_comb begin
        for (int i = 0; i < DEPTH; i++) begin
            trace_buffer[i] = buffer[i];
        end
        write_ptr   = wr_ptr;
        entry_count = count;
    end

endmodule
