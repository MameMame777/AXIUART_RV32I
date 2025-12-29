`timescale 1ns / 1ps
// FIXED BAUD RATE: 115200 bps
module AXIUART_Top #(
    parameter int CLK_FREQ_HZ = 125_000_000,    // System clock frequency (125MHz)
    parameter int UART_OVERSAMPLE = 16,         // UART oversampling factor
    parameter int BAUD_RATE = 115200,           // UART baud rate (FIXED)
    parameter int AXI_TIMEOUT = 2500,           // AXI timeout in clock cycles (20μs @ 125MHz)
    parameter int RX_FIFO_DEPTH = 64,           // RX FIFO depth
    parameter int TX_FIFO_DEPTH = 64,           // TX FIFO depth
    parameter int MAX_LEN = 16,                 // Maximum LEN field value
    parameter int REG_BASE_ADDR = 32'h0000_1000 // Register block base address
)(
    // Clock and reset
    input  logic        clk,
    input  logic        rst,
    
    // UART interface (external connections)
    input  logic        uart_rx,
    output logic        uart_tx,
    output logic        uart_rts_n,         // Request to Send (active low)
    input  logic        uart_cts_n,         // Clear to Send (active low)
    output logic [3:0]  led                 // 4-bit LED control
    
    // Simulation-only outputs
    `ifdef DEFINE_SIM
    // CPU trace outputs for fast UVM verification
    , output logic        cpu_trace_valid,
    output logic [15:0] cpu_trace_insn,
    output logic [15:0] cpu_trace_pc,
    output logic [2:0]  cpu_trace_rd_idx,
    output logic [15:0] cpu_trace_rd_value,
    output logic [2:0]  cpu_trace_rs_idx,
    output logic [15:0] cpu_trace_rs_value,
    output logic [2:0]  cpu_trace_flags,
    
    // System status outputs
    output logic        system_busy,
    output logic [7:0]  system_error,
    output logic        system_ready
    `endif
);

    // Internal AXI4-Lite interface connecting UART bridge to register block
    axi4_lite_if #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) axi_internal (
        .clk(clk),
        .rst(rst)
    );
    
    // Bridge control and status signals
    logic        bridge_reset_stats;
    logic        bridge_soft_reset;  // RESET command from parser
    logic [15:0] baud_div_config;
    logic [7:0]  timeout_config;
    logic [3:0]  debug_mode;
    
    logic        bridge_busy;
    logic [7:0]  bridge_error_code;
    logic [15:0] tx_count;
    logic [15:0] rx_count;
    logic [7:0]  fifo_status;
    
    // LED control is now CPU-driven via MMIO (test_led_internal removed)
    // logic [3:0]  test_led_internal;  // REMOVED - LED now from CPU MMIO

    // --------------------------------------------------------------------
    // TD4CPU debug wiring (Register_Block <-> CPU)
    // --------------------------------------------------------------------
    logic        cpu_halt_req_pulse;
    logic        cpu_run_req_pulse;
    logic        cpu_step_req_pulse;
    logic        cpu_clr_halt_reason_pulse;
    logic        cpu_halt_on_reset;
    logic        cpu_bp_global_en;
    logic        cpu_bp0_en;
    logic        cpu_bp1_en;
    logic        cpu_bp_match_fetch;
    logic [15:0] cpu_bp0_pc;
    logic [15:0] cpu_bp1_pc;

    logic        cpu_halted;
    logic        cpu_running;
    logic        cpu_break_hit;
    logic        cpu_brk_hit;
    logic [7:0]  cpu_halt_reason;

    logic [15:0] cpu_pc;
    logic [15:0] cpu_sp;
    logic [2:0]  cpu_flags;
    logic        cpu_wr_pc_pulse;
    logic [15:0] cpu_wr_pc_data;
    logic        cpu_wr_sp_pulse;
    logic [15:0] cpu_wr_sp_data;
    logic        cpu_wr_flags_pulse;
    logic [2:0]  cpu_wr_flags_data;

    logic [2:0]  cpu_reg_index;
    logic [15:0] cpu_reg_rdata;
    logic        cpu_reg_read_pulse;   // NEW: Read pulse for latch trigger
    logic        cpu_reg_write_pulse;
    logic [15:0] cpu_reg_wdata;

    logic [15:0] cpu_mem_addr;
    logic [15:0] cpu_mem_wdata;
    logic [15:0] cpu_mem_rdata;
    logic        cpu_mem_read_req_pulse;
    logic        cpu_mem_write_req_pulse;
    logic        cpu_mem_auto_inc;
    logic        cpu_mem_busy;
    logic        cpu_mem_err;
    
    // Trace buffer interface (register-based like CPU_MEM)
    logic [7:0]  cpu_trace_buf_addr;  // Derived from Register_Block.cpu_trace_addr_reg
    logic [31:0] cpu_trace_buf_rdata;
    logic [7:0]  cpu_trace_write_ptr;
    logic        cpu_trace_enable;
    logic        cpu_trace_clear_pulse;
    
    // Flow control signals
    logic        rx_fifo_full;
    logic        rx_fifo_high;
    logic        tx_ready;
    
    // Internal reset logic
    logic internal_rst;
    assign internal_rst = rst;
    
    // Top-level UART signal monitoring for debugging - disabled for production
    logic prev_uart_rx, prev_uart_tx;
    always @(posedge clk) begin
        if (rst) begin
            prev_uart_rx <= 1'b1;
            prev_uart_tx <= 1'b1;
        end else begin
            prev_uart_rx <= uart_rx;
            prev_uart_tx <= uart_tx;
        end
    end
    
    // Keep DUT baud rate aligned with UVM driver configuration in all builds
    localparam int EFFECTIVE_BAUD_RATE = BAUD_RATE;

    // UART-AXI4 Bridge instantiation
    Uart_Axi4_Bridge #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(EFFECTIVE_BAUD_RATE),
        .AXI_TIMEOUT(AXI_TIMEOUT),
        .UART_OVERSAMPLE(UART_OVERSAMPLE),
        .RX_FIFO_DEPTH(RX_FIFO_DEPTH),
        .TX_FIFO_DEPTH(TX_FIFO_DEPTH),
        .MAX_LEN(MAX_LEN)
    ) uart_bridge_inst (
        .clk(clk),
        .rst(internal_rst),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .uart_cts_n(uart_cts_n),        // Clear to Send input
        .rx_fifo_full_out(rx_fifo_full),    // RX FIFO status for RTS control
        .rx_fifo_high_out(rx_fifo_high),    // RX FIFO high threshold
        .tx_ready_out(tx_ready),            // TX readiness status
        .axi(axi_internal),  // 内部レジスタブロックに直接接続
        .baud_divisor_cfg(baud_div_config),
        
        // Status monitoring connections
        .bridge_busy(bridge_busy),
        .bridge_error_code(bridge_error_code),
        .tx_transaction_count(tx_count),
        .rx_transaction_count(rx_count),
        .fifo_status_flags(fifo_status),
        .reset_statistics(bridge_reset_stats),
        .soft_reset_request(bridge_soft_reset)  // RESET command output
    );
    
    // Register Block instantiation - UART bridgeからのみアクセス可能
    Register_Block #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32),
        .BASE_ADDR(REG_BASE_ADDR)
    ) register_block_inst (
        .clk(clk),
        .rst(rst),
        .soft_reset_request(bridge_soft_reset),  // Soft reset from RESET command
        .axi(axi_internal.slave),  // UARTブリッジからの内部アクセス
        
        // Control outputs
        .bridge_reset_stats(bridge_reset_stats),
        .baud_div_config(baud_div_config),
        .timeout_config(timeout_config),
        .debug_mode(debug_mode),
        // .test_led(test_led_internal),  // REMOVED - LED now CPU-controlled
        
        // Status inputs
        .bridge_busy(bridge_busy),
        .error_code(bridge_error_code),
        .tx_count(tx_count),
        .rx_count(rx_count),
        .fifo_status(fifo_status)

        // CPU debug interface
        , .cpu_halt_req_pulse(cpu_halt_req_pulse)
        , .cpu_run_req_pulse(cpu_run_req_pulse)
        , .cpu_step_req_pulse(cpu_step_req_pulse)
        , .cpu_clr_halt_reason_pulse(cpu_clr_halt_reason_pulse)
        , .cpu_halt_on_reset(cpu_halt_on_reset)
        , .cpu_bp_global_en(cpu_bp_global_en)
        , .cpu_bp0_en(cpu_bp0_en)
        , .cpu_bp1_en(cpu_bp1_en)
        , .cpu_bp_match_fetch(cpu_bp_match_fetch)
        , .cpu_bp0_pc(cpu_bp0_pc)
        , .cpu_bp1_pc(cpu_bp1_pc)

        , .cpu_halted(cpu_halted)
        , .cpu_running(cpu_running)
        , .cpu_break_hit(cpu_break_hit)
        , .cpu_brk_hit(cpu_brk_hit)
        , .cpu_halt_reason(cpu_halt_reason)

        , .cpu_pc(cpu_pc)
        , .cpu_sp(cpu_sp)
        , .cpu_flags(cpu_flags)
        , .cpu_wr_pc_pulse(cpu_wr_pc_pulse)
        , .cpu_wr_pc_data(cpu_wr_pc_data)
        , .cpu_wr_sp_pulse(cpu_wr_sp_pulse)
        , .cpu_wr_sp_data(cpu_wr_sp_data)
        , .cpu_wr_flags_pulse(cpu_wr_flags_pulse)
        , .cpu_wr_flags_data(cpu_wr_flags_data)

        , .cpu_reg_index(cpu_reg_index)
        , .cpu_reg_rdata(cpu_reg_rdata)
        , .cpu_reg_read_pulse(cpu_reg_read_pulse)   // NEW: Read pulse output
        , .cpu_reg_write_pulse(cpu_reg_write_pulse)
        , .cpu_reg_wdata(cpu_reg_wdata)

        , .cpu_mem_addr(cpu_mem_addr)
        , .cpu_mem_wdata(cpu_mem_wdata)
        , .cpu_mem_rdata(cpu_mem_rdata)
        , .cpu_mem_read_req_pulse(cpu_mem_read_req_pulse)
        , .cpu_mem_write_req_pulse(cpu_mem_write_req_pulse)
        , .cpu_mem_auto_inc(cpu_mem_auto_inc)
        , .cpu_mem_busy(cpu_mem_busy)
        , .cpu_mem_err(cpu_mem_err)
        
        // Trace buffer interface (register-based access like CPU_MEM)
        , .cpu_trace_buf_rdata(cpu_trace_buf_rdata)
        , .cpu_trace_write_ptr(cpu_trace_write_ptr)
        , .cpu_trace_enable(cpu_trace_enable)
        , .cpu_trace_clear_pulse(cpu_trace_clear_pulse)
    );

    // Derive trace buffer address from Register_Block's internal register
    assign cpu_trace_buf_addr = register_block_inst.cpu_trace_addr_reg[7:0];

    // Minimal TD4CPU core (debug + RAM bring-up)
    // RAM reduced to 1024 words (2KB) for initial synthesis
    // Increase after verifying BRAM inference and timing closure
    td4cpu_core #(
        .RAM_WORDS(1024)  // Reduced from 4096 to speed up synthesis
    ) cpu_inst (
        .clk(clk),
        .rst(rst),

        .dbg_halt_req_pulse(cpu_halt_req_pulse),
        .dbg_run_req_pulse(cpu_run_req_pulse),
        .dbg_step_req_pulse(cpu_step_req_pulse),
        .dbg_clr_halt_reason_pulse(cpu_clr_halt_reason_pulse),
        .dbg_halt_on_reset(cpu_halt_on_reset),

        .dbg_bp_global_en(cpu_bp_global_en),
        .dbg_bp0_en(cpu_bp0_en),
        .dbg_bp1_en(cpu_bp1_en),
        .dbg_bp_match_fetch(cpu_bp_match_fetch),
        .dbg_bp0_pc(cpu_bp0_pc),
        .dbg_bp1_pc(cpu_bp1_pc),

        .halted(cpu_halted),
        .running(cpu_running),
        .break_hit(cpu_break_hit),
        .brk_hit(cpu_brk_hit),
        .halt_reason(cpu_halt_reason),

        .pc(cpu_pc),
        .sp(cpu_sp),
        .flags(cpu_flags),

        .dbg_wr_pc_pulse(cpu_wr_pc_pulse),
        .dbg_wr_pc_data(cpu_wr_pc_data),
        .dbg_wr_sp_pulse(cpu_wr_sp_pulse),
        .dbg_wr_sp_data(cpu_wr_sp_data),
        .dbg_wr_flags_pulse(cpu_wr_flags_pulse),
        .dbg_wr_flags_data(cpu_wr_flags_data),

        .dbg_reg_index(cpu_reg_index),
        .dbg_reg_rdata(cpu_reg_rdata),
        .dbg_reg_read_pulse(cpu_reg_read_pulse),   // NEW: Read pulse input
        .dbg_reg_write_pulse(cpu_reg_write_pulse),
        .dbg_reg_wdata(cpu_reg_wdata),

        .dbg_mem_addr(cpu_mem_addr),
        .dbg_mem_wdata(cpu_mem_wdata),
        .dbg_mem_rdata(cpu_mem_rdata),
        .dbg_mem_read_req_pulse(cpu_mem_read_req_pulse),
        .dbg_mem_write_req_pulse(cpu_mem_write_req_pulse),
        .dbg_mem_busy(cpu_mem_busy),
        .dbg_mem_err(cpu_mem_err),
        
        // Trace outputs
        .trace_valid(cpu_trace_valid),
        .trace_insn(cpu_trace_insn),
        .trace_pc(cpu_trace_pc),
        .trace_rd_idx(cpu_trace_rd_idx),
        .trace_rd_value(cpu_trace_rd_value),
        .trace_rs_idx(cpu_trace_rs_idx),
        .trace_rs_value(cpu_trace_rs_value),
        .trace_flags(cpu_trace_flags),
        
        // Trace buffer interface
        .trace_buf_addr(cpu_trace_buf_addr),
        .trace_buf_rdata(cpu_trace_buf_rdata),
        .trace_write_ptr_out(cpu_trace_write_ptr),
        
        // Memory-Mapped IO: LED output
        .led_out(led)  // Direct connection to top-level LED pins
    );
    
    // Hardware Flow Control Logic
    // RTS (Request to Send) - Active Low
    // Assert RTS_n (Low) when system is ready to receive
    always_ff @(posedge clk) begin
        if (rst) begin
            uart_rts_n <= 1'b1;  // Deassert RTS (not ready) on reset
        end else begin
            // Deassert RTS (not ready to receive) when:
            // - RX FIFO is full
            // - RX FIFO is approaching high threshold
            // Otherwise assert RTS (ready to receive)
            uart_rts_n <= rx_fifo_full || rx_fifo_high;
        end
    end
    
    // LED control now from CPU's Memory-Mapped IO (led_out signal connected above)
    // Old: assign led = test_led_internal;  // REMOVED - LED now CPU-controlled
    
    // AXI4-Lite Address Router and Interconnect
    // System status outputs (simulation only)
    `ifdef DEFINE_SIM
    assign system_busy = bridge_busy;
    assign system_error = bridge_error_code;
    assign system_ready = !system_busy && (bridge_error_code == 8'h00);
    `endif

endmodule
