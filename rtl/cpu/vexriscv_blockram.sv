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
//   0x0000-0x1FFF: Block RAM (8KB, word-addressed internally)
//   0x4000-0x7FFF: MMIO region (LED register at 0x407C)
//
// Timing:
//   - Read latency: 1 cycle (registered output)
//   - Write-through: Write data available on next cycle
//   - Read-First mode: Read old data when writing same address
//
// Author: GitHub Copilot (Claude Sonnet 4.5)
// Date: January 17, 2026
//=====================================================================

module vexriscv_blockram #(
    parameter int ADDR_WIDTH = 11,  // 2^11 = 2048 words = 8KB
    parameter int DATA_WIDTH = 32,
    parameter int MMIO_BASE  = 32'h0000_4000,  // MMIO region start
    parameter int LED_ADDR   = 32'h0000_407C   // LED register address
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
    (* ram_style = "block" *) 
    logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
    
    // Initialize with NOP instructions (ADDI x0, x0, 0 = 0x00000013)
    initial begin
        for (int i = 0; i < (1<<ADDR_WIDTH); i++) begin
            mem[i] = 32'h0000_0013;  // NOP
        end
    end
    
    //=================================================================
    // Port A Logic (Read-First Mode)
    //=================================================================
    
    always_ff @(posedge clk) begin
        if (rst) begin
            a_rdata <= 32'h0000_0013;  // Return NOP on reset
        end else if (a_en) begin
            if (a_is_mmio) begin
                // MMIO read: Return LED register value
                a_rdata <= led_reg_rdata;
            end else begin
                // BRAM access: Read-First mode
                // Read old data before write (if write enabled)
                a_rdata <= mem[a_addr];
                
                // Write with byte enables
                if (a_we[0]) mem[a_addr][7:0]   <= a_wdata[7:0];
                if (a_we[1]) mem[a_addr][15:8]  <= a_wdata[15:8];
                if (a_we[2]) mem[a_addr][23:16] <= a_wdata[23:16];
                if (a_we[3]) mem[a_addr][31:24] <= a_wdata[31:24];
            end
        end
    end
    
    //=================================================================
    // Port B Logic (Read-First Mode)
    //=================================================================
    
    always_ff @(posedge clk) begin
        if (rst) begin
            b_rdata <= 32'h0000_0013;  // Return NOP on reset
        end else if (b_en) begin
            if (b_is_mmio) begin
                // MMIO read: Return LED register value
                b_rdata <= led_reg_rdata;
            end else begin
                // BRAM access: Read-First mode
                b_rdata <= mem[b_addr];
                
                // Write with byte enables
                if (b_we[0]) mem[b_addr][7:0]   <= b_wdata[7:0];
                if (b_we[1]) mem[b_addr][15:8]  <= b_wdata[15:8];
                if (b_we[2]) mem[b_addr][23:16] <= b_wdata[23:16];
                if (b_we[3]) mem[b_addr][31:24] <= b_wdata[31:24];
            end
        end
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
