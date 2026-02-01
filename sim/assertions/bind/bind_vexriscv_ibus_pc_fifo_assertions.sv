`timescale 1ns / 1ps
//==============================================================================
// Bind VexRiscv IBus PC FIFO Assertions
//==============================================================================

bind vexriscv_ibus_simple vexriscv_ibus_pc_fifo_assertions u_vexriscv_ibus_pc_fifo_assertions (
    .clk(clk),
    .rst(reset),
    .iBusRsp_flush(iBusRsp_flush),
    .rspPc_push(rspPc_push),
    .rspPc_pop(rspPc_pop),
    .rspPc_count(rspPc_count),
    .rspPc_push_payload(rspPc_push_payload),
    .iBus_rsp_payload_pc(iBus_rsp_payload_pc)
);
