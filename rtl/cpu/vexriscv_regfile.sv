`timescale 1ns/1ps
//==============================================================================
// VexRiscv Register File Module
//
// 32-entry × 32-bit register file with 2 read ports and 1 write port
// - x0 hardwired to zero
// - Synchronous reads (registered outputs)
// - Synchronous writes
//
// Extracted from VexRiscv_GenSmallAndProductive.v (RegFilePlugin)
// Original lines: 1053-1068
//==============================================================================

module vexriscv_regfile
    import vexriscv_pkg::*;
(
    input  logic        clk,
    input  logic        reset,
    
    // Read Port 1
    input  logic [4:0]  read_addr1,
    output logic [31:0] read_data1,
    
    // Read Port 2
    input  logic [4:0]  read_addr2,
    output logic [31:0] read_data2,
    
    // Write Port
    input  logic        write_valid,
    input  logic [4:0]  write_addr,
    input  logic [31:0] write_data,
    
    // Debug visibility
    output logic [31:0] debug_regfile [0:31]
);

    //==========================================================================
    // Register File Storage
    //==========================================================================
    
    logic [31:0] regfile [0:31];
    
    //==========================================================================
    // Synchronous Read Port 1
    // Original: lines 1053-1056
    //==========================================================================
    
    always_ff @(posedge clk) begin
        read_data1 <= regfile[read_addr1];
    end
    
    //==========================================================================
    // Synchronous Read Port 2
    // Original: lines 1059-1062
    //==========================================================================
    
    always_ff @(posedge clk) begin
        read_data2 <= regfile[read_addr2];
    end
    
    //==========================================================================
    // Synchronous Write Port
    // Original: lines 1065-1068
    // Note: write_valid corresponds to _zz_1 in original
    //==========================================================================
    
    always_ff @(posedge clk) begin
        if (write_valid && (write_addr != 5'b00000)) begin
            regfile[write_addr] <= write_data;
        end
    end
    
    //==========================================================================
    // x0 Hardwired to Zero
    // Ensures x0 always reads as zero
    //==========================================================================
    
    always_ff @(posedge clk) begin
        if (reset) begin
            regfile[0] <= 32'h00000000;
        end else begin
            regfile[0] <= 32'h00000000;  // Always force x0 to zero
        end
    end
    
    //==========================================================================
    // Debug Visibility
    //==========================================================================
    
    assign debug_regfile = regfile;

endmodule : vexriscv_regfile
