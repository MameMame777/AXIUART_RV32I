`timescale 1ns / 1ps
//=====================================================================
// VexRiscv DBus Adapter
//=====================================================================
// Description:
//   Adapts generated VexRiscv DBus interface to memory crossbar.
//   Currently a passthrough - exists for future extensions
//   (e.g., cache adapter, write buffer, bus width conversion).
//
// Interface:
//   - vex_*: Connection to generated VexRiscv core
//   - mem_*: Connection to memory crossbar
//
// Author: GitHub Copilot (Claude Opus 4.5)
// Date: February 6, 2026
//=====================================================================

module vexriscv_dbus_adapter (
    input  logic        clk,
    input  logic        rst,
    
    //=================================================================
    // VexRiscv DBus Interface (to generated core)
    //=================================================================
    input  logic        vex_dBus_cmd_valid,
    output logic        vex_dBus_cmd_ready,
    input  logic        vex_dBus_cmd_payload_wr,
    input  logic [3:0]  vex_dBus_cmd_payload_mask,
    input  logic [31:0] vex_dBus_cmd_payload_address,
    input  logic [31:0] vex_dBus_cmd_payload_data,
    input  logic [1:0]  vex_dBus_cmd_payload_size,
    output logic        vex_dBus_rsp_ready,
    output logic        vex_dBus_rsp_error,
    output logic [31:0] vex_dBus_rsp_data,
    
    //=================================================================
    // Memory Crossbar Interface
    //=================================================================
    output logic        mem_dBus_cmd_valid,
    input  logic        mem_dBus_cmd_ready,
    output logic        mem_dBus_cmd_payload_wr,
    output logic [3:0]  mem_dBus_cmd_payload_mask,
    output logic [31:0] mem_dBus_cmd_payload_address,
    output logic [31:0] mem_dBus_cmd_payload_data,
    output logic [1:0]  mem_dBus_cmd_payload_size,
    input  logic        mem_dBus_rsp_ready,
    input  logic        mem_dBus_rsp_error,
    input  logic [31:0] mem_dBus_rsp_data
);

    //=================================================================
    // Passthrough Logic
    //=================================================================
    
    // Command passthrough
    assign mem_dBus_cmd_valid           = vex_dBus_cmd_valid;
    assign vex_dBus_cmd_ready           = mem_dBus_cmd_ready;
    assign mem_dBus_cmd_payload_wr      = vex_dBus_cmd_payload_wr;
    assign mem_dBus_cmd_payload_mask    = vex_dBus_cmd_payload_mask;
    assign mem_dBus_cmd_payload_address = vex_dBus_cmd_payload_address;
    assign mem_dBus_cmd_payload_data    = vex_dBus_cmd_payload_data;
    assign mem_dBus_cmd_payload_size    = vex_dBus_cmd_payload_size;
    
    // Response passthrough
    assign vex_dBus_rsp_ready = mem_dBus_rsp_ready;
    assign vex_dBus_rsp_error = mem_dBus_rsp_error;
    assign vex_dBus_rsp_data  = mem_dBus_rsp_data;
    
    //=================================================================
    // Debug Logging (Simulation Only)
    //=================================================================
    
    `ifdef SIMULATION
    always_ff @(posedge clk) begin
        if (!rst && vex_dBus_cmd_valid && vex_dBus_cmd_ready) begin
            if (vex_dBus_cmd_payload_wr) begin
                $display("[DBUS_ADAPTER] Store: addr=0x%08X data=0x%08X mask=%b",
                         vex_dBus_cmd_payload_address,
                         vex_dBus_cmd_payload_data,
                         vex_dBus_cmd_payload_mask);
            end else begin
                $display("[DBUS_ADAPTER] Load request: addr=0x%08X size=%0d",
                         vex_dBus_cmd_payload_address,
                         vex_dBus_cmd_payload_size);
            end
        end
        if (!rst && vex_dBus_rsp_ready && !vex_dBus_cmd_payload_wr) begin
            $display("[DBUS_ADAPTER] Load response: data=0x%08X", vex_dBus_rsp_data);
        end
    end
    `endif

endmodule
