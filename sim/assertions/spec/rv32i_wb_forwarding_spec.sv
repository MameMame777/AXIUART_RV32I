`timescale 1ns / 1ps

//==============================================================================
// RV32I WB Forwarding Correctness Assertions
//==============================================================================
// Validates WB stage forwarding path alignment between selector metadata
// and forwarded data. Critical for catching timing skew bugs.
//
// Author: GitHub Copilot
// Date: 2026-01-12
//==============================================================================

module rv32i_wb_forwarding_spec (
    input  logic        clk,
    input  logic        rst,
    input  logic        soft_reset_active,
    
    // ID/EX pipeline register (forwarding control)
    input  logic        id_ex_valid,
    input  logic [31:0] id_ex_insn,
    input  logic [31:0] id_ex_pc,
    input  logic [4:0]  id_ex_rs1_addr,
    input  logic [4:0]  id_ex_rs2_addr,
    input  logic [1:0]  id_ex_forward_rs1,
    input  logic [1:0]  id_ex_forward_rs2,
    
    // WB stage metadata (delayed for hazard detection)
    input  logic [4:0]  wb_rd_addr_delayed,
    input  logic        wb_rf_wen_delayed,
    
    // WB stage current state
    input  logic [4:0]  wb_rd_addr_current,
    input  logic        wb_rf_wen_current,
    input  logic [31:0] wb_result_current,
    input  logic [31:0] wb_result_delayed,
    
    // Forwarded operands in EX stage
    input  logic [31:0] ex_rs1_forwarded,
    input  logic [31:0] ex_rs2_forwarded
);

    //==========================================================================
    // Property: WB Forward Selector Metadata Alignment
    //==========================================================================
    // When WB forwarding is selected, the delayed metadata (rd_addr, wen)
    // must match the register being read. This ensures data/selector synchronization.
    
    property p_wb_forward_metadata_alignment_rs1;
        @(posedge clk) disable iff (rst || soft_reset_active)
        (id_ex_valid && (id_ex_forward_rs1 == 2'b11) && (id_ex_rs1_addr != 5'b0)) |->
        (wb_rd_addr_delayed == id_ex_rs1_addr) && wb_rf_wen_delayed;
    endproperty
    
    property p_wb_forward_metadata_alignment_rs2;
        @(posedge clk) disable iff (rst || soft_reset_active)
        (id_ex_valid && (id_ex_forward_rs2 == 2'b11) && (id_ex_rs2_addr != 5'b0)) |->
        (wb_rd_addr_delayed == id_ex_rs2_addr) && wb_rf_wen_delayed;
    endproperty
    
    assert_wb_forward_metadata_rs1: assert property (p_wb_forward_metadata_alignment_rs1)
        else $error("[WB_FWD_METADATA] RS1 selector/metadata mismatch: PC=0x%08h insn=0x%08h rs1=x%0d fwd=%b delayed_rd=x%0d wen=%b",
                    id_ex_pc, id_ex_insn, id_ex_rs1_addr, id_ex_forward_rs1, wb_rd_addr_delayed, wb_rf_wen_delayed);
    
    assert_wb_forward_metadata_rs2: assert property (p_wb_forward_metadata_alignment_rs2)
        else $error("[WB_FWD_METADATA] RS2 selector/metadata mismatch: PC=0x%08h insn=0x%08h rs2=x%0d fwd=%b delayed_rd=x%0d wen=%b",
                    id_ex_pc, id_ex_insn, id_ex_rs2_addr, id_ex_forward_rs2, wb_rd_addr_delayed, wb_rf_wen_delayed);
    
    //==========================================================================
    // Property: WB Forward Data Uses Delayed Result
    //==========================================================================
    // When WB forwarding fires, the forwarded data must come from wb_result_delayed
    // (not wb_result_current), ensuring alignment with delayed metadata.
    
    property p_wb_forward_data_delayed_rs1;
        @(posedge clk) disable iff (rst || soft_reset_active)
        (id_ex_valid && (id_ex_forward_rs1 == 2'b11) && (id_ex_rs1_addr != 5'b0)) |->
        (ex_rs1_forwarded == wb_result_delayed);
    endproperty
    
    property p_wb_forward_data_delayed_rs2;
        @(posedge clk) disable iff (rst || soft_reset_active)
        (id_ex_valid && (id_ex_forward_rs2 == 2'b11) && (id_ex_rs2_addr != 5'b0)) |->
        (ex_rs2_forwarded == wb_result_delayed);
    endproperty
    
    assert_wb_forward_data_delayed_rs1: assert property (p_wb_forward_data_delayed_rs1)
        else $error("[WB_FWD_DATA] RS1 forwarded wrong data: PC=0x%08h got=0x%08h expected_delayed=0x%08h current=0x%08h",
                    id_ex_pc, ex_rs1_forwarded, wb_result_delayed, wb_result_current);
    
    assert_wb_forward_data_delayed_rs2: assert property (p_wb_forward_data_delayed_rs2)
        else $error("[WB_FWD_DATA] RS2 forwarded wrong data: PC=0x%08h got=0x%08h expected_delayed=0x%08h current=0x%08h",
                    id_ex_pc, ex_rs2_forwarded, wb_result_delayed, wb_result_current);
    
    //==========================================================================
    // Property: No WB Forwarding to x0
    //==========================================================================
    // Sanity check: WB forwarding should never select x0 (always reads as 0)
    
    property p_no_wb_forward_to_x0;
        @(posedge clk) disable iff (rst || soft_reset_active)
        id_ex_valid |->
        !((id_ex_forward_rs1 == 2'b11) && (id_ex_rs1_addr == 5'b0)) &&
        !((id_ex_forward_rs2 == 2'b11) && (id_ex_rs2_addr == 5'b0));
    endproperty
    
    assert_no_wb_forward_to_x0: assert property (p_no_wb_forward_to_x0)
        else $error("[WB_FWD_X0] Illegal WB forwarding to x0: PC=0x%08h rs1=x%0d fwd_rs1=%b rs2=x%0d fwd_rs2=%b",
                    id_ex_pc, id_ex_rs1_addr, id_ex_forward_rs1, id_ex_rs2_addr, id_ex_forward_rs2);
    
    //==========================================================================
    // Coverage: WB Forwarding Scenarios
    //==========================================================================
    
    cover_wb_forward_rs1_only: cover property (
        @(posedge clk) disable iff (rst || soft_reset_active)
        id_ex_valid && (id_ex_forward_rs1 == 2'b11) && (id_ex_forward_rs2 != 2'b11)
    );
    
    cover_wb_forward_rs2_only: cover property (
        @(posedge clk) disable iff (rst || soft_reset_active)
        id_ex_valid && (id_ex_forward_rs1 != 2'b11) && (id_ex_forward_rs2 == 2'b11)
    );
    
    cover_wb_forward_both: cover property (
        @(posedge clk) disable iff (rst || soft_reset_active)
        id_ex_valid && (id_ex_forward_rs1 == 2'b11) && (id_ex_forward_rs2 == 2'b11)
    );

endmodule
