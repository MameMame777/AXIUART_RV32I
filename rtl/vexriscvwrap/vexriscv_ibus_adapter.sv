`timescale 1ns / 1ps
//=====================================================================
// VexRiscv IBus Adapter
//=====================================================================
// Description:
//   Adapts generated VexRiscv IBus interface to memory crossbar with
//   PC tracking for response correlation.
//
//   The generated VexRiscv does NOT include iBus_rsp_payload_pc in its
//   response - we must track pending PCs in a FIFO and correlate them
//   with responses.
//
// Interface:
//   - vex_*: Connection to generated VexRiscv core
//   - mem_*: Connection to memory crossbar (with PC tracking)
//
// Author: GitHub Copilot (Claude Opus 4.5)
// Date: February 6, 2026
//=====================================================================

module vexriscv_ibus_adapter (
    input  logic        clk,
    input  logic        rst,
    
    //=================================================================
    // VexRiscv IBus Interface (to generated core)
    //=================================================================
    input  logic        vex_iBus_cmd_valid,
    output logic        vex_iBus_cmd_ready,
    input  logic [31:0] vex_iBus_cmd_payload_pc,
    output logic        vex_iBus_rsp_valid,
    output logic        vex_iBus_rsp_payload_error,
    output logic [31:0] vex_iBus_rsp_payload_inst,
    
    //=================================================================
    // Memory Crossbar Interface (with PC tracking)
    //=================================================================
    output logic        mem_iBus_cmd_valid,
    input  logic        mem_iBus_cmd_ready,
    output logic [31:0] mem_iBus_cmd_payload_pc,
    input  logic        mem_iBus_rsp_valid,
    input  logic        mem_iBus_rsp_payload_error,
    input  logic [31:0] mem_iBus_rsp_payload_inst,
    input  logic [31:0] mem_iBus_rsp_payload_pc   // Extended: PC returned with response
);

    //=================================================================
    // Passthrough Logic (PC FIFO is in mem_crossbar)
    //=================================================================
    
    // The memory crossbar already tracks PCs internally with a FIFO
    // This adapter is essentially a passthrough, but exists for future
    // extensions (e.g., cache adapter, prefetch buffer)
    
    // Command passthrough
    assign mem_iBus_cmd_valid      = vex_iBus_cmd_valid;
    assign vex_iBus_cmd_ready      = mem_iBus_cmd_ready;
    assign mem_iBus_cmd_payload_pc = vex_iBus_cmd_payload_pc;
    
    // Response passthrough
    assign vex_iBus_rsp_valid         = mem_iBus_rsp_valid;
    assign vex_iBus_rsp_payload_error = mem_iBus_rsp_payload_error;
    assign vex_iBus_rsp_payload_inst  = mem_iBus_rsp_payload_inst;
    
    //=================================================================
    // Debug Logging (Simulation Only)
    //=================================================================
    
    `ifdef SIMULATION
    always_ff @(posedge clk) begin
        if (!rst && vex_iBus_cmd_valid && vex_iBus_cmd_ready) begin
            $display("[IBUS_ADAPTER] Fetch request: PC=0x%08X", vex_iBus_cmd_payload_pc);
        end
        if (!rst && vex_iBus_rsp_valid) begin
            $display("[IBUS_ADAPTER] Fetch response: PC=0x%08X INST=0x%08X", 
                     mem_iBus_rsp_payload_pc, mem_iBus_rsp_payload_inst);
        end
    end
    `endif

endmodule
