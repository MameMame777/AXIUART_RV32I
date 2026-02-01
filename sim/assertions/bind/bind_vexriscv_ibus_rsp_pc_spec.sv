`timescale 1ns / 1ps
//==============================================================================
// Bind VexRiscv IBus Response/PC Alignment Specification
//==============================================================================

bind vexriscv_ibus_simple vexriscv_ibus_rsp_pc_spec u_vexriscv_ibus_rsp_pc_spec (
    .clk(clk),
    .rst(reset),
    .iBus_cmd_valid(iBus_cmd_valid),
    .iBus_cmd_ready(iBus_cmd_ready),
    .rspBuffer_pop_valid(rspBuffer_pop_valid),
    .rspBuffer_pop_ready(rspBuffer_pop_ready),
    .rspPc_push(rspPc_push),
    .rspPc_pop(rspPc_pop),
    .rspPc_count(rspPc_count)
);
