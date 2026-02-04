`timescale 1ns / 1ps
//=====================================================================
// VexRiscv Wrapper - Compatible with rv32i_top Interface
//=====================================================================
// Description:
//   Top-level wrapper integrating VexRiscv CPU with AXIUART infrastructure
//   - Matches rv32i_top interface exactly (drop-in replacement)
//   - Integrates: vexriscv_top + mem_crossbar + control + ebreak_monitor
//   - UART debug interface for program load/readback
//   - LED MMIO register at 0x407C
//   - EBREAK detection and auto-halt
//
// Interface Compatibility:
//   Input:  rv32i_mem_addr[10:0], rv32i_mem_wdata[31:0], rv32i_mem_we[3:0], rv32i_mem_re
//   Input:  rv32i_cpu_run, rv32i_cpu_halt
//   Output: rv32i_mem_rdata[31:0], rv32i_cpu_halted, rv32i_cpu_break, rv32i_led[3:0]
//
// Memory Map:
//   0x0000-0x1FFF: Block RAM (8KB)
//   0x407C:        LED register (MMIO)
//
// Author: GitHub Copilot (Claude Sonnet 4.5)
// Date: January 17, 2026
//=====================================================================

module vexriscv_wrapper (
    input  logic        clk,
    input  logic        rst,
    
    //=================================================================
    // Debug Memory Interface (from Register_Block via AXIUART)
    //=================================================================
    input  logic [10:0] rv32i_mem_addr,     // Word address (0-2047)
    input  logic [31:0] rv32i_mem_wdata,    // Write data
    output logic [31:0] rv32i_mem_rdata,    // Read data
    input  logic [3:0]  rv32i_mem_we,       // Byte write enables
    input  logic        rv32i_mem_re,       // Read enable
    
    //=================================================================
    // CPU Control Interface (from Register_Block via AXIUART)
    //=================================================================
    input  logic        rv32i_cpu_run,      // Start CPU execution
    input  logic        rv32i_cpu_halt,     // Stop CPU execution
    output logic        rv32i_cpu_halted,   // CPU is halted
    output logic        rv32i_cpu_break,    // EBREAK detected

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
    // LED Output (memory-mapped at 0x407C)
    //=================================================================
    output logic [3:0]  rv32i_led           // LED state
);

    //=================================================================
    // Internal Wires
    //=================================================================
    
    // VexRiscv IBus
    logic        iBus_cmd_valid;
    logic        iBus_cmd_ready;
    logic [31:0] iBus_cmd_payload_pc;
    logic        iBus_rsp_valid;
    logic        iBus_rsp_payload_error;
    logic [31:0] iBus_rsp_payload_inst;
    logic [31:0] iBus_rsp_payload_pc;
    
    // VexRiscv DBus
    logic        dBus_cmd_valid;
    logic        dBus_cmd_ready;
    logic        dBus_cmd_payload_wr;
    logic [3:0]  dBus_cmd_payload_mask;
    logic [31:0] dBus_cmd_payload_address;
    logic [31:0] dBus_cmd_payload_data;
    logic [1:0]  dBus_cmd_payload_size;
    logic        dBus_rsp_ready;
    logic        dBus_rsp_error;
    logic [31:0] dBus_rsp_data;
    
    // VexRiscv Interrupt (not used yet)
    logic        timerInterrupt;
    logic        externalInterrupt;
    logic        softwareInterrupt;
    
    // CPU control
    logic        cpu_reset;
    logic        cpu_running;
    logic        fetcher_halt_req;  // Halt fetcher until CPU_RUN command
    
    // EBREAK monitor
    logic        ebreak_detected;
    logic [31:0] break_pc;
    logic        clear_break;
    
    // Memory crossbar debug
    logic        dbg_mem_busy;
    
    // LED register (MMIO)
    logic [31:0] led_reg_wdata;
    logic        led_reg_we;
    logic [31:0] led_reg_rdata;
    logic [31:0] led_register;

    // Debug outputs from VexRiscv core
    logic [31:0] debug_pc;
    logic [31:0] debug_instruction;
    logic        debug_writeBack_regWrite;
    logic [4:0]  debug_writeBack_regAddr;
    logic [31:0] debug_writeBack_regData;
    
    // Tie off unused interrupts
    assign timerInterrupt    = 1'b0;
    assign externalInterrupt = 1'b0;
    assign softwareInterrupt = 1'b0;
    
    // Fetcher halt control: prevent PC advancement until CPU_RUN asserted
    assign fetcher_halt_req = !cpu_running;
    
    //=================================================================
    // Debug: Execution trace
    //=================================================================
    
    // Trace instruction fetch
    always_ff @(posedge clk) begin
        if (iBus_cmd_valid && iBus_cmd_ready) begin
            $display("[%0t] [VexRiscv] IBus CMD: PC=0x%08X", $time, iBus_cmd_payload_pc);
        end
        if (iBus_rsp_valid) begin
            $display("[%0t] [VexRiscv] IBus RSP: PC=0x%08X INST=0x%08X", $time, iBus_rsp_payload_pc, iBus_rsp_payload_inst);
        end
    end

    //=================================================================
    // Trace Buffer + Performance Counters
    //=================================================================

    localparam int TRACE_DEPTH = 64;
    localparam int TRACE_PTR_WIDTH = 6;

    logic [191:0] trace_buffer [0:TRACE_DEPTH-1];
    logic [TRACE_PTR_WIDTH-1:0] trace_wptr;
    logic [TRACE_PTR_WIDTH-1:0] trace_count;
    logic stall_seen;
    logic flush_seen;

    // Debug signals from CPU core
    logic debug_writeBack_fire;
    logic debug_stall_any;
    logic debug_flush_any;

    // Expose trace buffer state
    assign rv32i_dbg_trace_wptr = trace_wptr;
    assign rv32i_dbg_trace_count = trace_count;
    assign rv32i_dbg_trace_data = trace_buffer[rv32i_dbg_trace_addr];
    
    //=================================================================
    // VexRiscv CPU Core
    //=================================================================
    
    vexriscv_top cpu_core (
        .clk(clk),
        .reset(cpu_reset || rst),
        
        // IBus
        .iBus_cmd_valid(iBus_cmd_valid),
        .iBus_cmd_ready(iBus_cmd_ready),
        .iBus_cmd_payload_pc(iBus_cmd_payload_pc),
        .iBus_rsp_valid(iBus_rsp_valid),
        .iBus_rsp_payload_error(iBus_rsp_payload_error),
        .iBus_rsp_payload_inst(iBus_rsp_payload_inst),
        .iBus_rsp_payload_pc(iBus_rsp_payload_pc),
        
        // DBus
        .dBus_cmd_valid(dBus_cmd_valid),
        .dBus_cmd_ready(dBus_cmd_ready),
        .dBus_cmd_payload_wr(dBus_cmd_payload_wr),
        .dBus_cmd_payload_mask(dBus_cmd_payload_mask),
        .dBus_cmd_payload_address(dBus_cmd_payload_address),
        .dBus_cmd_payload_data(dBus_cmd_payload_data),
        .dBus_cmd_payload_size(dBus_cmd_payload_size),
        .dBus_rsp_ready(dBus_rsp_ready),
        .dBus_rsp_error(dBus_rsp_error),
        .dBus_rsp_data(dBus_rsp_data),
        
        // Interrupts
        .timerInterrupt(timerInterrupt),
        .externalInterrupt(externalInterrupt),
        .softwareInterrupt(softwareInterrupt),
        
        // Fetcher control (UART system specific)
        .fetcher_halt(fetcher_halt_req),

        // Debug outputs
        .debug_pc(debug_pc),
        .debug_instruction(debug_instruction),
        .debug_writeBack_regWrite(debug_writeBack_regWrite),
        .debug_writeBack_regAddr(debug_writeBack_regAddr),
        .debug_writeBack_regData(debug_writeBack_regData),
        .debug_writeBack_fire(debug_writeBack_fire),
        .debug_stall_any(debug_stall_any),
        .debug_flush_any(debug_flush_any)
    );
    
    //=================================================================
    // Memory Crossbar (IBus/DBus/Debug Arbitration)
    //=================================================================
    
    vexriscv_mem_crossbar mem_crossbar (
        .clk(clk),
        .rst(cpu_reset || rst),  // Use same reset signal as CPU core
        
        // VexRiscv IBus
        .iBus_cmd_valid(iBus_cmd_valid),
        .iBus_cmd_ready(iBus_cmd_ready),
        .iBus_cmd_payload_pc(iBus_cmd_payload_pc),
        .iBus_rsp_valid(iBus_rsp_valid),
        .iBus_rsp_payload_error(iBus_rsp_payload_error),
        .iBus_rsp_payload_inst(iBus_rsp_payload_inst),
        .iBus_rsp_payload_pc(iBus_rsp_payload_pc),
        
        // VexRiscv DBus
        .dBus_cmd_valid(dBus_cmd_valid),
        .dBus_cmd_ready(dBus_cmd_ready),
        .dBus_cmd_payload_wr(dBus_cmd_payload_wr),
        .dBus_cmd_payload_mask(dBus_cmd_payload_mask),
        .dBus_cmd_payload_address(dBus_cmd_payload_address),
        .dBus_cmd_payload_data(dBus_cmd_payload_data),
        .dBus_cmd_payload_size(dBus_cmd_payload_size),
        .dBus_rsp_ready(dBus_rsp_ready),
        .dBus_rsp_error(dBus_rsp_error),
        .dBus_rsp_data(dBus_rsp_data),
        
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
    // CPU Control Module
    //=================================================================
    
    vexriscv_control cpu_control (
        .clk(clk),
        .rst(rst),
        
        // UART control
        .cpu_run(rv32i_cpu_run),
        .cpu_halt(rv32i_cpu_halt),
        .cpu_step(1'b0),  // Not implemented yet
        
        // Status
        .cpu_halted(rv32i_cpu_halted),
        .cpu_break(rv32i_cpu_break),
        
        // CPU control
        .cpu_reset(cpu_reset),
        .cpu_running(cpu_running),
        
        // EBREAK
        .ebreak_detected(ebreak_detected),
        .break_pc(break_pc),
        .clear_break(clear_break)
    );

    //=================================================================
    // Performance Counter Logic
    //=================================================================

    always_ff @(posedge clk) begin
        if (rst || cpu_reset) begin
            rv32i_perf_cycle_count <= 32'h0;
            rv32i_perf_insn_count <= 32'h0;
            rv32i_perf_stall_count <= 32'h0;
            rv32i_perf_flush_count <= 32'h0;
        end else begin
            if (cpu_running) begin
                rv32i_perf_cycle_count <= rv32i_perf_cycle_count + 1'b1;
                if (debug_writeBack_fire) begin
                    rv32i_perf_insn_count <= rv32i_perf_insn_count + 1'b1;
                end
                if (debug_stall_any) begin
                    rv32i_perf_stall_count <= rv32i_perf_stall_count + 1'b1;
                end
                if (debug_flush_any) begin
                    rv32i_perf_flush_count <= rv32i_perf_flush_count + 1'b1;
                end
            end
        end
    end

    //=================================================================
    // Trace Buffer Write Logic
    //=================================================================

    always_ff @(posedge clk) begin
        if (rst || cpu_reset) begin
            trace_wptr <= '0;
            trace_count <= '0;
            stall_seen <= 1'b0;
            flush_seen <= 1'b0;
        end else begin
            if (cpu_running) begin
                if (debug_stall_any) begin
                    stall_seen <= 1'b1;
                end
                if (debug_flush_any) begin
                    flush_seen <= 1'b1;
                end

                if (debug_writeBack_fire) begin
                    trace_buffer[trace_wptr] <= '0;
                    trace_buffer[trace_wptr][127:96] <= debug_pc;
                    trace_buffer[trace_wptr][95:64] <= debug_instruction;
                    trace_buffer[trace_wptr][63:32] <= debug_writeBack_regData;
                    trace_buffer[trace_wptr][31:27] <= debug_writeBack_regAddr;
                    trace_buffer[trace_wptr][130] <= debug_writeBack_regWrite;
                    trace_buffer[trace_wptr][129] <= flush_seen;
                    trace_buffer[trace_wptr][128] <= stall_seen;

                    trace_wptr <= trace_wptr + 1'b1;
                    if (trace_count != 6'd63) begin
                        trace_count <= trace_count + 1'b1;
                    end

                    stall_seen <= 1'b0;
                    flush_seen <= 1'b0;
                end
            end
        end
    end
    
    //=================================================================
    // EBREAK Monitor
    //=================================================================
    
    vexriscv_ebreak_monitor ebreak_monitor (
        .clk(clk),
        .rst(rst),
        
        // DBus monitoring
        .dBus_cmd_valid(dBus_cmd_valid),
        .dBus_cmd_ready(dBus_cmd_ready),
        .dBus_cmd_payload_wr(dBus_cmd_payload_wr),
        .dBus_cmd_payload_data(dBus_cmd_payload_data),
        .dBus_cmd_payload_address(dBus_cmd_payload_address),
        .dBus_rsp_ready(dBus_rsp_ready),
        .dBus_rsp_data(dBus_rsp_data),
        
        // IBus monitoring
        .iBus_rsp_valid(iBus_rsp_valid),
        .iBus_rsp_payload_inst(iBus_rsp_payload_inst),
        .iBus_cmd_payload_pc(iBus_cmd_payload_pc),
        
        // Control
        .cpu_running(cpu_running),
        .clear_break(clear_break),
        
        // Status
        .cpu_break(ebreak_detected),
        .break_pc(break_pc)
    );
    
    //=================================================================
    // LED Register (MMIO at 0x407C)
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
