`timescale 1ns / 1ps
//==============================================================================
// Bind VexRiscv Jump Arbitration Specification
//==============================================================================

`ifdef ENABLE_ASSERTIONS

bind VexRiscv vexriscv_jump_arbitration_spec u_vexriscv_jump_arbitration_spec (
    .clk                                    (clk),
    .reset                                  (reset),
    .BranchPlugin_jumpInterface_valid       (BranchPlugin_jumpInterface_valid),
    .BranchPlugin_jumpInterface_payload     (BranchPlugin_jumpInterface_payload),
    .CsrPlugin_jumpInterface_valid          (CsrPlugin_jumpInterface_valid),
    .CsrPlugin_jumpInterface_payload        (CsrPlugin_jumpInterface_payload),
    .IBusSimplePlugin_jump_pcLoad_valid     (IBusSimplePlugin_jump_pcLoad_valid),
    .IBusSimplePlugin_jump_pcLoad_payload   (IBusSimplePlugin_jump_pcLoad_payload),
    .memory_arbitration_flushNext           (memory_arbitration_flushNext),
    .execute_arbitration_flushNext          (execute_arbitration_flushNext),
    .writeBack_arbitration_flushNext        (writeBack_arbitration_flushNext),
    .IBusSimplePlugin_fetchPc_pcReg         (IBusSimplePlugin_fetchPc_pcReg)
);

`endif // ENABLE_ASSERTIONS
