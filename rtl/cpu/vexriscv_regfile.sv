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
    // Asynchronous Read Port 1
    // Changed to async read to match VexRiscv Decode stage timing
    //==========================================================================
    
    always_comb begin
        read_data1 = regfile[read_addr1];
    end
    
    //==========================================================================
    // Asynchronous Read Port 2
    // Changed to async read to match VexRiscv Decode stage timing
    //==========================================================================
    
    always_comb begin
        read_data2 = regfile[read_addr2];
    end
    
    //==========================================================================
    // Register File Reset and Write
    // x0 is hardwired to zero, x1-x31 are initialized to zero on reset
    //==========================================================================
    
    always_ff @(posedge clk) begin
        if (reset) begin
            // Initialize all registers to zero on reset
            for (int i = 0; i < 32; i++) begin
                regfile[i] <= 32'h00000000;
            end
        end else begin
            // x0 always hardwired to zero
            regfile[0] <= 32'h00000000;
            
            // Write to x1-x31 when write_valid is asserted
            if (write_valid && (write_addr != 5'b00000)) begin
                regfile[write_addr] <= write_data;
            end
        end
    end
    
    //==========================================================================
    // Debug Visibility
    //==========================================================================
    
    assign debug_regfile = regfile;
    // Individual register debug visibility
    logic [31:0] debug_x0,  debug_x1,  debug_x2,  debug_x3;
    logic [31:0] debug_x4,  debug_x5,  debug_x6,  debug_x7;
    logic [31:0] debug_x8,  debug_x9,  debug_x10, debug_x11;
    logic [31:0] debug_x12, debug_x13, debug_x14, debug_x15;
    logic [31:0] debug_x16, debug_x17, debug_x18, debug_x19;
    logic [31:0] debug_x20, debug_x21, debug_x22, debug_x23;
    logic [31:0] debug_x24, debug_x25, debug_x26, debug_x27;
    logic [31:0] debug_x28, debug_x29, debug_x30, debug_x31;

    assign debug_x0  = regfile[0];
    assign debug_x1  = regfile[1];
    assign debug_x2  = regfile[2];
    assign debug_x3  = regfile[3];
    assign debug_x4  = regfile[4];
    assign debug_x5  = regfile[5];
    assign debug_x6  = regfile[6];
    assign debug_x7  = regfile[7];
    assign debug_x8  = regfile[8];
    assign debug_x9  = regfile[9];
    assign debug_x10 = regfile[10];
    assign debug_x11 = regfile[11];
    assign debug_x12 = regfile[12];
    assign debug_x13 = regfile[13];
    assign debug_x14 = regfile[14];
    assign debug_x15 = regfile[15];
    assign debug_x16 = regfile[16];
    assign debug_x17 = regfile[17];
    assign debug_x18 = regfile[18];
    assign debug_x19 = regfile[19];
    assign debug_x20 = regfile[20];
    assign debug_x21 = regfile[21];
    assign debug_x22 = regfile[22];
    assign debug_x23 = regfile[23];
    assign debug_x24 = regfile[24];
    assign debug_x25 = regfile[25];
    assign debug_x26 = regfile[26];
    assign debug_x27 = regfile[27];
    assign debug_x28 = regfile[28];
    assign debug_x29 = regfile[29];
    assign debug_x30 = regfile[30];
    assign debug_x31 = regfile[31];

endmodule : vexriscv_regfile
