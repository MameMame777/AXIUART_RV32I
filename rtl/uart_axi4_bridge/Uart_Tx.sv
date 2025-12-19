`timescale 1ns / 1ps

// UART Transmitter Module for UART-AXI4 Bridge
// 8N1 format with FIXED baud rate, LSB-first transmission
// FIXED BAUD RATE: 115200 bps
module Uart_Tx #(
    parameter int CLK_FREQ_HZ = 125_000_000,   // System clock frequency (125MHz)
    parameter int BAUD_RATE = 115200,          // UART baud rate (FIXED)
    parameter int OVERSAMPLE = 16              // Oversampling factor (must match Uart_Rx)
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       soft_reset_request,    // Soft reset from RESET command (pulse)
    input  logic [7:0] tx_data,               // Data to transmit
    input  logic       tx_start,              // Start transmission pulse
    input  logic       uart_cts_n,            // Clear to Send (active low)
    input  logic [15:0] baud_divisor,         // Runtime baud divisor (cycles per bit)
    output logic       uart_tx,               // UART TX line
    output logic       tx_busy,               // Transmission in progress
    output logic       tx_done                // Transmission complete pulse
);

    localparam int DEFAULT_DIV_CALC = (BAUD_RATE > 0) ? (CLK_FREQ_HZ / BAUD_RATE) : 1;
    localparam int DEFAULT_DIV_CLAMP = (DEFAULT_DIV_CALC < 1)
        ? 1
        : ((DEFAULT_DIV_CALC > 16'hFFFF) ? 16'hFFFF : DEFAULT_DIV_CALC);
    localparam logic [15:0] DEFAULT_BAUD_DIVISOR = 16'(DEFAULT_DIV_CLAMP);

    logic [15:0] config_baud_divisor;
    logic [15:0] active_baud_divisor;
    logic [15:0] baud_limit;
    logic [15:0] baud_counter;
    logic        baud_tick;
    
    // Bit counter
    logic [3:0] bit_counter;
    
    // State machine
    typedef enum logic [2:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BIT
    } tx_state_t;
    
    tx_state_t tx_state, tx_state_next;
    
    // Data shift register
    logic [7:0] tx_shift_reg;
    logic [7:0] tx_shift_reg_next;
    
    // Debug signals for FPGA debugging - UART bit-level analysis
    logic [7:0] debug_uart_tx_shift_reg;    // Shift register contents
    logic       debug_uart_tx_bit;          // Current bit being sent
    logic [2:0] debug_uart_tx_state;        // TX state machine
    logic [3:0] debug_uart_bit_counter;     // Bit position counter

    always_comb begin
        int unsigned candidate;

        candidate = (baud_divisor != 16'd0) ? baud_divisor : DEFAULT_BAUD_DIVISOR;
        if (candidate < 1) begin
            candidate = 1;
        end else if (candidate > 16'hFFFF) begin
            candidate = 16'hFFFF;
        end

    config_baud_divisor = 16'(candidate);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            active_baud_divisor <= DEFAULT_BAUD_DIVISOR;
        end else if (!tx_busy) begin
            // TX uses baud_divisor directly (no OVERSAMPLE multiplication)
            active_baud_divisor <= config_baud_divisor;
        end
    end

    always_comb begin
        baud_limit = (active_baud_divisor > 16'd0) ? (active_baud_divisor - 16'd1) : 16'd0;
    end
    
    // Baud rate generator
    always_ff @(posedge clk) begin
        if (rst) begin
            baud_counter <= '0;
        end else if (soft_reset_request) begin
            // SOFT RESET: Clear baud counter to resync timing
            baud_counter <= '0;
        end else begin
            if (tx_busy) begin
                if (baud_counter == baud_limit) begin
                    baud_counter <= '0;
                end else begin
                    baud_counter <= baud_counter + 1;
                end
            end else begin
                baud_counter <= '0;
            end
        end
    end
    // Pulse once per completed baud interval so start/data/stop bits hold for a full period
    assign baud_tick = tx_busy && (baud_counter == baud_limit);
    
    // State machine (sequential part)
    always_ff @(posedge clk) begin
        if (rst) begin
            tx_state <= IDLE;
            bit_counter <= '0;
            tx_shift_reg <= '0;
        end else if (soft_reset_request) begin
            // SOFT RESET: Return to IDLE state, abort current transmission
            tx_state <= IDLE;
            bit_counter <= '0;
            tx_shift_reg <= '0;
        end else begin
            tx_state <= tx_state_next;
            tx_shift_reg <= tx_shift_reg_next; // Use combinationally computed next value
            
            `ifdef ENABLE_DEBUG
                if (tx_start) begin
                end
                if (tx_state_next == START_BIT && tx_state == IDLE) begin
                end
                if (tx_state == DATA_BITS) begin
                end
            `endif
            
            // Bit counter management
            if (tx_state_next == IDLE) begin
                bit_counter <= '0;
            end else if (tx_state == DATA_BITS && baud_tick && bit_counter <= 7) begin
                bit_counter <= bit_counter + 1;
            end
        end
    end
    
    // State machine (combinational part) - tx_shift_reg_next logic
    always_comb begin
        tx_state_next = tx_state;
        tx_shift_reg_next = tx_shift_reg; // Default: hold current value
        
        case (tx_state)
            IDLE: begin
                // Only start transmission if CTS is asserted (active low)
                if (tx_start && !uart_cts_n) begin
                    tx_state_next = START_BIT;
                    tx_shift_reg_next = tx_data; // Latch data combinationally for same-cycle use
                    `ifdef ENABLE_DEBUG
                    `endif
                end
            end
            
            START_BIT: begin
                // Check CTS before proceeding - if CTS is deasserted, hold in START_BIT
                if (baud_tick && !uart_cts_n) begin
                    tx_state_next = DATA_BITS;
                end
            end
            
            DATA_BITS: begin
                // Continue transmission regardless of CTS during data bits
                // (CTS is checked at frame boundaries only)
                if (baud_tick) begin
                    if (bit_counter >= 7) begin
                        tx_state_next = STOP_BIT;
                    end else begin
                        // Shift for next bit (occurs at end of current bit period)
                        tx_shift_reg_next = {1'b0, tx_shift_reg[7:1]};
                    end
                end
            end
            
            STOP_BIT: begin
                if (baud_tick) begin
                    tx_state_next = IDLE;
                end
            end
        endcase
    end
    
    // Output generation
    logic uart_tx_int;
    logic tx_done_int;
    
    always_comb begin
        uart_tx_int = 1'b1;  // Default to idle high to prevent latch inference
        case (tx_state)
            IDLE:      uart_tx_int = 1'b1;         // Idle high
            START_BIT: uart_tx_int = 1'b0;         // Start bit low
            DATA_BITS: uart_tx_int = tx_shift_reg[0]; // LSB first
            STOP_BIT:  uart_tx_int = 1'b1;         // Stop bit high
            default:   uart_tx_int = 1'b1;         // Default case for completeness
        endcase
    end
    
    always_ff @(posedge clk) begin
        if (rst) begin
            tx_done_int <= 1'b0;
        end else begin
            tx_done_int <= (tx_state == STOP_BIT) && baud_tick;
        end
    end
    
    assign uart_tx = uart_tx_int;
    assign tx_busy = (tx_state != IDLE);
    assign tx_done = tx_done_int;
    
    // Debug signal assignments - UART bit-level debugging
    assign debug_uart_tx_shift_reg = tx_shift_reg;
    assign debug_uart_tx_bit = uart_tx_int;
    assign debug_uart_tx_state = tx_state;
    assign debug_uart_bit_counter = bit_counter;

    // Assertions for verification
    `ifdef ENABLE_UART_TX_ASSERTIONS
        // tx_done should be a single-cycle pulse
        assert_tx_done_pulse: assert property (
            @(posedge clk) disable iff (rst)
            tx_done |=> !tx_done
        ) else $error("UART_TX: tx_done should be a single-cycle pulse");

        // Should not start transmission when already busy
        assert_no_start_when_busy: assert property (
            @(posedge clk) disable iff (rst)
            tx_busy |-> !tx_start
        ) else $warning("UART_TX: tx_start asserted while busy");

        // TX line should be high when idle
        assert_tx_high_when_idle: assert property (
            @(posedge clk) disable iff (rst)
            (tx_state == IDLE) |-> uart_tx
        ) else $error("UART_TX: TX line should be high when idle");

        // TX line should be low during start bit
        assert_tx_low_during_start: assert property (
            @(posedge clk) disable iff (rst)
            (tx_state == START_BIT) |-> !uart_tx
        ) else $error("UART_TX: TX line should be low during start bit");

        // TX line should be high during stop bit
        assert_tx_high_during_stop: assert property (
            @(posedge clk) disable iff (rst)
            (tx_state == STOP_BIT) |-> uart_tx
        ) else $error("UART_TX: TX line should be high during stop bit");
    `endif

endmodule
