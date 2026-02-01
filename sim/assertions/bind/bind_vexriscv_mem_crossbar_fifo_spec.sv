`timescale 1ns / 1ps
//==============================================================================
// Bind VexRiscv Memory Crossbar FIFO Specification
//==============================================================================

bind vexriscv_mem_crossbar vexriscv_mem_crossbar_fifo_spec u_vexriscv_mem_crossbar_fifo_spec (
    .clk(clk),
    .rst(rst),
    .ibus_fifo_count(ibus_fifo_count),
    .ibus_fifo_empty(ibus_fifo_empty),
    .ibus_fifo_full(ibus_fifo_full),
    .dbus_fifo_count(dbus_fifo_count),
    .dbus_fifo_empty(dbus_fifo_empty),
    .dbus_fifo_full(dbus_fifo_full)
);
