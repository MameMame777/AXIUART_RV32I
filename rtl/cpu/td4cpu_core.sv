`timescale 1ns / 1ps

import td4cpu_isa_pkg::*;

module td4cpu_core #(
    parameter int RAM_WORDS = 4096
) (
    input  logic        clk,
    input  logic        rst,

    // Debug control inputs (one-cycle pulses)
    input  logic        dbg_halt_req_pulse,
    input  logic        dbg_run_req_pulse,
    input  logic        dbg_step_req_pulse,
    input  logic        dbg_clr_halt_reason_pulse,
    input  logic        dbg_halt_on_reset,

    input  logic        dbg_bp_global_en,
    input  logic        dbg_bp0_en,
    input  logic        dbg_bp1_en,
    input  logic        dbg_bp_match_fetch,
    input  logic [15:0] dbg_bp0_pc,
    input  logic [15:0] dbg_bp1_pc,

    // CPU state outputs for debug readback
    output logic        halted,
    output logic        running,
    output logic        break_hit,
    output logic        brk_hit,
    output logic [7:0]  halt_reason,

    output logic [15:0] pc,
    output logic [15:0] sp,
    output logic [2:0]  flags,

    // Debug write-back into CPU state (honored only while halted)
    input  logic        dbg_wr_pc_pulse,
    input  logic [15:0] dbg_wr_pc_data,
    input  logic        dbg_wr_sp_pulse,
    input  logic [15:0] dbg_wr_sp_data,
    input  logic        dbg_wr_flags_pulse,
    input  logic [2:0]  dbg_wr_flags_data,

    input  logic [2:0]  dbg_reg_index,
    output logic [15:0] dbg_reg_rdata,
    input  logic        dbg_reg_write_pulse,
    input  logic [15:0] dbg_reg_wdata,

    // Debug memory access (honored only while halted)
    input  logic [15:0] dbg_mem_addr,
    input  logic [15:0] dbg_mem_wdata,
    output logic [15:0] dbg_mem_rdata,
    input  logic        dbg_mem_read_req_pulse,
    input  logic        dbg_mem_write_req_pulse,
    output logic        dbg_mem_busy,
    output logic        dbg_mem_err
);

    localparam logic [7:0] HALT_REASON_NONE          = 8'h00;
    localparam logic [7:0] HALT_REASON_RESET_HALT    = 8'h01;
    localparam logic [7:0] HALT_REASON_EXTERNAL_HALT = 8'h02;
    localparam logic [7:0] HALT_REASON_STEP_DONE     = 8'h03;
    localparam logic [7:0] HALT_REASON_BREAKPOINT    = 8'h04;
    localparam logic [7:0] HALT_REASON_BRK           = 8'h05;
    localparam logic [7:0] HALT_REASON_PC_OOB        = 8'h06;

    logic [15:0] regfile [0:7];

    logic [15:0] ram [0:RAM_WORDS-1];

    // Combinational debug read of selected register
    always_comb begin
        dbg_reg_rdata = regfile[dbg_reg_index];
    end

    // Debug memory busy is a one-cycle pulse after request
    logic mem_busy_q;
    assign dbg_mem_busy = mem_busy_q;

    function automatic bit pc_matches_breakpoint(input logic [15:0] pc_in);
        bit hit;
        hit = 1'b0;
        if (dbg_bp_global_en && dbg_bp_match_fetch) begin
            if (dbg_bp0_en && (pc_in == dbg_bp0_pc)) hit = 1'b1;
            if (dbg_bp1_en && (pc_in == dbg_bp1_pc)) hit = 1'b1;
        end
        return hit;
    endfunction

    function automatic bit is_ram_addr_valid(input logic [15:0] a);
        return (a < RAM_WORDS);
    endfunction

    // Minimal instruction handling for bring-up:
    // - BRK causes HALT
    // - everything else treated as NOP (PC increments)
    function automatic bit is_brk_insn(input logic [15:0] insn);
        bit is_sys;
        bit z_ok;
        is_sys = (insn[15:12] == OP_SYS);
        z_ok = (insn[11:3] == 9'h000);
        return is_sys && z_ok && (insn[2:0] == SYSOP_BRK);
    endfunction

    logic step_pending;

    always_ff @(posedge clk) begin
        if (rst) begin
            pc <= 16'h0000;
            sp <= 16'hFFFE;
            flags <= 3'b000;

            halted <= 1'b1;
            running <= 1'b0;
            break_hit <= 1'b0;
            brk_hit <= 1'b0;
            halt_reason <= HALT_REASON_RESET_HALT;

            dbg_mem_rdata <= 16'h0000;
            dbg_mem_err <= 1'b0;
            mem_busy_q <= 1'b0;
            step_pending <= 1'b0;

            for (int i = 0; i < 8; i++) begin
                regfile[i] <= 16'h0000;
            end

            // RAM contents are left uninitialized by default.
            // In simulation, use $readmemh from a testbench if needed.
        end else begin
            mem_busy_q <= 1'b0;

            if (dbg_clr_halt_reason_pulse) begin
                break_hit <= 1'b0;
                brk_hit <= 1'b0;
                halt_reason <= HALT_REASON_NONE;
            end

            // External state changes: halt/run/step
            if (dbg_halt_req_pulse) begin
                halted <= 1'b1;
                running <= 1'b0;
                halt_reason <= HALT_REASON_EXTERNAL_HALT;
                step_pending <= 1'b0;
            end

            if (dbg_run_req_pulse) begin
                halted <= 1'b0;
                running <= 1'b1;
                step_pending <= 1'b0;
            end

            // Debug writes into state are accepted only while halted
            if (halted) begin
                if (dbg_wr_pc_pulse) pc <= dbg_wr_pc_data;
                if (dbg_wr_sp_pulse) sp <= dbg_wr_sp_data;
                if (dbg_wr_flags_pulse) flags <= dbg_wr_flags_data;
                if (dbg_reg_write_pulse) regfile[dbg_reg_index] <= dbg_reg_wdata;

                // Debug memory access (single-cycle)
                if (dbg_mem_read_req_pulse || dbg_mem_write_req_pulse) begin
                    mem_busy_q <= 1'b1;
                    dbg_mem_err <= 1'b0;

                    if (!is_ram_addr_valid(dbg_mem_addr)) begin
                        dbg_mem_err <= 1'b1;
                    end else begin
                        if (dbg_mem_write_req_pulse) begin
                            ram[dbg_mem_addr] <= dbg_mem_wdata;
                        end
                        if (dbg_mem_read_req_pulse) begin
                            dbg_mem_rdata <= ram[dbg_mem_addr];
                        end
                    end
                end
            end else begin
                // If a debug mem op is attempted while running, flag error.
                if (dbg_mem_read_req_pulse || dbg_mem_write_req_pulse) begin
                    mem_busy_q <= 1'b1;
                    dbg_mem_err <= 1'b1;
                end
            end

            // One-instruction step request: halt after next instruction completes
            if (dbg_step_req_pulse) begin
                step_pending <= 1'b1;
                halted <= 1'b0;
                running <= 1'b1;
            end

            // Execution (minimal bring-up): advance PC and stop on BRK/breakpoints
            if (running) begin
                // Breakpoint at fetch boundary
                if (pc_matches_breakpoint(pc)) begin
                    halted <= 1'b1;
                    running <= 1'b0;
                    break_hit <= 1'b1;
                    halt_reason <= HALT_REASON_BREAKPOINT;
                    step_pending <= 1'b0;
                end else if (!is_ram_addr_valid(pc)) begin
                    halted <= 1'b1;
                    running <= 1'b0;
                    halt_reason <= HALT_REASON_PC_OOB;
                    step_pending <= 1'b0;
                end else begin
                    logic [15:0] insn;
                    insn = ram[pc];

                    // Default NOP behavior
                    pc <= pc + 16'd1;

                    if (is_brk_insn(insn)) begin
                        halted <= 1'b1;
                        running <= 1'b0;
                        brk_hit <= 1'b1;
                        halt_reason <= HALT_REASON_BRK;
                        step_pending <= 1'b0;
                    end

                    // If we were stepping, halt after one instruction boundary
                    if (step_pending) begin
                        halted <= 1'b1;
                        running <= 1'b0;
                        halt_reason <= HALT_REASON_STEP_DONE;
                        step_pending <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
