`timescale 1ns / 1ps

module uart_unit_frame_parser_tb;
    localparam logic [7:0] SOF = 8'hA5;
    localparam logic [7:0] STATUS_OK = 8'h00;
    localparam logic [7:0] STATUS_CRC_ERR = 8'h01;
    localparam logic [7:0] STATUS_TIMEOUT = 8'h04;
    localparam logic [7:0] TEST_CMD = 8'h40;  // WRITE, increment, byte-size, len=1 byte

    logic clk;
    logic rst;

    logic [7:0] rx_fifo_data;
    logic rx_fifo_empty;
    logic rx_fifo_rd_en;
    logic [15:0] baud_divisor;

    logic [7:0] cmd;
    logic [31:0] addr;
    logic [7:0] data_out [0:63];
    logic [6:0] data_count;
    logic frame_valid;
    logic [7:0] error_status;
    logic frame_error;
    logic frame_consumed;
    logic parser_busy;
    logic soft_reset_request;
    logic [7:0] debug_cmd_in;
    logic [7:0] debug_cmd_decoded;
    logic [7:0] debug_status_out;
    logic [7:0] debug_crc_in;
    logic [7:0] debug_crc_calc;
    logic debug_crc_error;
    logic [3:0] debug_state;
    logic [7:0] debug_error_cause;

    byte unsigned rx_stream[$];
    int fail_count;

    Frame_Parser #(
        .CLK_FREQ_HZ(1000),
        .BAUD_RATE(100),
        .TIMEOUT_BYTE_TIMES(1),
        .ENABLE_TIMEOUT(1'b1),
        .ENABLE_ASSERTIONS(1'b0)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rx_fifo_data(rx_fifo_data),
        .rx_fifo_empty(rx_fifo_empty),
        .rx_fifo_rd_en(rx_fifo_rd_en),
        .baud_divisor(baud_divisor),
        .cmd(cmd),
        .addr(addr),
        .data_out(data_out),
        .data_count(data_count),
        .frame_valid(frame_valid),
        .error_status(error_status),
        .frame_error(frame_error),
        .frame_consumed(frame_consumed),
        .parser_busy(parser_busy),
        .soft_reset_request(soft_reset_request),
        .debug_cmd_in(debug_cmd_in),
        .debug_cmd_decoded(debug_cmd_decoded),
        .debug_status_out(debug_status_out),
        .debug_crc_in(debug_crc_in),
        .debug_crc_calc(debug_crc_calc),
        .debug_crc_error(debug_crc_error),
        .debug_state(debug_state),
        .debug_error_cause(debug_error_cause)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_comb begin
        rx_fifo_empty = (rx_stream.size() == 0);
        rx_fifo_data = rx_fifo_empty ? 8'h00 : rx_stream[0];
    end

    always_ff @(posedge clk) begin
        if (!rst && rx_fifo_rd_en && !rx_fifo_empty) begin
            void'(rx_stream.pop_front());
        end
    end

    function automatic logic [7:0] calc_crc8_byte(input logic [7:0] current_crc, input logic [7:0] data_byte);
        logic [7:0] crc_temp;
        begin
            crc_temp = current_crc ^ data_byte;
            repeat (8) begin
                if (crc_temp[7]) begin
                    crc_temp = (crc_temp << 1) ^ 8'h07;
                end else begin
                    crc_temp = crc_temp << 1;
                end
            end
            return crc_temp;
        end
    endfunction

    function automatic logic [7:0] calc_crc_payload(input byte unsigned payload[$]);
        logic [7:0] crc;
        begin
            crc = 8'h00;
            foreach (payload[i]) begin
                crc = calc_crc8_byte(crc, payload[i]);
            end
            return crc;
        end
    endfunction

    task automatic enqueue_frame(input byte unsigned payload[$], input logic [7:0] crc_value);
        begin
            rx_stream.push_back(SOF);
            foreach (payload[i]) begin
                rx_stream.push_back(payload[i]);
            end
            rx_stream.push_back(crc_value);
        end
    endtask

    task automatic consume_frame;
        begin
            frame_consumed = 1'b1;
            @(posedge clk);
            frame_consumed = 1'b0;
            repeat (3) @(posedge clk);
        end
    endtask

    task automatic wait_for_terminal_state(input int max_cycles, input string label);
        begin
            for (int i = 0; i < max_cycles; i++) begin
                @(posedge clk);
                if (frame_valid || frame_error) begin
                    return;
                end
            end
            $error("[FRAME_PARSER_UNIT] %s timeout waiting for frame_valid/frame_error", label);
            fail_count++;
        end
    endtask

    initial begin
        byte unsigned payload[$];
        logic [7:0] good_crc;
        logic [7:0] bad_crc;

        fail_count = 0;
        frame_consumed = 1'b0;
        baud_divisor = 16'd16;
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        // Case 1: valid frame parse
        payload.delete();
        payload.push_back(TEST_CMD);
        payload.push_back(8'h00);
        payload.push_back(8'h10);
        payload.push_back(8'h00);
        payload.push_back(8'h00);
        payload.push_back(8'h5A);
        good_crc = calc_crc_payload(payload);
        enqueue_frame(payload, good_crc);

        wait_for_terminal_state(300, "valid frame");
        if (!frame_valid) begin
            $error("[FRAME_PARSER_UNIT] valid frame: frame_valid not asserted");
            fail_count++;
        end
        if (frame_error) begin
            $error("[FRAME_PARSER_UNIT] valid frame: unexpected frame_error");
            fail_count++;
        end
        if (cmd !== TEST_CMD || addr !== 32'h0000_1000 || data_count !== 7'd1 || data_out[0] !== 8'h5A) begin
            $error("[FRAME_PARSER_UNIT] valid frame payload mismatch cmd=%02h addr=%08h count=%0d data0=%02h",
                   cmd, addr, data_count, data_out[0]);
            fail_count++;
        end
        if (error_status !== STATUS_OK) begin
            $error("[FRAME_PARSER_UNIT] valid frame status mismatch: %02h", error_status);
            fail_count++;
        end
        consume_frame();

        // Case 2: bad CRC rejection
        payload.delete();
        payload.push_back(TEST_CMD);
        payload.push_back(8'h04);
        payload.push_back(8'h10);
        payload.push_back(8'h00);
        payload.push_back(8'h00);
        payload.push_back(8'hA6);
        good_crc = calc_crc_payload(payload);
        bad_crc = good_crc ^ 8'hFF;
        enqueue_frame(payload, bad_crc);

        wait_for_terminal_state(300, "bad crc frame");
        if (!frame_error) begin
            $error("[FRAME_PARSER_UNIT] bad CRC frame: frame_error not asserted");
            fail_count++;
        end
        if (frame_valid) begin
            $error("[FRAME_PARSER_UNIT] bad CRC frame: frame_valid should be 0");
            fail_count++;
        end
        if (error_status !== STATUS_CRC_ERR) begin
            $error("[FRAME_PARSER_UNIT] bad CRC frame: expected STATUS_CRC_ERR got=%02h", error_status);
            fail_count++;
        end
        consume_frame();

        // Case 3: truncated frame timeout
        rx_stream.delete();
        rx_stream.push_back(SOF);
        rx_stream.push_back(TEST_CMD);

        wait_for_terminal_state(300, "truncated frame timeout");
        if (!frame_error) begin
            $error("[FRAME_PARSER_UNIT] truncated frame: frame_error not asserted");
            fail_count++;
        end
        if (frame_valid) begin
            $error("[FRAME_PARSER_UNIT] truncated frame: frame_valid should be 0");
            fail_count++;
        end
        consume_frame();

        if (fail_count == 0) begin
            $display("[FRAME_PARSER_UNIT] TEST PASSED");
            $finish;
        end else begin
            $fatal(1, "[FRAME_PARSER_UNIT] TEST FAILED (fail_count=%0d)", fail_count);
        end
    end

endmodule
