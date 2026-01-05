`timescale 1ns / 1ps
//==============================================================================
// Bind RV32I IF Stage Assertions to DUT
//==============================================================================
// This file binds the rv32i_if_timing_spec assertion module to the
// rv32i_if instance within the DUT hierarchy (rv32i_top.u_if).
//==============================================================================

bind rv32i_if rv32i_if_timing_spec u_if_assertions (
    .pc_current(pc_current),
    .if_stall(if_stall),
    .if_flush(if_flush),
    .branch_taken(branch_taken),
    .branch_target(branch_target),
    .exception_trap(exception_trap),
    .trap_vector(trap_vector),
    .mret_req(mret_req),
    .mret_pc(mret_pc),
    .insn_in(insn_in),
    .dbg_bp_enable(dbg_bp_enable),
    .dbg_bp_addr(dbg_bp_addr),
    .bp_skip_once(bp_skip_once),
    .running(running),
    .pc_next(pc_next),
    .pc_out(pc_out),
    .insn_out(insn_out),
    .valid_out(valid_out),
    .dbg_bp_hit(dbg_bp_hit),
    .cpu_break(cpu_break),
    .insn_ram_addr(insn_ram_addr)
);
