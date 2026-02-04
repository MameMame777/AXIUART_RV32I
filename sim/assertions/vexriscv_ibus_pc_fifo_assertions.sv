`timescale 1ns / 1ps
//==============================================================================
// VexRiscv IBus PC FIFO Assertions
//==============================================================================
// Observer-only assertions for PC FIFO sizing, alignment, and flush behavior.
//==============================================================================

module vexriscv_ibus_pc_fifo_assertions (
    input logic        clk,
    input logic        rst,
    input logic        iBusRsp_flush,
    input logic        rspPc_push,
    input logic        rspPc_pop,
    input logic [3:0]  rspPc_count,
    input logic [31:0] rspPc_push_payload,
    input logic [31:0] iBus_rsp_payload_pc
);

    // Assertion: Prevent overflow (push allowed only if a pop also occurs when full)
    property p_rsp_pc_no_overflow;
        @(posedge clk) disable iff (rst)
        (rspPc_count == 4'd8 && rspPc_push) |-> rspPc_pop;
    endproperty

    a_rsp_pc_no_overflow: assert property (p_rsp_pc_no_overflow)
        else $error("[IBUS_PC_FIFO] Overflow risk: push without pop while full");

    // Assertion: Prevent underflow
    property p_rsp_pc_no_underflow;
        @(posedge clk) disable iff (rst)
        (rspPc_count == 4'd0) |-> (!rspPc_pop || rspPc_push);
    endproperty

    a_rsp_pc_no_underflow: assert property (p_rsp_pc_no_underflow)
        else $error("[IBUS_PC_FIFO] Underflow: pop while empty");

    // Assertion: FIFO count consistency with push/pop activity
    property p_rsp_pc_count_consistency;
        @(posedge clk) disable iff (rst)
        (1'b1) |-> (
            (rspPc_push && !rspPc_pop) ? (rspPc_count == ($past(rspPc_count) + 4'd1)) :
            (!rspPc_push && rspPc_pop) ? (rspPc_count == ($past(rspPc_count) - 4'd1)) :
            (rspPc_count == $past(rspPc_count))
        );
    endproperty

    a_rsp_pc_count_consistency: assert property (p_rsp_pc_count_consistency)
        else $error("[IBUS_PC_FIFO] Count mismatch: push/pop vs rspPc_count");

    // Assertion: Flush clears FIFO count
    property p_rsp_pc_flush_clears_count;
        @(posedge clk) disable iff (rst)
        (iBusRsp_flush) |-> (rspPc_count == 4'd0);
    endproperty

    a_rsp_pc_flush_clears_count: assert property (p_rsp_pc_flush_clears_count)
        else $error("[IBUS_PC_FIFO] Flush did not clear FIFO count");

    // Assertion: Push payload matches response PC
    property p_rsp_pc_push_payload_match;
        @(posedge clk) disable iff (rst)
        (rspPc_push) |-> (rspPc_push_payload == iBus_rsp_payload_pc);
    endproperty

    a_rsp_pc_push_payload_match: assert property (p_rsp_pc_push_payload_match)
        else $error("[IBUS_PC_FIFO] Push payload mismatch vs iBus_rsp_payload_pc");

endmodule
