`include "../sv/axiuart_pkg.sv"

module axiuart_tb_top;
    import uvm_pkg::*;
    import axiuart_pkg::*;
    `include "uvm_macros.svh"
    `include "axiuart_test_pkg.sv"
    
    // Clock and reset
    logic clk;
    
    // Instantiate interfaces
    uart_if uart_vif(clk);
    
    // Instantiate DUT (AXIUART_Top has no external AXI ports!)
    AXIUART_Top #(
        .CLK_FREQ_HZ(125_000_000),  // Match actual testbench clock (125MHz)
        .BAUD_RATE(115200),
        .UART_OVERSAMPLE(16),
        .AXI_TIMEOUT(2500),
        .RX_FIFO_DEPTH(64),
        .TX_FIFO_DEPTH(64),
        .MAX_LEN(16),
        .REG_BASE_ADDR(32'h0000_1000)
    ) dut (
        .clk(clk),
        .rst(uart_vif.rst),  // Active-high reset
        
        // UART interface (external connections only)
        .uart_rx(uart_vif.uart_rx),
        .uart_tx(uart_vif.uart_tx),
        .uart_rts_n(uart_vif.uart_rts_n),
        .uart_cts_n(uart_vif.uart_cts_n),
        .led()  // Unconnected
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #4 clk = ~clk;  // 125MHz (matches DUT CLK_FREQ_HZ parameter)
    end
    
    // Set VIFs in config DB
    initial begin
        uvm_config_db#(virtual uart_if)::set(null, "*", "uart_vif", uart_vif);
        
        // Run test
        run_test("axiuart_basic_test");
    end
    
endmodule
