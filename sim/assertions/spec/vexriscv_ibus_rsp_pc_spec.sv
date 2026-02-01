`timescale 1ns / 1ps
//==============================================================================
// VexRiscv IBus Response/PC Alignment Specification
//==============================================================================
// Observer-only assertions for aligning IBus command/response with PC FIFO.
//==============================================================================

module vexriscv_ibus_rsp_pc_spec (
    input logic       clk,
    input logic       rst,
    input logic       rspBuffer_push_valid,
    input logic       rspBuffer_push_ready,
    input logic       rspBuffer_pop_valid,
    input logic       rspBuffer_pop_ready,
    input logic       rspPc_push,
    input logic       rspPc_pop,
    input logic [3:0] rspPc_count
);

    // Assertion: Response push must push a PC entry
    property p_cmd_push_alignment;
        @(posedge clk) disable iff (rst)
        (rspBuffer_push_valid && rspBuffer_push_ready) |-> rspPc_push;
    endproperty

    a_cmd_push_alignment: assert property (p_cmd_push_alignment)
        else $error("[IBUS_PC] rsp push without rspPc_push");

    // Assertion: Response pop must have a valid PC entry and pop it
    property p_rsp_pop_has_pc;
        @(posedge clk) disable iff (rst)
        (rspBuffer_pop_valid && rspBuffer_pop_ready) |-> (rspPc_pop && ((rspPc_count != 4'd0) || rspPc_push));
    endproperty

    a_rsp_pop_has_pc: assert property (p_rsp_pop_has_pc)
        else $error("[IBUS_PC] rsp pop without valid PC entry");

    // Assertion: No pop when FIFO is empty
    property p_no_pop_when_empty;
        @(posedge clk) disable iff (rst)
        (rspPc_count == 4'd0) |-> (!rspPc_pop || rspPc_push);
    endproperty

    a_no_pop_when_empty: assert property (p_no_pop_when_empty)
        else $error("[IBUS_PC] rspPc_pop asserted while FIFO empty");

    // Assertion: FIFO count stays within legal range
    property p_rsp_pc_count_range;
        @(posedge clk) disable iff (rst)
        (1'b1) |-> (rspPc_count <= 4'd8);
    endproperty

    a_rsp_pc_count_range: assert property (p_rsp_pc_count_range)
        else $error("[IBUS_PC] rspPc_count out of range: %0d", rspPc_count);

endmodule
