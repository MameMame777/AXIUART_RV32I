`timescale 1ns / 1ps

module uart_unit_uart_rx_tb;
    localparam int OVERSAMPLE = 16;
    localparam int BAUD_DIVISOR = 16;

    logic clk;
    logic rst;
    logic soft_reset_request;
    logic uart_rx;
    logic [15:0] baud_divisor;
    logic [7:0] rx_data;
    logic rx_valid;
    logic rx_error;
    logic rx_busy;

    logic [7:0] tx_data;
    logic tx_start;
    logic tx_busy;
    logic tx_done;
    logic tx_uart;
    logic uart_cts_n;
    logic manual_mode;
    logic manual_uart;

    int fail_count;

    Uart_Rx #(
        .CLK_FREQ_HZ(16_000),
        .BAUD_RATE(1_000),
        .OVERSAMPLE(OVERSAMPLE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .soft_reset_request(soft_reset_request),
        .uart_rx(uart_rx),
        .baud_divisor(baud_divisor),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_error(rx_error),
        .rx_busy(rx_busy)
    );

    Uart_Tx #(
        .CLK_FREQ_HZ(16_000),
        .BAUD_RATE(1_000),
        .OVERSAMPLE(OVERSAMPLE)
    ) stim_tx (
        .clk(clk),
        .rst(rst),
        .soft_reset_request(1'b0),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .uart_cts_n(uart_cts_n),
        .baud_divisor(baud_divisor),
        .uart_tx(tx_uart),
        .tx_busy(tx_busy),
        .tx_done(tx_done)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic apply_reset;
        begin
            rst = 1'b1;
            soft_reset_request = 1'b0;
            baud_divisor = BAUD_DIVISOR;
            tx_data = 8'h00;
            tx_start = 1'b0;
            uart_cts_n = 1'b0;
            manual_mode = 1'b0;
            manual_uart = 1'b1;
            repeat (4) @(posedge clk);
            rst = 1'b0;
            repeat (4) @(posedge clk);
        end
    endtask

    task automatic start_tx_byte(input logic [7:0] value);
        begin
            tx_data = value;
            tx_start = 1'b1;
            @(posedge clk);
            tx_start = 1'b0;
        end
    endtask

    task automatic wait_for_rx_valid(input int max_cycles, input string label, output bit seen);
        begin
            seen = 1'b0;
            if (rx_valid) begin
                seen = 1'b1;
                return;
            end
            for (int i = 0; i < max_cycles; i++) begin
                @(posedge clk);
                if (rx_valid) begin
                    seen = 1'b1;
                    return;
                end
            end
            $error("[UART_RX_UNIT] %s: timeout waiting for rx_valid", label);
            fail_count++;
        end
    endtask

    task automatic check(input logic cond, input string label);
        begin
            if (!cond) begin
                $error("[UART_RX_UNIT] check failed: %s", label);
                fail_count++;
            end
        end
    endtask

    always_comb begin
        uart_rx = manual_mode ? manual_uart : tx_uart;
    end

    initial begin
        bit seen;

        fail_count = 0;
        apply_reset();

        // Case 1: valid frame decode
        manual_mode = 1'b0;
        start_tx_byte(8'hA5);
        wait_for_rx_valid(800, "valid frame", seen);
        if (seen) begin
            check(rx_data == 8'hA5, "valid frame data = 0xA5");
            check(rx_error == 1'b0, "valid frame rx_error=0");
            @(posedge clk);
            check(!rx_valid, "rx_valid single-cycle pulse");
        end

        // Case 2: false-start rejection (short low glitch)
        manual_mode = 1'b1;
        manual_uart = 1'b1;
        repeat (6) @(posedge clk);
        manual_uart = 1'b0;
        repeat (2) @(posedge clk);
        manual_uart = 1'b1;
        repeat (120) @(posedge clk);
        check(!rx_valid, "false start does not produce rx_valid");

        // Case 3: soft reset abort mid-frame
        manual_mode = 1'b0;
        start_tx_byte(8'h3C);
        repeat (50) @(posedge clk);
        soft_reset_request = 1'b1;
        @(posedge clk);
        soft_reset_request = 1'b0;
        wait (tx_done == 1'b1);
        repeat (80) @(posedge clk);
        check(!rx_valid, "soft reset abort prevents completion");

        if (fail_count == 0) begin
            $display("[UART_RX_UNIT] TEST PASSED");
            $finish;
        end else begin
            $fatal(1, "[UART_RX_UNIT] TEST FAILED (fail_count=%0d)", fail_count);
        end
    end

endmodule
