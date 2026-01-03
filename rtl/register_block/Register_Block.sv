`timescale 1ns / 1ps

import axiuart_reg_pkg::*;

// FIXED AXI4-Lite Register Block for AXIUART System
// Corrected ready signal logic to avoid circular dependencies
module Register_Block #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int BASE_ADDR = axiuart_reg_pkg::BASE_ADDR
)(
    input  logic clk,
    input  logic rst,
    input  logic soft_reset_request,  // Soft reset from RESET command (pulse)
    
    // AXI4-Lite slave interface
    axi4_lite_if.slave axi,
    
    // Register interface to UART bridge
    output logic        bridge_reset_stats,    // Pulse to reset statistics counters
    output logic [15:0] baud_div_config,       // UART baud rate divider configuration
    output logic [7:0]  timeout_config,        // AXI timeout configuration
    output logic [3:0]  debug_mode,            // Debug mode selection
    
    // Status inputs from UART bridge
    input  logic        bridge_busy,           // Bridge is processing transaction
    input  logic [7:0]  error_code,            // Current error code
    input  logic [15:0] tx_count,              // TX transaction counter
    input  logic [15:0] rx_count,              // RX transaction counter
    input  logic [7:0]  fifo_status,           // FIFO status flags
    
    // RV32I CPU debug memory interface (32-bit, word-addressed)
    output logic [10:0] rv32i_mem_addr,        // Word address (0-2047 for 8KB)
    output logic [31:0] rv32i_mem_wdata,       // Write data
    input  logic [31:0] rv32i_mem_rdata,       // Read data
    output logic [3:0]  rv32i_mem_we,          // Byte write enables
    output logic        rv32i_mem_re,          // Read enable
    
    // RV32I CPU control interface
    output logic        rv32i_cpu_run,         // CPU run signal
    output logic        rv32i_cpu_halt,        // CPU halt signal
    input  logic        rv32i_cpu_halted,      // CPU halted status
    input  logic        rv32i_cpu_break        // EBREAK detected
);

    // Register address map - compute offsets from generated package
    // All addresses come from register_map/axiuart_registers.json
    localparam bit [11:0] REG_CONTROL    = (axiuart_reg_pkg::REG_CONTROL - BASE_ADDR);     // 0x000
    localparam bit [11:0] REG_STATUS     = (axiuart_reg_pkg::REG_STATUS - BASE_ADDR);      // 0x004
    localparam bit [11:0] REG_CONFIG     = (axiuart_reg_pkg::REG_CONFIG - BASE_ADDR);      // 0x008
    localparam bit [11:0] REG_DEBUG      = (axiuart_reg_pkg::REG_DEBUG - BASE_ADDR);       // 0x00C
    localparam bit [11:0] REG_TX_COUNT   = (axiuart_reg_pkg::REG_TX_COUNT - BASE_ADDR);    // 0x010
    localparam bit [11:0] REG_RX_COUNT   = (axiuart_reg_pkg::REG_RX_COUNT - BASE_ADDR);    // 0x014
    localparam bit [11:0] REG_FIFO_STAT  = (axiuart_reg_pkg::REG_FIFO_STAT - BASE_ADDR);   // 0x018
    localparam bit [11:0] REG_VERSION    = (axiuart_reg_pkg::REG_VERSION - BASE_ADDR);     // 0x01C
    localparam bit [11:0] REG_TEST_0     = (axiuart_reg_pkg::REG_TEST_0 - BASE_ADDR);      // 0x020
    localparam bit [11:0] REG_TEST_1     = (axiuart_reg_pkg::REG_TEST_1 - BASE_ADDR);      // 0x024
    localparam bit [11:0] REG_TEST_2     = (axiuart_reg_pkg::REG_TEST_2 - BASE_ADDR);      // 0x028
    localparam bit [11:0] REG_TEST_3     = (axiuart_reg_pkg::REG_TEST_3 - BASE_ADDR);      // 0x02C
    localparam bit [11:0] REG_TEST_4     = (axiuart_reg_pkg::REG_TEST_4 - BASE_ADDR);      // 0x040
    localparam bit [11:0] REG_REVISION   = (axiuart_reg_pkg::REG_REVISION - BASE_ADDR);    // 0x23C
    
    // RV32I CPU Memory Access Registers
    localparam bit [11:0] REG_CPU_MEM_ADDR   = (axiuart_reg_pkg::REG_CPU_MEM_ADDR - BASE_ADDR);   // 0x1228
    localparam bit [11:0] REG_CPU_MEM_WDATA  = (axiuart_reg_pkg::REG_CPU_MEM_WDATA - BASE_ADDR);  // 0x122C
    localparam bit [11:0] REG_CPU_MEM_RDATA  = (axiuart_reg_pkg::REG_CPU_MEM_RDATA - BASE_ADDR);  // 0x1230
    localparam bit [11:0] REG_CPU_MEM_CTRL   = (axiuart_reg_pkg::REG_CPU_MEM_CTRL - BASE_ADDR);   // 0x1234

    // Register storage
    logic [31:0] control_reg;      // RW - Control register
    logic [31:0] config_reg;       // RW - Configuration register  
    logic [31:0] debug_reg;        // RW - Debug register
    
    // Test registers for protocol debugging (added 2025-10-05)
    // Extended test set for pattern analysis (2025-10-09)
    logic [31:0] test_reg_0;       // RW - Test register 0 (pure read/write test)
    logic [31:0] test_reg_1;       // RW - Test register 1 (pattern test)
    logic [31:0] test_reg_2;       // RW - Test register 2 (increment test)
    logic [31:0] test_reg_3;       // RW - Test register 3 (mirror test)
    logic [31:0] test_reg_4;       // RW - Test register 4 (gap test)

    // RV32I CPU memory access registers
    logic [31:0] cpu_mem_addr_reg;     // RV32I memory address (byte address)
    logic [31:0] cpu_mem_wdata_reg;    // RV32I memory write data
    logic [31:0] cpu_mem_rdata_reg;    // RV32I memory read data
    logic [31:0] cpu_mem_ctrl_reg;     // RV32I memory control
    
    // RV32I memory access state
    logic        rv32i_mem_busy;       // RV32I memory operation in progress
    logic        rv32i_mem_busy_q;     // Delayed for edge detection
    logic        rv32i_mem_last_was_read; // Track read vs write for rdata capture
    
    // AXI4-Lite response codes
    localparam bit [1:0] RESP_OKAY   = 2'b00;
    localparam bit [1:0] RESP_SLVERR = 2'b10;
    localparam bit [7:0] STATUS_CRC_ERR = 8'h01;
    
    // Internal signals
    logic [11:0] addr_offset;
    logic [31:0] read_data;
    logic [1:0]  read_resp;
    logic [1:0]  write_resp;
    logic [31:0] write_addr_reg;   // CRITICAL: Write address tracking
    logic [7:0]  write_error_code_reg;  // Latches bridge error code at AW handshake
    logic [31:0] read_addr_reg;
    logic [31:0] active_addr;
    
    // AXI4-Lite control signals - defined before state machine
    wire aw_handshake = axi.awvalid && axi.awready;
    wire w_handshake = axi.wvalid && axi.wready;
    wire ar_handshake = axi.arvalid && axi.arready;
    
    // Address decoding logic added after state machine declaration
    
    // AXI4-Lite state machine - CORRECTED
    (* fsm_encoding = "one_hot" *)
    typedef enum logic [2:0] {
        IDLE,
        WRITE_ADDR,
        WRITE_DATA, 
        WRITE_RESP,
        READ_DATA
    } axi_state_t;
    
    axi_state_t axi_state, axi_next_state;
    
    // State machine sequential logic
    always_ff @(posedge clk) begin
        if (rst) begin
            axi_state <= IDLE;
        end else begin
            axi_state <= axi_next_state;
        end
    end
    
    // State machine combinational logic - CORRECTED
    always_comb begin
        axi_next_state = axi_state;
        
        case (axi_state)
            IDLE: begin
                if (axi.awvalid) begin
                    if (aw_handshake) begin
                        axi_next_state = WRITE_DATA;
                    end else begin
                        axi_next_state = WRITE_ADDR;
                    end
                end else if (axi.arvalid) begin
                    axi_next_state = READ_DATA;
                end
            end
            
            WRITE_ADDR: begin
                if (aw_handshake) begin
                    axi_next_state = WRITE_DATA;
                end
            end
            
            WRITE_DATA: begin
                if (w_handshake) begin
                    axi_next_state = WRITE_RESP;
                end
            end
            
            WRITE_RESP: begin
                if (axi.bready) begin
                    axi_next_state = IDLE;
                end
            end
            
            READ_DATA: begin
                if (axi.rready) begin
                    axi_next_state = IDLE;
                end
            end
            
            default: axi_next_state = IDLE;
        endcase
    end
    
    // Address decoding based on current transaction
    always_comb begin
        case (axi_state)
            READ_DATA: active_addr = read_addr_reg;
            default:   active_addr = write_addr_reg;
        endcase
    end

    assign addr_offset = active_addr[11:0];

    // Helper function to validate supported WSTRB patterns and alignment
    function automatic bit is_wstrb_supported(logic [1:0] addr_lsb, logic [3:0] wstrb);
        case (wstrb)
            4'b0001: return (addr_lsb == 2'b00);            // Byte lane 0 only
            4'b0011: return (addr_lsb == 2'b00);            // Lower halfword
            4'b1100: return (addr_lsb == 2'b10);            // Upper halfword
            4'b1111: return (addr_lsb == 2'b00);            // Full word
            default: return 1'b0;                           // Unsupported pattern
        endcase
    endfunction

    function automatic logic [31:0] apply_wstrb_mask(logic [31:0] current,
                                                     logic [31:0] wdata,
                                                     logic [3:0] wstrb);
        logic [31:0] mask;
        mask = '0;
        for (int i = 0; i < 4; i++) begin
            if (wstrb[i]) begin
                mask[8*i +: 8] = 8'hFF;
            end
        end
        return (current & ~mask) | (wdata & mask);
    endfunction

    function automatic bit is_write_access_valid(logic [11:0] offset,
                                                 logic [3:0] wstrb);
        logic [11:0] aligned_offset;
        bit within_register_range;
        aligned_offset = {offset[11:2], 2'b00};
        
        // Check if aligned offset matches any valid register
        case (aligned_offset)
            REG_CONTROL, REG_STATUS, REG_CONFIG, REG_DEBUG,
            REG_TX_COUNT, REG_RX_COUNT, REG_FIFO_STAT, REG_VERSION,
            REG_TEST_0, REG_TEST_1, REG_TEST_2, REG_TEST_3, REG_TEST_4,
            REG_CPU_MEM_ADDR, REG_CPU_MEM_WDATA, REG_CPU_MEM_CTRL,
            REG_REVISION: begin
                within_register_range = 1'b1;
            end
            default: begin
                within_register_range = 1'b0;
            end
        endcase
        
        if (!within_register_range) begin
            return 1'b0;
        end
        
        // Ensure access doesn't exceed the 4-byte register boundary
        if (offset > (aligned_offset + 12'd3)) begin
            return 1'b0;
        end
        
        return is_wstrb_supported(offset[1:0], wstrb);
    endfunction

    function automatic bit is_read_access_valid(logic [11:0] offset);
        logic [11:0] aligned_offset;
        aligned_offset = {offset[11:2], 2'b00};
        
        // Check if aligned offset matches any valid register
        case (aligned_offset)
            REG_CONTROL, REG_STATUS, REG_CONFIG, REG_DEBUG,
            REG_TX_COUNT, REG_RX_COUNT, REG_FIFO_STAT, REG_VERSION,
            REG_TEST_0, REG_TEST_1, REG_TEST_2, REG_TEST_3, REG_TEST_4,
            REG_CPU_MEM_ADDR, REG_CPU_MEM_WDATA, REG_CPU_MEM_RDATA, REG_CPU_MEM_CTRL,
            REG_REVISION: begin
                // Valid register found
            end
            default: begin
                return 1'b0;  // Invalid register address
            end
        endcase
        
        // Ensure access doesn't exceed the 4-byte register boundary
        if (offset > (aligned_offset + 12'd3)) begin
            return 1'b0;
        end
        
        // AXI4-Lite requires word-aligned reads for simplicity
        return (offset[1:0] == 2'b00);
    endfunction

    // Control signals derived from handshake
    wire write_enable = (axi_state == WRITE_DATA) && w_handshake;
    wire read_enable = (axi_state == READ_DATA);

    // RV32I CPU control outputs
    assign rv32i_cpu_run = cpu_mem_ctrl_reg[7];   // Bit[7]: CPU RUN
    assign rv32i_cpu_halt = cpu_mem_ctrl_reg[8];  // Bit[8]: CPU HALT
    
    // Latched address/data for stable values during BUSY period
    logic [31:0] latched_mem_addr;
    logic [31:0] latched_mem_wdata;
    
    // RV32I memory interface (Option A: mask address to 11 bits for 8KB = 2048 words)
    // Use latched values during BUSY to prevent register overwrites from affecting ongoing operations
    assign rv32i_mem_addr = rv32i_mem_busy ? latched_mem_addr[12:2] : cpu_mem_addr_reg[12:2];
    assign rv32i_mem_wdata = rv32i_mem_busy ? latched_mem_wdata : cpu_mem_wdata_reg;
    // rv32i_mem_we and rv32i_mem_re assigned below in sequential logic
    
    // Core AXI debug signals 
    wire axi_awvalid_debug = axi.awvalid;               // CRITICAL: Master awvalid reaches slave
    wire axi_wvalid_debug = axi.wvalid;                 // CRITICAL: Master wvalid reaches slave
    
    // AXI4-Lite data and address debug
    wire [31:0] axi_awaddr_debug = axi.awaddr;          // CRITICAL: Write address

    // RV32I CPU memory control status (read-only bits)
    logic [31:0] cpu_mem_ctrl_ro;
    always_comb begin
        cpu_mem_ctrl_ro = cpu_mem_ctrl_reg;
        cpu_mem_ctrl_ro[6] = rv32i_mem_busy;        // Bit[6]: BUSY status (RO)
        cpu_mem_ctrl_ro[9] = rv32i_cpu_halted;      // Bit[9]: CPU HALTED status (RO)
        cpu_mem_ctrl_ro[10] = rv32i_cpu_break;      // Bit[10]: CPU BREAK status (RO)
        // request bits are write-1-to-pulse; read as 0 for software clarity
        cpu_mem_ctrl_ro[4] = 1'b0;  // RV32I read_req
        cpu_mem_ctrl_ro[5] = 1'b0;  // RV32I write_req
    end
    
    wire [31:0] axi_wdata_debug = axi.wdata;            // CRITICAL: Write data
    wire [3:0] axi_wstrb_debug = axi.wstrb;
    
    // Special trigger signals for ILA
    wire reg_test_write_trigger = write_enable && 
                               ((write_addr_reg[11:0] >= 12'h020) && (write_addr_reg[11:0] <= 12'h02C));  // CRITICAL: REG_TEST write trigger
    
    // AXI4-Lite ready signals - FIXED: No circular dependencies
    assign axi.awready = (axi_state == IDLE) || (axi_state == WRITE_ADDR);
    assign axi.wready = (axi_state == WRITE_DATA);
    assign axi.arready = (axi_state == IDLE);
    
    // Write response channel
    wire axi_bvalid_debug = axi.bvalid;
    wire axi_bready_debug = axi.bready;
    wire [1:0] axi_bresp_debug = axi.bresp;
    assign axi.bvalid = (axi_state == WRITE_RESP);
    assign axi.bresp = write_resp;
    
    // Read response channel
    assign axi.rvalid = (axi_state == READ_DATA);
    assign axi.rdata = read_data;
    assign axi.rresp = read_resp;
    
    // Register write logic
    logic reset_stats_pulse;
    
    // Test register write detection signals - Extended (2025-10-09)
    logic test_reg_0_write_detect;
    logic test_reg_1_write_detect;
    logic test_reg_2_write_detect;
    logic test_reg_3_write_detect;
    logic test_reg_4_write_detect;

    always_ff @(posedge clk) begin
        if (rst) begin
            control_reg <= 32'h0000_0000;  // Default control register value
            config_reg <= 32'h0000_043D;   // Initial: divisor=1085 for 115200bps @ 125MHz (125M/115200=1085)
            debug_reg <= 32'h0000_0000;
            
            // Test register initialization - SAFE INITIAL VALUES (not test patterns)
            test_reg_0 <= 32'h00000000;    // Zero initial value
            test_reg_1 <= 32'h00000000;    // Zero initial value  
            test_reg_2 <= 32'h00000000;    // Zero initial value
            test_reg_3 <= 32'h00000000;    // Zero initial value
            test_reg_4 <= 32'h00000000;    // Zero initial value
            
            // Test register write detection initialization - Extended
            test_reg_0_write_detect <= 1'b0;
            test_reg_1_write_detect <= 1'b0;
            test_reg_2_write_detect <= 1'b0;
            test_reg_3_write_detect <= 1'b0;
            test_reg_4_write_detect <= 1'b0;
            
            write_resp <= RESP_OKAY;
            write_addr_reg <= BASE_ADDR;
            write_error_code_reg <= 8'h00;
            read_addr_reg <= BASE_ADDR;
            reset_stats_pulse <= 1'b0;

            // RV32I CPU memory access registers
            cpu_mem_addr_reg <= 32'h0000_0000;
            cpu_mem_wdata_reg <= 32'h0000_0000;
            cpu_mem_rdata_reg <= 32'h0000_0000;
            cpu_mem_ctrl_reg <= 32'h0000_0000;
            latched_mem_addr <= 32'h0000_0000;
            latched_mem_wdata <= 32'h0000_0000;
            
            // RV32I memory interface
            rv32i_mem_busy <= 1'b0;
            rv32i_mem_busy_q <= 1'b0;
            rv32i_mem_last_was_read <= 1'b0;
            rv32i_mem_we <= 4'b0000;
            rv32i_mem_re <= 1'b0;
        end else begin
            reset_stats_pulse <= 1'b0;
            
            // RV32I memory access busy tracking (registered BlockRAM with Read-First)
            // BlockRAM timing: RE asserted cycle N → data valid cycle N+1
            // Therefore, need 2-cycle busy for reads (1 cycle for writes)
            rv32i_mem_busy_q <= rv32i_mem_busy;
            if (rv32i_mem_we != 4'b0000 || rv32i_mem_re) begin
                rv32i_mem_busy <= 1'b1;
                rv32i_mem_last_was_read <= rv32i_mem_re;
            end else if (rv32i_mem_busy) begin
                // For reads: keep busy for 2 cycles (BRAM latency)
                // For writes: 1 cycle is sufficient
                if (rv32i_mem_last_was_read && rv32i_mem_busy_q) begin
                    rv32i_mem_busy <= 1'b1;  // Stay busy 1 more cycle for read
                end else begin
                    rv32i_mem_busy <= 1'b0;  // Operation complete
                end
            end
            
            // Capture RV32I read data when busy completes (data now valid)
            if (rv32i_mem_busy_q && !rv32i_mem_busy && rv32i_mem_last_was_read) begin
                cpu_mem_rdata_reg <= rv32i_mem_rdata;
            end
            
            // Clear RV32I control signals after operation starts
            if (rv32i_mem_busy) begin
                rv32i_mem_we <= 4'b0000;
                rv32i_mem_re <= 1'b0;
            end
            
            // Clear test register write detection flags
            test_reg_0_write_detect <= 1'b0;
            test_reg_1_write_detect <= 1'b0;


            // SOFT RESET: Clear all registers EXCEPT CONFIG (preserve baud rate)
            if (soft_reset_request) begin
                // Clear control register
                control_reg <= '0;
                
                // Preserve CONFIG register (baud rate configuration)
                // config_reg NOT reset
                
                // Clear debug register
                debug_reg <= '0;
                
                // Clear all test registers
                test_reg_0 <= '0;
                test_reg_1 <= '0;
                test_reg_2 <= '0;
                test_reg_3 <= '0;
                test_reg_4 <= '0;
            end else if (aw_handshake) begin
                write_addr_reg <= axi.awaddr;
                write_resp <= RESP_OKAY;
                write_error_code_reg <= error_code;
            end

            if (ar_handshake) begin
                read_addr_reg <= axi.araddr;
            end

            if (write_enable) begin
                logic [11:0] write_offset;
                logic [11:0] aligned_offset;
                bit write_ok;
                logic [31:0] masked_value;

                write_offset = write_addr_reg[11:0];
                aligned_offset = {write_offset[11:2], 2'b00};
                write_ok = is_write_access_valid(write_offset, axi.wstrb);

                if (write_ok) begin
                    case (aligned_offset)
                        REG_CONTROL: begin
                            masked_value = apply_wstrb_mask(control_reg, axi.wdata, axi.wstrb);
                            control_reg[0] <= masked_value[0];
                            control_reg[1] <= 1'b0; // Reserved bit forced low
                            control_reg[31:2] <= '0;
                            if (axi.wstrb[0] && axi.wdata[1]) begin
                                reset_stats_pulse <= 1'b1;
                            end
                        end

                        REG_CONFIG: begin
                            masked_value = apply_wstrb_mask(config_reg, axi.wdata, axi.wstrb);
                            config_reg[7:0] <= masked_value[7:0];
                            config_reg[15:8] <= masked_value[15:8];
                            config_reg[31:16] <= 16'b0;
                        end

                        REG_DEBUG: begin
                            masked_value = apply_wstrb_mask(debug_reg, axi.wdata, axi.wstrb);
                            debug_reg[3:0] <= masked_value[3:0];
                            debug_reg[31:4] <= 28'b0;
                        end

                        // Test registers - full 32-bit read/write (added 2025-10-05)
                        REG_TEST_0: begin
                            masked_value = apply_wstrb_mask(test_reg_0, axi.wdata, axi.wstrb);
                            test_reg_0 <= masked_value;
                            test_reg_0_write_detect <= 1'b1;
                        end

                        REG_TEST_1: begin
                            masked_value = apply_wstrb_mask(test_reg_1, axi.wdata, axi.wstrb);
                            test_reg_1 <= masked_value;
                            test_reg_1_write_detect <= 1'b1;
                        end

                        REG_TEST_2: begin
                            masked_value = apply_wstrb_mask(test_reg_2, axi.wdata, axi.wstrb);
                            test_reg_2 <= masked_value;
                            test_reg_2_write_detect <= 1'b1;
                        end

                        REG_TEST_3: begin
                            masked_value = apply_wstrb_mask(test_reg_3, axi.wdata, axi.wstrb);
                            test_reg_3 <= masked_value;
                            test_reg_3_write_detect <= 1'b1;
                        end

                        // Extended test registers (added 2025-10-09)
                        REG_TEST_4: begin
                            masked_value = apply_wstrb_mask(test_reg_4, axi.wdata, axi.wstrb);
                            test_reg_4 <= masked_value;
                            test_reg_4_write_detect <= 1'b1;
                        end

                        // ----------------------------------------------------------------
                        // RV32I CPU Memory Access Registers
                        // ----------------------------------------------------------------
                        REG_CPU_MEM_ADDR: begin
                            // Write full 32-bit byte address
                            cpu_mem_addr_reg <= apply_wstrb_mask(cpu_mem_addr_reg, axi.wdata, axi.wstrb);
                        end

                        REG_CPU_MEM_WDATA: begin
                            // Write full 32-bit data
                            cpu_mem_wdata_reg <= apply_wstrb_mask(cpu_mem_wdata_reg, axi.wdata, axi.wstrb);
                        end

                        REG_CPU_MEM_CTRL: begin
                            // RV32I memory operations (32-bit, byte-granular)
                            // Bits [3:0] = byte write enables (for write operations)
                            // Bit [4] = read request (write-1-to-pulse)
                            // Bit [5] = write request (write-1-to-pulse)
                            // Bit [6] = BUSY status (RO, handled in cpu_mem_ctrl_ro)
                            // Bit [7] = CPU RUN control (persistent)
                            // Bit [8] = CPU HALT control (persistent)
                            // Bits [9:10] = CPU status (RO, handled in cpu_mem_ctrl_ro)
                            masked_value = apply_wstrb_mask(cpu_mem_ctrl_reg, axi.wdata, axi.wstrb);
                            cpu_mem_ctrl_reg[7] <= masked_value[7];  // CPU RUN (persistent)
                            cpu_mem_ctrl_reg[8] <= masked_value[8];  // CPU HALT (persistent)

                            if (axi.wstrb[0]) begin
                                if (axi.wdata[4]) begin
                                    // Read request: set read enable and latch address
                                    latched_mem_addr <= cpu_mem_addr_reg;
                                    rv32i_mem_re <= 1'b1;
                                    rv32i_mem_busy <= 1'b1;
                                    rv32i_mem_last_was_read <= 1'b1;
                                end else if (axi.wdata[5]) begin
                                    // Write request: get byte enables from bits [3:0] and latch address/data
                                    // If byte enables are 0, default to full-word write (all bytes)
                                    latched_mem_addr <= cpu_mem_addr_reg;
                                    latched_mem_wdata <= cpu_mem_wdata_reg;
                                    rv32i_mem_we <= (axi.wdata[3:0] != 4'b0000) ? axi.wdata[3:0] : 4'b1111;
                                    rv32i_mem_busy <= 1'b1;
                                    rv32i_mem_last_was_read <= 1'b0;
                                end
                            end
                        end

                        default: begin
                            // Writes to RO registers succeed but have no effect
                        end
                        endcase

                        if (write_error_code_reg == STATUS_CRC_ERR) begin
                            write_resp <= RESP_SLVERR;
                        end else begin
                            write_resp <= RESP_OKAY;
                        end
                end else begin
                    write_resp <= RESP_SLVERR;
                end
            end
            
            // RV32I memory busy tracking (1-cycle registered RAM)
            rv32i_mem_busy_q <= rv32i_mem_busy;
            if (rv32i_mem_busy) begin
                // Clear control signals after 1 cycle
                rv32i_mem_we <= 4'b0000;
                rv32i_mem_re <= 1'b0;
                rv32i_mem_busy <= 1'b0;
            end
            
            // Capture RV32I read data when busy completes and was a read operation
            if (!rv32i_mem_busy && rv32i_mem_busy_q && rv32i_mem_last_was_read) begin
                cpu_mem_rdata_reg <= rv32i_mem_rdata;
            end
        end
    end
    
    assign bridge_reset_stats = reset_stats_pulse;

    // Register read logic
    always_comb begin
        logic [11:0] read_offset;
        logic [11:0] aligned_offset;
        bit read_ok;

        read_offset = read_addr_reg[11:0];
        aligned_offset = {read_offset[11:2], 2'b00};
        read_ok = is_read_access_valid(read_offset);

        read_resp = RESP_OKAY;
        read_data = '0;

        if (read_ok) begin
            case (aligned_offset)
                REG_CONTROL: begin
                    read_data = control_reg;
                end

                REG_STATUS: begin
                    read_data[0] = bridge_busy;
                    read_data[8:1] = error_code;
                    read_data[31:9] = '0;
                end

                REG_CONFIG: begin
                    read_data = config_reg;
                end

                REG_DEBUG: begin
                    read_data = debug_reg;
                end

                REG_TX_COUNT: begin
                    read_data[15:0] = tx_count;
                    read_data[31:16] = '0;
                end

                REG_RX_COUNT: begin
                    read_data[15:0] = rx_count;
                    read_data[31:16] = '0;
                end

                REG_FIFO_STAT: begin
                    read_data[7:0] = fifo_status;
                    read_data[31:8] = '0;
                end

                REG_VERSION: begin
                    read_data = 32'h0001_0000;  // Version 1.0.0
                end

                // Test registers - return stored values (added 2025-10-05, extended 2025-10-09)
                REG_TEST_0: begin
                    read_data = test_reg_0;
                end

                REG_TEST_1: begin
                    read_data = test_reg_1;
                end

                REG_TEST_2: begin
                    read_data = test_reg_2;
                end

                REG_TEST_3: begin
                    read_data = test_reg_3;
                end

                REG_TEST_4: begin
                    read_data = test_reg_4;
                end

                // ----------------------------------------------------------------
                // RV32I CPU Memory Access Registers
                // ----------------------------------------------------------------
                REG_CPU_MEM_ADDR: begin
                    read_data = cpu_mem_addr_reg;
                end

                REG_CPU_MEM_WDATA: begin
                    read_data = cpu_mem_wdata_reg;
                end

                REG_CPU_MEM_RDATA: begin
                    read_data = cpu_mem_rdata_reg;
                end

                REG_CPU_MEM_CTRL: begin
                    read_data = cpu_mem_ctrl_ro;
                end

                REG_REVISION: begin
                    read_data = 32'h2026_0103;  // Hardware revision: 2026-01-03 (RV32I only)
                end

                default: begin
                    read_data = '0;
                end
            endcase
        end else begin
            read_resp = RESP_SLVERR;
        end
    end
    
    // Output register mappings
    assign baud_div_config = config_reg[15:0];
    assign timeout_config = config_reg[15:8];
    assign debug_mode = debug_reg[3:0];

    `ifdef ENABLE_DEBUG
    // Critical debugging only - AXI handshakes and state transitions
    always_ff @(posedge clk) begin
        if (!rst && aw_handshake) begin
        end
        if (!rst && ar_handshake) begin
        end
    end
    `endif

    // Debug output
    initial begin
    end

endmodule
