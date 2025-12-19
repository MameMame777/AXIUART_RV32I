`timescale 1ns / 1ps

// Frame Builder module for UART-AXI4 Bridge
// Constructs response frames per protocol specification
// 
// Debug instrumentation added 2025-10-05 per fpga_debug_work_plan.md
// Phase 3&4 signals: debug_sof_sent, debug_sof_valid,
//                    debug_crc_input, debug_crc_result, debug_frame_state
module Frame_Builder (
    input  logic        clk,
    input  logic        rst,
    input  logic        soft_reset_request,    // Soft reset from RESET command (pulse)
    
    // Frame construction inputs
    input  logic [7:0]  status_code,        // Response status code
    input  logic [7:0]  cmd_echo,           // Echo of original command
    input  logic [31:0] addr_echo,          // Echo of address (for read responses)
    input  logic [7:0]  response_data [0:63], // Response data (for read responses)
    input  logic [6:0]  response_data_count,   // Number of response data bytes
    input  logic        build_response,     // Start building response
    input  logic        is_read_response,   // True for read response, false for write
    
    // FIFO interface (to UART TX)
    output logic [7:0]  tx_fifo_data,
    output logic        tx_fifo_wr_en,
    input  logic        tx_fifo_full,
    input  logic [6:0]  tx_fifo_count,      // TX FIFO current occupancy
    
    // Status
    output logic        builder_busy,
    output logic        response_complete,
    // Event debug outputs (single-cycle pulses)
    output logic        builder_start_pulse,
    output logic        builder_response_done_pulse,
    // Debug signals
    output logic [7:0] debug_cmd_echo,
    output logic [7:0] debug_cmd_out,
    output logic [3:0] debug_state
);

    // Protocol constants per specification
    localparam [7:0] SOF_DEVICE_TO_HOST = 8'h5A;    // Device to Host SOF
    localparam [7:0] STATUS_OK = 8'h00;              // Success status
    localparam [7:0] CMD_RESET = 8'hFF;              // RESET command (no response)
    
    // Debug signals for FPGA debugging - Phase 1 & 2 (ref: fpga_debug_work_plan.md)
    logic [7:0] debug_sof_raw;        // SOF before correction LUT
    logic [7:0] debug_sof_sent;       // SOF after UART staging FIFO
    logic       debug_sof_valid;      // SOF timing alignment
    logic [7:0] debug_crc_input;      // CRC module input bus
    logic [7:0] debug_crc_result;     // End of CRC pipeline
    logic [3:0] debug_frame_state;    // Frame builder FSM state
    logic [7:0] debug_status_input;   // STATUS before any correction
    logic [7:0] debug_status_output;  // STATUS sent to UART
    logic [7:0] debug_cmd_echo_in;    // CMD_ECHO received from bridge
    logic [7:0] debug_cmd_echo_out;   // CMD_ECHO sent to UART
    logic       debug_response_type;  // Read/Write response type flag
    logic [6:0] debug_data_count;     // Response data count
    
    // State machine
    typedef enum logic [3:0] {
        IDLE,
        SOF,
        STATUS,
        CMD,
        ADDR_BYTE0,
        ADDR_BYTE1,
        ADDR_BYTE2,
        ADDR_BYTE3,
        DATA,
        CRC,
        DONE,
        INTER_FRAME_GAP
    } builder_state_t;
    
    builder_state_t state, state_next;
    
    // Internal registers
    logic [7:0]  status_reg;
    logic [7:0]  cmd_reg;
    logic [31:0] addr_reg;
    logic [7:0]  data_reg [0:63];
    logic [6:0]  data_count_reg;
    logic [6:0]  data_index;
    logic        is_read_reg;
    
    // Edge detection for build_response
    logic        build_response_prev;
    logic        build_response_edge;
    
    // Registered FIFO outputs to fix timing
    logic [7:0]  tx_fifo_data_next;
    logic        tx_fifo_wr_en_next;
    
    // CRC calculator instance
    logic crc_enable;
    logic crc_reset;
    logic [7:0] crc_data_in;
    logic [7:0] crc_out;
    
    Crc8_Calculator crc_calc (
        .clk(clk),
        .rst(rst),
        .crc_enable(crc_enable),
        .data_in(crc_data_in),
        .crc_reset(crc_reset),
        .crc_out(crc_out),
        .crc_final()  // Not used here, use crc_out
    );
    
    // Edge detection assignment
    assign build_response_edge = build_response && !build_response_prev;
    
    // State machine (sequential part)
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            status_reg <= '0;
            cmd_reg <= '0;
            addr_reg <= '0;
            data_count_reg <= '0;
        end else if (soft_reset_request) begin
            // SOFT RESET: Clear all internal state, abort current frame
            state <= IDLE;
            status_reg <= '0;
            cmd_reg <= '0;
            addr_reg <= '0;
            data_count_reg <= '0;
            data_index <= '0;
            is_read_reg <= 1'b0;
            data_index <= '0;
            is_read_reg <= 1'b0;
            build_response_prev <= 1'b0;
            // Register FIFO outputs to fix timing issue
            tx_fifo_data <= '0;
            tx_fifo_wr_en <= 1'b0;
            // Initialize data array to prevent X-state propagation
            for (int i = 0; i < 64; i++) begin
                data_reg[i] <= '0;
            end
        end else begin
            state <= state_next;
            build_response_prev <= build_response;
            // Update registered FIFO outputs
            tx_fifo_data <= tx_fifo_data_next;
            tx_fifo_wr_en <= tx_fifo_wr_en_next;
            
            // Load inputs when build_response rising edge detected (single clock edge trigger)
            if (build_response_edge && (state == IDLE)) begin
                logic [6:0] sanitized_count;

                status_reg <= status_code;
                cmd_reg <= cmd_echo;
                addr_reg <= addr_echo;

                sanitized_count = response_data_count;
                if (response_data_count > 7'd64) begin
                    sanitized_count = 7'd64;
                    $error("[FRAME_BUILDER] response_data_count exceeds 64 bytes");
                end

                data_count_reg <= sanitized_count;
                data_index <= '0;
                is_read_reg <= is_read_response;
                
                // Copy response data
                for (int i = 0; i < 64; i++) begin
                    data_reg[i] <= response_data[i];
                end
            end
            
            // Increment data index when writing data bytes successfully
            if ((state == DATA) && tx_fifo_wr_en_next && !tx_fifo_full) begin
                if (data_index < 7'd64) begin
                    data_index <= data_index + 7'd1;
                end else begin
                    data_index <= 7'd64;
                    $error("[FRAME_BUILDER] data_index overflow detected");
                end
            end
            
            // Reset data_index when starting new frame
            if (build_response_edge) begin
                data_index <= '0;
                // pulse builder start
                builder_start_pulse <= 1'b1;
            end
            else begin
                builder_start_pulse <= 1'b0;
            end
        end
    end

    // Generate single-cycle pulse for response done when entering INTER_FRAME_GAP
    always_ff @(posedge clk) begin
        if (rst) begin
            builder_response_done_pulse <= 1'b0;
        end else begin
            if (state == DONE && state_next == INTER_FRAME_GAP) begin
                builder_response_done_pulse <= 1'b1;
            end else begin
                builder_response_done_pulse <= 1'b0;
            end
        end
    end

    // ---------------------------------------------------------------------
    // Debug tracing helpers (limited logging to avoid log flood)
    // ---------------------------------------------------------------------
    integer debug_build_count;
    integer debug_tx_write_count;
    logic response_complete_q;
    
    // FIFO space check signals (moved outside always_ff to fix synthesis issue)
    // Changed to 8-bit to properly represent TX_FIFO_DEPTH=128 (requires 8 bits)
    logic [7:0] fifo_required_space;
    logic [7:0] fifo_available_space;

    always_ff @(posedge clk) begin
        if (rst) begin
            debug_build_count <= 0;
            debug_tx_write_count <= 0;
            response_complete_q <= 1'b0;
            fifo_required_space <= '0;
            fifo_available_space <= '0;
        end else begin
            response_complete_q <= response_complete;

            if (build_response_edge && state == IDLE) begin
                // Calculate required FIFO space for response frame
                // SOF(1) + STATUS(1) + CMD(1) + ADDR(4) + DATA(response_data_count) + CRC(1)
                fifo_required_space <= 8'd8 + {1'b0, response_data_count};
                fifo_available_space <= 8'd128 - {1'b0, tx_fifo_count};  // TX_FIFO_DEPTH=128
                
                if ((8'd8 + {1'b0, response_data_count}) > (8'd128 - {1'b0, tx_fifo_count})) begin
                    $error("[%0t][FRAME_BUILDER_ERROR] Insufficient TX FIFO space: required=%0d available=%0d fifo_count=%0d",
                           $time, 8'd8 + {1'b0, response_data_count}, 8'd128 - {1'b0, tx_fifo_count}, tx_fifo_count);
                    // Note: Current design proceeds anyway; consider adding stall logic
                end
                
                // Track how many times the builder is kicked off
                debug_build_count <= debug_build_count + 1;
                // Reset byte counter for the new frame
                debug_tx_write_count <= 0;
            end

            if (tx_fifo_wr_en_next && !tx_fifo_full) begin
                debug_tx_write_count <= debug_tx_write_count + 1;
                if (debug_tx_write_count <= 16) begin
                end else if (debug_tx_write_count == 17) begin
                end
            end

            if (response_complete && !response_complete_q) begin
            end
        end
    end
    
    // State machine (combinational part)
    always_comb begin
        state_next = state;
        tx_fifo_data_next = '0;
        tx_fifo_wr_en_next = 1'b0;
        crc_enable = 1'b0;
        crc_reset = 1'b0;
        crc_data_in = '0;
        
        // Default debug signal assignments to prevent latches
        debug_sof_raw = 8'h00;
        debug_sof_sent = 8'h00;
        debug_sof_valid = 1'b0;
        debug_crc_input = 8'h00;
        debug_crc_result = crc_out;  // Always show current CRC output
        debug_cmd_echo_in = 8'h00;
        debug_status_input = 8'h00;
        debug_cmd_echo_out = 8'h00;
        debug_status_output = 8'h00;
        debug_response_type = 1'b0;
        
        crc_data_in = '0;
        
        case (state)
            IDLE: begin
                crc_reset = 1'b1;  // Reset CRC for new frame
                if (build_response_edge) begin
                    state_next = SOF;
                end
            end
            
            SOF: begin
                if (!tx_fifo_full) begin
                    // Debug signal assignments - Phase 1
                    debug_sof_raw = SOF_DEVICE_TO_HOST;                       // Protocol value 0x5A
                    debug_sof_sent = SOF_DEVICE_TO_HOST;                      // Send protocol value directly
                    debug_sof_valid = 1'b1;                                  // SOF timing marker
                    
                    // Send protocol specification value directly
                    tx_fifo_data_next = SOF_DEVICE_TO_HOST;  // Send 0x5A per protocol specification
                    tx_fifo_wr_en_next = 1'b1;
                    `ifdef ENABLE_DEBUG
                        // Frame_Builder sending SOF (protocol specification)
                    `endif
                    state_next = STATUS;
                end else begin
                    debug_sof_valid = 1'b0;  // Not sending SOF this cycle
                end
            end
            
            STATUS: begin
                if (!tx_fifo_full) begin
                    // Debug signal assignments - STATUS processing
                    debug_status_input = status_reg;                       // Original STATUS value
                    debug_status_output = status_reg;                      // Send original value directly
                    
                    // Send protocol specification value directly
                    tx_fifo_data_next = status_reg;  // Send original status value per protocol
                    tx_fifo_wr_en_next = 1'b1;
                    crc_enable = 1'b1;
                    crc_data_in = status_reg;  // CRC uses status value per protocol
                    
                    // Debug signal assignments - Phase 1
                    debug_crc_input = status_reg;
                    debug_crc_result = crc_out;
                    
                    `ifdef ENABLE_DEBUG
                        // Frame_Builder sending STATUS (protocol specification)
                    `endif
                    state_next = CMD;
                end
            end
            
            CMD: begin
                if (!tx_fifo_full) begin
                    // Send protocol specification value directly
                    tx_fifo_data_next = cmd_reg;  // Send original command echo per protocol
                    tx_fifo_wr_en_next = 1'b1;
                    crc_enable = 1'b1;
                    crc_data_in = cmd_reg;  // CRC uses original value per protocol
                    
                    // Debug signal assignments - CMD processing
                    debug_crc_input = cmd_reg;
                    debug_crc_result = crc_out;
                    debug_cmd_echo_in = cmd_echo;
                    debug_cmd_echo_out = cmd_reg;  // Send original command
                    debug_response_type = is_read_response;
                    
                    // Check for special RESET command - no response
                    if (cmd_reg == CMD_RESET) begin
                        // RESET command: No response, return to IDLE immediately
                        state_next = IDLE;
                    end else if (cmd_reg[7] == 1'b0) begin  // Write command (MSB=0)
                        // Write response: go directly to CRC after CMD
                        state_next = CRC;
                    end else if (cmd_reg[7]) begin  // Read command (MSB=1) - check success status
                        // Accept multiple success status values: 0x00 (spec), 0x40 (current), 0x80 (previous)
                        if ((status_reg == 8'h00) || (status_reg == 8'h40) || (status_reg == 8'h80)) begin
                            // Successful read response includes address and data
                            state_next = ADDR_BYTE0;
                        end else begin
                            // Error response - go directly to CRC
                            state_next = CRC;
                        end
                    end else begin
                        // Error response - go directly to CRC
                        state_next = CRC;
                    end
                end
            end
            
            ADDR_BYTE0: begin
                if (!tx_fifo_full) begin
                    tx_fifo_data_next = addr_reg[7:0];
                    tx_fifo_wr_en_next = 1'b1;
                    crc_enable = 1'b1;
                    crc_data_in = addr_reg[7:0];
                    state_next = ADDR_BYTE1;
                end
            end
            
            ADDR_BYTE1: begin
                if (!tx_fifo_full) begin
                    tx_fifo_data_next = addr_reg[15:8];
                    tx_fifo_wr_en_next = 1'b1;
                    crc_enable = 1'b1;
                    crc_data_in = addr_reg[15:8];
                    state_next = ADDR_BYTE2;
                end
            end
            
            ADDR_BYTE2: begin
                if (!tx_fifo_full) begin
                    tx_fifo_data_next = addr_reg[23:16];
                    tx_fifo_wr_en_next = 1'b1;
                    crc_enable = 1'b1;
                    crc_data_in = addr_reg[23:16];
                    state_next = ADDR_BYTE3;
                end
            end
            
            ADDR_BYTE3: begin
                if (!tx_fifo_full) begin
                    tx_fifo_data_next = addr_reg[31:24];
                    tx_fifo_wr_en_next = 1'b1;
                    crc_enable = 1'b1;
                    crc_data_in = addr_reg[31:24];
                    
                    if (data_count_reg > 0) begin
                        state_next = DATA;
                    end else begin
                        state_next = CRC;
                    end
                end
            end
            
            DATA: begin
                if (!tx_fifo_full && (data_index < data_count_reg)) begin
                    tx_fifo_data_next = data_reg[data_index];
                    tx_fifo_wr_en_next = 1'b1;
                    crc_enable = 1'b1;
                    crc_data_in = data_reg[data_index];
                    
                    // Check if this will be the last data byte after incrementing
                    if ((data_index + 7'd1) == data_count_reg) begin
                        state_next = CRC;
                    end
                    // else stay in DATA state for next byte
                end
            end
            
            CRC: begin
                if (!tx_fifo_full) begin
                    tx_fifo_data_next = crc_out;  // Normal CRC calculation
                    tx_fifo_wr_en_next = 1'b1;
                    state_next = DONE;
                end
            end
            
            DONE: begin
                 state_next = INTER_FRAME_GAP;
                 // Pulse response done next cycle
                 // builder_response_done_pulse is asserted in sequential logic
            end
            
            INTER_FRAME_GAP: begin
                // Wait one cycle for proper frame separation
                state_next = IDLE;
            end
        endcase
    end
    
    // Output assignments
    assign builder_busy = (state != IDLE);
    assign response_complete = (state == DONE) && (state_next == INTER_FRAME_GAP);
    
    // Debug signal assignments - Frame state decode
    assign debug_frame_state = state[3:0];  // FSM state for debugging
    // State encoding: 0=IDLE, 1=SOF, 2=STATUS, 3=CMD, 4=ADDR_BYTE0, 5=ADDR_BYTE1, 
    //                 6=ADDR_BYTE2, 7=ADDR_BYTE3, 8=DATA, 9=CRC, 10=DONE, 11=INTER_FRAME_GAP
    
    // New debug signal assignments for HW analysis
    assign debug_cmd_echo = cmd_reg;
    assign debug_cmd_out = cmd_reg;
    assign debug_state = state[3:0];

    // TX FIFO関連のデバッグ信号
    logic [7:0] debug_tx_fifo_data_out;
    logic debug_tx_fifo_wr_en_out;
    logic debug_cmd_state_active;
    
    assign debug_tx_fifo_data_out = tx_fifo_data;
    assign debug_tx_fifo_wr_en_out = tx_fifo_wr_en;
    assign debug_cmd_state_active = (state == CMD);

    // Assertions for verification
    `ifdef ENABLE_FRAME_BUILDER_ASSERTIONS
        // Should not start building when already busy
        assert_no_build_when_busy: assert property (
            @(posedge clk) disable iff (rst)
            builder_busy |-> !build_response
        ) else $warning("Frame_Builder: build_response asserted while busy");

        // response_complete should be a single-cycle pulse
        assert_response_complete_pulse: assert property (
            @(posedge clk) disable iff (rst)
            response_complete |=> !response_complete
        ) else $error("Frame_Builder: response_complete should be a single-cycle pulse");

        // Should not write to FIFO when full (CRITICAL SAFETY CHECK)
        assert_no_write_when_full: assert property (
            @(posedge clk) disable iff (rst)
            tx_fifo_full |-> !tx_fifo_wr_en
        ) else $error("Frame_Builder: Writing to FIFO when full");
        
        // FIFO space check at frame start (64-byte READ protection)
        assert_fifo_space_sufficient: assert property (
            @(posedge clk) disable iff (rst)
            (build_response && state == IDLE && is_read_response && response_data_count > 7'd56) |->
            (tx_fifo_count < 7'd72)  // Max frame 72 bytes, need space
        ) else $error("Frame_Builder: Insufficient FIFO space for large response");
    `endif

endmodule
