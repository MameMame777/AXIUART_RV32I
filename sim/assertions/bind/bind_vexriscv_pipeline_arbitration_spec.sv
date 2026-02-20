`timescale 1ns / 1ps
//==============================================================================
// Bind VexRiscv Pipeline Arbitration Specification
//==============================================================================

`ifdef ENABLE_ASSERTIONS

bind VexRiscv vexriscv_pipeline_arbitration_spec u_vexriscv_pipeline_arbitration_spec (
    .clk                              (clk),
    .reset                            (reset),
    // Decode stage
    .decode_arbitration_isValid       (decode_arbitration_isValid),
    .decode_arbitration_isStuck       (decode_arbitration_isStuck),
    .decode_arbitration_isStuckByOthers (decode_arbitration_isStuckByOthers),
    .decode_arbitration_isFlushed     (decode_arbitration_isFlushed),
    .decode_arbitration_isMoving      (decode_arbitration_isMoving),
    .decode_arbitration_isFiring      (decode_arbitration_isFiring),
    .decode_arbitration_haltItself    (decode_arbitration_haltItself),
    .decode_arbitration_flushNext     (decode_arbitration_flushNext),
    // Execute stage
    .execute_arbitration_isValid      (execute_arbitration_isValid),
    .execute_arbitration_isStuck      (execute_arbitration_isStuck),
    .execute_arbitration_isStuckByOthers (execute_arbitration_isStuckByOthers),
    .execute_arbitration_isFlushed    (execute_arbitration_isFlushed),
    .execute_arbitration_isMoving     (execute_arbitration_isMoving),
    .execute_arbitration_isFiring     (execute_arbitration_isFiring),
    .execute_arbitration_haltItself   (execute_arbitration_haltItself),
    .execute_arbitration_flushNext    (execute_arbitration_flushNext),
    // Memory stage
    .memory_arbitration_isValid       (memory_arbitration_isValid),
    .memory_arbitration_isStuck       (memory_arbitration_isStuck),
    .memory_arbitration_isFlushed     (memory_arbitration_isFlushed),
    .memory_arbitration_isMoving      (memory_arbitration_isMoving),
    .memory_arbitration_isFiring      (memory_arbitration_isFiring),
    .memory_arbitration_haltItself    (memory_arbitration_haltItself),
    .memory_arbitration_flushNext     (memory_arbitration_flushNext),
    // WriteBack stage
    .writeBack_arbitration_isValid    (writeBack_arbitration_isValid),
    .writeBack_arbitration_isStuck    (writeBack_arbitration_isStuck),
    .writeBack_arbitration_isFlushed  (writeBack_arbitration_isFlushed),
    .writeBack_arbitration_isMoving   (writeBack_arbitration_isMoving),
    .writeBack_arbitration_isFiring   (writeBack_arbitration_isFiring)
);

`endif // ENABLE_ASSERTIONS
