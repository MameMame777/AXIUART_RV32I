`timescale 1ns/1ps
//==============================================================================
// VexRiscv Execute Stage Module
//
// Execute stage operations:
// - ALU operations (ADD/SUB, SLT/SLTU, Bitwise)
// - Shifter operations (multi-cycle)
// - SRC1/SRC2 operand selection
// - Immediate generation
// - Result forwarding
//
// Extracted from VexRiscv_GenSmallAndProductive.v
// Original lines: ~2650-2800 (distributed across file)
//==============================================================================

module vexriscv_execute
    import vexriscv_pkg::*;
(
    input  logic        clk,
    input  logic        reset,
    
    // Execute stage inputs
    input  logic        execute_arbitration_isValid,
    input  logic        execute_arbitration_isStuck,
    input  logic        execute_arbitration_isStuckByOthers,
    input  logic [31:0] execute_PC,
    input  logic [31:0] execute_INSTRUCTION,
    input  logic [31:0] execute_RS1,
    input  logic [31:0] execute_RS2,
    
    // Control signals
    input  logic [1:0]  execute_ALU_CTRL,
    input  logic [1:0]  execute_ALU_BITWISE_CTRL,
    input  logic [1:0]  execute_SHIFT_CTRL,
    input  logic [1:0]  execute_SRC1_CTRL,
    input  logic [1:0]  execute_SRC2_CTRL,
    input  logic        execute_SRC_USE_SUB_LESS,
    input  logic        execute_SRC_LESS_UNSIGNED,
    input  logic        execute_SRC2_FORCE_ZERO,
    
    // Memory stage feedback for shifter
    input  logic [31:0] memory_REGFILE_WRITE_DATA,
    
    // Outputs
    output logic [31:0] execute_REGFILE_WRITE_DATA,
    output logic [31:0] execute_SRC1,
    output logic [31:0] execute_SRC2,
    output logic [31:0] execute_SRC_ADD_SUB,
    output logic        execute_SRC_LESS,
    output logic        execute_arbitration_haltItself_shifter
);

    //==========================================================================
    // Internal Signals
    //==========================================================================
    
    logic [31:0] execute_IntAluPlugin_bitwise;
    logic [31:0] alu_result;
    logic [31:0] src1_muxed;
    logic [31:0] src2_muxed;
    
    // Shifter signals
    logic        execute_LightShifterPlugin_isActive;
    logic        execute_LightShifterPlugin_isShift;
    logic [4:0]  execute_LightShifterPlugin_amplitudeReg;
    logic [4:0]  execute_LightShifterPlugin_amplitude;
    logic [31:0] execute_LightShifterPlugin_shiftInput;
    logic        execute_LightShifterPlugin_done;
    logic [31:0] shifter_result;
    
    // Immediate signals
    logic        imm_sign;
    logic [19:0] imm_i_extended;
    logic [19:0] imm_s_extended;
    
    //==========================================================================
    // SRC1 Mux
    //==========================================================================
    
    always_comb begin
        case (execute_SRC1_CTRL)
            2'b00: begin // RS
                src1_muxed = execute_RS1;
            end
            2'b01: begin // IMU (Upper Immediate)
                src1_muxed = {execute_INSTRUCTION[31:12], 12'h0};
            end
            2'b10: begin // PC_INCREMENT
                src1_muxed = {29'h0, 3'b100}; // +4
            end
            default: begin // URS1 (Unsigned RS1)
                src1_muxed = {27'h0, execute_INSTRUCTION[19:15]};
            end
        endcase
    end
    
    assign execute_SRC1 = src1_muxed;
    
    //==========================================================================
    // SRC2 Mux with Immediate Generation
    //==========================================================================
    
    assign imm_sign = execute_INSTRUCTION[31];
    assign imm_i_extended = {20{imm_sign}};
    assign imm_s_extended = {20{imm_sign}};
    
    always_comb begin
        case (execute_SRC2_CTRL)
            2'b00: begin // RS
                src2_muxed = execute_RS2;
            end
            2'b01: begin // IMI (I-type immediate)
                src2_muxed = {imm_i_extended, execute_INSTRUCTION[31:20]};
            end
            2'b10: begin // IMS (S-type immediate)
                src2_muxed = {imm_s_extended, execute_INSTRUCTION[31:25], execute_INSTRUCTION[11:7]};
            end
            default: begin // PC
                src2_muxed = execute_PC;
            end
        endcase
    end
    
    assign execute_SRC2 = src2_muxed;
    
    //==========================================================================
    // ALU - Add/Sub
    //==========================================================================
    
    always_comb begin
        if (execute_SRC_USE_SUB_LESS) begin
            execute_SRC_ADD_SUB = execute_SRC1 - execute_SRC2;
        end else begin
            execute_SRC_ADD_SUB = execute_SRC1 + execute_SRC2;
        end
        
        if (execute_SRC2_FORCE_ZERO) begin
            execute_SRC_ADD_SUB = execute_SRC1;
        end
    end
    
    //==========================================================================
    // ALU - Less Than Comparison
    //==========================================================================
    
    assign execute_SRC_LESS = ((execute_SRC1[31] == execute_SRC2[31]) ? 
                                execute_SRC_ADD_SUB[31] : 
                                (execute_SRC_LESS_UNSIGNED ? execute_SRC2[31] : execute_SRC1[31]));
    
    //==========================================================================
    // ALU - Bitwise Operations
    //==========================================================================
    
    always_comb begin
        case (execute_ALU_BITWISE_CTRL)
            2'b00: begin // XOR
                execute_IntAluPlugin_bitwise = execute_SRC1 ^ execute_SRC2;
            end
            2'b01: begin // OR
                execute_IntAluPlugin_bitwise = execute_SRC1 | execute_SRC2;
            end
            default: begin // AND
                execute_IntAluPlugin_bitwise = execute_SRC1 & execute_SRC2;
            end
        endcase
    end
    
    //==========================================================================
    // ALU Result Selection
    //==========================================================================
    
    always_comb begin
        case (execute_ALU_CTRL)
            2'b00: begin // ADD_SUB
                alu_result = execute_SRC_ADD_SUB;
            end
            2'b01: begin // SLT_SLTU
                alu_result = {31'h0, execute_SRC_LESS};
            end
            default: begin // BITWISE
                alu_result = execute_IntAluPlugin_bitwise;
            end
        endcase
    end
    
    //==========================================================================
    // Light Shifter Plugin (Multi-cycle)
    //==========================================================================
    
    assign execute_LightShifterPlugin_isShift = (execute_SHIFT_CTRL != 2'b00); // Not DISABLE
    assign execute_LightShifterPlugin_amplitude = execute_LightShifterPlugin_isActive ? 
                                                   execute_LightShifterPlugin_amplitudeReg : 
                                                   execute_SRC2[4:0];
    assign execute_LightShifterPlugin_shiftInput = execute_LightShifterPlugin_isActive ? 
                                                    memory_REGFILE_WRITE_DATA : 
                                                    execute_SRC1;
    assign execute_LightShifterPlugin_done = (execute_LightShifterPlugin_amplitude[4:1] == 4'b0000);
    
    always_comb begin
        case (execute_SHIFT_CTRL)
            2'b01: begin // SLL (Shift Left Logical)
                shifter_result = execute_LightShifterPlugin_shiftInput << 1;
            end
            2'b10: begin // SRL (Shift Right Logical)
                shifter_result = execute_LightShifterPlugin_shiftInput >> 1;
            end
            2'b11: begin // SRA (Shift Right Arithmetic)
                shifter_result = $signed(execute_LightShifterPlugin_shiftInput) >>> 1;
            end
            default: begin
                shifter_result = execute_LightShifterPlugin_shiftInput;
            end
        endcase
    end
    
    //==========================================================================
    // Shifter Control Logic
    //==========================================================================
    
    assign execute_arbitration_haltItself_shifter = ((execute_arbitration_isValid && 
                                                       execute_LightShifterPlugin_isShift) && 
                                                      (execute_SRC2[4:0] != 5'h0) &&
                                                      (!execute_LightShifterPlugin_done) &&
                                                      (!execute_arbitration_isStuckByOthers));
    
    //==========================================================================
    // Execute Result Selection
    //==========================================================================
    
    always_comb begin
        if (execute_LightShifterPlugin_isShift && execute_LightShifterPlugin_isActive) begin
            execute_REGFILE_WRITE_DATA = shifter_result;
        end else begin
            execute_REGFILE_WRITE_DATA = alu_result;
        end
    end
    
    //==========================================================================
    // Sequential Logic - Shifter State
    //==========================================================================
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            execute_LightShifterPlugin_isActive <= 1'b0;
            execute_LightShifterPlugin_amplitudeReg <= 5'h0;
        end else begin
            if (execute_arbitration_isValid && execute_LightShifterPlugin_isShift && 
                (execute_SRC2[4:0] != 5'h0) && (!execute_arbitration_isStuckByOthers)) begin
                execute_LightShifterPlugin_isActive <= 1'b1;
                execute_LightShifterPlugin_amplitudeReg <= execute_LightShifterPlugin_amplitude - 5'h1;
            end
            
            if (execute_LightShifterPlugin_done && (!execute_arbitration_isStuck)) begin
                execute_LightShifterPlugin_isActive <= 1'b0;
            end
        end
    end

endmodule : vexriscv_execute
