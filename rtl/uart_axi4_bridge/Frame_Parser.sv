`timescale 1ns / 1ps

// Frame Parser Module for UART-AXI4 Bridge
// Implements state machine from Section 6.6 of protocol specification
// FIXED BAUD RATE: 115200 bps
//
// Debug instrumentation added 2025-10-05 per fpga_debug_work_plan.md  
// Phase 1&2 signals: debug_rx_sof_raw, debug_rx_sof_proc, debug_crc_match,
//                    debug_status_gen, debug_error_cause
module Frame_Parser #(
    parameter int CLK_FREQ_HZ = 125_000_000,   // System clock frequency (125MHz)
    parameter int BAUD_RATE = 115200,          // UART baud rate (FIXED)
    parameter int TIMEOUT_BYTE_TIMES = 5,      // Reduced timeout: 5 byte times for faster simulation
    parameter bit ENABLE_TIMEOUT = 1'b0,       // Disable timeout for faster simulation
    parameter bit ENABLE_ASSERTIONS = 1'b1     // Enable SystemVerilog assertions for integrated debugging
)(
    input  logic        clk,
    input  logic        rst,
    
    // FIFO interface (from UART RX)
    input  logic [7:0]  rx_fifo_data,
    input  logic        rx_fifo_empty,
    output logic        rx_fifo_rd_en,
    input  logic [15:0] baud_divisor,
    
    // Parsed frame output
    output logic [7:0]  cmd,
    output logic [31:0] addr,
    output logic [7:0]  data_out [0:63],    // Max 16 x 32-bit = 64 bytes
    output logic [6:0]  data_count,         // Number of valid data bytes
    output logic        frame_valid,        // Frame is valid and ready
    output logic [7:0]  error_status,       // Error status code
    output logic        frame_error,        // Frame has error
    
    // Control
    input  logic        frame_consumed,     // Frame has been processed
    output logic        parser_busy,        // Parser is active
    output logic        soft_reset_request, // RESET command detected (pulse)
    // Debug signals for HW analysis
    output logic [7:0] debug_cmd_in,
    output logic [7:0] debug_cmd_decoded,
    output logic [7:0] debug_status_out,
    output logic [7:0] debug_crc_in,
    output logic [7:0] debug_crc_calc,
    output logic       debug_crc_error,
    output logic [3:0] debug_state,
    output logic [7:0] debug_error_cause
);

    // Protocol constants
    localparam [7:0] SOF_HOST_TO_DEVICE = 8'hA5;
    localparam [7:0] CMD_RESET = 8'hFF;  // Special RESET command
    
    // Status codes from Section 3
    localparam [7:0] STATUS_OK        = 8'h00;
    localparam [7:0] STATUS_CRC_ERR   = 8'h01;
    localparam [7:0] STATUS_CMD_INV   = 8'h02;
    localparam [7:0] STATUS_ADDR_ALIGN = 8'h03;
    localparam [7:0] STATUS_TIMEOUT   = 8'h04;
    localparam [7:0] STATUS_LEN_RANGE = 8'h07;
    
    // Debug signals for FPGA debugging - Phase 1 & 2 (ref: fpga_debug_work_plan.md)
    logic [7:0] debug_rx_sof_raw;     // Received SOF before correction
    logic [7:0] debug_rx_sof_proc;    // SOF after processing (should be 0x5A)
    logic       debug_crc_match;      // CRC validation result
    logic [7:0] debug_status_gen;     // STATUS generation trace
    logic [7:0] debug_error_cause_internal;    // Error source classification
    
    // Error cause encoding: 0x0=No error, 0x1=CRC mismatch, 0x2=AXI timeout, 0x3=Unsupported command
    
    // Timeout calculation - simplified for fixed baud rate
    // One UART byte at 115200 bps = (CLK_FREQ_HZ / BAUD_RATE) * 10 clocks
    localparam int CLOCKS_PER_BYTE = (CLK_FREQ_HZ / BAUD_RATE) * 10;
    localparam int TIMEOUT_CLOCKS = CLOCKS_PER_BYTE * TIMEOUT_BYTE_TIMES;
    localparam int TIMEOUT_WIDTH = $clog2(TIMEOUT_CLOCKS + 1);
    localparam logic [TIMEOUT_WIDTH-1:0] TIMEOUT_LIMIT = TIMEOUT_WIDTH'(TIMEOUT_CLOCKS);
    
    // State machine
    typedef enum logic [3:0] {
        IDLE,
        CMD,
        ADDR_BYTE0,
        ADDR_BYTE1,
        ADDR_BYTE2,
        ADDR_BYTE3,
        DATA_RX,
        CRC_RX,
        VALIDATE,
        POSTVTC,  // Post-validation cleanup for RESET command
        ERROR
    } parser_state_t;
    
    parser_state_t state, state_next;
    // Debug helper for readable state printouts during instrumentation runs
    function automatic string parser_state_to_string(parser_state_t st);
        case (st)
            IDLE:       return "IDLE";
            CMD:        return "CMD";
            ADDR_BYTE0: return "ADDR_BYTE0";
            ADDR_BYTE1: return "ADDR_BYTE1";
            ADDR_BYTE2: return "ADDR_BYTE2";
            ADDR_BYTE3: return "ADDR_BYTE3";
            DATA_RX:    return "DATA_RX";
            CRC_RX:     return "CRC_RX";
            VALIDATE:   return "VALIDATE";
            POSTVTC:    return "POSTVTC";
            ERROR:      return "ERROR";
            default:    return "UNKNOWN";
        endcase
    endfunction
    
    // Internal registers
    logic [7:0]  cmd_reg;
    logic [7:0]  current_cmd;     // Current command being processed
    logic [31:0] addr_reg;
    logic [7:0]  data_reg [0:63];
    logic [6:0]  data_byte_count;
    logic [7:0]  expected_crc;
    logic [7:0]  received_crc;
    logic [7:0]  error_status_reg;
    logic        is_reset_command; // Flag for RESET command (CMD=0xFF)
    
    // CRC calculation control signals - 重要な修正
    logic        crc_reset;
    logic        crc_enable;
    logic [7:0]  crc_data_in;
    
    // Timeout counter
    logic [TIMEOUT_WIDTH-1:0] timeout_counter;
    logic timeout_occurred;
    logic timeout_monitor_active;
    
    // CRC processing - simplified for direct bus logic
    // logic crc_data_read_flag;  // No longer needed - direct processing
    logic [7:0] rx_fifo_data_reg;  // Register to capture FIFO data after read
    // logic fifo_read_requested;  // No longer needed - direct processing  
    // logic fifo_data_ready;      // No longer needed - direct processing
    
    // CRC8 Calculator instantiation - Polynomial: 0x07
    Crc8_Calculator crc_calc (
        .clk(clk),
        .rst(crc_reset),
        .crc_enable(crc_enable),
        .data_in(crc_data_in),
        .crc_reset(crc_reset),
        .crc_out(expected_crc),
        .crc_final()
    );
    
    // Command field parsing
    logic rw_bit;
    logic inc_bit;
    logic [1:0] size_field;
    logic [3:0] len_field;
    logic [6:0] expected_data_bytes;  // Now a register (updated in sequential logic)
    
    // Debug signals for hardware analysis - CMD parsing
    logic [7:0] debug_rx_cmd_raw;
    logic [7:0] debug_rx_cmd_parsed;
    logic       debug_rx_rw_bit;
    logic       debug_rx_inc_bit;
    logic [1:0] debug_rx_size_field;
    logic [3:0] debug_rx_len_field;
    logic [6:0] debug_rx_expected_bytes;

    // Runtime debug trackers to understand parser progress in failing runs
    integer parser_state_transition_count;
    integer parser_byte_trace_count;
    
    always_comb begin
        rw_bit = current_cmd[7];
        inc_bit = current_cmd[6];
        size_field = current_cmd[5:4];
        len_field = current_cmd[3:0];
        
        // Debug signal assignments
        debug_rx_cmd_raw = rx_fifo_data;
        debug_rx_cmd_parsed = current_cmd;
        debug_rx_rw_bit = rw_bit;
        debug_rx_inc_bit = inc_bit;
        debug_rx_size_field = size_field;
        debug_rx_len_field = len_field;
        debug_rx_expected_bytes = expected_data_bytes;
    end
    
    // Command validation logic
    logic cmd_valid;
    always_comb begin
        cmd_valid = 1'b1;
        
        // RESET command (0xFF) is always valid - special case
        if (current_cmd == 8'hFF) begin
            cmd_valid = 1'b1;
        end
        else begin
            // Check for reserved size field  
            if (size_field == 2'b11) begin
                cmd_valid = 1'b0;
            end
            
            // Check LEN range (should be 1-16, encoded as 0-15)
            if (current_cmd[3:0] > 15) begin  // This is impossible with 4 bits, but for clarity
                cmd_valid = 1'b0;
            end
        end
    end
    
    // Timeout management
    always_comb begin
        if (ENABLE_TIMEOUT) begin
            unique case (state)
                CMD,
                ADDR_BYTE0,
                ADDR_BYTE1,
                ADDR_BYTE2,
                ADDR_BYTE3,
                DATA_RX,
                CRC_RX: timeout_monitor_active = 1'b1;
                default: timeout_monitor_active = 1'b0;
            endcase
        end else begin
            timeout_monitor_active = 1'b0;  // Disable timeout monitoring
        end
    end

    always_ff @(posedge clk) begin
        if (rst || !timeout_monitor_active) begin
            timeout_counter <= '0;
            timeout_occurred <= 1'b0;
        end else begin
            if (!rx_fifo_empty) begin
                timeout_counter <= '0;
                timeout_occurred <= 1'b0;
            end else if (timeout_counter >= TIMEOUT_LIMIT) begin
                timeout_occurred <= 1'b1;
            end else begin
                timeout_counter <= timeout_counter + 1;
            end
        end
    end
    
    // State machine (sequential part) - optimized debug output
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            cmd_reg <= '0;
            current_cmd <= '0;  // Initialize current_cmd to prevent X-state
            addr_reg <= '0;
            data_byte_count <= '0;
            received_crc <= 8'h00;  // Initialize to known value instead of X-state
            error_status_reg <= STATUS_OK;
            expected_data_bytes <= '0;  // Initialize expected_data_bytes to prevent X-state
            // Simplified - no complex CRC sync flags needed
            rx_fifo_data_reg <= 8'h00;
            // Initialize data array to prevent X-state propagation
            for (int i = 0; i < 64; i++) begin
                data_reg[i] <= '0;
            end
            parser_state_transition_count <= 0;
            parser_byte_trace_count <= 0;
        end else if (soft_reset_request) begin
            // SOFT RESET: Clear parser state but preserve configuration
            // This allows RESET command (0xFF) to clear internal state without full reset
            state <= IDLE;
            cmd_reg <= '0;
            current_cmd <= '0;
            addr_reg <= '0;
            data_byte_count <= '0;
            received_crc <= 8'h00;
            error_status_reg <= STATUS_OK;
            expected_data_bytes <= '0;
            rx_fifo_data_reg <= 8'h00;
            // Clear data array
            for (int i = 0; i < 64; i++) begin
                data_reg[i] <= '0;
            end
            // Reset trace counters
            parser_state_transition_count <= 0;
            parser_byte_trace_count <= 0;
        end else begin
            state <= state_next;
            
            // Debug only key state transitions (minimal output)
            `ifdef ENABLE_DEBUG
                // アサーション主体のデバッグに移行 - $display削除済み
            `endif

            if (state != state_next) begin
                parser_state_transition_count <= parser_state_transition_count + 1;
                if (parser_state_transition_count < 128) begin
                end
            end
            
            // FIFO read logic - simplified for direct processing
            if (rx_fifo_rd_en && !rx_fifo_empty) begin
                case (state)
                    CMD: begin
                        cmd_reg <= rx_fifo_data;
                        current_cmd <= rx_fifo_data;  // Capture immediately for later use
                        
                        // Check for special RESET command (no ADDR/DATA, jump to CRC)
                        if (rx_fifo_data == CMD_RESET) begin
                            is_reset_command <= 1'b1;
                        end else begin
                            is_reset_command <= 1'b0;
                        end
                        // expected_data_bytes calculation is handled separately above
                    end
                    ADDR_BYTE0: begin
                        addr_reg[7:0] <= rx_fifo_data;
                    end
                    ADDR_BYTE1: begin
                        addr_reg[15:8] <= rx_fifo_data;
                    end
                    ADDR_BYTE2: begin
                        addr_reg[23:16] <= rx_fifo_data;
                    end
                    ADDR_BYTE3: begin
                        addr_reg[31:24] <= rx_fifo_data;
                    end
                    DATA_RX: begin
                        if (data_byte_count < 7'd64) begin
                            data_reg[data_byte_count] <= rx_fifo_data;
                            data_byte_count <= data_byte_count + 7'd1;
                        end else begin
                            data_byte_count <= 7'd64;
                            $error("[FRAME_PARSER] data_byte_count overflow: frame longer than 64 bytes");
                        end
                    end
                    CRC_RX: begin
                        // Direct CRC processing - simple bus logic
                        received_crc <= rx_fifo_data;
                        
                        // Immediate CRC validation - no complex synchronization needed
                        if (rx_fifo_data == expected_crc) begin
                            error_status_reg <= STATUS_OK;
                        end else begin
                            error_status_reg <= STATUS_CRC_ERR;
                        end
                    end
                endcase

                if (parser_byte_trace_count < 64) begin
                    parser_byte_trace_count <= parser_byte_trace_count + 1;
                end
            end
            
            // Reset data byte count at start of new frame
            if (state == IDLE) begin
                data_byte_count <= '0;
                error_status_reg <= STATUS_OK;
                current_cmd <= '0;
                expected_data_bytes <= '0;  // Reset expected data bytes
                if (state_next == CMD) begin
                    parser_byte_trace_count <= 0;
                end
            end
            
            // Handle expected_data_bytes calculation separately to prevent X-state contamination
            if (state == CMD && rx_fifo_rd_en && !rx_fifo_empty) begin
                logic [6:0] bytes_calc;

                if (rx_fifo_data[7] == 1'b1) begin  // READ command (RW bit = 1)
                    bytes_calc = 7'd0;  // No data bytes for read commands
                end else begin  // WRITE command (RW bit = 0)
                    case (rx_fifo_data[5:4])  // SIZE field
                        2'b00: bytes_calc = (rx_fifo_data[3:0] + 7'd1);          // BYTE (8-bit)
                        2'b01: bytes_calc = (rx_fifo_data[3:0] + 7'd1) * 7'd2;   // HALF (16-bit)
                        2'b10: bytes_calc = (rx_fifo_data[3:0] + 7'd1) * 7'd4;   // WORD (32-bit)
                        default: bytes_calc = 7'd0;                              // Invalid size
                    endcase
                end

                if (bytes_calc > 7'd64) begin
                    $error("[FRAME_PARSER] expected_data_bytes=%0d exceeds 64", bytes_calc);
                end

                expected_data_bytes <= bytes_calc;
            end
            
            // Set error status in validation state
            if (state == VALIDATE) begin
                if (!cmd_valid) begin
                    error_status_reg <= (size_field == 2'b11) ? STATUS_CMD_INV : STATUS_LEN_RANGE;
                    // Debug error cause: 0x3 = Unsupported command
                    debug_error_cause_internal <= 8'h03;
                end else if (received_crc != expected_crc) begin
                    error_status_reg <= STATUS_CRC_ERR;
                    // Debug error cause: 0x1 = CRC mismatch
                    debug_error_cause_internal <= 8'h01;
                end else begin
                    error_status_reg <= STATUS_OK;
                    // Debug error cause: 0x0 = No error
                    debug_error_cause_internal <= 8'h00;
                end
            end
            
            // Handle timeout
            if (timeout_occurred && (state != IDLE) && (state != ERROR)) begin
                error_status_reg <= STATUS_TIMEOUT;
                // Debug error cause: 0x2 = AXI timeout
                debug_error_cause_internal <= 8'h02;
            end
            
            // Clear frame_consumed acknowledgment
            if (frame_consumed) begin
                // Frame has been processed, ready for next frame
            end
        end
    end
    
    // State machine (combinational part)
    always_comb begin
        state_next = state;
        rx_fifo_rd_en = 1'b0;
        crc_enable = 1'b0;
        crc_reset = 1'b0;
        crc_data_in = rx_fifo_data;
        
        // Default debug signal assignments to prevent latches
        debug_rx_sof_raw = 8'h00;
        debug_rx_sof_proc = 8'h00;
        debug_crc_match = 1'b0;
        debug_status_gen = error_status_reg;  // Always show current status
        
        case (state)
            IDLE: begin
                if (!rx_fifo_empty) begin
                    if (rx_fifo_data == SOF_HOST_TO_DEVICE) begin
                        // Debug signal assignments - Phase 2
                        debug_rx_sof_raw = rx_fifo_data;
                        debug_rx_sof_proc = SOF_HOST_TO_DEVICE;  // Expected processed value
                        
                        rx_fifo_rd_en = 1'b1;
                        crc_reset = 1'b1;  // Reset CRC when SOF is detected (fix timing)
                        state_next = CMD;
                    end else begin
                        // Debug signal assignments for invalid SOF
                        debug_rx_sof_raw = rx_fifo_data;
                        debug_rx_sof_proc = 8'h00;  // Mark as invalid
                        
                        rx_fifo_rd_en = 1'b1;  // Discard invalid SOF
                    end
                end
            end
            
            CMD: begin
                if (!rx_fifo_empty) begin
                    rx_fifo_rd_en = 1'b1;
                    crc_enable = 1'b1;
                    // RESET command (0xFF) has no ADDR/DATA, jump directly to CRC
                    if (rx_fifo_data == CMD_RESET) begin
                        state_next = CRC_RX;
                    end else begin
                        state_next = ADDR_BYTE0;
                    end
                end else if (timeout_occurred) begin
                    state_next = ERROR;
                end
            end
            
            ADDR_BYTE0: begin
                if (!rx_fifo_empty) begin
                    rx_fifo_rd_en = 1'b1;
                    crc_enable = 1'b1;
                    state_next = ADDR_BYTE1;
                end else if (timeout_occurred) begin
                    state_next = ERROR;
                end
            end
            
            ADDR_BYTE1: begin
                if (!rx_fifo_empty) begin
                    rx_fifo_rd_en = 1'b1;
                    crc_enable = 1'b1;
                    state_next = ADDR_BYTE2;
                end else if (timeout_occurred) begin
                    state_next = ERROR;
                end
            end
            
            ADDR_BYTE2: begin
                if (!rx_fifo_empty) begin
                    rx_fifo_rd_en = 1'b1;
                    crc_enable = 1'b1;
                    state_next = ADDR_BYTE3;
                end else if (timeout_occurred) begin
                    state_next = ERROR;
                end
            end
            
            ADDR_BYTE3: begin
                if (!rx_fifo_empty) begin
                    rx_fifo_rd_en = 1'b1;
                    crc_enable = 1'b1;
                    // Proper state transition based on command type and expected data bytes
                    if (expected_data_bytes == 0) begin
                        state_next = CRC_RX;  // No data bytes, go directly to CRC
                    end else begin
                        state_next = DATA_RX;  // Has data bytes, go to DATA_RX
                    end
                end else if (timeout_occurred) begin
                    state_next = ERROR;
                end
            end
            
            DATA_RX: begin
                if (!rx_fifo_empty) begin
                    rx_fifo_rd_en = 1'b1;
                    crc_enable = 1'b1;
                    // Safer comparison: check if we've received all expected data bytes
                    if ((data_byte_count + 7'd1) >= expected_data_bytes) begin
                        state_next = CRC_RX;
                    end else begin
                    end
                end else if (timeout_occurred) begin
                    state_next = ERROR;
                end
            end
            
            CRC_RX: begin
                if (!rx_fifo_empty) begin
                    // Read CRC byte from FIFO - processing happens in FIFO read logic above
                    rx_fifo_rd_en = 1'b1;
                    state_next = VALIDATE;  // Move to VALIDATE immediately after reading CRC
                end else if (timeout_occurred) begin
                    state_next = ERROR;
                end else begin
                    state_next = CRC_RX;  // Stay in CRC_RX waiting for data
                end
            end
            
            VALIDATE: begin
                // Debug signal assignments - Phase 2
                debug_crc_match = (received_crc == expected_crc);
                debug_status_gen = error_status_reg;
                
                // RESET command special handling: bypass frame_consumed wait
                if (current_cmd == 8'hFF && cmd_valid) begin
                    state_next = POSTVTC;  // Immediate transition for RESET
                end
                // Soft reset during validation: abort and return to IDLE
                else if (soft_reset_request) begin
                    state_next = IDLE;
                end
                else if (frame_consumed) begin
                    state_next = IDLE;
                end else begin
                    state_next = VALIDATE;  // Stay in VALIDATE until frame is consumed
                end
            end
            
            POSTVTC: begin
                // Post-validation cleanup - single cycle transition
                // CRITICAL: Immediately clear frame_valid_hold in combinational logic
                // (sequential clear in always_ff happens 1 cycle too late)
                // This is required because POSTVTC→IDLE transition is instant
                
                // Also handle soft_reset during this transient state
                if (soft_reset_request) begin
                    state_next = IDLE;
                end else begin
                    state_next = IDLE;
                end
            end
            
            ERROR: begin
                if (frame_consumed) begin
                    state_next = IDLE;
                end else begin
                    state_next = ERROR;  // Stay in ERROR until frame is consumed
                end
            end
        endcase
    end
    
    // Frame valid持続制御のための追加ロジック
    logic frame_valid_hold;
    logic frame_consumed_reg;  // frame_consumedパルスをラッチ
    
    // frame_consumed パルス検出とラッチ
    always_ff @(posedge clk) begin
        if (rst) begin
            frame_consumed_reg <= 1'b0;
        end else begin
            if (frame_consumed) begin
                frame_consumed_reg <= 1'b1;  // frame_consumedパルスをラッチ
            end else if (state == IDLE) begin
                frame_consumed_reg <= 1'b0;  // 次のフレーム開始時にクリア
            end
        end
    end
    
    // frame_valid信号の正確な制御 - CRITICAL FIX
    // CRITICAL: POSTVTC state requires immediate clearing (not 1 cycle later)
    logic postvtc_clear;
    assign postvtc_clear = (state == POSTVTC);  // Combinational clear signal
    
    always_ff @(posedge clk) begin
        if (rst) begin
            frame_valid_hold <= 1'b0;
        end else if (soft_reset_request || postvtc_clear) begin
            // SOFT RESET or POSTVTC state: clear frame_valid_hold immediately
            frame_valid_hold <= 1'b0;
        end else begin
            // CRITICAL: frame_consumed検出時は即座にクリア（最優先）
            if (frame_consumed || frame_consumed_reg) begin
                frame_valid_hold <= 1'b0;  // frame_consumedパルスまたはラッチで即座にクリア
            end else begin
                // CRITICAL FIX: frame_valid_holdはVALIDATE状態でのみ1に設定
                case (state)
                    VALIDATE: begin
                        // VALIDATE状態でのframe_valid評価
                        // CRITICAL: RESET command (0xFF) should NOT set frame_valid_hold
                        if (soft_reset_request) begin
                            frame_valid_hold <= 1'b0;  // Soft reset always clears
                        end else if (current_cmd == 8'hFF) begin
                            // RESET command (0xFF) is a control command, not a data frame
                            // It should NOT generate frame_valid even if CRC passes
                            frame_valid_hold <= 1'b0;
                        end else if (cmd_valid && (received_crc == expected_crc)) begin
                            frame_valid_hold <= 1'b1;  // 条件満足時のみ有効フレーム
                        end else begin
                            frame_valid_hold <= 1'b0;  // CRCエラーまたはコマンドエラー時は無効
                        end
                    end
                    IDLE: begin
                        // IDLE状態では必ずframe_valid_holdをクリア
                        frame_valid_hold <= 1'b0;
                    end
                    default: begin
                        // その他の状態では現在値を保持（VALIDATE後の遷移中）
                        // NOTE: POSTVTC case removed - handled by postvtc_clear above
                    end
                endcase
            end
        end
    end
    
    // Output assignments
    assign cmd = cmd_reg;
    assign addr = addr_reg;
    assign data_count = data_byte_count;
    assign frame_valid = frame_valid_hold && (state == VALIDATE);  // CRITICAL: Only valid in VALIDATE state
    assign error_status = error_status_reg;
    assign frame_error = ((state == VALIDATE) && (error_status_reg != STATUS_OK)) || 
                        (state == ERROR) || timeout_occurred;
    assign parser_busy = (state != IDLE) && !soft_reset_request;  // Clear busy on soft reset
    
    // RESET command handling: generate pulse in VALIDATE state for RESET command
    logic soft_reset_pulse;
    logic soft_reset_pulse_reg;  // Register to ensure clean 1-cycle pulse
    
    always_ff @(posedge clk) begin
        if (rst) begin
            soft_reset_pulse <= 1'b0;
            soft_reset_pulse_reg <= 1'b0;
        end else begin
            // Generate 1-cycle pulse when RESET command validated
            if (state == VALIDATE && current_cmd == 8'hFF && cmd_valid && !soft_reset_pulse_reg) begin
                soft_reset_pulse <= 1'b1;
                soft_reset_pulse_reg <= 1'b1;  // Prevent re-trigger
            end else begin
                soft_reset_pulse <= 1'b0;
                // Clear flag when leaving VALIDATE
                if (state != VALIDATE) begin
                    soft_reset_pulse_reg <= 1'b0;
                end
            end
        end
    end
    
    assign soft_reset_request = soft_reset_pulse;

    // Assertion: frame_valid_hold cleanup after frame_consumed
    `ifdef ENABLE_DEBUG
    property frame_valid_cleared_after_consumed;
        @(posedge clk) disable iff (rst)
        (frame_consumed && frame_valid_hold) |=> !frame_valid_hold;
    endproperty
    assert property (frame_valid_cleared_after_consumed) else
        $error("[FP_ASSERT] frame_valid_hold not cleared after frame_consumed at time=%0t", $time);

    // Assertion: frame_valid_hold only valid in VALIDATE or POSTVTC (transition state)
    property frame_valid_state_constraint;
        @(posedge clk) disable iff (rst)
        (frame_valid_hold && (state != VALIDATE) && (state != POSTVTC)) |=> !frame_valid_hold;
    endproperty
    assert property (frame_valid_state_constraint) else
        $error("[FP_ASSERT] frame_valid_hold=1 outside VALIDATE/POSTVTC! state=%0d at time=%0t", state, $time);
    `endif
    
    // Debug signal assignments for hardware analysis
    assign debug_cmd_in = rx_fifo_data;
    assign debug_cmd_decoded = cmd_reg;
    assign debug_status_out = error_status_reg;
    assign debug_crc_in = received_crc;
    assign debug_crc_calc = expected_crc;
    assign debug_crc_error = (received_crc != expected_crc);
    assign debug_crc_received = received_crc;
    assign debug_crc_expected = expected_crc;
    assign debug_error_status = error_status_reg;
    assign debug_state = state;
    assign debug_parser_state = state;
    assign debug_error_cause = debug_error_cause_internal;
    assign debug_frame_valid_flag = frame_valid;
    
    // Copy data array to output
    always_comb begin
        for (int i = 0; i < 64; i++) begin
            data_out[i] = data_reg[i];
        end
    end

    // Runtime visibility for frame_valid activity
    logic frame_valid_q;
    integer frame_valid_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            frame_valid_q <= 1'b0;
            frame_valid_count <= 0;
        end else begin
            frame_valid_q <= frame_valid;
            if (frame_valid && !frame_valid_q) begin
                frame_valid_count <= frame_valid_count + 1;
                // Track transitions into VALIDATE to confirm handshake timing
            end
        end
    end

endmodule
