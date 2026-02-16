`timescale 1ns / 1ps
// UART to AXI4-Lite Bridge with RV32I CPU
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
    output logic [3:0]  led,                 // 4-bit LED control
    
    output logic        led5_r,             // RGB LED Red
    output logic        led5_g,             // RGB LED Green
    output logic        led5_b             // RGB LED Blue
    // Simulation-only outputs
    `ifdef DEFINE_SIM
    // System status outputs
    , output logic        system_busy,
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
    
    // --------------------------------------------------------------------
    // RV32I CPU debug wiring (Register_Block <-> RV32I CPU)
    // --------------------------------------------------------------------
    logic [11:0] rv32i_mem_addr;        // Word address from Register_Block (16KB)
    logic [31:0] rv32i_mem_wdata;       // Write data to RV32I RAM
    logic [31:0] rv32i_mem_rdata;       // Read data from RV32I RAM
    logic [3:0]  rv32i_mem_we;          // Byte write enables
    logic        rv32i_mem_re;          // Read enable
    
    logic        rv32i_cpu_run;         // CPU run signal from Register_Block
    logic        rv32i_cpu_halt;        // CPU halt signal from Register_Block
    logic        rv32i_cpu_step;        // CPU step pulse from Register_Block
    logic        rv32i_cpu_halted;      // CPU halted status
    logic        rv32i_cpu_break;       // EBREAK detected
    logic [3:0]  rv32i_led;             // LED output from RV32I
    logic [3:0]  rv32i_dbg_bp_enable;   // Breakpoint enable mask
    logic [31:0] rv32i_dbg_bp_addr [0:3]; // Breakpoint addresses
    logic [3:0]  rv32i_dbg_bp_hit;      // Breakpoint hit flags
    logic [4:0]  rv32i_dbg_rf_addr;     // Register file read address
    logic [31:0] rv32i_dbg_rf_rdata;    // Register file read data
    logic        rv32i_dbg_soft_reset;  // CPU soft reset pulse
    logic        rv32i_dbg_reset_done;  // CPU reset done status

    // RV32I performance counters
    logic [31:0] rv32i_perf_cycle_count;
    logic [31:0] rv32i_perf_insn_count;
    logic [31:0] rv32i_perf_stall_count;
    logic [31:0] rv32i_perf_flush_count;

    // RV32I trace buffer interface
    logic [5:0]  rv32i_dbg_trace_addr;
    logic [191:0] rv32i_dbg_trace_data;
    logic [5:0]  rv32i_dbg_trace_wptr;
    logic [5:0]  rv32i_dbg_trace_count;
    
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
    
    // RGB LED PWM Control
    // 8-bit PWM counter for brightness control
    logic [7:0] pwm_counter;
    logic [7:0] led_r_brightness;  // Red brightness threshold (0=off, 255=full)
    logic [7:0] led_g_brightness;  // Green brightness threshold
    logic [7:0] led_b_brightness;  // Blue brightness threshold
    
    // PWM counter: Free-running 8-bit counter (488kHz @ 125MHz)
    always_ff @(posedge clk) begin
        if (rst) begin
            pwm_counter <= 8'h00;
        end else begin
            pwm_counter <= pwm_counter + 1'b1;  // Wrap at 255
        end
    end
    
    // Brightness control logic
    localparam int CPU_HALT_BRIGHTNESS = 8'd128;
    localparam int CPU_RUN_BRIGHTNESS  = 8'd128;

    always_ff @(posedge clk) begin
        if (rst) begin
            led_r_brightness <= CPU_HALT_BRIGHTNESS; // Default: 50% brightness (halted at reset)
            led_g_brightness <= 8'd0;                // Default: Off (not running at reset)
            led_b_brightness <= 8'd0;                // Default: Off
        end else begin
            // Red LED: Bright when CPU halted, off when running
            led_r_brightness <= rv32i_cpu_halted ? 8'd255 : 8'd0;
            // Green LED: Bright when CPU running, off when halted
            led_g_brightness <= rv32i_cpu_halted ? 8'd0 : 8'd192;
            // Blue LED: Bright on CPU break
            led_b_brightness <= rv32i_cpu_break ? 8'd255 : 8'd0;
        end
    end
    
    // PWM output generation: LED on when counter < brightness
    always_ff @(posedge clk) begin
        if (rst) begin
            led5_r <= 1'b0;
            led5_g <= 1'b0;
            led5_b <= 1'b0;
        end else begin
            led5_r <= (pwm_counter < led_r_brightness);
            led5_g <= (pwm_counter < led_g_brightness);
            led5_b <= (pwm_counter < led_b_brightness);
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
        .fifo_status(fifo_status),
        
        // RV32I CPU memory debug interface
        .rv32i_mem_addr(rv32i_mem_addr),
        .rv32i_mem_wdata(rv32i_mem_wdata),
        .rv32i_mem_rdata(rv32i_mem_rdata),
        .rv32i_mem_we(rv32i_mem_we),
        .rv32i_mem_re(rv32i_mem_re),
        .rv32i_cpu_run(rv32i_cpu_run),
        .rv32i_cpu_halt(rv32i_cpu_halt),
        .rv32i_cpu_step(rv32i_cpu_step),
        .rv32i_cpu_halted(rv32i_cpu_halted),
        .rv32i_cpu_break(rv32i_cpu_break),

        // RV32I hardware breakpoint interface
        .rv32i_dbg_bp_enable(rv32i_dbg_bp_enable),
        .rv32i_dbg_bp_addr(rv32i_dbg_bp_addr),
        .rv32i_dbg_bp_hit(rv32i_dbg_bp_hit),

        // RV32I performance counters
        .rv32i_perf_cycle_count(rv32i_perf_cycle_count),
        .rv32i_perf_insn_count(rv32i_perf_insn_count),
        .rv32i_perf_stall_count(rv32i_perf_stall_count),
        .rv32i_perf_flush_count(rv32i_perf_flush_count),

        // RV32I register file snapshot interface
        .rv32i_dbg_rf_addr(rv32i_dbg_rf_addr),
        .rv32i_dbg_rf_rdata(rv32i_dbg_rf_rdata),

        // RV32I trace buffer interface
        .rv32i_dbg_trace_addr(rv32i_dbg_trace_addr),
        .rv32i_dbg_trace_data(rv32i_dbg_trace_data),
        .rv32i_dbg_trace_wptr(rv32i_dbg_trace_wptr),
        .rv32i_dbg_trace_count(rv32i_dbg_trace_count),

        // RV32I software reset interface
        .rv32i_dbg_soft_reset(rv32i_dbg_soft_reset),
        .rv32i_dbg_reset_done(rv32i_dbg_reset_done)
    );

    // --------------------------------------------------------------------
    // VexRiscv CPU Core Instantiation
    // --------------------------------------------------------------------
    // VexRiscv GenSmallAndProductive CPU with UART debug interface
    vexriscv_wrapper vexriscv_inst (
        .clk(clk),
        .rst(rst),
        
        // Debug memory interface (from Register_Block via UART)
        .rv32i_mem_addr(rv32i_mem_addr),
        .rv32i_mem_wdata(rv32i_mem_wdata),
        .rv32i_mem_rdata(rv32i_mem_rdata),
        .rv32i_mem_we(rv32i_mem_we),
        .rv32i_mem_re(rv32i_mem_re),
        
        // CPU control (from Register_Block via UART)
        .rv32i_cpu_run(rv32i_cpu_run),
        .rv32i_cpu_halt(rv32i_cpu_halt),
        .rv32i_cpu_step(rv32i_cpu_step),
        .rv32i_cpu_halted(rv32i_cpu_halted),
        .rv32i_cpu_break(rv32i_cpu_break),

        // Hardware breakpoints
        .rv32i_dbg_bp_enable(rv32i_dbg_bp_enable),
        .rv32i_dbg_bp_addr(rv32i_dbg_bp_addr),
        .rv32i_dbg_bp_hit(rv32i_dbg_bp_hit),

        // Performance counters
        .rv32i_perf_cycle_count(rv32i_perf_cycle_count),
        .rv32i_perf_insn_count(rv32i_perf_insn_count),
        .rv32i_perf_stall_count(rv32i_perf_stall_count),
        .rv32i_perf_flush_count(rv32i_perf_flush_count),

        // Register file snapshot
        .rv32i_dbg_rf_addr(rv32i_dbg_rf_addr),
        .rv32i_dbg_rf_rdata(rv32i_dbg_rf_rdata),

        // Trace buffer interface
        .rv32i_dbg_trace_addr(rv32i_dbg_trace_addr),
        .rv32i_dbg_trace_data(rv32i_dbg_trace_data),
        .rv32i_dbg_trace_wptr(rv32i_dbg_trace_wptr),
        .rv32i_dbg_trace_count(rv32i_dbg_trace_count),

        // Debug soft reset
        .rv32i_dbg_soft_reset(rv32i_dbg_soft_reset),
        .rv32i_dbg_reset_done(rv32i_dbg_reset_done),
        
        // LED output (MMIO at 0x407C)
        .rv32i_led(rv32i_led)
    );
    
    // LED output from RV32I CPU
    assign led = rv32i_led;
    
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
    
    // AXI4-Lite Address Router and Interconnect
    // System status outputs (simulation only)
    `ifdef DEFINE_SIM
    assign system_busy = bridge_busy;
    assign system_error = bridge_error_code;
    assign system_ready = !system_busy && (bridge_error_code == 8'h00);
    `endif

endmodule
