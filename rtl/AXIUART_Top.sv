`timescale 1ns / 1ps
// FIXED BAUD RATE: 115200 bps
module AXIUART_Top #(
    parameter int CLK_FREQ_HZ = 125_000_000,    // System clock frequency (125MHz)
    parameter int UART_OVERSAMPLE = 16,         // UART oversampling factor
    parameter int BAUD_RATE = 115200,           // UART baud rate (FIXED)
    parameter int AXI_TIMEOUT = 2500,           // AXI timeout in clock cycles (20μs @ 125MHz)
    parameter int RX_FIFO_DEPTH = 64,           // RX FIFO depth
    parameter int TX_FIFO_DEPTH = 64,           // TX FIFO depth
    parameter int MAX_LEN = 16,                 // Maximum LEN field value
    parameter int REG_BASE_ADDR = 32'h0000_1000 // Register block base address
)(
    // Clock and reset
    input  logic        clk,
    input  logic        rst,
    
    // UART interface (external connections)
    input  logic        uart_rx,
    output logic        uart_tx,
    output logic        uart_rts_n,         // Request to Send (active low)
    input  logic        uart_cts_n,         // Clear to Send (active low)
    output logic [3:0]  led                 // 4-bit LED control
    // System status outputs - simulation only
    `ifdef DEFINE_SIM
    // Simulation-only system status outputs
    , output logic        system_busy,
    output logic [7:0]  system_error,
    output logic        system_ready
    `endif
);

    // Internal AXI4-Lite interface connecting UART bridge to register block
    axi4_lite_if #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) axi_internal (
        .clk(clk),
        .rst(rst)
    );
    
    // Bridge control and status signals
    logic        bridge_reset_stats;
    logic        bridge_soft_reset;  // RESET command from parser
    logic [15:0] baud_div_config;
    logic [7:0]  timeout_config;
    logic [3:0]  debug_mode;
    
    logic        bridge_busy;
    logic [7:0]  bridge_error_code;
    logic [15:0] tx_count;
    logic [15:0] rx_count;
    logic [7:0]  fifo_status;
    
    logic [3:0]  test_led_internal;  // LED control from register block
    
    // Flow control signals
    logic        rx_fifo_full;
    logic        rx_fifo_high;
    logic        tx_ready;
    
    // Internal reset logic
    logic internal_rst;
    assign internal_rst = rst;
    
    // Top-level UART signal monitoring for debugging - disabled for production
    logic prev_uart_rx, prev_uart_tx;
    always @(posedge clk) begin
        if (rst) begin
            prev_uart_rx <= 1'b1;
            prev_uart_tx <= 1'b1;
        end else begin
            prev_uart_rx <= uart_rx;
            prev_uart_tx <= uart_tx;
        end
    end
    
    // Keep DUT baud rate aligned with UVM driver configuration in all builds
    localparam int EFFECTIVE_BAUD_RATE = BAUD_RATE;

    // UART-AXI4 Bridge instantiation
    Uart_Axi4_Bridge #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(EFFECTIVE_BAUD_RATE),
        .AXI_TIMEOUT(AXI_TIMEOUT),
        .UART_OVERSAMPLE(UART_OVERSAMPLE),
        .RX_FIFO_DEPTH(RX_FIFO_DEPTH),
        .TX_FIFO_DEPTH(TX_FIFO_DEPTH),
        .MAX_LEN(MAX_LEN)
    ) uart_bridge_inst (
        .clk(clk),
        .rst(internal_rst),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .uart_cts_n(uart_cts_n),        // Clear to Send input
        .rx_fifo_full_out(rx_fifo_full),    // RX FIFO status for RTS control
        .rx_fifo_high_out(rx_fifo_high),    // RX FIFO high threshold
        .tx_ready_out(tx_ready),            // TX readiness status
        .axi(axi_internal),  // 内部レジスタブロックに直接接続
        .baud_divisor_cfg(baud_div_config),
        
        // Status monitoring connections
        .bridge_busy(bridge_busy),
        .bridge_error_code(bridge_error_code),
        .tx_transaction_count(tx_count),
        .rx_transaction_count(rx_count),
        .fifo_status_flags(fifo_status),
        .reset_statistics(bridge_reset_stats),
        .soft_reset_request(bridge_soft_reset)  // RESET command output
    );
    
    // Register Block instantiation - UART bridgeからのみアクセス可能
    Register_Block #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32),
        .BASE_ADDR(REG_BASE_ADDR)
    ) register_block_inst (
        .clk(clk),
        .rst(rst),
        .soft_reset_request(bridge_soft_reset),  // Soft reset from RESET command
        .axi(axi_internal.slave),  // UARTブリッジからの内部アクセス
        
        // Control outputs
        .bridge_reset_stats(bridge_reset_stats),
        .baud_div_config(baud_div_config),
        .timeout_config(timeout_config),
        .debug_mode(debug_mode),
        .test_led(test_led_internal),  // LED control output
        
        // Status inputs
        .bridge_busy(bridge_busy),
        .error_code(bridge_error_code),
        .tx_count(tx_count),
        .rx_count(rx_count),
        .fifo_status(fifo_status)
    );
    
    // Hardware Flow Control Logic
    // RTS (Request to Send) - Active Low
    // Assert RTS_n (Low) when system is ready to receive
    always_ff @(posedge clk) begin
        if (rst) begin
            uart_rts_n <= 1'b1;  // Deassert RTS (not ready) on reset
        end else begin
            // Deassert RTS (not ready to receive) when:
            // - RX FIFO is full
            // - RX FIFO is approaching high threshold
            // Otherwise assert RTS (ready to receive)
            uart_rts_n <= rx_fifo_full || rx_fifo_high;
        end
    end
    
    // LED control from TEST_LED register
    assign led = test_led_internal;
    
    // AXI4-Lite Address Router and Interconnect
    // System status outputs (simulation only)
    `ifdef DEFINE_SIM
    assign system_busy = bridge_busy;
    assign system_error = bridge_error_code;
    assign system_ready = !system_busy && (bridge_error_code == 8'h00);
    `endif

endmodule
