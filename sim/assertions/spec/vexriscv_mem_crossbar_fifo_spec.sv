`timescale 1ns / 1ps
//==============================================================================
// VexRiscv Memory Crossbar FIFO Count Specification
//==============================================================================
// Observer-only assertions for IBus/DBus FIFO count consistency.
//==============================================================================

module vexriscv_mem_crossbar_fifo_spec (
    input logic       clk,
    input logic       rst,
    input logic [2:0] ibus_fifo_count,
    input logic       ibus_fifo_empty,
    input logic       ibus_fifo_full,
    input logic [1:0] dbus_fifo_count,
    input logic       dbus_fifo_empty,
    input logic       dbus_fifo_full
);

    // Assertion: IBus empty implies count is zero
    property p_ibus_empty_count;
        @(posedge clk) disable iff (rst)
        ibus_fifo_empty |-> (ibus_fifo_count == 3'd0);
    endproperty

    a_ibus_empty_count: assert property (p_ibus_empty_count)
        else $error("[CROSSBAR_IBUS] empty asserted with count=%0d", ibus_fifo_count);

    // Assertion: IBus full implies count is max
    property p_ibus_full_count;
        @(posedge clk) disable iff (rst)
        ibus_fifo_full |-> (ibus_fifo_count == 3'd7);
    endproperty

    a_ibus_full_count: assert property (p_ibus_full_count)
        else $error("[CROSSBAR_IBUS] full asserted with count=%0d", ibus_fifo_count);

    // Assertion: IBus count within range
    property p_ibus_count_range;
        @(posedge clk) disable iff (rst)
        (1'b1) |-> (ibus_fifo_count <= 3'd7);
    endproperty

    a_ibus_count_range: assert property (p_ibus_count_range)
        else $error("[CROSSBAR_IBUS] count out of range: %0d", ibus_fifo_count);

    // Assertion: DBus empty implies count is zero
    property p_dbus_empty_count;
        @(posedge clk) disable iff (rst)
        dbus_fifo_empty |-> (dbus_fifo_count == 2'd0);
    endproperty

    a_dbus_empty_count: assert property (p_dbus_empty_count)
        else $error("[CROSSBAR_DBUS] empty asserted with count=%0d", dbus_fifo_count);

    // Assertion: DBus full implies count is max
    property p_dbus_full_count;
        @(posedge clk) disable iff (rst)
        dbus_fifo_full |-> (dbus_fifo_count == 2'd2);
    endproperty

    a_dbus_full_count: assert property (p_dbus_full_count)
        else $error("[CROSSBAR_DBUS] full asserted with count=%0d", dbus_fifo_count);

    // Assertion: DBus count within range
    property p_dbus_count_range;
        @(posedge clk) disable iff (rst)
        (1'b1) |-> (dbus_fifo_count <= 2'd2);
    endproperty

    a_dbus_count_range: assert property (p_dbus_count_range)
        else $error("[CROSSBAR_DBUS] count out of range: %0d", dbus_fifo_count);

endmodule
