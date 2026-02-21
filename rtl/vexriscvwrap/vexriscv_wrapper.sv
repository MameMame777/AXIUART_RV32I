`timescale 1ns / 1ps
//=====================================================================
// VexRiscv Wrapper - Generated RTL Integration
//=====================================================================
// Description:
//   Top-level wrapper integrating SpinalHDL-generated VexRiscv CPU
//   with AXIUART infrastructure.
//
//   Replaces hand-written vexriscv_top.sv and internal pipeline modules
//   with the generated VexRiscv.v core + adapter infrastructure.
//
// Components:
//   - VexRiscv: Generated CPU core (SpinalHDL)
//   - vexriscv_ibus_adapter: IBus interface adaptation
//   - vexriscv_dbus_adapter: DBus interface adaptation  
//   - vexriscv_debug_bridge: DebugPlugin protocol bridge
//   - vexriscv_mem_crossbar: Memory arbitration
//   - vexriscv_blockram: 8KB dual-port BRAM
//   - vexriscv_ebreak_monitor: EBREAK detection
//   - vexriscv_control: Run/halt FSM
//   - vexriscv_trace_probe: Execution trace capture
//
// Interface Compatibility:
//   Maintains identical interface to Register_Block as previous wrapper.
//
// Author: GitHub Copilot (Claude Opus 4.5)
// Date: February 6, 2026
//=====================================================================

module vexriscv_wrapper (
    input  logic        clk,
    input  logic        rst,
    
    //=================================================================
    // Debug Memory Interface (from Register_Block via AXIUART)
    //=================================================================
    input  logic [11:0] rv32i_mem_addr,     // Word address (0-4095 for 16KB)
    input  logic [31:0] rv32i_mem_wdata,    // Write data
    output logic [31:0] rv32i_mem_rdata,    // Read data
    input  logic [3:0]  rv32i_mem_we,       // Byte write enables
    input  logic        rv32i_mem_re,       // Read enable
    
    //=================================================================
    // CPU Control Interface (from Register_Block via AXIUART)
    //=================================================================
    input  logic        rv32i_cpu_run,      // Start CPU execution
    input  logic        rv32i_cpu_halt,     // Stop CPU execution
    input  logic        rv32i_cpu_step,     // Single-step pulse
    output logic        rv32i_cpu_halted,   // CPU is halted
    output logic        rv32i_cpu_break,    // EBREAK detected

    //=================================================================
    // Breakpoint / Register Snapshot Interface
    //=================================================================
    input  logic [3:0]  rv32i_dbg_bp_enable,
    input  logic [31:0] rv32i_dbg_bp_addr [0:3],
    output logic [3:0]  rv32i_dbg_bp_hit,
    input  logic [4:0]  rv32i_dbg_rf_addr,
    output logic [31:0] rv32i_dbg_rf_rdata,
    input  logic        rv32i_dbg_soft_reset,
    output logic        rv32i_dbg_reset_done,

    //=================================================================
    // Performance Counters (exposed via Register_Block)
    //=================================================================
    output logic [31:0] rv32i_perf_cycle_count,
    output logic [31:0] rv32i_perf_insn_count,
    output logic [31:0] rv32i_perf_stall_count,
    output logic [31:0] rv32i_perf_flush_count,

    //=================================================================
    // Trace Buffer Interface (exposed via Register_Block)
    //=================================================================
    input  logic [5:0]  rv32i_dbg_trace_addr,  // Trace entry index
    output logic [191:0] rv32i_dbg_trace_data, // Trace entry data
    output logic [5:0]  rv32i_dbg_trace_wptr,  // Write pointer
    output logic [5:0]  rv32i_dbg_trace_count, // Entry count
    
    //=================================================================
    // LED Output (memory-mapped at 0x8000407C)
    //=================================================================
    output logic [3:0]  rv32i_led           // LED state
);

    //=================================================================
    // Internal Wires - VexRiscv Core Interface
    //=================================================================
    
    // IBus (to VexRiscv core)
    logic        vex_iBus_cmd_valid;
    logic        vex_iBus_cmd_ready;
    logic [31:0] vex_iBus_cmd_payload_pc;
    logic        vex_iBus_rsp_valid;
    logic        vex_iBus_rsp_payload_error;
    logic [31:0] vex_iBus_rsp_payload_inst;
    
    // DBus (to VexRiscv core)
    logic        vex_dBus_cmd_valid;
    logic        vex_dBus_cmd_ready;
    logic        vex_dBus_cmd_payload_wr;
    logic [3:0]  vex_dBus_cmd_payload_mask;
    logic [31:0] vex_dBus_cmd_payload_address;
    logic [31:0] vex_dBus_cmd_payload_data;
    logic [1:0]  vex_dBus_cmd_payload_size;
    logic        vex_dBus_rsp_ready;
    logic        vex_dBus_rsp_error;
    logic [31:0] vex_dBus_rsp_data;
    
    // Debug Bus (to VexRiscv core)
    logic        debug_bus_cmd_valid;
    logic        debug_bus_cmd_ready;
    logic        debug_bus_cmd_payload_wr;
    logic [7:0]  debug_bus_cmd_payload_address;
    logic [31:0] debug_bus_cmd_payload_data;
    logic [31:0] debug_bus_rsp_data;
    logic        debug_resetOut;
    
    // Interrupts (unused)
    logic        timerInterrupt;
    logic        externalInterrupt;
    logic        softwareInterrupt;
    
    assign timerInterrupt    = 1'b0;
    assign externalInterrupt = 1'b0;
    assign softwareInterrupt = 1'b0;
    
    //=================================================================
    // Internal Wires - Memory Crossbar Interface
    //=================================================================
    
    // IBus (from crossbar)
    logic        mem_iBus_cmd_valid;
    logic        mem_iBus_cmd_ready;
    logic [31:0] mem_iBus_cmd_payload_pc;
    logic        mem_iBus_rsp_valid;
    logic        mem_iBus_rsp_payload_error;
    logic [31:0] mem_iBus_rsp_payload_inst;
    logic [31:0] mem_iBus_rsp_payload_pc;
    
    // DBus (from crossbar)
    logic        mem_dBus_cmd_valid;
    logic        mem_dBus_cmd_ready;
    logic        mem_dBus_cmd_payload_wr;
    logic [3:0]  mem_dBus_cmd_payload_mask;
    logic [31:0] mem_dBus_cmd_payload_address;
    logic [31:0] mem_dBus_cmd_payload_data;
    logic [1:0]  mem_dBus_cmd_payload_size;
    logic        mem_dBus_rsp_ready;
    logic        mem_dBus_rsp_error;
    logic [31:0] mem_dBus_rsp_data;
    
    //=================================================================
    // Internal Wires - Control/Status
    //=================================================================
    
    logic        cpu_reset;
    logic        cpu_running;
    logic        cpu_effective_halted;
    logic        cpu_boot_hold_reset;
    logic        cpu_run_pulse;
    logic        cpu_run_reset_pulse;
    logic [3:0]  cpu_run_reset_cnt;
    logic        rv32i_cpu_run_d;
    logic        cpu_control_reset;
    logic        cpu_control_running;
    logic        ctrl_cpu_halted;
    logic        dbg_cpu_halted;   // From debug bridge
    
    // EBREAK monitor
    logic        ebreak_detected;
    logic        ebreak_detected_raw;
    logic [31:0] break_pc;
    logic        clear_break;
    localparam logic [31:0] EBREAK_OPCODE = 32'h0010_0073;

    // EBREAK auto-halt: latch that generates a halt edge for the debug bridge
    // when EBREAK is first detected, ensuring VexRiscv actually stops.
    logic        ebreak_prev;
    logic        ebreak_halt_latch;
    logic        combined_cpu_halt;
    
    // Memory crossbar debug
    logic        dbg_mem_busy;
    logic [3:0]  dbg_bp_hit_comb;
    
    // LED register (MMIO)
    logic [31:0] led_reg_wdata;
    logic        led_reg_we;
    logic [31:0] led_reg_rdata;
    logic [31:0] led_register;
    logic [31:0] dbg_rf_rdata_reg;
    logic [31:0] dbg_rf_shadow [0:31];

    // Hierarchical probe signals (declared early for EBREAK logic use)
    logic [31:0] probe_writeBack_PC;
    logic [31:0] probe_writeBack_INSTRUCTION;
    logic        probe_writeBack_REGFILE_WRITE_VALID;
    logic [4:0]  probe_writeBack_REGFILE_WRITE_ADDR;
    logic [31:0] probe_writeBack_REGFILE_WRITE_DATA;
    logic        probe_writeBack_arbitration_isFiring;
    logic        probe_decode_arbitration_isStuckByOthers;
    logic        probe_decode_arbitration_flushNext;
    
    // Debug bridge is the control owner for run/halt/step/reset.
    // Keep core in reset until first RUN pulse so code load completes deterministically.
    always_ff @(posedge clk) begin
        if (rst || rv32i_dbg_soft_reset || debug_resetOut) begin
            rv32i_cpu_run_d <= 1'b0;
            cpu_boot_hold_reset <= 1'b1;
            cpu_run_reset_cnt <= 4'b0000;
        end else begin
            rv32i_cpu_run_d <= rv32i_cpu_run;
            if (rv32i_cpu_run && !rv32i_cpu_run_d) begin
                if (ebreak_detected) begin
                    cpu_run_reset_cnt <= 4'hF;
                end else begin
                    cpu_run_reset_cnt <= 4'h3;
                end
            end else if (cpu_run_reset_cnt != 4'b0000) begin
                cpu_run_reset_cnt <= cpu_run_reset_cnt - 1'b1;
            end
            if (rv32i_cpu_run && !rv32i_cpu_run_d) begin
                cpu_boot_hold_reset <= 1'b0;
            end
        end
    end

    assign cpu_run_reset_pulse = (cpu_run_reset_cnt != 4'b0000);
    assign cpu_run_pulse = rv32i_cpu_run && !rv32i_cpu_run_d;
    assign cpu_effective_halted = dbg_cpu_halted || ebreak_detected;
    assign rv32i_cpu_halted = cpu_effective_halted;
    assign rv32i_cpu_break = ebreak_detected;
    assign cpu_running = ~cpu_effective_halted;
    assign cpu_reset = cpu_boot_hold_reset || rv32i_dbg_soft_reset || debug_resetOut || cpu_run_reset_pulse;
    assign clear_break = cpu_run_pulse;
    assign rv32i_dbg_reset_done = ~cpu_reset;

    // Detect EBREAK when instruction reaches execute stage with ENV=EBREAK.
    assign ebreak_detected_raw = cpu_core.execute_arbitration_isValid &&
                                 (cpu_core.execute_ENV_CTRL == 2'd3);

    always_ff @(posedge clk) begin
        if (rst || clear_break) begin
            ebreak_detected <= 1'b0;
            break_pc <= 32'h0000_0000;
        end else if (ebreak_detected_raw && cpu_running) begin
            ebreak_detected <= 1'b1;
            break_pc <= cpu_core.execute_PC;
        end
    end

    // EBREAK auto-halt: on rising edge of ebreak_detected, latch a halt request.
    // This creates a rising edge on combined_cpu_halt, which the debug bridge
    // translates into a CTRL_HALT command sent to VexRiscv's DebugPlugin.
    // Without this, EBREAK only sets a status flag while VexRiscv continues
    // executing and traps to mtvec, corrupting the register file.
    always_ff @(posedge clk) begin
        if (rst || clear_break) begin
            ebreak_prev       <= 1'b0;
            ebreak_halt_latch <= 1'b0;
        end else begin
            ebreak_prev <= ebreak_detected;
            if (ebreak_detected && !ebreak_prev)
                ebreak_halt_latch <= 1'b1;
        end
    end
    assign combined_cpu_halt = rv32i_cpu_halt || ebreak_halt_latch;
    
    //=================================================================
    // VexRiscv Generated CPU Core
    //=================================================================
    
    VexRiscv cpu_core (
        .clk(clk),
        .reset(cpu_reset || rst),
        
        // IBus
        .iBus_cmd_valid(vex_iBus_cmd_valid),
        .iBus_cmd_ready(vex_iBus_cmd_ready),
        .iBus_cmd_payload_pc(vex_iBus_cmd_payload_pc),
        .iBus_rsp_valid(vex_iBus_rsp_valid),
        .iBus_rsp_payload_error(vex_iBus_rsp_payload_error),
        .iBus_rsp_payload_inst(vex_iBus_rsp_payload_inst),
        
        // DBus
        .dBus_cmd_valid(vex_dBus_cmd_valid),
        .dBus_cmd_ready(vex_dBus_cmd_ready),
        .dBus_cmd_payload_wr(vex_dBus_cmd_payload_wr),
        .dBus_cmd_payload_mask(vex_dBus_cmd_payload_mask),
        .dBus_cmd_payload_address(vex_dBus_cmd_payload_address),
        .dBus_cmd_payload_data(vex_dBus_cmd_payload_data),
        .dBus_cmd_payload_size(vex_dBus_cmd_payload_size),
        .dBus_rsp_ready(vex_dBus_rsp_ready),
        .dBus_rsp_error(vex_dBus_rsp_error),
        .dBus_rsp_data(vex_dBus_rsp_data),
        
        // Debug Bus
        .debug_bus_cmd_valid(debug_bus_cmd_valid),
        .debug_bus_cmd_ready(debug_bus_cmd_ready),
        .debug_bus_cmd_payload_wr(debug_bus_cmd_payload_wr),
        .debug_bus_cmd_payload_address(debug_bus_cmd_payload_address),
        .debug_bus_cmd_payload_data(debug_bus_cmd_payload_data),
        .debug_bus_rsp_data(debug_bus_rsp_data),
        .debug_resetOut(debug_resetOut),
        
        // Interrupts
        .timerInterrupt(timerInterrupt),
        .externalInterrupt(externalInterrupt),
        .softwareInterrupt(softwareInterrupt)
    );
    
    //=================================================================
    // IBus Adapter
    //=================================================================
    
    vexriscv_ibus_adapter ibus_adapter (
        .clk(clk),
        .rst(rst),
        
        // VexRiscv interface
        .vex_iBus_cmd_valid(vex_iBus_cmd_valid),
        .vex_iBus_cmd_ready(vex_iBus_cmd_ready),
        .vex_iBus_cmd_payload_pc(vex_iBus_cmd_payload_pc),
        .vex_iBus_rsp_valid(vex_iBus_rsp_valid),
        .vex_iBus_rsp_payload_error(vex_iBus_rsp_payload_error),
        .vex_iBus_rsp_payload_inst(vex_iBus_rsp_payload_inst),
        
        // Memory crossbar interface
        .mem_iBus_cmd_valid(mem_iBus_cmd_valid),
        .mem_iBus_cmd_ready(mem_iBus_cmd_ready),
        .mem_iBus_cmd_payload_pc(mem_iBus_cmd_payload_pc),
        .mem_iBus_rsp_valid(mem_iBus_rsp_valid),
        .mem_iBus_rsp_payload_error(mem_iBus_rsp_payload_error),
        .mem_iBus_rsp_payload_inst(mem_iBus_rsp_payload_inst),
        .mem_iBus_rsp_payload_pc(mem_iBus_rsp_payload_pc)
    );
    
    //=================================================================
    // DBus Adapter
    //=================================================================
    
    vexriscv_dbus_adapter dbus_adapter (
        .clk(clk),
        .rst(rst),
        
        // VexRiscv interface
        .vex_dBus_cmd_valid(vex_dBus_cmd_valid),
        .vex_dBus_cmd_ready(vex_dBus_cmd_ready),
        .vex_dBus_cmd_payload_wr(vex_dBus_cmd_payload_wr),
        .vex_dBus_cmd_payload_mask(vex_dBus_cmd_payload_mask),
        .vex_dBus_cmd_payload_address(vex_dBus_cmd_payload_address),
        .vex_dBus_cmd_payload_data(vex_dBus_cmd_payload_data),
        .vex_dBus_cmd_payload_size(vex_dBus_cmd_payload_size),
        .vex_dBus_rsp_ready(vex_dBus_rsp_ready),
        .vex_dBus_rsp_error(vex_dBus_rsp_error),
        .vex_dBus_rsp_data(vex_dBus_rsp_data),
        
        // Memory crossbar interface
        .mem_dBus_cmd_valid(mem_dBus_cmd_valid),
        .mem_dBus_cmd_ready(mem_dBus_cmd_ready),
        .mem_dBus_cmd_payload_wr(mem_dBus_cmd_payload_wr),
        .mem_dBus_cmd_payload_mask(mem_dBus_cmd_payload_mask),
        .mem_dBus_cmd_payload_address(mem_dBus_cmd_payload_address),
        .mem_dBus_cmd_payload_data(mem_dBus_cmd_payload_data),
        .mem_dBus_cmd_payload_size(mem_dBus_cmd_payload_size),
        .mem_dBus_rsp_ready(mem_dBus_rsp_ready),
        .mem_dBus_rsp_error(mem_dBus_rsp_error),
        .mem_dBus_rsp_data(mem_dBus_rsp_data)
    );
    
    //=================================================================
    // Debug Bridge
    //=================================================================
    
    vexriscv_debug_bridge debug_bridge (
        .clk(clk),
        .rst(rst),
        
        // Register Block interface
        .reg_cpu_run(rv32i_cpu_run),
        .reg_cpu_halt(combined_cpu_halt),  // combined: explicit halt OR auto-halt on EBREAK
        .reg_cpu_step(rv32i_cpu_step),
        .reg_cpu_reset(rv32i_dbg_soft_reset),
        .reg_cpu_halted(dbg_cpu_halted),
        .reg_debug_resetOut(),
        
        // Breakpoints
        .reg_bp_enable(rv32i_dbg_bp_enable),
        .reg_bp_address(rv32i_dbg_bp_addr),
        
        // VexRiscv Debug Bus
        .debug_bus_cmd_valid(debug_bus_cmd_valid),
        .debug_bus_cmd_ready(debug_bus_cmd_ready),
        .debug_bus_cmd_payload_wr(debug_bus_cmd_payload_wr),
        .debug_bus_cmd_payload_address(debug_bus_cmd_payload_address),
        .debug_bus_cmd_payload_data(debug_bus_cmd_payload_data),
        .debug_bus_rsp_data(debug_bus_rsp_data),
        .debug_resetOut(debug_resetOut)
    );
    
    //=================================================================
    // Memory Crossbar (IBus/DBus/Debug Arbitration)
    //=================================================================
    
    vexriscv_mem_crossbar mem_crossbar (
        .clk(clk),
        .rst(rst),

        // IBus
        .iBus_cmd_valid(mem_iBus_cmd_valid),
        .iBus_cmd_ready(mem_iBus_cmd_ready),
        .iBus_cmd_payload_pc(mem_iBus_cmd_payload_pc),
        .iBus_rsp_valid(mem_iBus_rsp_valid),
        .iBus_rsp_payload_error(mem_iBus_rsp_payload_error),
        .iBus_rsp_payload_inst(mem_iBus_rsp_payload_inst),
        .iBus_rsp_payload_pc(mem_iBus_rsp_payload_pc),
        
        // DBus
        .dBus_cmd_valid(mem_dBus_cmd_valid),
        .dBus_cmd_ready(mem_dBus_cmd_ready),
        .dBus_cmd_payload_wr(mem_dBus_cmd_payload_wr),
        .dBus_cmd_payload_mask(mem_dBus_cmd_payload_mask),
        .dBus_cmd_payload_address(mem_dBus_cmd_payload_address),
        .dBus_cmd_payload_data(mem_dBus_cmd_payload_data),
        .dBus_cmd_payload_size(mem_dBus_cmd_payload_size),
        .dBus_rsp_ready(mem_dBus_rsp_ready),
        .dBus_rsp_error(mem_dBus_rsp_error),
        .dBus_rsp_data(mem_dBus_rsp_data),
        
        // Debug interface
        .dbg_mem_addr(rv32i_mem_addr),
        .dbg_mem_wdata(rv32i_mem_wdata),
        .dbg_mem_rdata(rv32i_mem_rdata),
        .dbg_mem_we(rv32i_mem_we),
        .dbg_mem_re(rv32i_mem_re),
        .dbg_mem_busy(dbg_mem_busy),
        .cpu_halted(rv32i_cpu_halted),
        
        // LED register MMIO
        .led_reg_wdata(led_reg_wdata),
        .led_reg_we(led_reg_we),
        .led_reg_rdata(led_reg_rdata)
    );
    
    //=================================================================
    // CPU Control Module (kept for assertion hierarchy compatibility)
    //=================================================================

    vexriscv_control cpu_control (
        .clk(clk),
        .rst(rst),

        .cpu_run(rv32i_cpu_run),
        .cpu_halt(rv32i_cpu_halt),
        .cpu_step(rv32i_cpu_step),

        .cpu_halted(ctrl_cpu_halted),
        .cpu_break(),

        .cpu_reset(cpu_control_reset),
        .cpu_running(cpu_control_running),

        .ebreak_detected(ebreak_detected),
        .break_pc(break_pc),
        .clear_break()
    );

    //=================================================================
    // Trace Probe (Internal Signal Taps)
    //=================================================================
    
    // Connect via hierarchical references
    // Note: These are internal wires in VexRiscv.v
    assign probe_writeBack_PC = cpu_core.writeBack_PC;
    assign probe_writeBack_INSTRUCTION = cpu_core.writeBack_INSTRUCTION;
    assign probe_writeBack_REGFILE_WRITE_VALID = cpu_core.lastStageRegFileWrite_valid;
    assign probe_writeBack_REGFILE_WRITE_ADDR = cpu_core.lastStageRegFileWrite_payload_address;
    assign probe_writeBack_REGFILE_WRITE_DATA = cpu_core.lastStageRegFileWrite_payload_data;
    assign probe_writeBack_arbitration_isFiring = cpu_core.writeBack_arbitration_isFiring;
    assign probe_decode_arbitration_isStuckByOthers = cpu_core.decode_arbitration_isStuckByOthers;
    assign probe_decode_arbitration_flushNext = cpu_core.decode_arbitration_flushNext;
    
    vexriscv_trace_probe trace_probe (
        .clk(clk),
        .rst(rst),
        
        // Control
        .cpu_running(cpu_running),
        .cpu_reset(cpu_reset),
        
        // VexRiscv internal signals
        .writeBack_PC(probe_writeBack_PC),
        .writeBack_INSTRUCTION(probe_writeBack_INSTRUCTION),
        .writeBack_REGFILE_WRITE_VALID(probe_writeBack_REGFILE_WRITE_VALID),
        .writeBack_REGFILE_WRITE_ADDR(probe_writeBack_REGFILE_WRITE_ADDR),
        .writeBack_REGFILE_WRITE_DATA(probe_writeBack_REGFILE_WRITE_DATA),
        .writeBack_arbitration_isFiring(probe_writeBack_arbitration_isFiring),
        .decode_arbitration_isStuckByOthers(probe_decode_arbitration_isStuckByOthers),
        .decode_arbitration_flushNext(probe_decode_arbitration_flushNext),
        
        // Trace buffer interface
        .trace_addr(rv32i_dbg_trace_addr),
        .trace_data(rv32i_dbg_trace_data),
        .trace_wptr(rv32i_dbg_trace_wptr),
        .trace_count(rv32i_dbg_trace_count)
    );
    
    //=================================================================
    // Performance Counters
    //=================================================================
    
    // Use hierarchical references to CsrPlugin counters
    // mcycle and minstret are exposed by CsrPlugin
    assign rv32i_perf_cycle_count = cpu_core.CsrPlugin_mcycle[31:0];
    assign rv32i_perf_insn_count  = cpu_core.CsrPlugin_minstret[31:0];
    
    // Stall and flush counters derived from pipeline signals
    logic [31:0] stall_count_reg;
    logic [31:0] flush_count_reg;
    
    always_ff @(posedge clk) begin
        if (rst || cpu_reset) begin
            stall_count_reg <= 32'h0;
            flush_count_reg <= 32'h0;
        end else if (cpu_running) begin
            if (probe_decode_arbitration_isStuckByOthers) begin
                stall_count_reg <= stall_count_reg + 1'b1;
            end
            if (probe_decode_arbitration_flushNext) begin
                flush_count_reg <= flush_count_reg + 1'b1;
            end
        end
    end
    
    assign rv32i_perf_stall_count = stall_count_reg;
    assign rv32i_perf_flush_count = flush_count_reg;

    //=================================================================
    // Register file snapshot / breakpoint hit reporting
    //=================================================================

    integer dbg_rf_idx;

    always_ff @(posedge clk) begin
        if (rst || rv32i_dbg_soft_reset || debug_resetOut || cpu_reset) begin
            for (dbg_rf_idx = 0; dbg_rf_idx < 32; dbg_rf_idx = dbg_rf_idx + 1) begin
                dbg_rf_shadow[dbg_rf_idx] <= 32'h0000_0000;
            end
        end else if (probe_writeBack_arbitration_isFiring &&
                     probe_writeBack_REGFILE_WRITE_VALID &&
                     (probe_writeBack_REGFILE_WRITE_ADDR != 5'd0)) begin
            dbg_rf_shadow[probe_writeBack_REGFILE_WRITE_ADDR] <= probe_writeBack_REGFILE_WRITE_DATA;
        end
    end

    always_ff @(posedge clk) begin
        if (rst || rv32i_dbg_soft_reset || debug_resetOut) begin
            dbg_rf_rdata_reg <= 32'h0000_0000;
        end else if (rv32i_dbg_rf_addr == 5'd0) begin
            dbg_rf_rdata_reg <= 32'h0000_0000;
        end else begin
            dbg_rf_rdata_reg <= dbg_rf_shadow[rv32i_dbg_rf_addr];
        end
    end

    assign rv32i_dbg_rf_rdata = dbg_rf_rdata_reg;

    always_comb begin
        dbg_bp_hit_comb[0] = rv32i_dbg_bp_enable[0] && (break_pc == rv32i_dbg_bp_addr[0]);
        dbg_bp_hit_comb[1] = rv32i_dbg_bp_enable[1] && (break_pc == rv32i_dbg_bp_addr[1]);
        dbg_bp_hit_comb[2] = rv32i_dbg_bp_enable[2] && (break_pc == rv32i_dbg_bp_addr[2]);
        dbg_bp_hit_comb[3] = rv32i_dbg_bp_enable[3] && (break_pc == rv32i_dbg_bp_addr[3]);
    end

    always_ff @(posedge clk) begin
        if (rst || cpu_reset || clear_break || !ebreak_detected) begin
            rv32i_dbg_bp_hit <= 4'b0000;
        end else begin
            rv32i_dbg_bp_hit <= dbg_bp_hit_comb;
        end
    end
    
    //=================================================================
    // LED Register (MMIO at 0x8000407C)
    //=================================================================
    
    always_ff @(posedge clk) begin
        if (rst) begin
            led_register <= 32'h0000_0000;
        end else if (led_reg_we) begin
            led_register <= led_reg_wdata;
        end
    end
    
    assign led_reg_rdata = led_register;
    assign rv32i_led = led_register[3:0];
    
    //=================================================================
    // Debug Logging (Simulation Only)
    //=================================================================
    
    `ifdef SIMULATION
    // CPU state logging
    always_ff @(posedge clk) begin
        if (!rst && rv32i_cpu_run && rv32i_cpu_halted) begin
            $display("[VEXRISCV_WRAPPER] CPU START requested");
        end
        if (!rst && rv32i_cpu_halt && !rv32i_cpu_halted) begin
            $display("[VEXRISCV_WRAPPER] CPU HALT requested");
        end
    end
    
    // Debug memory access logging
    always_ff @(posedge clk) begin
        if (!rst && rv32i_cpu_halted && (rv32i_mem_re || (|rv32i_mem_we))) begin
            $display("[VEXRISCV_WRAPPER] Debug %s: addr=0x%08X data=0x%08X we=%b",
                     rv32i_mem_re ? "READ" : "WRITE",
                     {rv32i_mem_addr, 2'b00},
                     rv32i_mem_re ? rv32i_mem_rdata : rv32i_mem_wdata,
                     rv32i_mem_we);
        end
    end
    
    // LED register write logging
    always_ff @(posedge clk) begin
        if (!rst && led_reg_we) begin
            $display("[VEXRISCV_WRAPPER] LED register write: 0x%08X (LED[3:0]=%b)",
                     led_reg_wdata, led_reg_wdata[3:0]);
        end
    end
    
    // EBREAK logging
    always_ff @(posedge clk) begin
        if (!rst && ebreak_detected && cpu_running) begin
            $display("[VEXRISCV_WRAPPER] EBREAK detected at PC=0x%08X", break_pc);
        end
    end
    `endif

endmodule
