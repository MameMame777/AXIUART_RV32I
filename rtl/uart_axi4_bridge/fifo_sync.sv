`timescale 1ns / 1ps

// Synchronous FIFO for UART-AXI4 Bridge
// 64-deep, 8-bit wide FIFO with proper count width
module fifo_sync #(
    parameter int DATA_WIDTH = 8,
    parameter int FIFO_DEPTH = 64,
    parameter int ADDR_WIDTH = $clog2(FIFO_DEPTH),
    parameter int COUNT_WIDTH = $clog2(FIFO_DEPTH) + 1  // 7 bits for 64-deep FIFO
)(
    input  logic                    clk,
    input  logic                    rst,
    
    // Write interface
    input  logic                    wr_en,
    input  logic [DATA_WIDTH-1:0]   wr_data,
    output logic                    full,
    output logic                    almost_full,
    
    // Read interface
    input  logic                    rd_en,
    output logic [DATA_WIDTH-1:0]   rd_data,
    output logic                    empty,
    output logic                    almost_empty,
    
    // Status
    output logic [COUNT_WIDTH-1:0]  count
);

    // Memory array
    logic [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];
    
    // Pointers
    logic [ADDR_WIDTH-1:0] wr_ptr;
    logic [ADDR_WIDTH-1:0] rd_ptr;
    logic [COUNT_WIDTH-1:0] fifo_count;
    
    // Unified pointer management and memory write (single always_ff block)
    always_ff @(posedge clk) begin
        if (rst) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            fifo_count <= '0;
            // Memory initialization removed - not necessary since pointers control access
            // Old data becomes inaccessible after pointer reset
        end else begin
            // Write pointer and memory write (combined to avoid MultiBlockWrite)
            if (wr_en && !full) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr <= (wr_ptr == FIFO_DEPTH-1) ? '0 : wr_ptr + 1;
            end
            
            // Read pointer
            if (rd_en && !empty) begin
                rd_ptr <= (rd_ptr == FIFO_DEPTH-1) ? '0 : rd_ptr + 1;
            end
            
            // Count update
            case ({wr_en && !full, rd_en && !empty})
                2'b01: fifo_count <= fifo_count - 1;  // Read only
                2'b10: fifo_count <= fifo_count + 1;  // Write only
                default: fifo_count <= fifo_count;    // Both or neither
            endcase
        end
    end
    
    // Memory read (combinational)
    assign rd_data = mem[rd_ptr];
    
    // Status flags
    assign empty = (fifo_count == 0);
    assign full = (fifo_count == FIFO_DEPTH);
    assign almost_empty = (fifo_count <= 1);
    assign almost_full = (fifo_count >= FIFO_DEPTH-1);
    assign count = fifo_count;

    // Assertions for verification
    `ifdef ENABLE_FIFO_ASSERTIONS
        // Count should never exceed depth
        assert_count_range: assert property (
            @(posedge clk) disable iff (rst)
            fifo_count <= FIFO_DEPTH
        ) else $error("FIFO: Count exceeds depth");

        // Empty and full should be mutually exclusive
        assert_empty_full_exclusive: assert property (
            @(posedge clk) disable iff (rst)
            !(empty && full)
        ) else $error("FIFO: Empty and full both asserted");

        // No write when full
        assert_no_write_when_full: assert property (
            @(posedge clk) disable iff (rst)
            full |-> !wr_en
        ) else $warning("FIFO: Write attempt when full");

        // No read when empty
        assert_no_read_when_empty: assert property (
            @(posedge clk) disable iff (rst)
            empty |-> !rd_en
        ) else $warning("FIFO: Read attempt when empty");
    `endif

endmodule
