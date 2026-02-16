`timescale 1ns / 1ps

module uart_unit_fifo_sync_tb;
    localparam int FIFO_DEPTH = 4;

    logic clk;
    logic rst;
    logic wr_en;
    logic [7:0] wr_data;
    logic full;
    logic almost_full;
    logic rd_en;
    logic [7:0] rd_data;
    logic empty;
    logic almost_empty;
    logic [2:0] count;

    int fail_count;

    fifo_sync #(
        .DATA_WIDTH(8),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .full(full),
        .almost_full(almost_full),
        .rd_en(rd_en),
        .rd_data(rd_data),
        .empty(empty),
        .almost_empty(almost_empty),
        .count(count)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic apply_reset;
        begin
            rst = 1'b1;
            wr_en = 1'b0;
            rd_en = 1'b0;
            wr_data = 8'h00;
            repeat (2) @(posedge clk);
            rst = 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic write_byte(input logic [7:0] value);
        begin
            wr_data = value;
            wr_en = 1'b1;
            @(posedge clk);
            wr_en = 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic read_byte(output logic [7:0] value);
        begin
            value = rd_data;
            rd_en = 1'b1;
            @(posedge clk);
            rd_en = 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic check(input logic condition, input string label);
        begin
            if (!condition) begin
                $error("[FIFO_UNIT] check failed: %s", label);
                fail_count++;
            end
        end
    endtask

    initial begin
        logic [7:0] v;

        fail_count = 0;
        apply_reset();

        // Empty condition after reset
        check(empty && !full && (count == 0), "reset empty/full/count");

        // Fill exactly to depth (boundary)
        write_byte(8'h11);
        write_byte(8'h22);
        write_byte(8'h33);
        write_byte(8'h44);
        check(full && !empty && (count == FIFO_DEPTH), "full at exact depth");
        check(almost_full, "almost_full asserted near/full");

        // Overflow attempt should not change count
        write_byte(8'h55);
        check(full && (count == FIFO_DEPTH), "overflow write blocked");

        // Read all data and verify order
        read_byte(v); check(v == 8'h11, "read order item0");
        read_byte(v); check(v == 8'h22, "read order item1");
        read_byte(v); check(v == 8'h33, "read order item2");
        read_byte(v); check(v == 8'h44, "read order item3");
        check(empty && !full && (count == 0), "empty after draining");

        // Simultaneous read/write keeps count and updates queue correctly
        write_byte(8'hA1);
        write_byte(8'hB2);
        check(count == 2, "prefill count for simultaneous rw");

        wr_data = 8'hC3;
        wr_en = 1'b1;
        rd_en = 1'b1;
        v = rd_data;
        @(posedge clk);
        wr_en = 1'b0;
        rd_en = 1'b0;
        @(posedge clk);

        check(v == 8'hA1, "simultaneous rw read returns old head");
        check(count == 2, "simultaneous rw count unchanged");

        read_byte(v); check(v == 8'hB2, "simultaneous rw remaining item0");
        read_byte(v); check(v == 8'hC3, "simultaneous rw remaining item1");

        if (fail_count == 0) begin
            $display("[FIFO_UNIT] TEST PASSED");
            $finish;
        end else begin
            $fatal(1, "[FIFO_UNIT] TEST FAILED (fail_count=%0d)", fail_count);
        end
    end

endmodule
