`timescale 1ns / 1ps

// AXI4-Lite interface definition for UART-AXI4 Bridge
// Supports 32-bit data and address widths per protocol specification
interface axi4_lite_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst
);

    // Write address channel
    logic [ADDR_WIDTH-1:0]  awaddr;
    logic [2:0]             awprot;
    logic                   awvalid;
    logic                   awready;

    // Write data channel
    logic [DATA_WIDTH-1:0]  wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;
    logic                   wvalid;
    logic                   wready;

    // Write response channel
    logic [1:0]             bresp;
    logic                   bvalid;
    logic                   bready;

    // Read address channel
    logic [ADDR_WIDTH-1:0]  araddr;
    logic [2:0]             arprot;
    logic                   arvalid;
    logic                   arready;

    // Read data channel
    logic [DATA_WIDTH-1:0]  rdata;
    logic [1:0]             rresp;
    logic                   rvalid;
    logic                   rready;

    // Master modport - for AXI4-Lite master (UART bridge)
    modport master (
        // Write address channel
        output awaddr,
        output awprot,
        output awvalid,
        input  awready,

        // Write data channel
        output wdata,
        output wstrb,
        output wvalid,
        input  wready,

        // Write response channel
        input  bresp,
        input  bvalid,
        output bready,

        // Read address channel
        output araddr,
        output arprot,
        output arvalid,
        input  arready,

        // Read data channel
        input  rdata,
        input  rresp,
        input  rvalid,
        output rready
    );

    // Slave modport - for AXI4-Lite slave (memory/registers)
    modport slave (
        // Write address channel
        input  awaddr,
        input  awprot,
        input  awvalid,
        output awready,

        // Write data channel
        input  wdata,
        input  wstrb,
        input  wvalid,
        output wready,

        // Write response channel
        output bresp,
        output bvalid,
        input  bready,

        // Read address channel
        input  araddr,
        input  arprot,
        input  arvalid,
        output arready,

        // Read data channel
        output rdata,
        output rresp,
        output rvalid,
        input  rready
    );

    // Monitor modport - for UVM passive monitoring
    modport monitor (
        // Write address channel
        input awaddr,
        input awprot,
        input awvalid,
        input awready,

        // Write data channel
        input wdata,
        input wstrb,
        input wvalid,
        input wready,

        // Write response channel
        input bresp,
        input bvalid,
        input bready,

        // Read address channel
        input araddr,
        input arprot,
        input arvalid,
        input arready,

        // Read data channel
        input rdata,
        input rresp,
        input rvalid,
        input rready
    );

    // Clock and reset aliases for UVM compatibility
    logic aclk;
    logic aresetn;
    
    assign aclk = clk;
    assign aresetn = ~rst;  // Convert active-high reset to active-low

endinterface
