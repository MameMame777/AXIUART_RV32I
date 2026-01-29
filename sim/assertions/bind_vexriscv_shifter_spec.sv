// Bind module for VexRiscv Shifter Specification
// Binds vexriscv_shifter_spec to vexriscv_execute module
// Non-invasive assertion insertion following project conventions

bind vexriscv_execute vexriscv_shifter_spec u_shifter_spec (
    .clk                                    (clk),
    .resetn                                 (!reset),
    // Execute stage signals
    .execute_arbitration_isValid            (execute_arbitration_isValid),
    .execute_SHIFT_CTRL                     (execute_SHIFT_CTRL),
    .execute_SRC2_4_0                       (execute_SRC2[4:0]),
    .execute_shifter_result                 (execute_shifter_result),
    .execute_SRC_ADD_SUB                    (execute_SRC_ADD_SUB),
    // Shifter internal signals
    .execute_LightShifterPlugin_isActive    (execute_LightShifterPlugin_isActive),
    .execute_LightShifterPlugin_done        (execute_LightShifterPlugin_done),
    .execute_LightShifterPlugin_amplitude   (execute_LightShifterPlugin_amplitude),
    .execute_LightShifterPlugin_shiftInput  (execute_LightShifterPlugin_shiftInput),
    // Feedback from memory stage
    .memory_REGFILE_WRITE_DATA              (memory_REGFILE_WRITE_DATA)
);
