`timescale 1ns / 1ps

//==============================================================================
// VexRiscv CPU Testbench Top Module - UVM Compatible
//==============================================================================
// Full system testbench for VexRiscv CPU via UART interface
// Uses complete AXIUART_Top (UART→AXI4→Register_Block→VexRiscv)
//
// Author: GitHub Copilot
// Date: 2026-01-18
//==============================================================================

module rv32i_tb_top;
    import uvm_pkg::*;
    import axiuart_pkg::*;
    `include "uvm_macros.svh"
    
    // Include AXIUART test classes
    `include "axiuart_test_pkg.sv"

    // Include VexRiscv test classes (base + all stages)
    `include "vexriscv_test_pkg.sv"

    // Include RV32I exception/perf test classes (extend vexriscv_base_test)
    `include "rv32i_test_pkg.sv"
    
    //==========================================================================
    // CLOCK GENERATION
    //==========================================================================
    
    logic clk;
    
    // 125MHz clock (matches AXIUART_Top CLK_FREQ_HZ parameter)
    initial begin
        clk = 0;
        forever #4 clk = ~clk;  // 8ns period = 125MHz
    end
    
    //==========================================================================
    // INTERFACE INSTANTIATION
    //==========================================================================
    
    uart_if uart_vif(clk);
    
    //==========================================================================
    // LED OUTPUTS
    //==========================================================================
    
    logic [3:0] led;        // 4-bit LED from CPU memory-mapped I/O
    logic led5_r;           // RGB LED Red (CPU halted indicator)
    logic led5_g;           // RGB LED Green (CPU running indicator)
    logic led5_b;           // RGB LED Blue (EBREAK indicator)
    
    //==========================================================================
    // DUT INSTANTIATION - Complete AXIUART System
    //==========================================================================
    
    AXIUART_Top #(
        .CLK_FREQ_HZ(125_000_000),  // 125MHz
        .BAUD_RATE(115200),
        .UART_OVERSAMPLE(16),
        .AXI_TIMEOUT(2500),
        .RX_FIFO_DEPTH(64),
        .TX_FIFO_DEPTH(64),
        .MAX_LEN(16),
        .REG_BASE_ADDR(32'h0000_1000)
    ) dut (
        .clk(clk),
        .rst(uart_vif.rst),
        
        // UART interface
        .uart_rx(uart_vif.uart_rx),
        .uart_tx(uart_vif.uart_tx),
        .uart_rts_n(uart_vif.uart_rts_n),
        .uart_cts_n(uart_vif.uart_cts_n),
        
        // LED outputs
        .led(led),
        .led5_r(led5_r),
        .led5_g(led5_g),
        .led5_b(led5_b)
    );
    
    //==========================================================================
    // UVM INITIALIZATION
    //==========================================================================
    
    initial begin
        // Display test banner
        $display("========================================");
        $display("[TB] VexRiscv UVM Testbench");
        $display("[TB] Full system: UART → AXI4 → Register_Block → VexRiscv");
        $display("[TB] Clock: 125MHz, UART: 115200 baud");
        $display("========================================");
        
        // Set virtual interface in config_db
        uvm_config_db#(virtual uart_if)::set(null, "*", "uart_vif", uart_vif);
        
        // Run test (test name specified via +UVM_TESTNAME= command line argument)
        run_test();
    end
    
    //==========================================================================
    // TIMEOUT WATCHDOG
    //==========================================================================
    
    initial begin
        #100ms;  // 100ms timeout (much longer for UART-based tests)
        $display("========================================");
        $display("*** FATAL: Simulation timeout after 100ms ***");
        $display("========================================");
        $finish;
    end
    
    //==========================================================================
    // LED MONITORING (optional debug)
    //==========================================================================
    
    always @(posedge clk) begin
        if (led !== 4'b0000) begin
            $display("[TB] LED output changed: 0x%h", led);
        end
    end
    
endmodule
