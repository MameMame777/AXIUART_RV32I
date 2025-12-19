`timescale 1ns / 1ps

// Top-level UART-AXI4-Lite Bridge Module
// Implements complete protocol per AXIUART_/docs/uart_axi4_protocol.md
// FIXED BAUD RATE: 115200 bps
//
// Debug instrumentation added 2025-10-05 per fpga_debug_work_plan.md
// Phase 3&4 signals: debug_uart_tx_data, debug_uart_tx_valid, debug_uart_rx_data,
//                    debug_uart_rx_valid, debug_axi_awaddr, debug_axi_wdata, 
//                    debug_axi_bresp, debug_axi_araddr, debug_axi_rresp, debug_axi_state
module Uart_Axi4_Bridge #(
    parameter int CLK_FREQ_HZ = 125_000_000,    // System clock frequency (125MHz)
    parameter int BAUD_RATE = 115200,           // UART baud rate (FIXED)
    parameter int AXI_TIMEOUT = 2500,           // AXI timeout in clock cycles (20μs @ 125MHz)
    parameter int UART_OVERSAMPLE = 16,         // UART oversampling factor
    parameter int RX_FIFO_DEPTH = 64,           // RX FIFO depth
    parameter int TX_FIFO_DEPTH = 128,          // TX FIFO depth (64→128 for 64-byte READ responses)
    parameter int MAX_LEN = 16,                 // Maximum LEN field value
    parameter int PARSER_TIMEOUT_BYTE_TIMES = 10, // Parser byte-time timeout window
    parameter bit ENABLE_PARSER_TIMEOUT = 1'b1   // Enable parser timeout based recovery
)(
    // Clock and reset
    input  logic        clk,
    input  logic        rst,
    
    // UART interface
    input  logic        uart_rx,
    output logic        uart_tx,
    input  logic        uart_cts_n,            // Clear to Send (active low)
    output logic        rx_fifo_full_out,      // RX FIFO full status
    output logic        rx_fifo_high_out,      // RX FIFO high threshold status
    output logic        tx_ready_out,          // TX ready status
    
    // AXI4-Lite master interface
    axi4_lite_if.master axi,
    
    // Status monitoring outputs
    output logic        bridge_busy,            // Bridge is actively processing
    output logic [7:0]  bridge_error_code,     // Current error code
    output logic [15:0] tx_transaction_count,  // TX transaction counter
    output logic [15:0] rx_transaction_count,  // RX transaction counter
    output logic [7:0]  fifo_status_flags,     // FIFO status flags
    output logic        soft_reset_request,    // RESET command detected (pulse)
    // Debug signals for HW debug
    output logic [7:0] debug_parser_cmd,
    output logic [7:0] debug_builder_cmd_echo,
    output logic [7:0] debug_builder_cmd_out,
    output logic [7:0] debug_parser_status,
    output logic [7:0] debug_builder_status,
    output logic [3:0] debug_parser_state,
    output logic [3:0] debug_builder_state,

    // Additional instrumentation outputs (control-flow visibility)
    output logic [2:0] debug_main_state,              // Main bridge state
    output logic       debug_builder_build_response,  // Builder trigger request
    output logic       debug_builder_start_issued,    // Builder start issued flag
    output logic       debug_axi_start_issued,        // AXI start issued flag
    output logic       debug_axi_transaction_done,    // AXI transaction done
    output logic       debug_parser_frame_valid,      // Parser frame valid
    output logic       debug_parser_frame_error,      // Parser frame error
    output logic [7:0] debug_captured_cmd_out,        // Captured CMD for bridge
    output logic [7:0] debug_axi_status_out,          // AXI status visibility

    // Runtime configuration inputs
    input  logic [15:0] baud_divisor_cfg,      // Configured baud divisor (cycles per bit)
    
    // Statistics reset input
    input  logic        reset_statistics       // Pulse to reset counters
);

    // FIFO width calculation (7 bits for 64-deep FIFO)
    localparam int RX_FIFO_WIDTH = $clog2(RX_FIFO_DEPTH) + 1;
    localparam int TX_FIFO_WIDTH = $clog2(TX_FIFO_DEPTH) + 1;
    
    localparam int DEFAULT_DIV_CALC = (BAUD_RATE > 0)
        ? ((CLK_FREQ_HZ + BAUD_RATE - 1) / BAUD_RATE)
        : 1;
    localparam int DEFAULT_DIV_CLAMP = (DEFAULT_DIV_CALC < 1)
        ? 1
        : ((DEFAULT_DIV_CALC > 16'hFFFF) ? 16'hFFFF : DEFAULT_DIV_CALC);
    localparam logic [15:0] DEFAULT_BAUD_DIVISOR = 16'(DEFAULT_DIV_CLAMP);
    localparam int MAX_BAUD_DIVISOR = 16'hFFFF;

    // Debug signals for FPGA debugging - Phase 3 & 4 (ref: fpga_debug_work_plan.md)
    logic [7:0] debug_uart_tx_data;      // UART TX data cross-check
    logic       debug_uart_tx_valid;     // UART TX byte start marker
    // Builder debug pulses
    logic       debug_builder_start;
    logic       debug_builder_done;
    // TX FIFO/Start debug
    logic       debug_tx_fifo_wr;
    logic [7:0] debug_tx_fifo_data;
    logic [7:0] debug_uart_rx_data;      // UART RX data validation
    logic       debug_uart_rx_valid;     // UART RX parser timing
    logic [31:0] debug_axi_awaddr;       // AXI write address tracking
    logic [31:0] debug_axi_wdata;        // AXI write data ordering
    logic [1:0]  debug_axi_bresp;        // AXI write response mapping
    logic [31:0] debug_axi_araddr;       // AXI read address tracking
    logic [1:0]  debug_axi_rresp;        // AXI read response validation
    logic [3:0]  debug_axi_state;        // AXI transaction FSM state
    logic [7:0]  debug_parser_cmd_out;   // CMD from Parser to Bridge
    logic [7:0]  debug_bridge_status;    // STATUS from Bridge to Builder
    logic [3:0]  debug_bridge_state;     // Bridge main FSM state
    logic [15:0] config_baud_divisor;
    logic [15:0] runtime_baud_divisor;

    always_comb begin
        int unsigned candidate;

        candidate = (baud_divisor_cfg != 16'd0) ? baud_divisor_cfg : DEFAULT_BAUD_DIVISOR;
        if (candidate < 1) begin
            candidate = 1;
        end else if (candidate > MAX_BAUD_DIVISOR) begin
            candidate = MAX_BAUD_DIVISOR;
        end

    config_baud_divisor = 16'(candidate);
        runtime_baud_divisor = config_baud_divisor;
    end
    
    // UART RX signals
    logic [7:0] rx_data;
    logic rx_valid;
    logic rx_error;
    logic rx_busy;
    
    // UART TX signals
    logic [7:0] tx_data;
    logic tx_start;
    logic tx_busy;
    logic tx_done;
    
    // RX FIFO signals
    logic [7:0] rx_fifo_data;
    logic rx_fifo_wr_en;
    logic rx_fifo_full;
    logic rx_fifo_empty;
    logic rx_fifo_rd_en;
    logic [7:0] rx_fifo_rd_data;
    logic [RX_FIFO_WIDTH-1:0] rx_fifo_count;
    
    // TX FIFO signals
    logic [7:0] tx_fifo_data;
    logic tx_fifo_wr_en;
    logic tx_fifo_full;
    logic tx_fifo_empty;
    logic tx_fifo_rd_en;
    logic [7:0] tx_fifo_rd_data;
    logic [TX_FIFO_WIDTH-1:0] tx_fifo_count;
    
    // Frame parser signals
    logic [7:0] parser_cmd;
    logic [31:0] parser_addr;
    logic [7:0] parser_data_out [0:63];
    logic [6:0] parser_data_count;
    logic parser_frame_valid;
    logic [7:0] parser_error_status;
    logic parser_frame_error;
    logic parser_frame_consumed;
    logic parser_busy;
    logic parser_soft_reset;  // RESET command detected signal
    
    // Soft reset output connection
    assign soft_reset_request = parser_soft_reset;
    
    // AXI master signals
    logic [7:0] axi_write_data [0:63];
    logic axi_start_transaction;
    logic axi_transaction_done;
    logic [7:0] axi_status;
    logic [7:0] axi_read_data [0:63];
    logic [6:0] axi_read_data_count;
    
    // Frame builder signals
    logic [7:0] builder_status_code;
    logic [7:0] builder_cmd_echo;
    logic [31:0] builder_addr_echo;
    logic [7:0] builder_response_data [0:63];
    logic [6:0] builder_response_data_count;
    logic builder_build_response;
    logic builder_is_read_response;
    logic builder_busy;
    logic builder_response_complete;
    
    // Main control state machine
    typedef enum logic [2:0] {
        MAIN_IDLE,
        MAIN_AXI_TRANSACTION,        MAIN_BUILD_RESPONSE,
        MAIN_WAIT_RESPONSE,
        MAIN_DISABLED_RESPONSE
    } main_state_t;
    
    main_state_t main_state, main_state_next;

    function automatic string main_state_to_string(main_state_t state);
        case (state)
            MAIN_IDLE:             return "MAIN_IDLE";
            MAIN_AXI_TRANSACTION:  return "MAIN_AXI_TRANSACTION";
            MAIN_BUILD_RESPONSE:   return "MAIN_BUILD_RESPONSE";
            MAIN_WAIT_RESPONSE:    return "MAIN_WAIT_RESPONSE";
            MAIN_DISABLED_RESPONSE:return "MAIN_DISABLED_RESPONSE";
            default:               return "UNKNOWN";
        endcase
    endfunction

    // CMD保持用レジスタ - Frame_Parserの出力が消える前にキャプチャ
    logic [7:0] captured_cmd;
    logic [31:0] captured_addr;
    logic [6:0] captured_read_data_count;
    logic axi_transaction_done_prev;
    
    // Transaction control flags - CRITICAL FIX for AXI transactions
    logic axi_start_issued;
    logic builder_start_issued;
    
    localparam logic [31:0] CONTROL_ADDR = 32'h0000_1000;
    localparam logic [7:0] STATUS_BUSY_CODE = 8'h06;
    localparam logic [7:0] STATUS_TIMEOUT_CODE = 8'h04;
    
    // UART RX instance
    Uart_Rx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE),
        .OVERSAMPLE(UART_OVERSAMPLE)
    ) uart_rx_inst (
        .clk(clk),
        .rst(rst),
        .soft_reset_request(parser_soft_reset),  // RESET command propagation
        .uart_rx(uart_rx),
        .baud_divisor(runtime_baud_divisor),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_error(rx_error),
        .rx_busy(rx_busy)
    );
    
    // UART TX instance
    Uart_Tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE),
        .OVERSAMPLE(UART_OVERSAMPLE)
    ) uart_tx_inst (
        .clk(clk),
        .rst(rst),
        .soft_reset_request(parser_soft_reset),  // RESET command propagation
        .tx_data(tx_data),
        .tx_start(tx_start),
        .uart_cts_n(uart_cts_n),        // Clear to Send input
        .baud_divisor(runtime_baud_divisor),
        .uart_tx(uart_tx),
        .tx_busy(tx_busy),
        .tx_done(tx_done)
    );
    
    // RX FIFO instance
    fifo_sync #(
        .DATA_WIDTH(8),
        .FIFO_DEPTH(RX_FIFO_DEPTH)
    ) rx_fifo (
        .clk(clk),
        .rst(rst),
        .wr_en(rx_fifo_wr_en),
        .wr_data(rx_data),
        .full(rx_fifo_full),
        .almost_full(),
        .rd_en(rx_fifo_rd_en),
        .rd_data(rx_fifo_rd_data),
        .empty(rx_fifo_empty),
        .almost_empty(),
        .count(rx_fifo_count)
    );
    
    // TX FIFO instance
    fifo_sync #(
        .DATA_WIDTH(8),
        .FIFO_DEPTH(TX_FIFO_DEPTH)
    ) tx_fifo (
        .clk(clk),
        .rst(rst),
        .wr_en(tx_fifo_wr_en),
        .wr_data(tx_fifo_data),
        .full(tx_fifo_full),
        .almost_full(),
        .rd_en(tx_fifo_rd_en),
        .rd_data(tx_fifo_rd_data),
        .empty(tx_fifo_empty),
        .almost_empty(),
        .count(tx_fifo_count)
    );
    
    // Frame parser instance
    Frame_Parser #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE),
        .TIMEOUT_BYTE_TIMES(PARSER_TIMEOUT_BYTE_TIMES),
        .ENABLE_TIMEOUT(ENABLE_PARSER_TIMEOUT)
    ) frame_parser (
        .clk(clk),
        .rst(rst),
        .rx_fifo_data(rx_fifo_rd_data),
        .rx_fifo_empty(rx_fifo_empty),
        .rx_fifo_rd_en(rx_fifo_rd_en),
        .baud_divisor(runtime_baud_divisor),
        .cmd(parser_cmd),
        .addr(parser_addr),
        .data_out(parser_data_out),
        .data_count(parser_data_count),
        .frame_valid(parser_frame_valid),
        .error_status(parser_error_status),
        .frame_error(parser_frame_error),
        .frame_consumed(parser_frame_consumed),
        .parser_busy(parser_busy),
        .soft_reset_request(parser_soft_reset),  // RESET command output
        .debug_cmd_in(debug_parser_cmd),
        .debug_cmd_decoded(),
        .debug_status_out(debug_parser_status),
        .debug_crc_in(),
        .debug_crc_calc(),
        .debug_crc_error(),
        .debug_state(debug_parser_state),
        .debug_error_cause()
    );
    
    // AXI4-Lite master instance
    Axi4_Lite_Master #(
        .AXI_TIMEOUT(AXI_TIMEOUT),
        .EARLY_BUSY_THRESHOLD(100)
    ) axi_master (
        .clk(clk),
        .rst(rst),
        .cmd(captured_cmd),      // 修正: parser_cmd → captured_cmd
        .addr(captured_addr),    // 修正: parser_addr → captured_addr
        .write_data(axi_write_data),
        .start_transaction(axi_start_transaction),
        .transaction_done(axi_transaction_done),
        .axi_status(axi_status),
        .read_data(axi_read_data),
        .read_data_count(axi_read_data_count),
        .axi(axi)
    );
    
    // Frame builder instance
    Frame_Builder frame_builder (
        .clk(clk),
        .rst(rst),
        .soft_reset_request(parser_soft_reset),  // RESET command propagation
        .status_code(builder_status_code),
        .cmd_echo(builder_cmd_echo),
        .addr_echo(builder_addr_echo),
        .response_data(builder_response_data),
        .response_data_count(builder_response_data_count),
        .build_response(builder_build_response),
        .is_read_response(builder_is_read_response),
        .tx_fifo_data(tx_fifo_data),
        .tx_fifo_wr_en(tx_fifo_wr_en),
        .tx_fifo_full(tx_fifo_full),
        .tx_fifo_count(tx_fifo_count),
        .builder_busy(builder_busy),
        .response_complete(builder_response_complete),
        .debug_cmd_echo(debug_builder_cmd_echo),
        .debug_cmd_out(debug_builder_cmd_out),
        .debug_state(debug_builder_state),
        .builder_start_pulse(debug_builder_start),
        .builder_response_done_pulse(debug_builder_done)
    );
    
    // RX FIFO write control with overflow error handling
    assign rx_fifo_wr_en = rx_valid && !rx_error && !rx_fifo_full;
    
    // RX FIFO overflow error detection and logging
    always_ff @(posedge clk) begin
        if (rst) begin
            // Reset - no overflow error
        end else begin
            if (rx_valid && !rx_error && rx_fifo_full) begin
                $error("[%0t][UART_BRIDGE_RX_OVERFLOW] RX FIFO full, dropping byte 0x%02h (fifo_count=%0d)",
                       $time, rx_data, rx_fifo_count);
                // Data loss - critical error condition
            end
        end
    end

    // Comprehensive UART RX debug output with data path analysis
    always @(posedge clk) begin
        if (rst) begin
            // Bridge reset - UART RX interface initialized
        end else begin
            // Monitor UART RX activity with enhanced detail - ALWAYS active
            if (rx_valid) begin
                // RX valid detected
                if (rx_data == 8'hA5) begin
                    // SOF DETECTED: SOF byte (0xA5) received and being written to RX FIFO
                end
            end
            
            // Monitor RX FIFO write operations
            if (rx_fifo_wr_en) begin
                // RX FIFO WRITE: Writing data to FIFO
            end
            
            // Monitor RX FIFO read operations
            if (rx_fifo_rd_en) begin
                // RX FIFO READ: Parser reading data from FIFO
            end
            
            // Monitor when frame parsing starts
            if (parser_frame_valid) begin
                // FRAME PARSER: Frame valid asserted - parsed successfully
            end
            
            // Monitor SOF detection in FIFO
            if (!rx_fifo_empty && rx_fifo_rd_data == 8'hA5) begin
                // SOF IN FIFO: SOF byte (0xA5) available in RX FIFO for parser
            end
        end
    end
    
    // TX FIFO read control and UART TX feeding
    logic tx_start_req, tx_start_reg;
    logic tx_byte_done_delayed;  // Delay tx_done to release tx_start cleanly
    
    assign tx_start_req = !tx_fifo_empty && !tx_busy && !tx_start_reg;
    assign tx_fifo_rd_en = tx_start_req;
    assign tx_data = tx_fifo_rd_data;  // Combinational read from synchronous FIFO
    assign tx_start = tx_start_req;  // Single-cycle pulse for UART TX
    
    `ifdef ENABLE_DEBUG
        always_ff @(posedge clk) begin
            if (tx_start_req) begin
            end
        end
    `endif
    
    // Delay tx_done by one cycle to hold tx_start_reg until UART finishes
    always_ff @(posedge clk) begin
        if (rst) begin
            tx_byte_done_delayed <= 1'b0;
        end else begin
            tx_byte_done_delayed <= tx_done;
        end
    end

    // Generate single-cycle pulse for tx_start
    always_ff @(posedge clk) begin
        if (rst) begin
            tx_start_reg <= 1'b0;
        end else if (tx_byte_done_delayed) begin
            tx_start_reg <= 1'b0;
        end else if (tx_start_req) begin
            tx_start_reg <= 1'b1;
        end
    end
    
    // Copy parser data to AXI write data
    always_comb begin
        for (int i = 0; i < 64; i++) begin
            axi_write_data[i] = parser_data_out[i];
        end
    end
    
    // Main control state machine (sequential part)
    always_ff @(posedge clk) begin
        if (rst) begin
            main_state <= MAIN_IDLE;
            captured_cmd <= 8'h00;
            captured_addr <= 32'h00000000;
            captured_read_data_count <= 7'd0;
            axi_transaction_done_prev <= 1'b0;
            // Bridge reset - state=IDLE
        end else if (parser_soft_reset) begin
            // Soft reset: preserve CONFIG, reset operational state
            // Note: FIFOs are self-draining, state machines reset to IDLE
            main_state <= MAIN_IDLE;
            captured_cmd <= 8'hFF;  // Mark as RESET command for Frame_Builder
            captured_addr <= 32'h00000000;
            captured_read_data_count <= 7'd0;
            axi_transaction_done_prev <= 1'b0;
            // CONFIG registers (baud_divisor) are NOT reset here
            // They are preserved in Register_Block and Uart_Tx/Rx modules
        end else begin
            // Always show state transitions
            if (main_state != main_state_next) begin
                // Bridge state transition
            end
            main_state <= main_state_next;
            
            // Frame_Parserの出力が有効な時にキャプチャ (修正: 条件を緩和)
            // 問題修正: parser_frame_validが真の時は常にキャプチャ
            if (parser_frame_valid) begin
                captured_cmd <= parser_cmd;
                captured_addr <= parser_addr;
                captured_read_data_count <= 7'd0;
                // Bridge captured CMD and ADDR
            end
            
            // Frame_Parserからエラーが通知された場合は即座にキャプチャ
            if (parser_frame_error && !parser_frame_valid) begin
                captured_cmd <= parser_cmd;  // エラー時でもCMDをキャプチャ
                captured_addr <= parser_addr;
                captured_read_data_count <= 7'd0;
                // Bridge captured ERROR CMD and ADDR
            end

            if (axi_transaction_done && !axi_transaction_done_prev) begin
                if (captured_cmd[7] && (axi_status == 8'h00)) begin
                    captured_read_data_count <= axi_read_data_count;
                end else begin
                    captured_read_data_count <= 7'd0;
                end
            end

            axi_transaction_done_prev <= axi_transaction_done;
        end
    end
    
    // Registers to generate single-cycle pulses
    always_ff @(posedge clk) begin
        if (rst) begin
            axi_start_issued <= 1'b0;
            builder_start_issued <= 1'b0;
        end else begin
            // Reset flags when leaving respective states
            if (main_state != MAIN_AXI_TRANSACTION) begin
                axi_start_issued <= 1'b0;
            end
            if ((main_state != MAIN_BUILD_RESPONSE) && (main_state != MAIN_DISABLED_RESPONSE)) begin
                builder_start_issued <= 1'b0;
            end
            
            // Set flags when issuing commands
            if (main_state == MAIN_AXI_TRANSACTION && !axi_start_issued) begin
                axi_start_issued <= 1'b1;
            end
            if (((main_state == MAIN_BUILD_RESPONSE) || (main_state == MAIN_DISABLED_RESPONSE)) && !builder_start_issued) begin
                builder_start_issued <= 1'b1;
            end
        end
    end

    // Main control state machine (combinational part)
    logic control_write_cmd;

    // CRITICAL DEBUG: Always monitor key signals + frame_valid transition detection
    // Frame valid detection - use simple level detection in state machine
    // Removed redundant edge detection logic that caused timing conflicts

    always_comb begin
        main_state_next = main_state;
        axi_start_transaction = 1'b0;
        parser_frame_consumed = 1'b0;
        builder_build_response = 1'b0;
        builder_is_read_response = 1'b0;
        builder_status_code = 8'h00;
        builder_cmd_echo = 8'h00;
        builder_addr_echo = 32'h00000000;
    builder_response_data_count = 7'd0;

        control_write_cmd = (!parser_cmd[7]) && (parser_addr == CONTROL_ADDR);
        
        // Copy AXI read data to builder response data
        for (int i = 0; i < 64; i++) begin
            builder_response_data[i] = axi_read_data[i];
        end
        
        case (main_state)
            MAIN_IDLE: begin
                if (parser_frame_valid) begin
                    main_state_next = MAIN_AXI_TRANSACTION;
                end else if (parser_frame_error) begin
                    main_state_next = MAIN_BUILD_RESPONSE;
                end

                if (parser_frame_valid && main_state_next == MAIN_IDLE) begin
                end
            end
            
            MAIN_AXI_TRANSACTION: begin
                // Issue AXI transaction only once per frame
                axi_start_transaction = !axi_start_issued;
                
                // Add debug output for AXI transaction start
                if (!axi_start_issued) begin
                    // AXI transaction START
                end
                
                if (axi_transaction_done) begin
                    // AXI transaction DONE
                    main_state_next = MAIN_BUILD_RESPONSE;
                end
            end
            
            MAIN_BUILD_RESPONSE: begin
                // Wait for builder to be ready before issuing response
                // CRITICAL FIX: Frame_Builder only captures inputs when state==IDLE
                if (!builder_busy) begin
                    // Issue build response only once per frame
                    builder_build_response = !builder_start_issued;
                    builder_cmd_echo = captured_cmd;  // 修正: parser_cmd → captured_cmd
                    builder_addr_echo = captured_addr; // 修正: parser_addr → captured_addr
                    
                    if (parser_frame_error) begin
                        // Error response
                        builder_status_code = parser_error_status;
                        builder_is_read_response = 1'b0;
                        builder_response_data_count = 7'd0;
                    end else begin
                        // Normal response
                        builder_status_code = axi_status;
                        builder_is_read_response = captured_cmd[7];  // 修正: parser_cmd[7] → captured_cmd[7]
                        
                        if (captured_cmd[7]) begin  // 修正: parser_cmd[7] → captured_cmd[7]
                            if (axi_status == 8'h00) begin  // Success
                                builder_response_data_count = captured_read_data_count;
                            end else begin  // Error
                                builder_response_data_count = 7'd0;
                            end
                        end else begin  // Write response
                            builder_response_data_count = 7'd0;
                        end
                    end
                    
                    // Only advance to MAIN_WAIT_RESPONSE after issuing build command
                    main_state_next = MAIN_WAIT_RESPONSE;
                    
                    `ifdef ENABLE_DEBUG
                        if (!builder_start_issued) begin
                            // Bridge starting response
                        end
                    `endif
                end else begin
                    // Builder busy - stay in this state
                    main_state_next = MAIN_BUILD_RESPONSE;
                end
            end
            
            MAIN_WAIT_RESPONSE: begin
                if (builder_response_complete) begin
                    parser_frame_consumed = 1'b1;
                    main_state_next = MAIN_IDLE;
                    `ifdef ENABLE_DEBUG
                        // Bridge MAIN_WAIT_RESPONSE->MAIN_IDLE, frame_consumed=1
                    `endif
                end else begin
                    `ifdef ENABLE_DEBUG
                        // Bridge MAIN_WAIT_RESPONSE waiting for response_complete
                    `endif
                end
            end

            MAIN_DISABLED_RESPONSE: begin
                // Wait for builder to be ready before issuing response
                if (!builder_busy) begin
                    builder_build_response = !builder_start_issued;
                    builder_cmd_echo = captured_cmd;  // 修正: parser_cmd → captured_cmd
                    builder_addr_echo = captured_addr; // 修正: parser_addr → captured_addr
                    builder_status_code = STATUS_BUSY_CODE;
                    builder_is_read_response = captured_cmd[7]; // 修正: parser_cmd[7] → captured_cmd[7]
                    builder_response_data_count = 7'd0;
                    
                    // Advance to wait state
                    main_state_next = MAIN_WAIT_RESPONSE;
                end else begin
                    // Builder busy - stay in this state
                    main_state_next = MAIN_DISABLED_RESPONSE;
                end
            end
        endcase
    end

    // Assertions for verification
    `ifdef ENABLE_BRIDGE_ASSERTIONS
        // UART RX data should not be lost due to FIFO overflow
        assert_no_rx_data_loss: assert property (
            @(posedge clk) disable iff (rst)
            rx_valid && !rx_error |-> !rx_fifo_full
        ) else $warning("UART_Bridge: RX data lost due to FIFO overflow");

    localparam int MAX_BIT_TIME_CYCLES = (MAX_BAUD_DIVISOR < 1) ? 1 : MAX_BAUD_DIVISOR;
    localparam int PARSER_STALL_LIMIT = MAX_BIT_TIME_CYCLES * (PARSER_TIMEOUT_BYTE_TIMES + 2) * 12;

        // Frame parser should eventually become non-busy
        generate
            if (ENABLE_PARSER_TIMEOUT) begin : gen_parser_timeout_assert
                assert_parser_eventually_idle: assert property (
                    @(posedge clk) disable iff (rst)
                        parser_busy |-> ##[1:PARSER_STALL_LIMIT] !parser_busy
                ) else $error("UART_Bridge: Parser stuck in busy state");
            end
        endgenerate

        // AXI transaction should eventually complete
        assert_axi_eventually_done: assert property (
            @(posedge clk) disable iff (rst)
            axi_start_transaction |-> ##[1:5000] axi_transaction_done
        ) else $error("UART_Bridge: AXI transaction never completes");

        // If parser reports a valid frame while bridge is in MAIN_IDLE, ensure
        // the combinational next state leaves IDLE on the very next cycle.
        property p_parser_frame_advances;
            @(posedge clk) disable iff (rst)
                (main_state == MAIN_IDLE && parser_frame_valid) |=> (main_state_next != MAIN_IDLE);
        endproperty

        assert_parser_frame_advances: assert property (p_parser_frame_advances)
            else $error("UART_Bridge: parser_frame_valid observed in MAIN_IDLE but next state remains IDLE");
    `endif

    // Statistics counters
    logic [15:0] tx_count_reg;
    logic [15:0] rx_count_reg;
    
    // Transaction completion detection
    logic tx_transaction_complete;
    logic rx_transaction_complete;
    
    assign tx_transaction_complete = builder_response_complete && !captured_cmd[7]; // Write transaction (修正)
    assign rx_transaction_complete = builder_response_complete && captured_cmd[7];  // Read transaction (修正)
    
    // Statistics counter logic
    always_ff @(posedge clk) begin
        if (rst || reset_statistics) begin
            tx_count_reg <= 16'h0000;
            rx_count_reg <= 16'h0000;
        end else begin
            if (tx_transaction_complete) begin
                tx_count_reg <= tx_count_reg + 1'b1;
            end
            if (rx_transaction_complete) begin
                rx_count_reg <= rx_count_reg + 1'b1;
            end
        end
    end
    
    // Status monitoring logic
    always_comb begin
        // Bridge busy status - active when processing any transaction
        bridge_busy = parser_busy || (main_state != MAIN_IDLE) || tx_busy || rx_busy;
        
        // Error code reporting - prioritized error status
        if (parser_frame_error) begin
            bridge_error_code = parser_error_status;
        end else if (axi_status != 8'h00) begin
            bridge_error_code = axi_status;
        end else if (rx_error) begin
            bridge_error_code = 8'h01; // UART RX error
        end else begin
            bridge_error_code = 8'h00; // No error
        end
        
        // FIFO status flags - Enhanced for flow control
        fifo_status_flags[0] = rx_fifo_full;
        fifo_status_flags[1] = rx_fifo_empty;
        fifo_status_flags[2] = tx_fifo_full;
        fifo_status_flags[3] = tx_fifo_empty;
        fifo_status_flags[4] = (rx_fifo_count > (RX_FIFO_DEPTH * 3/4)); // High threshold
        fifo_status_flags[5] = (tx_fifo_count < (TX_FIFO_DEPTH / 4));   // TX low threshold
        fifo_status_flags[6] = (rx_fifo_count > (RX_FIFO_DEPTH / 2));   // RX half full
        fifo_status_flags[7] = rx_fifo_full;   // Duplicate for easy access
    end
    
    // Flow control output assignments (internal signals)
    // rx_fifo_full comes directly from FIFO .full port
    assign rx_fifo_high = fifo_status_flags[4];  // High threshold (75% full)
    assign tx_ready = !tx_busy && !tx_fifo_empty;  // Bridge always enabled
    
    // Flow control port output assignments
    assign rx_fifo_full_out = rx_fifo_full;
    assign rx_fifo_high_out = rx_fifo_high;
    assign tx_ready_out = tx_ready;
    
    // Output assignments
    assign tx_transaction_count = tx_count_reg;
    assign rx_transaction_count = rx_count_reg;
    
    // Debug signal assignments - Phase 3 & 4 (UART and AXI visibility)
    assign debug_uart_tx_data = tx_data;           // TX data from FIFO to UART
    assign debug_uart_tx_valid = tx_start;         // TX byte start marker
    assign debug_tx_fifo_wr = tx_fifo_wr_en;
    assign debug_tx_fifo_data = tx_fifo_data;
    assign debug_uart_rx_data = rx_data;           // RX data from UART
    assign debug_uart_rx_valid = rx_valid;         // RX data valid timing
    assign debug_axi_awaddr = axi.awaddr;          // AXI write address
    assign debug_axi_wdata = axi.wdata;            // AXI write data
    assign debug_axi_bresp = axi.bresp;            // AXI write response
    assign debug_axi_araddr = axi.araddr;          // AXI read address  
    assign debug_axi_rresp = axi.rresp;            // AXI read response
    assign debug_axi_state = {1'b0, main_state};   // AXI transaction FSM state (padded to 4 bits)
    
    // Debug signal assignments for newly added HW debug signals
    assign debug_builder_status = builder_status_code;
    
    // 新しいデバッグ信号: CMD キャプチャ状況
    logic [7:0] debug_captured_cmd;
    logic [31:0] debug_captured_addr;
    
    assign debug_captured_cmd = captured_cmd;
    assign debug_captured_addr = captured_addr;

    // -------------------------------------------------------------------------
    // Map internal control signals to top-level debug outputs
    // These provide visibility into the bridge FSM and gating conditions
    // and are intended for simulation-only instrumentation.
    // -------------------------------------------------------------------------
    assign debug_main_state                = main_state;               // 3-bit enum -> 3-bit output
    assign debug_builder_build_response    = builder_build_response;   // Builder request signal
    assign debug_builder_start_issued      = builder_start_issued;     // Builder start issued flag
    assign debug_axi_start_issued          = axi_start_issued;         // AXI start issued flag
    assign debug_axi_transaction_done      = axi_transaction_done;     // AXI transaction complete
    assign debug_parser_frame_valid        = parser_frame_valid;       // Parser indicates a valid frame
    assign debug_parser_frame_error        = parser_frame_error;       // Parser reported an error
    assign debug_captured_cmd_out          = captured_cmd;             // Captured CMD latched by bridge
    assign debug_axi_status_out            = axi_status;               // AXI transaction status

    // -----------------------------------------------------------------------------
    // Temporary handshake instrumentation for simulation debug only
    // -----------------------------------------------------------------------------
    logic parser_frame_valid_q;
    logic parser_frame_error_q;
    logic parser_busy_q;
    logic axi_start_transaction_q;
    logic axi_transaction_done_q;
    logic builder_response_complete_q;
    logic rx_valid_q;
    logic rx_fifo_wr_en_q;
    logic rx_fifo_rd_en_q;
    logic rx_error_q;
    integer parser_frame_valid_count;
    integer parser_frame_error_count;
    integer parser_busy_count;
    integer axi_start_transaction_count;
    integer axi_transaction_done_count;
    integer builder_response_complete_count;
    integer rx_valid_count;
    integer rx_fifo_write_count;
    integer rx_fifo_read_count;
    integer rx_error_count;
    integer build_state_entry_count;
    logic build_state_wait_logged;

    main_state_t main_state_q;
    logic builder_build_response_q;
    logic builder_start_issued_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            parser_frame_valid_q <= 1'b0;
            parser_frame_error_q <= 1'b0;
            parser_busy_q <= 1'b0;
            axi_start_transaction_q <= 1'b0;
            axi_transaction_done_q <= 1'b0;
            builder_response_complete_q <= 1'b0;
            rx_valid_q <= 1'b0;
            rx_fifo_wr_en_q <= 1'b0;
            rx_fifo_rd_en_q <= 1'b0;
            rx_error_q <= 1'b0;
            parser_frame_valid_count <= 0;
            parser_frame_error_count <= 0;
            parser_busy_count <= 0;
            axi_start_transaction_count <= 0;
            axi_transaction_done_count <= 0;
            builder_response_complete_count <= 0;
            rx_valid_count <= 0;
            rx_fifo_write_count <= 0;
            rx_fifo_read_count <= 0;
            rx_error_count <= 0;
            main_state_q <= MAIN_IDLE;
            builder_build_response_q <= 1'b0;
            builder_start_issued_q <= 1'b0;
        end else begin
            parser_frame_valid_q <= parser_frame_valid;
            parser_frame_error_q <= parser_frame_error;
            parser_busy_q <= parser_busy;
            axi_start_transaction_q <= axi_start_transaction;
            axi_transaction_done_q <= axi_transaction_done;
            builder_response_complete_q <= builder_response_complete;
            builder_build_response_q <= builder_build_response;
            builder_start_issued_q <= builder_start_issued;
            rx_valid_q <= rx_valid;
            rx_fifo_wr_en_q <= rx_fifo_wr_en;
            rx_fifo_rd_en_q <= rx_fifo_rd_en;
            rx_error_q <= rx_error;
            if (main_state != MAIN_BUILD_RESPONSE) begin
                build_state_wait_logged <= 1'b0;
            end

            if (main_state != main_state_q) begin
            end
            if (main_state == MAIN_BUILD_RESPONSE && main_state_q != MAIN_BUILD_RESPONSE) begin
                build_state_entry_count <= build_state_entry_count + 1;
                build_state_wait_logged <= 1'b0;
            end

            if (main_state == MAIN_BUILD_RESPONSE && builder_start_issued && !builder_build_response && !build_state_wait_logged) begin
                build_state_wait_logged <= 1'b1;
            end

            if (parser_frame_valid && !parser_frame_valid_q) begin
                parser_frame_valid_count <= parser_frame_valid_count + 1;
                if (main_state == MAIN_IDLE) begin
                end
            end

            if (parser_frame_error && !parser_frame_error_q) begin
                parser_frame_error_count <= parser_frame_error_count + 1;
                if (parser_error_status == STATUS_TIMEOUT_CODE) begin
                end
            end

            if (parser_busy && !parser_busy_q) begin
                parser_busy_count <= parser_busy_count + 1;
            end

            if (!parser_busy && parser_busy_q) begin
            end

            if (rx_valid && !rx_valid_q) begin
                rx_valid_count <= rx_valid_count + 1;
                if (rx_valid_count < 16) begin
                end else if (rx_valid_count == 16) begin
                end
            end

            if (rx_fifo_wr_en && !rx_fifo_wr_en_q) begin
                rx_fifo_write_count <= rx_fifo_write_count + 1;
                if (rx_fifo_write_count < 16) begin
                end else if (rx_fifo_write_count == 16) begin
                end
            end

            if (rx_fifo_rd_en && !rx_fifo_rd_en_q) begin
                rx_fifo_read_count <= rx_fifo_read_count + 1;
                if (rx_fifo_read_count < 16) begin
                end else if (rx_fifo_read_count == 16) begin
                end
            end

            if (rx_error && !rx_error_q) begin
                rx_error_count <= rx_error_count + 1;
                if (rx_error_count < 8) begin
                end else if (rx_error_count == 8) begin
                end
            end

            if (axi_start_transaction && !axi_start_transaction_q) begin
                axi_start_transaction_count <= axi_start_transaction_count + 1;
            end

            if (axi_transaction_done && !axi_transaction_done_q) begin
                axi_transaction_done_count <= axi_transaction_done_count + 1;
            end

            if (builder_build_response && !builder_build_response_q) begin
            end

            if (builder_start_issued && !builder_start_issued_q) begin
            end

            if (builder_response_complete && !builder_response_complete_q) begin
                builder_response_complete_count <= builder_response_complete_count + 1;
            end

            main_state_q <= main_state;
        end
    end

endmodule
