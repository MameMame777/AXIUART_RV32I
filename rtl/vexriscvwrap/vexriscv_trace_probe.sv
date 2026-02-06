`timescale 1ns / 1ps
//=====================================================================
// VexRiscv Trace Probe
//=====================================================================
// Description:
//   Captures internal VexRiscv signals for trace buffer via
//   hierarchical references. Formats 192-bit trace entries compatible
//   with existing Register_Block trace interface.
//
// Trace Entry Format (192 bits):
//   [191:132] - Reserved
//   [131]     - Valid (instruction committed)
//   [130]     - Register write
//   [129]     - Flush occurred
//   [128]     - Stall occurred
//   [127:96]  - PC
//   [95:64]   - Instruction
//   [63:32]   - Register write data
//   [31:27]   - Register write address
//   [26:0]    - Reserved/future use
//
// Note: Hierarchical references require the VexRiscv instance to be
//       named 'cpu_core' in the parent module.
//
// Author: GitHub Copilot (Claude Opus 4.5)
// Date: February 6, 2026
//=====================================================================

module vexriscv_trace_probe (
    input  logic        clk,
    input  logic        rst,
    
    //=================================================================
    // Control Interface
    //=================================================================
    input  logic        cpu_running,      // CPU is executing
    input  logic        cpu_reset,        // CPU reset active
    
    //=================================================================
    // VexRiscv Internal Signals (directly connected)
    //=================================================================
    input  logic [31:0] writeBack_PC,
    input  logic [31:0] writeBack_INSTRUCTION,
    input  logic        writeBack_REGFILE_WRITE_VALID,
    input  logic [4:0]  writeBack_REGFILE_WRITE_ADDR,
    input  logic [31:0] writeBack_REGFILE_WRITE_DATA,
    input  logic        writeBack_arbitration_isFiring,
    input  logic        decode_arbitration_isStuckByOthers,
    input  logic        decode_arbitration_flushNext,
    
    //=================================================================
    // Trace Buffer Interface
    //=================================================================
    input  logic [5:0]  trace_addr,       // Trace entry read address
    output logic [191:0] trace_data,      // Trace entry data
    output logic [5:0]  trace_wptr,       // Write pointer
    output logic [5:0]  trace_count       // Entry count (max 63)
);

    //=================================================================
    // Trace Buffer (64 entries x 192 bits)
    //=================================================================
    
    localparam int TRACE_DEPTH = 64;
    localparam int TRACE_PTR_WIDTH = 6;
    
    logic [191:0] trace_buffer [0:TRACE_DEPTH-1];
    logic [TRACE_PTR_WIDTH-1:0] wr_ptr;
    logic [TRACE_PTR_WIDTH-1:0] entry_count;
    
    //=================================================================
    // Stall/Flush Tracking
    //=================================================================
    
    logic stall_seen;
    logic flush_seen;
    
    always_ff @(posedge clk) begin
        if (rst || cpu_reset) begin
            stall_seen <= 1'b0;
            flush_seen <= 1'b0;
        end else if (cpu_running) begin
            if (decode_arbitration_isStuckByOthers) begin
                stall_seen <= 1'b1;
            end
            if (decode_arbitration_flushNext) begin
                flush_seen <= 1'b1;
            end
            // Clear on instruction commit
            if (writeBack_arbitration_isFiring) begin
                stall_seen <= 1'b0;
                flush_seen <= 1'b0;
            end
        end
    end
    
    //=================================================================
    // Trace Entry Write Logic
    //=================================================================
    
    always_ff @(posedge clk) begin
        if (rst || cpu_reset) begin
            wr_ptr <= '0;
            entry_count <= '0;
            // Note: trace_buffer not reset (reduces synthesis complexity)
            // Old entries are overwritten as new data arrives
        end else if (cpu_running && writeBack_arbitration_isFiring) begin
            // Format trace entry
            trace_buffer[wr_ptr] <= '0;
            trace_buffer[wr_ptr][131]     <= 1'b1;  // Valid
            trace_buffer[wr_ptr][130]     <= writeBack_REGFILE_WRITE_VALID;
            trace_buffer[wr_ptr][129]     <= flush_seen;
            trace_buffer[wr_ptr][128]     <= stall_seen;
            trace_buffer[wr_ptr][127:96]  <= writeBack_PC;
            trace_buffer[wr_ptr][95:64]   <= writeBack_INSTRUCTION;
            trace_buffer[wr_ptr][63:32]   <= writeBack_REGFILE_WRITE_DATA;
            trace_buffer[wr_ptr][31:27]   <= writeBack_REGFILE_WRITE_ADDR;
            
            // Advance pointer
            wr_ptr <= wr_ptr + 1'b1;
            if (entry_count != 6'd63) begin
                entry_count <= entry_count + 1'b1;
            end
        end
    end
    
    //=================================================================
    // Output Assignments
    //=================================================================
    
    // Register output to break timing path (fixes #57: -0.805ns WNS)
    always_ff @(posedge clk) begin
        if (rst || cpu_reset) begin
            trace_data <= '0;
        end else begin
            trace_data <= trace_buffer[trace_addr];
        end
    end
    
    assign trace_wptr  = wr_ptr;
    assign trace_count = entry_count;
    
    //=================================================================
    // Debug Logging (Simulation Only)
    //=================================================================
    
    `ifdef SIMULATION
    always_ff @(posedge clk) begin
        if (!rst && cpu_running && writeBack_arbitration_isFiring) begin
            $display("[TRACE_PROBE] Entry %0d: PC=0x%08X INST=0x%08X rd=x%0d data=0x%08X stall=%b flush=%b",
                     wr_ptr,
                     writeBack_PC,
                     writeBack_INSTRUCTION,
                     writeBack_REGFILE_WRITE_ADDR,
                     writeBack_REGFILE_WRITE_DATA,
                     stall_seen,
                     flush_seen);
        end
    end
    `endif

endmodule
