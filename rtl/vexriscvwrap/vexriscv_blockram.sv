`timescale 1ns / 1ps
//=====================================================================
// VexRiscv Dual-Port Block RAM with MMIO Support
//=====================================================================
// Description:
//   True dual-port Block RAM (8KB) for VexRiscv instruction/data memory
//   - Port A: IBus (instruction fetch) or Debug interface (when halted)
//   - Port B: DBus (data access) or Debug interface (when halted)
//   - Byte-granular write enables (4-bit mask)
//   - MMIO decode: LED register at 0x407C bypasses BRAM
//   - Read-First mode for Xilinx RAMB36E1 inference
//
// Memory Map:
//   0x80000000-0x80001FFF: Block RAM (8KB, word-addressed internally)
//   0x80004000-0x80007FFF: MMIO region (LED register at 0x8000407C)
//
// Timing:
//   - Read latency: 1 cycle (registered output)
//   - Write-through: Write data available on next cycle
//   - Read-First mode: Read old data when writing same address
//
// Synthesis Notes (Issue #5 fix):
//   - BRAM logic separated from reset and MMIO handling for RAMB36E1 inference
//   - Loop-based byte-enable pattern for Vivado recognition
//   - MMIO mux moved to combinational output stage after BRAM register
//   - Pipeline registers align MMIO selection with BRAM output timing
//
// Author: GitHub Copilot (Claude Sonnet 4.5)
// Date: January 17, 2026
// Modified: January 31, 2026 (Issue #5 - Synth 8-2914 fix)
//=====================================================================

module vexriscv_blockram #(
    parameter int ADDR_WIDTH = 11,  // 2^11 = 2048 words = 8KB
    parameter int DATA_WIDTH = 32,
    parameter int MMIO_BASE  = 32'h8000_4000,  // MMIO region start (VexRiscv 0x80000000 base)
    parameter int LED_ADDR   = 32'h8000_407C   // LED register address
)(
    input  logic        clk,
    input  logic        rst,

    // Port A (IBus / Debug when halted)
    input  logic                        a_en,
    input  logic [ADDR_WIDTH-1:0]       a_addr,      // Word address
    input  logic [3:0]                  a_we,        // Byte write enables
    input  logic [DATA_WIDTH-1:0]       a_wdata,
    output logic [DATA_WIDTH-1:0]       a_rdata,
    input  logic [31:0]                 a_byte_addr, // Full byte address for MMIO decode
    output logic                        a_mmio_access, // High when accessing MMIO

    // Port B (DBus / Debug when halted)
    input  logic                        b_en,
    input  logic [ADDR_WIDTH-1:0]       b_addr,      // Word address
    input  logic [3:0]                  b_we,        // Byte write enables
    input  logic [DATA_WIDTH-1:0]       b_wdata,
    output logic [DATA_WIDTH-1:0]       b_rdata,
    input  logic [31:0]                 b_byte_addr, // Full byte address for MMIO decode
    output logic                        b_mmio_access, // High when accessing MMIO

    // MMIO LED Register Interface
    output logic [31:0] led_reg_wdata,  // LED register write data
    output logic        led_reg_we,     // LED register write enable
    input  logic [31:0] led_reg_rdata   // LED register read data
);

    //=================================================================
    // MMIO Address Decode
    //=================================================================

    // Detect MMIO region access (0x4000-0x7FFF)
    logic a_is_mmio, b_is_mmio;

    always_comb begin
        a_is_mmio = (a_byte_addr >= MMIO_BASE) && (a_byte_addr < (MMIO_BASE + 32'h4000));
        b_is_mmio = (b_byte_addr >= MMIO_BASE) && (b_byte_addr < (MMIO_BASE + 32'h4000));
    end

    assign a_mmio_access = a_is_mmio;
    assign b_mmio_access = b_is_mmio;

    // LED register write control
    // LED is at 0x407C, accessible from either port
    logic a_led_write, b_led_write;

    always_comb begin
        a_led_write = a_en && (a_byte_addr == LED_ADDR) && (|a_we);
        b_led_write = b_en && (b_byte_addr == LED_ADDR) && (|b_we);
    end

    // LED register write mux (Port B has priority)
    assign led_reg_we    = b_led_write || (a_led_write && !b_en);
    assign led_reg_wdata = b_led_write ? b_wdata : a_wdata;

    //=================================================================
    // Block RAM Instantiation (8KB, True Dual-Port)
    //=================================================================

    // Infer Xilinx RAMB36E1 primitive with Read-First mode
    // Note: Reset and MMIO logic are separated for proper inference
    (* ram_style = "block" *)
    logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    // Initialize with NOP instructions (ADDI x0, x0, 0 = 0x00000013)
    initial begin
        for (int i = 0; i < (1<<ADDR_WIDTH); i++) begin
            mem[i] = 32'h0000_0013;  // NOP
        end
    end

    //=================================================================
    // Internal BRAM Output Registers (Pure BRAM for inference)
    //=================================================================

    // Internal BRAM read outputs (before MMIO mux)
    logic [DATA_WIDTH-1:0] bram_out_a;
    logic [DATA_WIDTH-1:0] bram_out_b;

    // Pipeline registers to align MMIO selection with BRAM output timing
    logic        a_mmio_sel_r;    // MMIO selected for Port A (registered)
    logic        b_mmio_sel_r;    // MMIO selected for Port B (registered)
    logic [31:0] a_mmio_data_r;   // MMIO data for Port A (registered)
    logic [31:0] b_mmio_data_r;   // MMIO data for Port B (registered)
    logic        a_reset_out_r;   // Force reset output for Port A
    logic        b_reset_out_r;   // Force reset output for Port B

    //=================================================================
    // Port A BRAM Logic (Pure - no reset, no MMIO mux)
    // Loop-based byte-enable pattern for Vivado RAMB36E1 inference
    //=================================================================

    always_ff @(posedge clk) begin
        if (a_en && !a_is_mmio) begin
            // Read-First: Read old data before write
            bram_out_a <= mem[a_addr];
            // Write with loop-based byte enables (Vivado recognizes this pattern)
            for (int i = 0; i < 4; i++) begin
                if (a_we[i]) mem[a_addr][i*8 +: 8] <= a_wdata[i*8 +: 8];
            end
        end
    end

    //=================================================================
    // Port B BRAM Logic (Pure - no reset, no MMIO mux)
    // Loop-based byte-enable pattern for Vivado RAMB36E1 inference
    //=================================================================

    always_ff @(posedge clk) begin
        if (b_en && !b_is_mmio) begin
            // Read-First: Read old data before write
            bram_out_b <= mem[b_addr];
            // Write with loop-based byte enables (Vivado recognizes this pattern)
            for (int i = 0; i < 4; i++) begin
                if (b_we[i]) mem[b_addr][i*8 +: 8] <= b_wdata[i*8 +: 8];
            end
        end
    end

    //=================================================================
    // Port A MMIO/Reset Pipeline (aligns with BRAM output timing)
    //=================================================================

    always_ff @(posedge clk) begin
        if (rst) begin
            // On reset, force NOP output regardless of access type
            a_reset_out_r <= 1'b1;
            a_mmio_sel_r  <= 1'b0;
            a_mmio_data_r <= 32'h0000_0013;  // NOP
        end else begin
            a_reset_out_r <= 1'b0;
            if (a_en) begin
                // Pipeline MMIO selection to align with BRAM registered output
                a_mmio_sel_r  <= a_is_mmio;
                a_mmio_data_r <= led_reg_rdata;
            end
        end
    end

    //=================================================================
    // Port B MMIO/Reset Pipeline (aligns with BRAM output timing)
    //=================================================================

    always_ff @(posedge clk) begin
        if (rst) begin
            // On reset, force NOP output regardless of access type
            b_reset_out_r <= 1'b1;
            b_mmio_sel_r  <= 1'b0;
            b_mmio_data_r <= 32'h0000_0013;  // NOP
        end else begin
            b_reset_out_r <= 1'b0;
            if (b_en) begin
                // Pipeline MMIO selection to align with BRAM registered output
                b_mmio_sel_r  <= b_is_mmio;
                b_mmio_data_r <= led_reg_rdata;
            end
        end
    end

    //=================================================================
    // Output Multiplexers (Combinational - after all registers)
    // Priority: Reset > MMIO > BRAM
    //=================================================================

    always_comb begin
        if (a_reset_out_r)
            a_rdata = 32'h0000_0013;  // NOP on reset
        else if (a_mmio_sel_r)
            a_rdata = a_mmio_data_r;  // MMIO read data
        else
            a_rdata = bram_out_a;     // BRAM read data
    end

    always_comb begin
        if (b_reset_out_r)
            b_rdata = 32'h0000_0013;  // NOP on reset
        else if (b_mmio_sel_r)
            b_rdata = b_mmio_data_r;  // MMIO read data
        else
            b_rdata = bram_out_b;     // BRAM read data
    end

    //=================================================================
    // Assertions (Simulation Only)
    //=================================================================

    `ifdef SIMULATION
    // Check for simultaneous write to same address (potential data corruption)
    always_ff @(posedge clk) begin
        if (!rst && a_en && b_en && !a_is_mmio && !b_is_mmio &&
            (|a_we) && (|b_we) && (a_addr == b_addr)) begin
            $warning("[VEXRISCV_BLOCKRAM] Simultaneous write to address 0x%08X from both ports (Port A: 0x%08X, Port B: 0x%08X)",
                     {a_addr, 2'b00}, a_wdata, b_wdata);
        end
    end

    // Monitor MMIO accesses
    always_ff @(posedge clk) begin
        if (!rst && a_en && a_is_mmio && (|a_we)) begin
            $display("[VEXRISCV_BLOCKRAM] Port A MMIO write: addr=0x%08X data=0x%08X we=%b",
                     a_byte_addr, a_wdata, a_we);
        end
        if (!rst && b_en && b_is_mmio && (|b_we)) begin
            $display("[VEXRISCV_BLOCKRAM] Port B MMIO write: addr=0x%08X data=0x%08X we=%b",
                     b_byte_addr, b_wdata, b_we);
        end
    end
    `endif

endmodule
