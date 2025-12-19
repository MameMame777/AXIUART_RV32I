`timescale 1ns / 1ps

// AXI4-Lite Master Module for UART-AXI4 Bridge
// Performs AXI4-Lite transactions based on parsed UART commands
module Axi4_Lite_Master #(
    parameter int AXI_TIMEOUT = 2500,          // Timeout in clock cycles (20μs @ 125MHz)
    parameter int EARLY_BUSY_THRESHOLD = 250   // Early BUSY threshold (2μs @ 125MHz)
)(
    input  logic        clk,
    input  logic        rst,
    
    // Command interface
    input  logic [7:0]  cmd,               // Command byte from parser
    input  logic [31:0] addr,              // Address from parser
    input  logic [7:0]  write_data [0:63], // Write data from parser
    input  logic        start_transaction, // Start AXI transaction
    output logic        transaction_done,  // Transaction complete
    output logic [7:0]  axi_status,        // Transaction status
    
    // Read data output
    output logic [7:0]  read_data [0:63],  // Read data for frame builder
    output logic [6:0]  read_data_count,   // Number of read data bytes
    
    // AXI4-Lite Master Interface
    axi4_lite_if.master axi
);

    // Status codes from protocol specification
    localparam [7:0] STATUS_OK        = 8'h00;
    localparam [7:0] STATUS_ADDR_ALIGN = 8'h03;
    localparam [7:0] STATUS_TIMEOUT   = 8'h04;
    localparam [7:0] STATUS_AXI_SLVERR = 8'h05;
    localparam [7:0] STATUS_BUSY      = 8'h06;
    
    // Command field registers
    logic [7:0] cmd_reg;           // CRITICAL: Stored command for analysis
    logic       rw_bit;            // Read/Write bit analysis
    logic       inc_bit;
    logic [1:0] size_field;
    logic [3:0] len_field;

    assign rw_bit = cmd_reg[7];
    assign inc_bit = cmd_reg[6];
    assign size_field = cmd_reg[5:4];
    assign len_field = cmd_reg[3:0];

    // State machine - CRITICAL for debugging WRITE_ADDR stuck issue
    typedef enum logic [3:0] {
        IDLE            = 4'h0,
        CHECK_ALIGNMENT = 4'h1,
        WRITE_ADDR      = 4'h2,
        WRITE_DATA      = 4'h3,
        WRITE_RESP      = 4'h4,
        READ_ADDR       = 4'h5,
        READ_DATA       = 4'h6,
        NEXT_BEAT       = 4'h7,
        DONE            = 4'h8,
        ERROR           = 4'h9
    } axi_state_t;
    
    axi_state_t state, state_next;
    
    // Address alignment checker
    logic [31:0] current_addr;
    logic addr_ok;
    logic [3:0] wstrb;
    logic [2:0] align_status;
    
    Address_Aligner addr_aligner (
        .addr(current_addr),
        .size(size_field),
        .addr_ok(addr_ok),
        .wstrb(wstrb),
        .status_code(align_status)
    );
    
    // Beat size calculation
    logic [2:0] beat_size;
    always_comb begin
        case (size_field)
            2'b00: beat_size = 1;  // 8-bit
            2'b01: beat_size = 2;  // 16-bit
            2'b10: beat_size = 4;  // 32-bit
            default: beat_size = 0; // Invalid
        endcase
    end
    
    // Internal registers
    logic [3:0] beat_counter;
    logic [6:0] data_byte_index;
    logic [7:0] status_reg;
    logic [15:0] timeout_counter;   // CRITICAL: Timeout monitoring
    logic early_busy_sent;

    // Flattened view of write_data for waveform/debug visibility
    (* keep = "true" *) logic [(64 * 8) - 1:0] write_data_flat;

    // Internal valid/ready tracking to avoid reading modport outputs
    logic awvalid_int;  // CRITICAL: Write address valid from master
    logic wvalid_int;   // CRITICAL: Write data valid from master
    logic arvalid_int;
    logic bready_int;
    logic rready_int;

    // Handshake indicators - CRITICAL for WRITE_DATA stuck debugging
    logic aw_handshake;  // CRITICAL: Write address handshake detection
    logic w_handshake;   // CRITICAL: Write data handshake detection
    logic ar_handshake;
    logic b_handshake;
    logic r_handshake;

    // Timeout detection for stuck state analysis
    logic timeout_occurred; // CRITICAL: Timeout detection

    // Generate internal valid flags
    assign awvalid_int = (state == WRITE_ADDR);
    assign wvalid_int  = (state == WRITE_DATA);
    assign bready_int  = (state == WRITE_RESP);
    assign arvalid_int = (state == READ_ADDR);
    assign rready_int  = (state == READ_DATA);

    // Handshake detection logic
    assign aw_handshake = awvalid_int && axi.awready;
    assign w_handshake  = wvalid_int  && axi.wready;
    assign b_handshake  = bready_int  && axi.bvalid;
    assign ar_handshake = arvalid_int && axi.arready;
    assign r_handshake  = rready_int  && axi.rvalid;
    
    // Timeout and busy logic
    logic early_busy_threshold_reached;
    
    // Transaction done signal management
    logic transaction_done_reg;
    
    always_comb begin
        timeout_occurred = (timeout_counter >= AXI_TIMEOUT);
        early_busy_threshold_reached = (timeout_counter >= EARLY_BUSY_THRESHOLD);
    end
    
    // Provide continuous flattened mapping for tools that cannot display 2-D arrays
    always_comb begin
        write_data_flat = '0;
        for (int i = 0; i < 64; i++) begin
            write_data_flat[(i * 8) +: 8] = write_data[i];
        end
    end

    // State machine (sequential part)
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            beat_counter <= '0;
            current_addr <= '0;
            data_byte_index <= '0;
            status_reg <= STATUS_OK;
            timeout_counter <= '0;
            early_busy_sent <= 1'b0;
            transaction_done_reg <= 1'b0;
            cmd_reg <= 8'h00;
            // Initialize read_data array to prevent X-state propagation
            for (int i = 0; i < 64; i++) begin
                read_data[i] <= '0;
            end
            read_data_count <= '0;
        end else begin
            state <= state_next;
            
            // Initialize on transaction start
            if (start_transaction && (state == IDLE)) begin
                beat_counter <= '0;
                current_addr <= addr;
                data_byte_index <= '0;
                status_reg <= STATUS_OK;
                timeout_counter <= '0;
                early_busy_sent <= 1'b0;
                transaction_done_reg <= 1'b0;  // Clear done flag when starting new transaction
                cmd_reg <= cmd;
                `ifdef ENABLE_DEBUG
                    // Simulation-only trace to confirm master sees start_transaction
                `endif
            end
            
            // Update beat counter and address for next beat
            if (state == NEXT_BEAT) begin
                logic [6:0] next_index;
                logic [6:0] beat_size_ext;

                beat_counter <= beat_counter + 1;
                if (inc_bit) begin
                    current_addr <= current_addr + beat_size;
                end

                beat_size_ext = {4'b0000, beat_size};
                next_index = data_byte_index + beat_size_ext;
                if (next_index > 7'd64) begin
                    next_index = 7'd64;
                    $error("[AXI_MASTER] data_byte_index exceeded 64 bytes");
                end
                data_byte_index <= next_index;
            end
            
            // Timeout counter management
            if ((state == WRITE_ADDR) || (state == WRITE_DATA) || (state == WRITE_RESP) ||
                (state == READ_ADDR) || (state == READ_DATA)) begin
                if (!timeout_occurred) begin
                    timeout_counter <= timeout_counter + 1;
                end
            end else begin
                timeout_counter <= '0;
            end
            
            // Early BUSY status tracking
            if ((state == READ_DATA) && early_busy_threshold_reached && !early_busy_sent) begin
                early_busy_sent <= 1'b1;
                // Note: In real implementation, this would trigger BUSY response
                // For now, we continue waiting until full timeout
            end
            
            // Status updates
            if (state == CHECK_ALIGNMENT) begin
                if (!addr_ok) begin
                    status_reg <= STATUS_ADDR_ALIGN;
                end
            end
            
            if (timeout_occurred && ((state == WRITE_ADDR) || (state == WRITE_DATA) || 
                                   (state == WRITE_RESP) || (state == READ_ADDR) || (state == READ_DATA))) begin
                status_reg <= early_busy_sent ? STATUS_BUSY : STATUS_TIMEOUT;
            end
            
            // Set transaction_done_reg when reaching completion states
            if ((state == DONE) || (state == ERROR)) begin
                transaction_done_reg <= 1'b1;
                `ifdef ENABLE_DEBUG
                `endif
            end
            
            // Clear transaction_done_reg when returning to IDLE state
            if (state == IDLE && state_next == IDLE && !start_transaction) begin
                transaction_done_reg <= 1'b0;
            end
            
            if ((state == WRITE_RESP) && b_handshake) begin
                if (axi.bresp != 2'b00) begin  // OKAY = 2'b00
                    status_reg <= STATUS_AXI_SLVERR;
                end
            end

            if ((state == READ_DATA) && r_handshake) begin
                if (axi.rresp != 2'b00) begin  // OKAY = 2'b00
                    status_reg <= STATUS_AXI_SLVERR;
                end
                
                // Read data capture - moved from separate always_ff block
                case (size_field)
                    2'b00: begin  // 8-bit
                        if (data_byte_index < 7'd64) begin
                            read_data[data_byte_index] <= axi.rdata[7:0];
                        end else begin
                            $error("[AXI_MASTER] byte index overflow for 8-bit read");
                        end
                    end
                    2'b01: begin  // 16-bit
                        if (data_byte_index <= 7'd62) begin
                            read_data[data_byte_index] <= axi.rdata[7:0];
                            read_data[data_byte_index + 1] <= axi.rdata[15:8];
                        end else begin
                            $error("[AXI_MASTER] byte index overflow for 16-bit read");
                        end
                    end
                    2'b10: begin  // 32-bit
                        if (data_byte_index <= 7'd60) begin
                            read_data[data_byte_index] <= axi.rdata[7:0];
                            read_data[data_byte_index + 1] <= axi.rdata[15:8];
                            read_data[data_byte_index + 2] <= axi.rdata[23:16];
                            read_data[data_byte_index + 3] <= axi.rdata[31:24];
                        end else begin
                            $error("[AXI_MASTER] byte index overflow for 32-bit read");
                        end
                    end
                endcase
                
                // Update read data count
                if (beat_counter >= len_field) begin
                    logic [6:0] read_count_next;
                    logic [6:0] beat_size_ext;

                    beat_size_ext = {4'b0000, beat_size};
                    read_count_next = data_byte_index + beat_size_ext;
                    if (read_count_next > 7'd64) begin
                        read_count_next = 7'd64;
                        $error("[AXI_MASTER] read_data_count exceeded 64 bytes");
                    end
                    read_data_count <= read_count_next;
                end
            end
            
            // Reset read_data_count when idle
            if (state == IDLE) begin
                read_data_count <= '0;
            end
        end
    end
    
    // State machine (combinational part)
    always_comb begin
        state_next = state;
        
        case (state)
            IDLE: begin
                if (start_transaction) begin
                    state_next = CHECK_ALIGNMENT;
                end
            end
            
            CHECK_ALIGNMENT: begin
                if (!addr_ok) begin
                    state_next = ERROR;
                end else if (rw_bit) begin  // Read
                    state_next = READ_ADDR;
                end else begin  // Write
                    state_next = WRITE_ADDR;
                end
            end
            
            WRITE_ADDR: begin
                if (aw_handshake) begin
                    state_next = WRITE_DATA;
                end else if (timeout_occurred) begin
                    state_next = ERROR;
                end
            end
            
            WRITE_DATA: begin
                if (w_handshake) begin
                    state_next = WRITE_RESP;
                end else if (timeout_occurred) begin
                    state_next = ERROR;
                end
            end
            
            WRITE_RESP: begin
                if (b_handshake) begin
                    if (beat_counter >= len_field) begin
                        state_next = DONE;
                    end else begin
                        state_next = NEXT_BEAT;
                    end
                end else if (timeout_occurred) begin
                    state_next = ERROR;
                end
            end
            
            READ_ADDR: begin
                if (ar_handshake) begin
                    state_next = READ_DATA;
                end else if (timeout_occurred) begin
                    state_next = ERROR;
                end
            end
            
            READ_DATA: begin
                if (r_handshake) begin
                    if (beat_counter >= len_field) begin
                        state_next = DONE;
                    end else begin
                        state_next = NEXT_BEAT;
                    end
                end else if (timeout_occurred) begin
                    state_next = ERROR;
                end
            end
            
            NEXT_BEAT: begin
                if (rw_bit) begin  // Read
                    state_next = READ_ADDR;
                end else begin  // Write
                    state_next = WRITE_ADDR;
                end
            end
            
            DONE: begin
                state_next = IDLE;
            end
            
            ERROR: begin
                state_next = IDLE;
            end
        endcase
        `ifdef ENABLE_DEBUG
        `endif
    end
    
    // AXI4-Lite signal assignments
    always_comb begin
        // Default values
        axi.awaddr = current_addr;
        axi.awprot = 3'b000;  // Non-secure, unprivileged, data access

        axi.wdata = '0;
        axi.wstrb = wstrb;

        axi.araddr = current_addr;
        axi.arprot = 3'b000;  // Non-secure, unprivileged, data access

        // Assign interface signals
        axi.awvalid = awvalid_int;
        axi.wvalid  = wvalid_int;
        axi.bready  = bready_int;
        axi.arvalid = arvalid_int;
        axi.rready  = rready_int;

        // Pack write data based on size, byte index, and current address alignment
        if (wvalid_int) begin
            case (size_field)
                2'b00: begin  // 8-bit
                    int lane;
                    lane = current_addr[1:0];
                    axi.wdata[(lane * 8) +: 8] = write_data[data_byte_index];
                end
                2'b01: begin  // 16-bit
                    logic [7:0] byte0;
                    logic [7:0] byte1;
                    byte0 = write_data[data_byte_index];
                    byte1 = write_data[data_byte_index + 1];

                    if (current_addr[1] == 1'b0) begin
                        axi.wdata[7:0]  = byte0;
                        axi.wdata[15:8] = byte1;
                    end else begin
                        axi.wdata[23:16] = byte0;
                        axi.wdata[31:24] = byte1;
                    end
                end
                2'b10: begin  // 32-bit
                    axi.wdata[7:0]   = write_data[data_byte_index];
                    axi.wdata[15:8]  = write_data[data_byte_index + 1];
                    axi.wdata[23:16] = write_data[data_byte_index + 2];
                    axi.wdata[31:24] = write_data[data_byte_index + 3];
                end
            endcase
        end
    end
    
    // Output assignments
    // Transaction done signal - hold high until next transaction starts
    assign transaction_done = transaction_done_reg;
    assign axi_status = status_reg;

    // Enable debug by default for troubleshooting
    `define ENABLE_DEBUG

    `ifdef ENABLE_DEBUG
    function automatic string axi_master_state_to_string(axi_state_t s);
        case (s)
            IDLE:            return "IDLE";
            CHECK_ALIGNMENT: return "CHECK_ALIGNMENT";
            WRITE_ADDR:      return "WRITE_ADDR";
            WRITE_DATA:      return "WRITE_DATA";
            WRITE_RESP:      return "WRITE_RESP";
            READ_ADDR:       return "READ_ADDR";
            READ_DATA:       return "READ_DATA";
            NEXT_BEAT:       return "NEXT_BEAT";
            DONE:            return "DONE";
            ERROR:           return "ERROR";
            default:         return "UNKNOWN";
        endcase
    endfunction

    axi_state_t state_debug_prev;

    always_ff @(posedge clk) begin
        if (rst) begin
            state_debug_prev <= IDLE;
        end else begin
            if (state != state_debug_prev) begin
                // AXI Master state transition
            end
            if (aw_handshake) begin
                // AXI Master AW handshake
            end
            if (w_handshake) begin
                // AXI Master W handshake
            end
            if (b_handshake) begin
                // AXI Master B handshake
            end
            if (ar_handshake) begin
                // AXI Master AR handshake
            end
            if (r_handshake) begin
                // AXI Master R handshake
            end
            state_debug_prev <= state;
        end
    end
    `endif

endmodule
