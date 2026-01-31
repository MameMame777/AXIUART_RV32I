`timescale 1ns/1ps
//==============================================================================
// VexRiscv HazardSimplePlugin Module
//
// Data hazard detection and forwarding control:
// - RAW hazard detection for RS1/RS2
// - Forwarding from Execute/Memory/WriteBack stages
// - WriteBack buffer for register write data
// - Pipeline stall generation
//
// Extracted from VexRiscv_GenSmallAndProductive.v
// Original lines: ~679-707, 1750-1850 (distributed across file)
//==============================================================================

module vexriscv_hazard_simple
    import vexriscv_pkg::*;
(
    input  logic        clk,
    input  logic        reset,
    
    // Decode stage inputs
    input  logic        decode_arbitration_isValid,
    input  logic        decode_RS1_USE,
    input  logic        decode_RS2_USE,
    input  logic [4:0]  decode_INSTRUCTION_rs1,
    input  logic [4:0]  decode_INSTRUCTION_rs2,
    input  logic [31:0] decode_RegFilePlugin_rs1Data,
    input  logic [31:0] decode_RegFilePlugin_rs2Data,
    
    // Execute stage inputs
    input  logic        execute_arbitration_isValid,
    input  logic        execute_REGFILE_WRITE_VALID,
    input  logic        execute_BYPASSABLE_EXECUTE_STAGE,
    input  logic [4:0]  execute_INSTRUCTION_rd,
    input  logic [31:0] execute_REGFILE_WRITE_DATA,
    
    // Memory stage inputs
    input  logic        memory_arbitration_isValid,
    input  logic        memory_REGFILE_WRITE_VALID,
    input  logic        memory_BYPASSABLE_MEMORY_STAGE,
    input  logic [4:0]  memory_INSTRUCTION_rd,
    input  logic [31:0] memory_REGFILE_WRITE_DATA,
    
    // WriteBack stage inputs
    input  logic        writeBack_arbitration_isValid,
    input  logic        writeBack_REGFILE_WRITE_VALID,
    input  logic [4:0]  writeBack_INSTRUCTION_rd,
    input  logic [31:0] writeBack_REGFILE_WRITE_DATA,
    input  logic        writeBack_MEMORY_ENABLE,
    input  logic [31:0] writeBack_DBusSimplePlugin_rspFormated,
    
    // Hazard outputs
    output logic [31:0] decode_RS1,
    output logic [31:0] decode_RS2,
    output logic        decode_arbitration_haltByOther_hazard
);

    //==========================================================================
    // Internal Signals
    //==========================================================================
    
    logic        src0Hazard;
    logic        src1Hazard;
    
    logic        writeBackWrites_valid;
    logic [4:0]  writeBackWrites_payload_address;
    logic [31:0] writeBackWrites_payload_data;
    
    logic        writeBackBuffer_valid;
    logic [4:0]  writeBackBuffer_payload_address;
    logic [31:0] writeBackBuffer_payload_data;
    
    logic        addr0Match;
    logic        addr1Match;

    logic [31:0] writeBack_forward_data;
    
    // Condition signals for each stage
    logic        when_HazardSimplePlugin_l47;
    logic        when_HazardSimplePlugin_l48;
    logic        when_HazardSimplePlugin_l51;
    logic        when_HazardSimplePlugin_l45;
    logic        when_HazardSimplePlugin_l57;
    logic        when_HazardSimplePlugin_l58;
    
    logic        when_HazardSimplePlugin_l48_1;
    logic        when_HazardSimplePlugin_l51_1;
    logic        when_HazardSimplePlugin_l45_1;
    logic        when_HazardSimplePlugin_l57_1;
    logic        when_HazardSimplePlugin_l58_1;
    
    logic        when_HazardSimplePlugin_l48_2;
    logic        when_HazardSimplePlugin_l51_2;
    logic        when_HazardSimplePlugin_l45_2;
    logic        when_HazardSimplePlugin_l57_2;
    logic        when_HazardSimplePlugin_l58_2;
    
    logic        when_HazardSimplePlugin_l105;
    logic        when_HazardSimplePlugin_l108;
    logic        when_HazardSimplePlugin_l113;

    // Direct WriteBack stage forwarding conditions (not through buffer)
    logic        writeBack_direct_forward_valid;
    logic        writeBack_direct_rs1_match;
    logic        writeBack_direct_rs2_match;
    
    //==========================================================================
    // WriteBack Write Interface
    //==========================================================================
    
    assign writeBackWrites_valid = writeBack_arbitration_isValid && writeBack_REGFILE_WRITE_VALID;
    assign writeBackWrites_payload_address = writeBack_INSTRUCTION_rd;
    assign writeBack_forward_data = writeBack_MEMORY_ENABLE ? writeBack_DBusSimplePlugin_rspFormated : writeBack_REGFILE_WRITE_DATA;
    assign writeBackWrites_payload_data = writeBack_forward_data;
    
    //==========================================================================
    // Address Match Detection (for WriteBack buffer forwarding)
    //==========================================================================
    
    assign addr0Match = (writeBackBuffer_payload_address == decode_INSTRUCTION_rs1);
    assign addr1Match = (writeBackBuffer_payload_address == decode_INSTRUCTION_rs2);
    
    //==========================================================================
    // WriteBack Stage Hazard Conditions
    //==========================================================================
    
    assign when_HazardSimplePlugin_l47 = (writeBackBuffer_valid && (writeBackBuffer_payload_address != 5'h0));
    assign when_HazardSimplePlugin_l48 = (decode_INSTRUCTION_rs1 == writeBackBuffer_payload_address);
    assign when_HazardSimplePlugin_l51 = (decode_INSTRUCTION_rs2 == writeBackBuffer_payload_address);
    assign when_HazardSimplePlugin_l45 = (writeBackBuffer_valid && (writeBackBuffer_payload_address != 5'h0));
    
    assign when_HazardSimplePlugin_l57 = (decode_RS1_USE && decode_INSTRUCTION_rs1 == 5'h0);
    assign when_HazardSimplePlugin_l58 = (decode_RS2_USE && decode_INSTRUCTION_rs2 == 5'h0);
    
    //==========================================================================
    // Memory Stage Hazard Conditions
    //==========================================================================
    
    assign when_HazardSimplePlugin_l48_1 = (decode_INSTRUCTION_rs1 == memory_INSTRUCTION_rd);
    assign when_HazardSimplePlugin_l51_1 = (decode_INSTRUCTION_rs2 == memory_INSTRUCTION_rd);
    assign when_HazardSimplePlugin_l45_1 = (memory_arbitration_isValid && memory_REGFILE_WRITE_VALID && (memory_INSTRUCTION_rd != 5'h0));
    
    assign when_HazardSimplePlugin_l57_1 = (decode_RS1_USE && (!memory_BYPASSABLE_MEMORY_STAGE) && (decode_INSTRUCTION_rs1 == memory_INSTRUCTION_rd));
    assign when_HazardSimplePlugin_l58_1 = (decode_RS2_USE && (!memory_BYPASSABLE_MEMORY_STAGE) && (decode_INSTRUCTION_rs2 == memory_INSTRUCTION_rd));
    
    //==========================================================================
    // Execute Stage Hazard Conditions
    //==========================================================================
    
    assign when_HazardSimplePlugin_l48_2 = (decode_INSTRUCTION_rs1 == execute_INSTRUCTION_rd);
    assign when_HazardSimplePlugin_l51_2 = (decode_INSTRUCTION_rs2 == execute_INSTRUCTION_rd);
    assign when_HazardSimplePlugin_l45_2 = (execute_arbitration_isValid && execute_REGFILE_WRITE_VALID && (execute_INSTRUCTION_rd != 5'h0));
    
    assign when_HazardSimplePlugin_l57_2 = (decode_RS1_USE && (!execute_BYPASSABLE_EXECUTE_STAGE) && (decode_INSTRUCTION_rs1 == execute_INSTRUCTION_rd));
    assign when_HazardSimplePlugin_l58_2 = (decode_RS2_USE && (!execute_BYPASSABLE_EXECUTE_STAGE) && (decode_INSTRUCTION_rs2 == execute_INSTRUCTION_rd));

    //==========================================================================
    // WriteBack Stage Direct Forwarding Conditions
    // These check the CURRENT WriteBack stage, not the buffer (which is 1 cycle delayed)
    //==========================================================================

    assign writeBack_direct_forward_valid = (writeBack_arbitration_isValid && writeBack_REGFILE_WRITE_VALID && (writeBack_INSTRUCTION_rd != 5'h0));
    assign writeBack_direct_rs1_match = (decode_INSTRUCTION_rs1 == writeBack_INSTRUCTION_rd);
    assign writeBack_direct_rs2_match = (decode_INSTRUCTION_rs2 == writeBack_INSTRUCTION_rd);

    //==========================================================================
    // Hazard Flag Generation
    //==========================================================================
    
    always_comb begin
        src0Hazard = 1'b0;
        // WriteBack buffer hazard for RS1
        if (when_HazardSimplePlugin_l47) begin
            if (when_HazardSimplePlugin_l48) begin
                src0Hazard = 1'b1;
            end
        end
        // Memory stage hazard for RS1
        if (when_HazardSimplePlugin_l45_1) begin
            if (when_HazardSimplePlugin_l57_1) begin
                src0Hazard = 1'b1;
            end
        end
        // Execute stage hazard for RS1
        if (when_HazardSimplePlugin_l45_2) begin
            if (when_HazardSimplePlugin_l57_2) begin
                src0Hazard = 1'b1;
            end
        end
        // Override: no hazard if RS1 not used
        if (when_HazardSimplePlugin_l105) begin
            src0Hazard = 1'b0;
        end
    end
    
    always_comb begin
        src1Hazard = 1'b0;
        // WriteBack buffer hazard for RS2
        if (when_HazardSimplePlugin_l47) begin
            if (when_HazardSimplePlugin_l51) begin
                src1Hazard = 1'b1;
            end
        end
        // Memory stage hazard for RS2
        if (when_HazardSimplePlugin_l45_1) begin
            if (when_HazardSimplePlugin_l58_1) begin
                src1Hazard = 1'b1;
            end
        end
        // Execute stage hazard for RS2
        if (when_HazardSimplePlugin_l45_2) begin
            if (when_HazardSimplePlugin_l58_2) begin
                src1Hazard = 1'b1;
            end
        end
        // Override: no hazard if RS2 not used
        if (when_HazardSimplePlugin_l108) begin
            src1Hazard = 1'b0;
        end
    end
    
    //==========================================================================
    // Pipeline Stall Control
    //==========================================================================
    
    assign when_HazardSimplePlugin_l105 = (!decode_RS1_USE);
    assign when_HazardSimplePlugin_l108 = (!decode_RS2_USE);
    assign when_HazardSimplePlugin_l113 = (decode_arbitration_isValid && (src0Hazard || src1Hazard));
    
    assign decode_arbitration_haltByOther_hazard = when_HazardSimplePlugin_l113;
    
    //==========================================================================
    // RS1 Forwarding Logic with Priority
    //==========================================================================
    
    always_comb begin
        decode_RS1 = decode_RegFilePlugin_rs1Data;
        
        // Priority 1: WriteBack buffer
        if (writeBackBuffer_valid) begin
            if (addr0Match) begin
                decode_RS1 = writeBackBuffer_payload_data;
            end
        end
        
        // Priority 2: WriteBack stage (direct, not through buffer)
        // Fixed: Check current WriteBack stage validity, not buffer
        if (writeBack_direct_forward_valid) begin
            if (writeBack_direct_rs1_match) begin
                decode_RS1 = writeBack_forward_data;
            end
        end
        
        // Priority 3: Memory stage (bypassable)
        if (when_HazardSimplePlugin_l45_1) begin
            if (memory_BYPASSABLE_MEMORY_STAGE) begin
                if (when_HazardSimplePlugin_l48_1) begin
                    decode_RS1 = memory_REGFILE_WRITE_DATA;
                end
            end
        end
        
        // Priority 4: Execute stage (bypassable)
        if (when_HazardSimplePlugin_l45_2) begin
            if (execute_BYPASSABLE_EXECUTE_STAGE) begin
                if (when_HazardSimplePlugin_l48_2) begin
                    decode_RS1 = execute_REGFILE_WRITE_DATA;
                end
            end
        end
    end
    
    //==========================================================================
    // RS2 Forwarding Logic with Priority
    //==========================================================================
    
    always_comb begin
        decode_RS2 = decode_RegFilePlugin_rs2Data;
        
        // Priority 1: WriteBack buffer
        if (writeBackBuffer_valid) begin
            if (addr1Match) begin
                decode_RS2 = writeBackBuffer_payload_data;
            end
        end
        
        // Priority 2: WriteBack stage (direct, not through buffer)
        // Fixed: Check current WriteBack stage validity, not buffer
        if (writeBack_direct_forward_valid) begin
            if (writeBack_direct_rs2_match) begin
                decode_RS2 = writeBack_forward_data;
            end
        end
        
        // Priority 3: Memory stage (bypassable)
        if (when_HazardSimplePlugin_l45_1) begin
            if (memory_BYPASSABLE_MEMORY_STAGE) begin
                if (when_HazardSimplePlugin_l51_1) begin
                    decode_RS2 = memory_REGFILE_WRITE_DATA;
                end
            end
        end
        
        // Priority 4: Execute stage (bypassable)
        if (when_HazardSimplePlugin_l45_2) begin
            if (execute_BYPASSABLE_EXECUTE_STAGE) begin
                if (when_HazardSimplePlugin_l51_2) begin
                    decode_RS2 = execute_REGFILE_WRITE_DATA;
                end
            end
        end
    end
    
    //==========================================================================
    // Sequential Logic - WriteBack Buffer
    //==========================================================================
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            writeBackBuffer_valid <= 1'b0;
            writeBackBuffer_payload_address <= 5'h0;
            writeBackBuffer_payload_data <= 32'h0;
        end else begin
            if (writeBackWrites_valid) begin
                writeBackBuffer_valid <= 1'b1;
                writeBackBuffer_payload_address <= writeBackWrites_payload_address;
                writeBackBuffer_payload_data <= writeBackWrites_payload_data;
            end
        end
    end

endmodule : vexriscv_hazard_simple
