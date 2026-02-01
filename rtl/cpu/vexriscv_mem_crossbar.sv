`timescale 1ns / 1ps
//=====================================================================
// VexRiscv Memory Crossbar with Buffered Access
//=====================================================================
// Description:
//   Arbitrates IBus/DBus/Debug access to dual-port Block RAM with FIFO buffering
//   - IBus: 7-deep FIFO for pending instruction fetches (matches VexRiscv max)
//   - DBus: 2-deep FIFO for load/store transactions
//   - Debug: Direct access when CPU halted (takes over both ports)
//   - MMIO decode: Routes LED register access (0x8000407C) to separate interface
//   - Waveform logging: $display transactions for debugging
//
// Memory Map (VexRiscv standard 0x80000000 base):
//   0x80000000-0x80001FFF: Block RAM (8KB)
//   0x8000407C:            LED register (MMIO)
//   Debug interface uses word addresses (0-2047) independent of CPU address space
//
// Port Allocation:
//   - Port A: IBus (instruction fetch) or Debug (when halted)
//   - Port B: DBus (data access) or Debug (when halted)
//
// Arbitration Rules:
//   1. CPU halted: Debug has exclusive access to both ports
//   2. CPU running:
//      - Port A priority: IBus > Debug (should never conflict)
//      - Port B priority: DBus > Debug (should never conflict)
//      - IBus vs DBus: No conflict (separate ports)
//
// Performance:
//   - IBus latency: +1 cycle (FIFO + BRAM registered output = 2 cycles total)
//   - DBus latency: +1 cycle (FIFO + BRAM registered output = 2 cycles total)
//   - Debug latency: 2 cycles (direct BRAM access, registered output)
//
// Author: GitHub Copilot (Claude Sonnet 4.5)
// Date: January 17, 2026
//=====================================================================

module vexriscv_mem_crossbar (
    input  logic        clk,
    input  logic        rst,
    
    //=================================================================
    // VexRiscv IBus Interface (Instruction Fetch)
    //=================================================================
    input  logic        iBus_cmd_valid,
    output logic        iBus_cmd_ready,
    input  logic [31:0] iBus_cmd_payload_pc,      // Byte address
    
    output logic        iBus_rsp_valid,
    output logic        iBus_rsp_payload_error,
    output logic [31:0] iBus_rsp_payload_inst,
    output logic [31:0] iBus_rsp_payload_pc,
    
    //=================================================================
    // VexRiscv DBus Interface (Data Access)
    //=================================================================
    input  logic        dBus_cmd_valid,
    output logic        dBus_cmd_ready,
    input  logic        dBus_cmd_payload_wr,
    input  logic [3:0]  dBus_cmd_payload_mask,
    input  logic [31:0] dBus_cmd_payload_address, // Byte address
    input  logic [31:0] dBus_cmd_payload_data,
    input  logic [1:0]  dBus_cmd_payload_size,
    
    output logic        dBus_rsp_ready,
    output logic        dBus_rsp_error,
    output logic [31:0] dBus_rsp_data,
    
    //=================================================================
    // Debug Interface (UART access when halted)
    //=================================================================
    input  logic [10:0] dbg_mem_addr,              // Word address (0-2047)
    input  logic [31:0] dbg_mem_wdata,
    output logic [31:0] dbg_mem_rdata,
    input  logic [3:0]  dbg_mem_we,                // Byte write enables
    input  logic        dbg_mem_re,                // Read enable
    output logic        dbg_mem_busy,              // Operation in progress
    input  logic        cpu_halted,                // CPU is halted
    
    //=================================================================
    // MMIO LED Register Interface
    //=================================================================
    output logic [31:0] led_reg_wdata,
    output logic        led_reg_we,
    input  logic [31:0] led_reg_rdata
);

    //=================================================================
    // Internal Block RAM Signals
    //=================================================================
    
    // Port A wires (IBus / Debug)
    logic        ram_a_en;
    logic [10:0] ram_a_addr;
    logic [3:0]  ram_a_we;
    logic [31:0] ram_a_wdata;
    logic [31:0] ram_a_rdata;
    logic [31:0] ram_a_byte_addr;
    logic        ram_a_mmio_access;
    
    // Port B wires (DBus / Debug)
    logic        ram_b_en;
    logic [10:0] ram_b_addr;
    logic [3:0]  ram_b_we;
    logic [31:0] ram_b_wdata;
    logic [31:0] ram_b_rdata;
    logic [31:0] ram_b_byte_addr;
    logic        ram_b_mmio_access;
    
    //=================================================================
    // IBus Request FIFO (7 entries)
    //=================================================================
    
    typedef struct packed {
        logic [31:0] pc;
    } ibus_req_t;
    
    ibus_req_t ibus_fifo_din;
    ibus_req_t ibus_fifo_dout;
    logic ibus_fifo_push;
    logic ibus_fifo_pop;
    logic ibus_fifo_empty;
    logic ibus_fifo_full;
    logic [2:0] ibus_fifo_count;
    
    ibus_req_t [6:0] ibus_fifo;
    logic [2:0] ibus_wr_ptr;
    logic [2:0] ibus_rd_ptr;
    
    assign ibus_fifo_count = ibus_wr_ptr - ibus_rd_ptr;
    assign ibus_fifo_empty = (ibus_fifo_count == 3'b000);
    assign ibus_fifo_full  = (ibus_fifo_count == 3'b111);
    
    // IBus command handshake: Accept when FIFO not full
    // Remove cpu_halted gating - VexRiscv handles halt internally via fetcher_halt
    assign iBus_cmd_ready = !ibus_fifo_full;
    assign ibus_fifo_push = iBus_cmd_valid && iBus_cmd_ready;
    assign ibus_fifo_din  = '{pc: iBus_cmd_payload_pc};
    
    always_ff @(posedge clk) begin
        if (rst) begin
            ibus_wr_ptr <= 3'b000;
            // Initialize FIFO to prevent X propagation
            for (int i = 0; i < 7; i++) begin
                ibus_fifo[i] <= '0;
            end
        end else if (ibus_fifo_push) begin
            ibus_fifo[ibus_wr_ptr] <= ibus_fifo_din;
            ibus_wr_ptr <= ibus_wr_ptr + 1'b1;
        end
    end
    
    assign ibus_fifo_dout = ibus_fifo[ibus_rd_ptr];
    
    //=================================================================
    // DBus Request FIFO (2 entries)
    //=================================================================
    
    typedef struct packed {
        logic        wr;
        logic [3:0]  mask;
        logic [31:0] address;
        logic [31:0] data;
    } dbus_req_t;
    
    dbus_req_t dbus_fifo_din;
    dbus_req_t dbus_fifo_dout;
    logic dbus_fifo_push;
    logic dbus_fifo_pop;
    logic dbus_fifo_pop_done;
    logic dbus_fifo_empty;
    logic dbus_fifo_full;
    logic [1:0] dbus_fifo_count;  // 2-bit counter for 2-entry FIFO (0, 1, 2)

    dbus_req_t [1:0] dbus_fifo;
    logic dbus_wr_ptr;
    logic dbus_rd_ptr;

    assign dbus_fifo_empty = (dbus_fifo_count == 2'd0);
    assign dbus_fifo_full  = (dbus_fifo_count == 2'd2);
    
    // DBus command handshake: Accept when FIFO not full
    assign dBus_cmd_ready = !dbus_fifo_full && !cpu_halted;
    assign dbus_fifo_push = dBus_cmd_valid && dBus_cmd_ready;
    assign dbus_fifo_din  = '{
        wr:      dBus_cmd_payload_wr,
        mask:    dBus_cmd_payload_mask,
        address: dBus_cmd_payload_address,
        data:    dBus_cmd_payload_data
    };
    
    always_ff @(posedge clk) begin
        if (rst) begin
            dbus_wr_ptr <= 1'b0;
            dbus_fifo_count <= 2'd0;
            // Initialize FIFO to prevent X propagation
            for (int i = 0; i < 2; i++) begin
                dbus_fifo[i] <= '0;
            end
        end else begin
            // FIFO push
            if (dbus_fifo_push) begin
                dbus_fifo[dbus_wr_ptr] <= dbus_fifo_din;
                dbus_wr_ptr <= ~dbus_wr_ptr;
            end

            // FIFO count update (handle simultaneous push/pop)
            case ({dbus_fifo_push, dbus_fifo_pop_done})
                2'b10: dbus_fifo_count <= dbus_fifo_count + 1'b1;  // Push only
                2'b01: dbus_fifo_count <= dbus_fifo_count - 1'b1;  // Pop done only
                default: dbus_fifo_count <= dbus_fifo_count;       // Both or neither
            endcase
        end
    end

    assign dbus_fifo_dout = dbus_fifo[dbus_rd_ptr];
    
    //=================================================================
    // IBus → Port A State Machine
    //=================================================================
    
    typedef enum logic [1:0] {
        IBUS_IDLE,
        IBUS_READ_WAIT,
        IBUS_RESPOND
    } ibus_state_t;
    
    ibus_state_t ibus_state;
    logic [31:0] ibus_rdata_buf;
    logic [31:0] ibus_pc_buf;
    
    // Remove cpu_halted gating - VexRiscv won't issue commands when halted anyway
    // The cpu_halted check was preventing FIFO from being serviced, causing pipeline starvation
    assign ibus_fifo_pop = (ibus_state == IBUS_IDLE) && !ibus_fifo_empty;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            ibus_state <= IBUS_IDLE;
            ibus_rd_ptr <= 3'b000;
            iBus_rsp_valid <= 1'b0;
            iBus_rsp_payload_inst <= 32'h0000_0013;
            iBus_rsp_payload_error <= 1'b0;
            iBus_rsp_payload_pc <= 32'h0;
            ibus_rdata_buf <= 32'h0;
            ibus_pc_buf <= 32'h0;
        end else begin
            case (ibus_state)
                IBUS_IDLE: begin
                    iBus_rsp_valid <= 1'b0;
                    if (ibus_fifo_pop) begin
                        // Issue read to Port A
                        ibus_pc_buf <= ibus_fifo_dout.pc;
                        ibus_state <= IBUS_READ_WAIT;
                    end
                end
                
                IBUS_READ_WAIT: begin
                    // Wait 1 cycle for BRAM registered output
                    ibus_rdata_buf <= ram_a_rdata;
                    ibus_state <= IBUS_RESPOND;
                end
                
                IBUS_RESPOND: begin
                    // Send response to VexRiscv
                    iBus_rsp_valid <= 1'b1;
                    iBus_rsp_payload_inst <= ibus_rdata_buf;
                    iBus_rsp_payload_error <= 1'b0;  // No error support yet
                    iBus_rsp_payload_pc <= ibus_pc_buf;
                    
                    // Pop FIFO entry
                    ibus_rd_ptr <= ibus_rd_ptr + 1'b1;
                    ibus_state <= IBUS_IDLE;
                end
            endcase
        end
    end
    
    //=================================================================
    // DBus → Port B State Machine
    //=================================================================
    
    typedef enum logic [1:0] {
        DBUS_IDLE,
        DBUS_ACCESS,
        DBUS_RESPOND
    } dbus_state_t;
    
    dbus_state_t dbus_state;
    logic [31:0] dbus_rdata_buf;
    logic        dbus_was_read;

    // FIFO pop signals
    assign dbus_fifo_pop = (dbus_state == DBUS_IDLE) && !dbus_fifo_empty && !cpu_halted;
    assign dbus_fifo_pop_done = (dbus_state == DBUS_RESPOND);  // Count decrements when response sent
    
    always_ff @(posedge clk) begin
        if (rst) begin
            dbus_state <= DBUS_IDLE;
            dbus_rd_ptr <= 1'b0;
            dBus_rsp_ready <= 1'b0;
            dBus_rsp_data <= 32'h0;
            dBus_rsp_error <= 1'b0;
            dbus_rdata_buf <= 32'h0;
            dbus_was_read <= 1'b0;
        end else begin
            case (dbus_state)
                DBUS_IDLE: begin
                    dBus_rsp_ready <= 1'b0;
                    if (dbus_fifo_pop) begin
                        dbus_was_read <= !dbus_fifo_dout.wr;
                        dbus_state <= DBUS_ACCESS;
                    end
                end
                
                DBUS_ACCESS: begin
                    // Wait 1 cycle for BRAM operation
                    if (!dbus_was_read) begin
                        // Write: No read data needed
                        dbus_state <= DBUS_RESPOND;
                    end else begin
                        // Read: Capture data from BRAM output
                        // Note: ram_b_rdata already handles MMIO mux via registered
                        // selection (b_mmio_sel_r) in vexriscv_blockram, so we don't
                        // need to check ram_b_mmio_access here.
                        dbus_rdata_buf <= ram_b_rdata;
                        dbus_state <= DBUS_RESPOND;
                    end
                end
                
                DBUS_RESPOND: begin
                    // Send response to VexRiscv
                    if (dbus_was_read) begin
                        dBus_rsp_ready <= 1'b1;
                        dBus_rsp_data <= dbus_rdata_buf;
                        dBus_rsp_error <= 1'b0;
                    end
                    
                    // Pop FIFO entry
                    dbus_rd_ptr <= ~dbus_rd_ptr;
                    dbus_state <= DBUS_IDLE;
                end
            endcase
        end
    end
    
    //=================================================================
    // Debug Interface State Machine
    //=================================================================
    
    typedef enum logic [1:0] {
        DBG_IDLE,
        DBG_ACCESS,
        DBG_RESPOND
    } dbg_state_t;
    
    dbg_state_t dbg_state;
    logic [31:0] dbg_rdata_buf;
    logic        dbg_was_read;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            dbg_state <= DBG_IDLE;
            dbg_mem_rdata <= 32'h0;
            dbg_mem_busy <= 1'b0;
            dbg_rdata_buf <= 32'h0;
            dbg_was_read <= 1'b0;
        end else begin
            case (dbg_state)
                DBG_IDLE: begin
                    dbg_mem_busy <= 1'b0;
                    if (cpu_halted && (dbg_mem_re || (|dbg_mem_we))) begin
                        dbg_mem_busy <= 1'b1;
                        dbg_was_read <= dbg_mem_re;
                        dbg_state <= DBG_ACCESS;
                    end
                end
                
                DBG_ACCESS: begin
                    // Wait 1 cycle for BRAM operation
                    if (dbg_was_read) begin
                        dbg_rdata_buf <= ram_a_rdata;  // Debug uses Port A
                    end
                    dbg_state <= DBG_RESPOND;
                end
                
                DBG_RESPOND: begin
                    if (dbg_was_read) begin
                        dbg_mem_rdata <= dbg_rdata_buf;
                    end
                    dbg_mem_busy <= 1'b0;
                    dbg_state <= DBG_IDLE;
                end
            endcase
        end
    end
    
    //=================================================================
    // Port A Multiplexer (IBus / Debug)
    //=================================================================
    
    always_comb begin
        if (cpu_halted && (dbg_mem_re || (|dbg_mem_we))) begin
            // Debug access (active check, not state-based)
            ram_a_en        = 1'b1;
            ram_a_addr      = dbg_mem_addr;
            ram_a_we        = dbg_mem_we;
            ram_a_wdata     = dbg_mem_wdata;
            ram_a_byte_addr = {dbg_mem_addr, 2'b00};
        end else if (ibus_state == IBUS_IDLE && ibus_fifo_pop) begin
            // IBus read
            ram_a_en        = 1'b1;
            ram_a_addr      = 11'((ibus_fifo_dout.pc - 32'h80000000) >> 2);  // Subtract base, convert to word addr, mask to 11-bit
            ram_a_we        = 4'b0000;
            ram_a_wdata     = 32'h0;
            ram_a_byte_addr = ibus_fifo_dout.pc;
        end else begin
            // Idle
            ram_a_en        = 1'b0;
            ram_a_addr      = 11'h000;
            ram_a_we        = 4'b0000;
            ram_a_wdata     = 32'h0;
            ram_a_byte_addr = 32'h0;
        end
    end
    
    //=================================================================
    // Port B Multiplexer (DBus / Debug)
    //=================================================================
    
    always_comb begin
        if (cpu_halted && (dbg_state != DBG_IDLE)) begin
            // Debug access (fallback to Port B if needed)
            ram_b_en        = 1'b0;  // Debug uses Port A primarily
            ram_b_addr      = 11'h000;
            ram_b_we        = 4'b0000;
            ram_b_wdata     = 32'h0;
            ram_b_byte_addr = 32'h0;
        end else if (dbus_state == DBUS_IDLE && dbus_fifo_pop) begin
            // DBus access
            ram_b_en        = 1'b1;
            ram_b_addr      = 11'((dbus_fifo_dout.address - 32'h80000000) >> 2);  // Subtract base, convert to word addr, mask to 11-bit
            ram_b_we        = dbus_fifo_dout.wr ? dbus_fifo_dout.mask : 4'b0000;
            ram_b_wdata     = dbus_fifo_dout.data;
            ram_b_byte_addr = dbus_fifo_dout.address;
        end else begin
            // Idle
            ram_b_en        = 1'b0;
            ram_b_addr      = 11'h000;
            ram_b_we        = 4'b0000;
            ram_b_wdata     = 32'h0;
            ram_b_byte_addr = 32'h0;
        end
    end
    
    //=================================================================
    // Block RAM Instance
    //=================================================================
    
    vexriscv_blockram #(
        .ADDR_WIDTH(11),
        .DATA_WIDTH(32)
    ) blockram_inst (
        .clk(clk),
        .rst(rst),
        
        // Port A
        .a_en(ram_a_en),
        .a_addr(ram_a_addr),
        .a_we(ram_a_we),
        .a_wdata(ram_a_wdata),
        .a_rdata(ram_a_rdata),
        .a_byte_addr(ram_a_byte_addr),
        .a_mmio_access(ram_a_mmio_access),
        
        // Port B
        .b_en(ram_b_en),
        .b_addr(ram_b_addr),
        .b_we(ram_b_we),
        .b_wdata(ram_b_wdata),
        .b_rdata(ram_b_rdata),
        .b_byte_addr(ram_b_byte_addr),
        .b_mmio_access(ram_b_mmio_access),
        
        // MMIO LED
        .led_reg_wdata(led_reg_wdata),
        .led_reg_we(led_reg_we),
        .led_reg_rdata(led_reg_rdata)
    );
    
    //=================================================================
    // Waveform Logging (Simulation Only)
    //=================================================================
    
    `ifdef SIMULATION
    always_ff @(posedge clk) begin
        if (!rst && ibus_fifo_push) begin
            $display("[CROSSBAR] IBus CMD: pc=0x%08X (fifo_count=%0d)", 
                     iBus_cmd_payload_pc, ibus_fifo_count + 1);
        end
        if (!rst && iBus_rsp_valid) begin
            $display("[CROSSBAR] IBus RSP: inst=0x%08X", iBus_rsp_payload_inst);
        end
        if (!rst && dbus_fifo_push) begin
            $display("[CROSSBAR] DBus CMD: %s addr=0x%08X data=0x%08X mask=%b",
                     dBus_cmd_payload_wr ? "WR" : "RD",
                     dBus_cmd_payload_address, dBus_cmd_payload_data, dBus_cmd_payload_mask);
        end
        if (!rst && dBus_rsp_ready) begin
            $display("[CROSSBAR] DBus RSP: data=0x%08X", dBus_rsp_data);
        end
        if (!rst && cpu_halted && dbg_state == DBG_ACCESS) begin
            $display("[CROSSBAR] Debug %s: addr=0x%08X data=0x%08X",
                     dbg_was_read ? "READ" : "WRITE",
                     {dbg_mem_addr, 2'b00}, dbg_was_read ? 32'h0 : dbg_mem_wdata);
        end
        if (!rst && ibus_fifo_full && iBus_cmd_valid) begin
            $warning("[CROSSBAR] IBus FIFO full, stalling fetch (pc=0x%08X)", iBus_cmd_payload_pc);
        end
    end
    `endif

endmodule
