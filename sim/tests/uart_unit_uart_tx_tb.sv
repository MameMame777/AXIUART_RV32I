`timescale 1ns / 1ps

module uart_unit_uart_tx_tb;
    localparam int BAUD_DIVISOR = 8;

    logic clk;
    logic rst;
    logic soft_reset_request;
    logic [7:0] tx_data;
    logic tx_start;
    logic uart_cts_n;
    logic [15:0] baud_divisor;
    logic uart_tx;
    logic tx_busy;
    logic tx_done;

    int fail_count;

    Uart_Tx #(
        .CLK_FREQ_HZ(8_000),
        .BAUD_RATE(1_000),
        .OVERSAMPLE(16)
    ) dut (
        .clk(clk),
        .rst(rst),
        .soft_reset_request(soft_reset_request),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .uart_cts_n(uart_cts_n),
        .baud_divisor(baud_divisor),
        .uart_tx(uart_tx),
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
            tx_data = 8'h00;
            tx_start = 1'b0;
            uart_cts_n = 1'b0;
            baud_divisor = BAUD_DIVISOR;
            repeat (4) @(posedge clk);
            rst = 1'b0;
            repeat (4) @(posedge clk);
        end
    endtask

    task automatic start_tx(input logic [7:0] value);
        begin
            tx_data = value;
            tx_start = 1'b1;
            @(posedge clk);
            tx_start = 1'b0;
        end
    endtask

    task automatic wait_until_busy(input int max_cycles, input string label, output bit seen);
        begin
            seen = 1'b0;
            for (int i = 0; i < max_cycles; i++) begin
                @(posedge clk);
                if (tx_busy) begin
                    seen = 1'b1;
                    return;
                end
            end
            $error("[UART_TX_UNIT] %s: timeout waiting for tx_busy", label);
            fail_count++;
        end
    endtask

    task automatic wait_until_done(input int max_cycles, input string label, output bit seen);
        begin
            seen = 1'b0;
            for (int i = 0; i < max_cycles; i++) begin
                @(posedge clk);
                if (tx_done) begin
                    seen = 1'b1;
                    return;
                end
            end
            $error("[UART_TX_UNIT] %s: timeout waiting for tx_done", label);
            fail_count++;
        end
    endtask

    task automatic check(input logic cond, input string label);
        begin
            if (!cond) begin
                $error("[UART_TX_UNIT] check failed: %s", label);
                fail_count++;
            end
        end
    endtask

    initial begin
        bit seen;
        logic [7:0] test_byte;

        fail_count = 0;
        apply_reset();

        // Case 1: normal transmit framing + tx_done pulse
        test_byte = 8'h96;
        start_tx(test_byte);
        wait_until_busy(40, "normal tx start", seen);

        repeat (BAUD_DIVISOR/2) @(posedge clk);
        check(uart_tx == 1'b0, "start bit is low");

        for (int i = 0; i < 8; i++) begin
            repeat (BAUD_DIVISOR) @(posedge clk);
            check(uart_tx == test_byte[i], $sformatf("data bit[%0d] matches", i));
        end

        repeat (BAUD_DIVISOR) @(posedge clk);
        check(uart_tx == 1'b1, "stop bit is high");

        wait_until_done(40, "normal tx done", seen);
        if (seen) begin
            @(posedge clk);
            check(!tx_done, "tx_done single-cycle pulse");
            check(!tx_busy, "tx not busy after done");
            check(uart_tx, "tx line idle high after done");
        end

        // Case 2: CTS gate blocks start when deasserted (active low)
        uart_cts_n = 1'b1;
        start_tx(8'h55);
        repeat (BAUD_DIVISOR*3) @(posedge clk);
        check(!tx_busy, "tx blocked when cts_n=1");
        check(uart_tx, "tx line stays idle when blocked");
        uart_cts_n = 1'b0;

        // Case 3: soft reset abort while busy
        start_tx(8'h3C);
        wait_until_busy(40, "soft reset case start", seen);
        if (seen) begin
            repeat (BAUD_DIVISOR*2) @(posedge clk);
            soft_reset_request = 1'b1;
            @(posedge clk);
            soft_reset_request = 1'b0;
            repeat (4) @(posedge clk);
            check(!tx_busy, "soft reset clears busy");
            check(uart_tx, "soft reset returns line to idle high");
        end

        if (fail_count == 0) begin
            $display("[UART_TX_UNIT] TEST PASSED");
            $finish;
        end else begin
            $fatal(1, "[UART_TX_UNIT] TEST FAILED (fail_count=%0d)", fail_count);
        end
    end

endmodule
