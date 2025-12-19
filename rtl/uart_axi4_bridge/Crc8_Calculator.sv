`timescale 1ns / 1ps

// CRC8 Calculator Module for UART-AXI4 Bridge
// Polynomial: 0x07 (x^8 + x^2 + x^1 + 1)
// Initial value: 0x00, no reflection, no XOR output
// Corrected implementation using table-based approach
module Crc8_Calculator (
    input  logic        clk,
    input  logic        rst,
    input  logic        crc_enable,    // Enable CRC calculation for this byte
    input  logic [7:0]  data_in,       // Input data byte
    input  logic        crc_reset,     // Reset CRC to initial value
    output logic [7:0]  crc_out,       // Current CRC value
    output logic [7:0]  crc_final      // Final CRC value (same as crc_out)
);

    // CRC8 register
    logic [7:0] crc_reg;
    logic [7:0] crc_next;

    // CRC calculation function - table-free bit-by-bit approach  
    function logic [7:0] calc_crc8_byte(logic [7:0] current_crc, logic [7:0] data_byte);
        automatic logic [7:0] crc_temp;
        crc_temp = current_crc ^ data_byte;
        
        // Process each bit with polynomial 0x07
        if (crc_temp[7]) crc_temp = (crc_temp << 1) ^ 8'h07; else crc_temp = crc_temp << 1;
        if (crc_temp[7]) crc_temp = (crc_temp << 1) ^ 8'h07; else crc_temp = crc_temp << 1;
        if (crc_temp[7]) crc_temp = (crc_temp << 1) ^ 8'h07; else crc_temp = crc_temp << 1;
        if (crc_temp[7]) crc_temp = (crc_temp << 1) ^ 8'h07; else crc_temp = crc_temp << 1;
        if (crc_temp[7]) crc_temp = (crc_temp << 1) ^ 8'h07; else crc_temp = crc_temp << 1;
        if (crc_temp[7]) crc_temp = (crc_temp << 1) ^ 8'h07; else crc_temp = crc_temp << 1;
        if (crc_temp[7]) crc_temp = (crc_temp << 1) ^ 8'h07; else crc_temp = crc_temp << 1;
        if (crc_temp[7]) crc_temp = (crc_temp << 1) ^ 8'h07; else crc_temp = crc_temp << 1;
        
        return crc_temp;
    endfunction

    // CRC calculation logic (combinational)
    always_comb begin
        if (crc_enable) begin
            crc_next = calc_crc8_byte(crc_reg, data_in);
        end else begin
            crc_next = crc_reg;  // Hold current value when disabled
        end
    end

    // CRC register update (sequential)
    always_ff @(posedge clk) begin
        if (rst || crc_reset) begin
            crc_reg <= 8'h00;  // Initial value per specification
        end else begin
            crc_reg <= crc_next;
        end
    end

    // Output assignments - provide both current and next values
    assign crc_out = crc_next;    // Combinational output (immediate)
    assign crc_final = crc_next;  // Same as crc_out

    // Assertions for verification
    `ifdef ENABLE_CRC8_ASSERTIONS
        // Verify reset behavior
        assert_reset_behavior: assert property (
            @(posedge clk) (rst || crc_reset) |=> (crc_out == 8'h00)
        ) else $error("CRC8: Reset behavior violation");

        // Verify stability when not enabled
        assert_stability_when_disabled: assert property (
            @(posedge clk) disable iff (rst || crc_reset)
            !crc_enable |=> $stable(crc_out)
        ) else $error("CRC8: Stability violation when disabled");
    `endif

endmodule
