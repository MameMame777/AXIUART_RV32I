`timescale 1ns / 1ps
//==============================================================================
// VexRiscv Fetch Cycle Verification Assertions
//==============================================================================
// Purpose: Diagnose why CPU is not fetching instructions after reset
//
// Checks:
//   1. Reset signal synchronization (cpu_reset, rst)
//   2. Boot sequence (fetchPc_booted flag)
//   3. Fetch control (fetcher_halt)
//   4. IBus handshake protocol (cmd_valid, cmd_ready)
//   5. BRAM access (address, data, enable)
//   6. CPU control state machine
//
// This module uses hierarchical paths to access internal signals for debugging.
// It combines SVA assertions with $display statements for immediate feedback.
//
// Author: GitHub Copilot (Claude Sonnet 4.5)
// Date: January 19, 2026
//==============================================================================

module vexriscv_fetch_verification (
    input logic clk,
    input logic rst
);

    //==========================================================================
    // Signal Access via Hierarchical Paths
    //==========================================================================
    
    // Top-level wrapper signals
    logic        cpu_reset;
    logic        cpu_running;
    logic        cpu_halted;
    
    // IBus signals
    logic        iBus_cmd_valid;
    logic        iBus_cmd_ready;
    logic [31:0] iBus_cmd_payload_pc;
    logic        iBus_rsp_valid;
    logic [31:0] iBus_rsp_payload_inst;
    
    // Internal CPU fetch signals (via hierarchy)
    logic        fetchPc_booted;
    logic        fetcher_halt;
    logic [31:0] fetchPc_pcReg;
    logic        fetchPc_output_valid;
    logic        fetchPc_output_ready;
    
    // BRAM signals
    logic        ram_a_en;
    logic [10:0] ram_a_addr;
    logic [31:0] ram_a_rdata;
    
    // Control signals
    logic        rv32i_cpu_run;
    logic        cpu_run_regbit;
    logic        cpu_halt_regbit;
    logic        ebreak_detected;
    logic [2:0]  cpu_state;
    
    // Assign from hierarchy
    assign cpu_reset = $root.rv32i_tb_top.dut.vexriscv_inst.cpu_reset;
    assign cpu_running = $root.rv32i_tb_top.dut.vexriscv_inst.cpu_running;
    assign cpu_halted = $root.rv32i_tb_top.dut.vexriscv_inst.rv32i_cpu_halted;
    
    assign rv32i_cpu_run = $root.rv32i_tb_top.dut.vexriscv_inst.rv32i_cpu_run;
    assign cpu_run_regbit = $root.rv32i_tb_top.dut.register_block_inst.cpu_mem_ctrl_reg[7];
    assign cpu_halt_regbit = $root.rv32i_tb_top.dut.register_block_inst.cpu_mem_ctrl_reg[8];
    
    assign ebreak_detected = $root.rv32i_tb_top.dut.vexriscv_inst.cpu_control.ebreak_detected;
    assign cpu_state = $root.rv32i_tb_top.dut.vexriscv_inst.cpu_control.state;
    
    assign iBus_cmd_valid = $root.rv32i_tb_top.dut.vexriscv_inst.iBus_cmd_valid;
    assign iBus_cmd_ready = $root.rv32i_tb_top.dut.vexriscv_inst.iBus_cmd_ready;
    assign iBus_cmd_payload_pc = $root.rv32i_tb_top.dut.vexriscv_inst.iBus_cmd_payload_pc;
    assign iBus_rsp_valid = $root.rv32i_tb_top.dut.vexriscv_inst.iBus_rsp_valid;
    assign iBus_rsp_payload_inst = $root.rv32i_tb_top.dut.vexriscv_inst.iBus_rsp_payload_inst;
    
    assign fetchPc_booted = $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.u_ibus.fetchPc_booted;
    assign fetcher_halt = $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.u_ibus.fetcher_halt;
    assign fetchPc_pcReg = $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.u_ibus.fetchPc_pcReg;
    assign fetchPc_output_valid = $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.u_ibus.fetchPc_output_valid;
    assign fetchPc_output_ready = $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.u_ibus.fetchPc_output_ready;
    
    assign ram_a_en = $root.rv32i_tb_top.dut.vexriscv_inst.mem_crossbar.blockram_inst.a_en;
    assign ram_a_addr = $root.rv32i_tb_top.dut.vexriscv_inst.mem_crossbar.blockram_inst.a_addr;
    assign ram_a_rdata = $root.rv32i_tb_top.dut.vexriscv_inst.mem_crossbar.blockram_inst.a_rdata;
    
    //==========================================================================
    // Reset Sequence Monitoring
    //==========================================================================
    
    always_ff @(posedge clk) begin
        if ($fell(rst)) begin
            $display("[%0t] [FETCH_VERIFY] System reset released", $time);
        end
        if ($fell(cpu_reset)) begin
            $display("[%0t] [FETCH_VERIFY] CPU reset released", $time);
        end
    end
    
    property p_reset_sync;
        @(posedge clk) (rst && $past(rst)) |-> cpu_reset;
    endproperty

    ast_reset_sync: assert property (p_reset_sync)
        else $error("[FETCH_VERIFY] Reset desynchronized: rst=%b cpu_reset=%b", rst, cpu_reset);

    property p_reset_deassert;
        @(posedge clk) $fell(rst) |-> ##[0:1] !cpu_reset;
    endproperty

    ast_reset_deassert: assert property (p_reset_deassert)
        else $error("[FETCH_VERIFY] CPU reset not deasserted within 1 cycle of rst falling");
    
    //==========================================================================
    // CPU Control Signal Monitoring
    //==========================================================================
    
    // Track timing of control signal transitions
    int cpu_run_to_running_cycles;
    logic [31:0] pc_when_halted_falls;
    logic [31:0] pc_when_boot_completes;
    logic timing_tracking_active;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            cpu_run_to_running_cycles <= 0;
            pc_when_halted_falls <= 32'h0;
            pc_when_boot_completes <= 32'h0;
            timing_tracking_active <= 1'b0;
        end else begin
            // Track cycles from cpu_run to cpu_running
            if ($rose(rv32i_cpu_run)) begin
                cpu_run_to_running_cycles <= 0;
                timing_tracking_active <= 1'b1;
            end else if (timing_tracking_active && !cpu_running) begin
                cpu_run_to_running_cycles <= cpu_run_to_running_cycles + 1;
            end else if ($rose(cpu_running)) begin
                timing_tracking_active <= 1'b0;
            end
            
            // Capture PC when halted falls
            if ($fell(cpu_halted)) begin
                pc_when_halted_falls <= fetchPc_pcReg;
            end
            
            // Capture PC when boot completes
            if ($rose(fetchPc_booted)) begin
                pc_when_boot_completes <= fetchPc_pcReg;
            end
        end
    end
    
    always_ff @(posedge clk) begin
        if ($rose(cpu_run_regbit)) begin
            $display("[%0t] [FETCH_VERIFY] Register bit[7] (CPU RUN) asserted", $time);
        end
        if ($rose(rv32i_cpu_run)) begin
            $display("[%0t] [FETCH_VERIFY] rv32i_cpu_run signal asserted", $time);
        end
        if ($rose(cpu_running)) begin
            $display("[%0t] [FETCH_VERIFY] cpu_running asserted (state machine = RUNNING) state=%0d", $time, cpu_state);
            $display("[%0t] [FETCH_VERIFY] >>> Latency: cpu_run to cpu_running = %0d cycles", $time, cpu_run_to_running_cycles);
            $display("[%0t] [FETCH_VERIFY] >>> PC at boot completion: 0x%h, PC now: 0x%h", $time, pc_when_boot_completes, fetchPc_pcReg);
            if (fetchPc_pcReg != pc_when_boot_completes) begin
                $display("[%0t] [FETCH_VERIFY] >>> WARNING: PC advanced %0d instructions while halted!", 
                         $time, (fetchPc_pcReg - pc_when_boot_completes) >> 2);
            end
        end
        if ($rose(cpu_halted)) begin
            $display("[%0t] [FETCH_VERIFY] *** CPU HALTED *** (cpu_halted asserted) state=%0d cpu_halt_regbit=%b", $time, cpu_state, cpu_halt_regbit);
            $display("[%0t] [FETCH_VERIFY] >>> PC when HALTED rises = 0x%h", $time, fetchPc_pcReg);
        end
        if ($fell(cpu_halted)) begin
            $display("[%0t] [FETCH_VERIFY] CPU RUNNING (cpu_halted deasserted) state=%0d", $time, cpu_state);
            $display("[%0t] [FETCH_VERIFY] >>> PC when HALTED falls = 0x%h", $time, fetchPc_pcReg);
            
            // Check if PC advanced while halted
            if (fetchPc_pcReg != 32'h80000000 && fetchPc_booted) begin
                $display("[%0t] [FETCH_VERIFY] *** WARNING: PC != 0x80000000 when cpu_halted falls! PC=0x%h ***", $time, fetchPc_pcReg);
                $display("[%0t] [FETCH_VERIFY] *** This means PC advanced %0d instructions while halted! ***", 
                         $time, (fetchPc_pcReg - 32'h80000000) >> 2);
            end
        end
        if ($rose(ebreak_detected)) begin
            $display("[%0t] [FETCH_VERIFY] *** EBREAK DETECTED *** PC=%h", $time, fetchPc_pcReg);
        end
        if ($rose(cpu_halt_regbit)) begin
            $display("[%0t] [FETCH_VERIFY] *** Register bit[8] (CPU HALT) asserted ***", $time);
        end
    end
    
    // Check if register bit matches signal
    always_ff @(posedge clk) begin
        if (!rst && (cpu_run_regbit != rv32i_cpu_run)) begin
            $display("[%0t] [FETCH_VERIFY] WARNING: Register bit[7]=%b but rv32i_cpu_run=%b",
                     $time, cpu_run_regbit, rv32i_cpu_run);
        end
    end
    
    // Detect if CPU stuck in halted state
    int halted_cycle_count = 0;
    always_ff @(posedge clk) begin
        if (rst || cpu_reset) begin
            halted_cycle_count <= 0;
        end else if (!rst && !cpu_reset && fetchPc_booted && cpu_halted && !cpu_running) begin
            halted_cycle_count <= halted_cycle_count + 1;
            if (halted_cycle_count == 20) begin
                $error("[FETCH_VERIFY] CPU stuck in HALTED state for 20 cycles after boot");
                $display("[%0t] [FETCH_VERIFY]   cpu_halted=%b cpu_running=%b", $time, cpu_halted, cpu_running);
                $display("[%0t] [FETCH_VERIFY]   cpu_run_regbit=%b rv32i_cpu_run=%b", $time, cpu_run_regbit, rv32i_cpu_run);
            end
        end else begin
            halted_cycle_count <= 0;
        end
    end
    
    //==========================================================================
    // Boot Sequence Monitoring
    //==========================================================================
    
    always_ff @(posedge clk) begin
        if ($rose(fetchPc_booted)) begin
            $display("[%0t] [FETCH_VERIFY] CPU boot complete, fetchPc_booted=1", $time);
            $display("[%0t] [FETCH_VERIFY] Initial PC=0x%08X", $time, fetchPc_pcReg);
        end
    end
    
    property p_boot_after_reset;
        @(posedge clk) disable iff (rst || cpu_reset)
        $fell(cpu_reset) |-> ##[1:20] fetchPc_booted;
    endproperty
    
    ast_boot_after_reset: assert property (p_boot_after_reset)
        else $error("[FETCH_VERIFY] CPU failed to boot within 20 cycles after reset release");
    
    //==========================================================================
    // IBus Handshake Monitoring
    //==========================================================================
    
    always_ff @(posedge clk) begin
        if (iBus_cmd_valid && iBus_cmd_ready) begin
            $display("[%0t] [FETCH_VERIFY] IBus CMD: PC=0x%08X", $time, iBus_cmd_payload_pc);
        end
        if (iBus_rsp_valid) begin
            $display("[%0t] [FETCH_VERIFY] IBus RSP: INST=0x%08X", $time, iBus_rsp_payload_inst);
        end
    end
    
    property p_ibus_ready;
        @(posedge clk) disable iff (rst || cpu_reset)
        iBus_cmd_valid |-> ##[0:5] iBus_cmd_ready;
    endproperty
    
    ast_ibus_ready: assert property (p_ibus_ready)
        else $error("[FETCH_VERIFY] IBus cmd_ready timeout: PC=0x%08X", iBus_cmd_payload_pc);
    
    //==========================================================================
    // BRAM Access Monitoring
    //==========================================================================
    
    always_ff @(posedge clk) begin
        if (ram_a_en && !rst) begin
            $display("[%0t] [FETCH_VERIFY] BRAM READ: addr=0x%03X data=0x%08X", 
                     $time, ram_a_addr, ram_a_rdata);
        end
    end
    
    //==========================================================================
    // First Fetch Tracking
    //==========================================================================
    
    logic first_fetch_seen;
    
    always_ff @(posedge clk) begin
        if (rst || cpu_reset) begin
            first_fetch_seen <= 1'b0;
        end else if (iBus_cmd_valid && iBus_cmd_ready && !first_fetch_seen) begin
            first_fetch_seen <= 1'b1;
            $display("[%0t] [FETCH_VERIFY] ========================================", $time);
            $display("[%0t] [FETCH_VERIFY] FIRST INSTRUCTION FETCH", $time);
            $display("[%0t] [FETCH_VERIFY] PC = 0x%08X", $time, iBus_cmd_payload_pc);
            $display("[%0t] [FETCH_VERIFY] ========================================", $time);
        end
    end
    
    property p_first_fetch_timing;
        @(posedge clk) disable iff (rst)
        $rose(cpu_running) |-> ##[1:50] first_fetch_seen;
    endproperty
    
    ast_first_fetch_timing: assert property (p_first_fetch_timing)
        else $error("[FETCH_VERIFY] No instruction fetch within 50 cycles of cpu_running");
    
    //==========================================================================
    // PC Value Verification
    //==========================================================================
    
    always_ff @(posedge clk) begin
        if ($fell(cpu_reset)) begin
            if (fetchPc_pcReg !== 32'h80000000) begin
                $error("[FETCH_VERIFY] PC after reset = 0x%08X (expected 0x80000000)", fetchPc_pcReg);
            end else begin
                $display("[%0t] [FETCH_VERIFY] PC correctly initialized to 0x80000000", $time);
            end
        end
    end
    
    //==========================================================================
    // Status Report
    //==========================================================================
    
    int status_report_cycle = 0;
    
    always_ff @(posedge clk) begin
        if (!rst && !cpu_reset) begin
            status_report_cycle++;
            if (status_report_cycle == 10 || status_report_cycle == 30) begin
                $display("[%0t] [FETCH_VERIFY] ========== STATUS (cycle %0d after reset) ==========", $time, status_report_cycle);
                $display("[%0t] [FETCH_VERIFY] cpu_reset=%b rst=%b cpu_running=%b cpu_halted=%b", 
                         $time, cpu_reset, rst, cpu_running, cpu_halted);
                $display("[%0t] [FETCH_VERIFY] cpu_run_regbit=%b rv32i_cpu_run=%b",
                         $time, cpu_run_regbit, rv32i_cpu_run);
                $display("[%0t] [FETCH_VERIFY] fetchPc_booted=%b fetcher_halt=%b PC=0x%08X", 
                         $time, fetchPc_booted, fetcher_halt, fetchPc_pcReg);
                $display("[%0t] [FETCH_VERIFY] fetchPc_output_valid=%b ready=%b", 
                         $time, fetchPc_output_valid, fetchPc_output_ready);
                $display("[%0t] [FETCH_VERIFY] iBus_cmd_valid=%b ready=%b PC=0x%08X", 
                         $time, iBus_cmd_valid, iBus_cmd_ready, iBus_cmd_payload_pc);
                $display("[%0t] [FETCH_VERIFY] first_fetch_seen=%b", $time, first_fetch_seen);
                $display("[%0t] [FETCH_VERIFY] ======================================================", $time);
            end
        end else begin
            status_report_cycle = 0;
        end
    end

endmodule
