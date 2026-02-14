`timescale 1ns / 1ps

module uart_unit_crc8_tb;
    logic clk;
    logic rst;
    logic crc_enable;
    logic [7:0] data_in;
    logic crc_reset;
    logic [7:0] crc_out;
    logic [7:0] crc_final;

    int fail_count;

    Crc8_Calculator dut (
        .clk(clk),
        .rst(rst),
        .crc_enable(crc_enable),
        .data_in(data_in),
        .crc_reset(crc_reset),
        .crc_out(crc_out),
        .crc_final(crc_final)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic apply_reset;
        begin
            rst = 1'b1;
            crc_enable = 1'b0;
            crc_reset = 1'b0;
            data_in = 8'h00;
            repeat (2) @(posedge clk);
            rst = 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic pulse_crc_reset;
        begin
            crc_reset = 1'b1;
            @(posedge clk);
            crc_reset = 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic push_byte(input logic [7:0] value);
        begin
            data_in = value;
            crc_enable = 1'b1;
            @(posedge clk);
            crc_enable = 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic check_crc(input logic [7:0] expected, input string label);
        begin
            if (crc_out !== expected || crc_final !== expected) begin
                $error("[CRC8_UNIT] %s failed: expected=0x%02h got_out=0x%02h got_final=0x%02h",
                       label, expected, crc_out, crc_final);
                fail_count++;
            end
        end
    endtask

    initial begin
        fail_count = 0;
        apply_reset();

        // Known pattern: 12 34 56 78 -> CRC=1C
        pulse_crc_reset();
        push_byte(8'h12);
        push_byte(8'h34);
        push_byte(8'h56);
        push_byte(8'h78);
        check_crc(8'h1C, "Known vector 12 34 56 78");

        // Zero data input: 00 -> CRC=00
        pulse_crc_reset();
        push_byte(8'h00);
        check_crc(8'h00, "Zero data vector 00");

        // All-ones data input: FF -> CRC=F3
        pulse_crc_reset();
        push_byte(8'hFF);
        check_crc(8'hF3, "All-ones vector FF");

        if (fail_count == 0) begin
            $display("[CRC8_UNIT] TEST PASSED");
            $finish;
        end else begin
            $fatal(1, "[CRC8_UNIT] TEST FAILED (fail_count=%0d)", fail_count);
        end
    end

endmodule
