`timescale 1ns / 1ps
//==============================================================================
// Bind VexRiscv Hazard Plugin Specification
//==============================================================================

`ifdef ENABLE_ASSERTIONS

bind VexRiscv vexriscv_hazard_plugin_spec u_vexriscv_hazard_plugin_spec (
    .clk                                          (clk),
    .reset                                        (reset),
    // Hazard detection
    .HazardSimplePlugin_src0Hazard                (HazardSimplePlugin_src0Hazard),
    .HazardSimplePlugin_src1Hazard                (HazardSimplePlugin_src1Hazard),
    .when_HazardSimplePlugin_l113                 (when_HazardSimplePlugin_l113),
    // Decode stage
    .decode_arbitration_isValid                   (decode_arbitration_isValid),
    .decode_arbitration_haltItself                (decode_arbitration_haltItself),
    .decode_RS1_USE                               (decode_RS1_USE),
    .decode_RS2_USE                               (decode_RS2_USE),
    // Execute stage
    .execute_arbitration_isValid                  (execute_arbitration_isValid),
    .execute_REGFILE_WRITE_VALID                  (execute_REGFILE_WRITE_VALID),
    .execute_BYPASSABLE_EXECUTE_STAGE             (execute_BYPASSABLE_EXECUTE_STAGE),
    .execute_MEMORY_ENABLE                        (execute_MEMORY_ENABLE),
    .execute_MEMORY_STORE                         (execute_MEMORY_STORE),
    // Memory stage
    .memory_arbitration_isValid                   (memory_arbitration_isValid),
    .memory_BYPASSABLE_MEMORY_STAGE               (memory_BYPASSABLE_MEMORY_STAGE),
    // Bypass flags
    .when_HazardSimplePlugin_l58_2                (when_HazardSimplePlugin_l58_2),
    .when_HazardSimplePlugin_l48_2                (when_HazardSimplePlugin_l48_2),
    .when_HazardSimplePlugin_l51_2                (when_HazardSimplePlugin_l51_2),
    // WriteBack buffer
    .HazardSimplePlugin_writeBackBuffer_valid             (HazardSimplePlugin_writeBackBuffer_valid),
    .HazardSimplePlugin_writeBackBuffer_payload_address   (HazardSimplePlugin_writeBackBuffer_payload_address),
    .HazardSimplePlugin_writeBackBuffer_payload_data      (HazardSimplePlugin_writeBackBuffer_payload_data),
    .HazardSimplePlugin_addr0Match                        (HazardSimplePlugin_addr0Match),
    .HazardSimplePlugin_addr1Match                        (HazardSimplePlugin_addr1Match),
    // WB write
    .lastStageRegFileWrite_valid                  (lastStageRegFileWrite_valid),
    .lastStageRegFileWrite_payload_address        (lastStageRegFileWrite_payload_address),
    .lastStageRegFileWrite_payload_data           (lastStageRegFileWrite_payload_data),
    .writeBack_arbitration_isFiring               (writeBack_arbitration_isFiring)
);

`endif // ENABLE_ASSERTIONS
