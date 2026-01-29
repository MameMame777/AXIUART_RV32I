// VexRiscv Shifter Specification Module
// Purpose: SVA assertions for LightShifterPlugin verification
// Usage: Bind to vexriscv_top module via bind_vexriscv_shifter_spec.sv

module vexriscv_shifter_spec (
    input  logic        clk,
    input  logic        resetn,
    // Execute stage signals
    input  logic        execute_arbitration_isValid,
    input  logic [1:0]  execute_SHIFT_CTRL,
    input  logic [4:0]  execute_SRC2_4_0,
    input  logic [31:0] execute_shifter_result,
    input  logic [31:0] execute_SRC_ADD_SUB,
    // Shifter internal signals
    input  logic        execute_LightShifterPlugin_isActive,
    input  logic        execute_LightShifterPlugin_done,
    input  logic [4:0]  execute_LightShifterPlugin_amplitude,
    input  logic [31:0] execute_LightShifterPlugin_shiftInput,
    // Feedback from memory stage
    input  logic [31:0] memory_REGFILE_WRITE_DATA
);

    // =========================================================================
    // Local Parameters
    // =========================================================================
    localparam SHIFT_CTRL_DISABLE = 2'b00;
    localparam SHIFT_CTRL_SLL     = 2'b01;
    localparam SHIFT_CTRL_SRL     = 2'b10;
    localparam SHIFT_CTRL_SRA     = 2'b11;

    // =========================================================================
    // Property: Shifter Activation
    // When SHIFT_CTRL != DISABLE and shift amount != 0, shifter should activate
    // =========================================================================
    property p_shifter_activation;
        @(posedge clk) disable iff (!resetn)
        (execute_arbitration_isValid &&
         execute_SHIFT_CTRL != SHIFT_CTRL_DISABLE &&
         execute_SRC2_4_0 != 5'h0)
        |-> ##[0:32] execute_LightShifterPlugin_isActive;
    endproperty

    assert property (p_shifter_activation)
        else $error("[SHIFTER_SPEC] Shifter failed to activate for non-zero shift");

    // =========================================================================
    // Property: Shifter Done Condition
    // Shifter should complete when amplitude[4:1] == 0 (amplitude <= 1)
    // =========================================================================
    property p_shifter_done_condition;
        @(posedge clk) disable iff (!resetn)
        (execute_LightShifterPlugin_isActive &&
         execute_LightShifterPlugin_amplitude[4:1] == 4'b0000)
        |-> execute_LightShifterPlugin_done;
    endproperty

    assert property (p_shifter_done_condition)
        else $error("[SHIFTER_SPEC] Shifter done flag not asserted when amplitude <= 1");

    // =========================================================================
    // Property: Feedback Loop Integrity
    // When shifter is active, input should come from memory_REGFILE_WRITE_DATA
    // =========================================================================
    property p_feedback_loop;
        @(posedge clk) disable iff (!resetn)
        execute_LightShifterPlugin_isActive
        |-> (execute_LightShifterPlugin_shiftInput == memory_REGFILE_WRITE_DATA);
    endproperty

    assert property (p_feedback_loop)
        else $error("[SHIFTER_SPEC] Feedback loop mismatch: shiftInput != memory_REGFILE_WRITE_DATA");

    // =========================================================================
    // Property: Shifter Result Valid
    // When shifter completes, result should be defined (not X)
    // Note: execute_REGFILE_WRITE_DATA is computed at top level, not visible here
    // =========================================================================
    property p_shifter_result_valid;
        @(posedge clk) disable iff (!resetn)
        (execute_arbitration_isValid &&
         execute_SHIFT_CTRL != SHIFT_CTRL_DISABLE &&
         execute_SRC2_4_0 != 5'h0 &&
         execute_LightShifterPlugin_done)
        |-> (execute_shifter_result !== 32'hxxxxxxxx);
    endproperty

    assert property (p_shifter_result_valid)
        else $error("[SHIFTER_SPEC] Shifter result is undefined when done");

    // =========================================================================
    // Property: Zero Shift No Activation
    // When shift amount is 0, shifter should not become active
    // =========================================================================
    property p_zero_shift_no_activation;
        @(posedge clk) disable iff (!resetn)
        (execute_arbitration_isValid &&
         execute_SHIFT_CTRL != SHIFT_CTRL_DISABLE &&
         execute_SRC2_4_0 == 5'h0)
        |-> !execute_LightShifterPlugin_isActive;
    endproperty

    assert property (p_zero_shift_no_activation)
        else $error("[SHIFTER_SPEC] Shifter should not activate for zero shift amount");

    // =========================================================================
    // Property: Amplitude Decrement
    // Amplitude should decrement by 1 each cycle while shifter is active
    // =========================================================================
    property p_amplitude_decrement;
        @(posedge clk) disable iff (!resetn)
        (execute_LightShifterPlugin_isActive &&
         !execute_LightShifterPlugin_done &&
         execute_LightShifterPlugin_amplitude > 5'd1)
        |=> (execute_LightShifterPlugin_amplitude == $past(execute_LightShifterPlugin_amplitude) - 1);
    endproperty

    assert property (p_amplitude_decrement)
        else $error("[SHIFTER_SPEC] Amplitude did not decrement correctly");

    // =========================================================================
    // Cover Properties for Debug
    // =========================================================================
    cover property (@(posedge clk)
        execute_SHIFT_CTRL == SHIFT_CTRL_SLL && execute_SRC2_4_0 > 5'd0);

    cover property (@(posedge clk)
        execute_SHIFT_CTRL == SHIFT_CTRL_SRL && execute_SRC2_4_0 > 5'd0);

    cover property (@(posedge clk)
        execute_SHIFT_CTRL == SHIFT_CTRL_SRA && execute_SRC2_4_0 > 5'd0);

    cover property (@(posedge clk)
        execute_LightShifterPlugin_isActive && execute_LightShifterPlugin_done);

endmodule
