`timescale 1ns/1ps
//==============================================================================
// VexRiscv DBusSimplePlugin Module
//
// Data bus interface with:
// - Memory command generation (address, data, mask)
// - Load/Store data formatting
// - Response shifting and sign extension
// - Alignment fault handling
//
// Extracted from VexRiscv_GenSmallAndProductive.v
// Original lines: ~553-566, 2353-2550 (distributed across file)
//==============================================================================

module vexriscv_dbus_simple
    import vexriscv_pkg::*;
(
    input  logic        clk,
    input  logic        reset,
    
    // External data bus interface
    output logic        dBus_cmd_valid,
    input  logic        dBus_cmd_ready,
    output logic        dBus_cmd_payload_wr,
    output logic [3:0]  dBus_cmd_payload_mask,
    output logic [31:0] dBus_cmd_payload_address,
    output logic [31:0] dBus_cmd_payload_data,
    output logic [1:0]  dBus_cmd_payload_size,
    input  logic        dBus_rsp_ready,
    input  logic        dBus_rsp_error,
    input  logic [31:0] dBus_rsp_data,
    
    // Execute stage interface
    input  logic        execute_arbitration_isValid,
    input  logic        execute_arbitration_isStuckByOthers,
    input  logic        execute_arbitration_isFlushed,
    input  logic        execute_MEMORY_ENABLE,
    input  logic        execute_MEMORY_STORE,
    input  logic        execute_ALIGNEMENT_FAULT,
    input  logic [31:0] execute_INSTRUCTION,
    input  logic [31:0] execute_RS2,
    input  logic [31:0] execute_SRC_ADD,
    
    // Memory stage interface
    input  logic        memory_arbitration_isValid,
    input  logic        memory_MEMORY_ENABLE,
    input  logic        memory_MEMORY_STORE,
    
    // WriteBack stage interface
    input  logic        writeBack_arbitration_isValid,
    input  logic        writeBack_MEMORY_ENABLE,
    input  logic [31:0] writeBack_INSTRUCTION,
    input  logic [1:0]  writeBack_MEMORY_ADDRESS_LOW,
    input  logic [31:0] writeBack_MEMORY_READ_DATA,
    
    // Outputs
    output logic [31:0] writeBack_DBusSimplePlugin_rspFormated,

    // Stall signals for arbitration
    output logic        execute_DBus_cmdWait,   // Stall EX when cmd not ready
    output logic        memory_DBus_rspWait     // Stall MEM when rsp not ready (load)
);

    //==========================================================================
    // Internal Signals
    //==========================================================================
    
    logic        execute_DBusSimplePlugin_skipCmd;
    logic [31:0] dBus_cmd_payload_data_pre;
    logic [3:0]  execute_DBusSimplePlugin_formalMask_base;
    logic [3:0]  execute_DBusSimplePlugin_formalMask;
    
    logic [31:0] writeBack_DBusSimplePlugin_rspShifted;
    logic [1:0]  switch_Misc_l245;
    logic        writeBack_DBusSimplePlugin_rspFormated_byte_sign;
    logic [31:0] writeBack_DBusSimplePlugin_rspFormated_byte;
    logic        writeBack_DBusSimplePlugin_rspFormated_half_sign;
    logic [31:0] writeBack_DBusSimplePlugin_rspFormated_half;
    
    logic        when_DBusSimplePlugin_l435;
    logic        when_DBusSimplePlugin_l490;
    logic        when_DBusSimplePlugin_l566;
    
    //==========================================================================
    // Execute Stage - Command Skip Logic
    //==========================================================================
    
    always_comb begin
        execute_DBusSimplePlugin_skipCmd = 1'b0;
        if (execute_ALIGNEMENT_FAULT) begin
            execute_DBusSimplePlugin_skipCmd = 1'b1;
        end
    end
    
    //==========================================================================
    // Execute Stage - Command Valid
    //==========================================================================
    
    assign dBus_cmd_valid = (((((execute_arbitration_isValid && execute_MEMORY_ENABLE) && 
                                 (!execute_arbitration_isStuckByOthers)) && 
                                 (!execute_arbitration_isFlushed)) && 
                                 (!execute_DBusSimplePlugin_skipCmd)) && 
                                 1'b1); // No extra skip condition
    
    assign dBus_cmd_payload_wr = execute_MEMORY_STORE;
    assign dBus_cmd_payload_size = execute_INSTRUCTION[13:12];
    
    //==========================================================================
    // Execute Stage - Store Data Formatting
    //==========================================================================
    
    always_comb begin
        case (dBus_cmd_payload_size)
            2'b00: begin // Byte
                dBus_cmd_payload_data_pre = {4{execute_RS2[7:0]}};
            end
            2'b01: begin // Half
                dBus_cmd_payload_data_pre = {2{execute_RS2[15:0]}};
            end
            default: begin // Word
                dBus_cmd_payload_data_pre = execute_RS2[31:0];
            end
        endcase
    end
    
    assign dBus_cmd_payload_data = dBus_cmd_payload_data_pre;
    
    //==========================================================================
    // Execute Stage - Byte Mask Generation
    //==========================================================================
    
    always_comb begin
        case (dBus_cmd_payload_size)
            2'b00: begin // Byte
                execute_DBusSimplePlugin_formalMask_base = 4'b0001;
            end
            2'b01: begin // Half
                execute_DBusSimplePlugin_formalMask_base = 4'b0011;
            end
            default: begin // Word
                execute_DBusSimplePlugin_formalMask_base = 4'b1111;
            end
        endcase
    end
    
    assign execute_DBusSimplePlugin_formalMask = (execute_DBusSimplePlugin_formalMask_base << execute_SRC_ADD[1:0]);
    assign dBus_cmd_payload_mask = execute_DBusSimplePlugin_formalMask;
    assign dBus_cmd_payload_address = execute_SRC_ADD;
    
    //==========================================================================
    // Stall Conditions
    //==========================================================================
    
    assign when_DBusSimplePlugin_l435 = ((((execute_arbitration_isValid && execute_MEMORY_ENABLE) && 
                                           (!dBus_cmd_ready)) && 
                                           (!execute_DBusSimplePlugin_skipCmd)) && 
                                           1'b1); // No extra skip condition
    
    assign when_DBusSimplePlugin_l490 = (((memory_arbitration_isValid && memory_MEMORY_ENABLE) &&
                                          (!memory_MEMORY_STORE)) &&
                                          ((!dBus_rsp_ready) || 1'b0));

    // Export stall signals for use in vexriscv_top arbitration
    assign execute_DBus_cmdWait = when_DBusSimplePlugin_l435;
    assign memory_DBus_rspWait  = when_DBusSimplePlugin_l490;

    //==========================================================================
    // WriteBack Stage - Load Response Shifting
    //==========================================================================
    
    always_comb begin
        writeBack_DBusSimplePlugin_rspShifted = writeBack_MEMORY_READ_DATA;
        case (writeBack_MEMORY_ADDRESS_LOW)
            2'b01: begin
                writeBack_DBusSimplePlugin_rspShifted[7:0] = writeBack_MEMORY_READ_DATA[15:8];
            end
            2'b10: begin
                writeBack_DBusSimplePlugin_rspShifted[15:0] = writeBack_MEMORY_READ_DATA[31:16];
            end
            2'b11: begin
                writeBack_DBusSimplePlugin_rspShifted[7:0] = writeBack_MEMORY_READ_DATA[31:24];
            end
            default: begin
                // No shift needed for 2'b00
            end
        endcase
    end
    
    //==========================================================================
    // WriteBack Stage - Load Response Sign Extension
    //==========================================================================
    
    assign switch_Misc_l245 = writeBack_INSTRUCTION[13:12];
    
    // Byte sign extension
    assign writeBack_DBusSimplePlugin_rspFormated_byte_sign = (writeBack_DBusSimplePlugin_rspShifted[7] && 
                                                                (!writeBack_INSTRUCTION[14])); // Signed load
    always_comb begin
        writeBack_DBusSimplePlugin_rspFormated_byte[31:8] = {24{writeBack_DBusSimplePlugin_rspFormated_byte_sign}};
        writeBack_DBusSimplePlugin_rspFormated_byte[7:0] = writeBack_DBusSimplePlugin_rspShifted[7:0];
    end
    
    // Half sign extension
    assign writeBack_DBusSimplePlugin_rspFormated_half_sign = (writeBack_DBusSimplePlugin_rspShifted[15] && 
                                                                (!writeBack_INSTRUCTION[14])); // Signed load
    always_comb begin
        writeBack_DBusSimplePlugin_rspFormated_half[31:16] = {16{writeBack_DBusSimplePlugin_rspFormated_half_sign}};
        writeBack_DBusSimplePlugin_rspFormated_half[15:0] = writeBack_DBusSimplePlugin_rspShifted[15:0];
    end
    
    // Format selection
    always_comb begin
        case (switch_Misc_l245)
            2'b00: begin // Byte
                writeBack_DBusSimplePlugin_rspFormated = writeBack_DBusSimplePlugin_rspFormated_byte;
            end
            2'b01: begin // Half
                writeBack_DBusSimplePlugin_rspFormated = writeBack_DBusSimplePlugin_rspFormated_half;
            end
            default: begin // Word
                writeBack_DBusSimplePlugin_rspFormated = writeBack_DBusSimplePlugin_rspShifted;
            end
        endcase
    end
    
    //==========================================================================
    // WriteBack Valid Condition
    //==========================================================================
    
    assign when_DBusSimplePlugin_l566 = (writeBack_arbitration_isValid && writeBack_MEMORY_ENABLE);

endmodule : vexriscv_dbus_simple
