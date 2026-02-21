`timescale 1ns / 1ps
//==============================================================================
// VexRiscv Hazard Plugin Specification
//==============================================================================
// Observer-only assertions for HazardSimplePlugin correctness.
// Checks: RAW hazard detection, bypass priority, load-use stall, and
// bypassWriteBackBuffer validity.
// Bind target: VexRiscv
//==============================================================================

`ifdef ENABLE_ASSERTIONS

module vexriscv_hazard_plugin_spec (
    input logic clk,
    input logic reset,

    // Hazard detection results
    input logic HazardSimplePlugin_src0Hazard,
    input logic HazardSimplePlugin_src1Hazard,

    // Hazard stall condition (= decode_isValid && (src0Hazard || src1Hazard))
    input logic when_HazardSimplePlugin_l113,

    // Decode stage
    input logic decode_arbitration_isValid,
    input logic decode_arbitration_haltItself,
    input logic decode_RS1_USE,
    input logic decode_RS2_USE,

    // Execute stage bypass capability
    input logic execute_arbitration_isValid,
    input logic execute_REGFILE_WRITE_VALID,
    input logic execute_BYPASSABLE_EXECUTE_STAGE,
    input logic execute_MEMORY_ENABLE,
    input logic execute_MEMORY_STORE,

    // Memory stage bypass capability
    input logic memory_arbitration_isValid,
    input logic memory_BYPASSABLE_MEMORY_STAGE,

    // Execute stage non-bypassable hazard flag (=!execute_BYPASSABLE_EXECUTE_STAGE)
    input logic when_HazardSimplePlugin_l58_2,

    // Destination address match: execute.rd == decode.rs1 and .rs2
    input logic when_HazardSimplePlugin_l48_2,
    input logic when_HazardSimplePlugin_l51_2,

    // WriteBack buffer (extra bypass register for one cycle after WB)
    input logic HazardSimplePlugin_writeBackBuffer_valid,
    input logic [4:0] HazardSimplePlugin_writeBackBuffer_payload_address,
    input logic [31:0] HazardSimplePlugin_writeBackBuffer_payload_data,
    input logic HazardSimplePlugin_addr0Match,
    input logic HazardSimplePlugin_addr1Match,

    // WB write (to verify buffer is updated correctly)
    input logic lastStageRegFileWrite_valid,
    input logic [4:0] lastStageRegFileWrite_payload_address,
    input logic [31:0] lastStageRegFileWrite_payload_data,

    input logic writeBack_arbitration_isFiring
);

    // -------------------------------------------------------------------------
    // Check 1: RAW hazard detection → decode stage must stall
    // When hazard is detected (decode is valid, either RS has hazard),
    // the decode stage must halt itself to stall the pipeline.
    // -------------------------------------------------------------------------
    property p_hazard_causes_decode_stall;
        @(posedge clk) disable iff (reset)
        when_HazardSimplePlugin_l113 |-> decode_arbitration_haltItself;
    endproperty

    a_hazard_causes_decode_stall: assert property (p_hazard_causes_decode_stall)
        else $error("[HAZARD] RAW hazard detected but decode_haltItself=0 (src0=%0b, src1=%0b)",
            HazardSimplePlugin_src0Hazard, HazardSimplePlugin_src1Hazard);

    // No hazard when RS not used (RS use checks clear spurious hazards)
    property p_no_hazard_when_rs1_not_used;
        @(posedge clk) disable iff (reset)
        !decode_RS1_USE |-> !HazardSimplePlugin_src0Hazard;
    endproperty

    a_no_hazard_when_rs1_not_used: assert property (p_no_hazard_when_rs1_not_used)
        else $error("[HAZARD] src0Hazard set but decode_RS1_USE=0");

    property p_no_hazard_when_rs2_not_used;
        @(posedge clk) disable iff (reset)
        !decode_RS2_USE |-> !HazardSimplePlugin_src1Hazard;
    endproperty

    a_no_hazard_when_rs2_not_used: assert property (p_no_hazard_when_rs2_not_used)
        else $error("[HAZARD] src1Hazard set but decode_RS2_USE=0");

    // -------------------------------------------------------------------------
    // Check 2: Bypass priority (EX > MEM > WB)
    // When execute stage is bypassable, it does NOT cause a hazard stall.
    // The non-bypassable flag (l58_2) must be 0 when execute is bypassable.
    // -------------------------------------------------------------------------
    property p_execute_bypassable_no_stall_flag;
        @(posedge clk) disable iff (reset)
        execute_BYPASSABLE_EXECUTE_STAGE |-> !when_HazardSimplePlugin_l58_2;
    endproperty

    a_execute_bypassable_no_stall_flag: assert property (p_execute_bypassable_no_stall_flag)
        else $error("[HAZARD] execute is bypassable but l58_2 (non-bypassable flag) is set");

    // When execute stage provides bypassable result matching decode RS1, no RS1 hazard
    property p_execute_bypass_clears_rs1_hazard;
        @(posedge clk) disable iff (reset)
        (execute_arbitration_isValid && execute_REGFILE_WRITE_VALID &&
         execute_BYPASSABLE_EXECUTE_STAGE && when_HazardSimplePlugin_l48_2 && decode_RS1_USE)
        |-> !HazardSimplePlugin_src0Hazard;
    endproperty

    a_execute_bypass_clears_rs1_hazard: assert property (p_execute_bypass_clears_rs1_hazard)
        else $error("[HAZARD] execute bypassable, dest matches RS1, but src0Hazard is still set");

    // -------------------------------------------------------------------------
    // Check 3: Load-use mandatory stall
    // A load instruction (MEMORY_ENABLE && !MEMORY_STORE) in execute stage
    // must be marked as non-bypassable (cannot forward from execute).
    // -------------------------------------------------------------------------
    property p_load_is_not_bypassable;
        @(posedge clk) disable iff (reset)
        (execute_arbitration_isValid && execute_MEMORY_ENABLE && !execute_MEMORY_STORE)
        |-> !execute_BYPASSABLE_EXECUTE_STAGE;
    endproperty

    a_load_is_not_bypassable: assert property (p_load_is_not_bypassable)
        else $error("[HAZARD] load instruction in execute but BYPASSABLE_EXECUTE_STAGE=1 (load-use stall missing)");

    // When a load is in execute and its destination matches decode RS1 (and RS1 is used),
    // a hazard must be raised to force the load-use stall.
    property p_load_use_hazard_detected;
        @(posedge clk) disable iff (reset)
        (execute_arbitration_isValid && execute_MEMORY_ENABLE && !execute_MEMORY_STORE &&
         when_HazardSimplePlugin_l48_2 && decode_arbitration_isValid && decode_RS1_USE)
        |-> HazardSimplePlugin_src0Hazard;
    endproperty

    a_load_use_hazard_detected: assert property (p_load_use_hazard_detected)
        else $error("[HAZARD] load-use dependency on RS1 exists but src0Hazard=0");

    // -------------------------------------------------------------------------
    // Check 4: bypassWriteBackBuffer correctness
    // After WB stage fires a register write, the writeBackBuffer must be updated
    // with the correct address in the following cycle.
    // -------------------------------------------------------------------------
    property p_writeback_buffer_updated_after_wb;
        @(posedge clk) disable iff (reset)
        (lastStageRegFileWrite_valid && writeBack_arbitration_isFiring &&
         (lastStageRegFileWrite_payload_address != 5'd0))
        |=> (HazardSimplePlugin_writeBackBuffer_valid &&
             (HazardSimplePlugin_writeBackBuffer_payload_address ==
              $past(lastStageRegFileWrite_payload_address)));
    endproperty

    a_writeback_buffer_updated_after_wb: assert property (p_writeback_buffer_updated_after_wb)
        else $error("[HAZARD] writeBackBuffer not updated after WB fire (addr=%0d)",
            $past(lastStageRegFileWrite_payload_address));

    // When writeBackBuffer is valid and addr0 matches, bypass data must be used
    // Note: addr0Match is a pure address comparison (no valid check) - the caller
    // gates on writeBackBuffer_valid before using the result.
    property p_addr0match_implies_bypass_used;
        @(posedge clk) disable iff (reset)
        (HazardSimplePlugin_writeBackBuffer_valid && HazardSimplePlugin_addr0Match && decode_RS1_USE)
        |-> !HazardSimplePlugin_src0Hazard;
    endproperty

    a_addr0match_implies_bypass_used: assert property (p_addr0match_implies_bypass_used)
        else $error("[HAZARD] writeBackBuffer valid+addr0Match but src0Hazard still set");

endmodule

`endif // ENABLE_ASSERTIONS
