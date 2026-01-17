`timescale 1ns/1ps
//==============================================================================
// VexRiscv RegFile Test Module
// Simple testbench to verify SystemVerilog compilation
//==============================================================================

module vexriscv_regfile_test
    import vexriscv_pkg::*;
();

    logic        clk;
    logic        reset;
    logic [4:0]  read_addr1;
    logic [31:0] read_data1;
    logic [4:0]  read_addr2;
    logic [31:0] read_data2;
    logic        write_valid;
    logic [4:0]  write_addr;
    logic [31:0] write_data;
    logic [31:0] debug_regfile [0:31];

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    
    vexriscv_regfile dut (
        .clk            (clk),
        .reset          (reset),
        .read_addr1     (read_addr1),
        .read_data1     (read_data1),
        .read_addr2     (read_addr2),
        .read_data2     (read_data2),
        .write_valid    (write_valid),
        .write_addr     (write_addr),
        .write_data     (write_data),
        .debug_regfile  (debug_regfile)
    );

    //==========================================================================
    // Clock Generation
    //==========================================================================
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    //==========================================================================
    // Simple Test Sequence
    //==========================================================================
    
    initial begin
        $display("[INFO] VexRiscv RegFile Compilation Test");
        $display("[INFO] SystemVerilog package imported successfully");
        $display("[INFO] Module instantiated successfully");
        $display("[TEST] Proof-of-concept PASSED");
        $finish;
    end

endmodule : vexriscv_regfile_test
