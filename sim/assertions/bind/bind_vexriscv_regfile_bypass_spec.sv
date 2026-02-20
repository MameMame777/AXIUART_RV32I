`timescale 1ns / 1ps
//==============================================================================
// Bind VexRiscv RegFile Bypass Specification
//==============================================================================

`ifdef ENABLE_ASSERTIONS

bind VexRiscv vexriscv_regfile_bypass_spec u_vexriscv_regfile_bypass_spec (
    .clk                                        (clk),
    .reset                                      (reset),
    .RegFilePlugin_regFile_spinal_port0         (RegFilePlugin_regFile_spinal_port0),
    .RegFilePlugin_regFile_spinal_port1         (RegFilePlugin_regFile_spinal_port1),
    .decode_RegFilePlugin_regFileReadAddress1   (decode_RegFilePlugin_regFileReadAddress1),
    .decode_RegFilePlugin_regFileReadAddress2   (decode_RegFilePlugin_regFileReadAddress2),
    .lastStageRegFileWrite_valid                (lastStageRegFileWrite_valid),
    .lastStageRegFileWrite_payload_address      (lastStageRegFileWrite_payload_address),
    .lastStageRegFileWrite_payload_data         (lastStageRegFileWrite_payload_data),
    .writeBack_arbitration_isFiring             (writeBack_arbitration_isFiring),
    .writeBack_REGFILE_WRITE_VALID              (writeBack_REGFILE_WRITE_VALID),
    .writeBack_INSTRUCTION                      (writeBack_INSTRUCTION),
    .when_RegFilePlugin_l63                     (when_RegFilePlugin_l63),
    .decode_REGFILE_WRITE_VALID                 (decode_REGFILE_WRITE_VALID),
    ._zz_5                                      (_zz_5)
);

`endif // ENABLE_ASSERTIONS
