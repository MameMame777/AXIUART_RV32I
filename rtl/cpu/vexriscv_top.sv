`timescale 1ns/1ps
//==============================================================================
// VexRiscv Top Module - Simplified Integration
//
// Top-level integration of VexRiscv CPU modules:
// - Instruction Fetch (IBusSimplePlugin)
// - Data Bus (DBusSimplePlugin)
// - Register File
// - Hazard Detection & Forwarding
// - Branch Resolution
// - CSR & Interrupt Management
// - Execute Stage (ALU, Shifter)
//
// This is a simplified integration focusing on the extracted modules.
// Full decoder ROM and pipeline control logic still require extraction.
//
// Architecture: 4-stage pipeline (Fetch/Decode/Execute/Memory-WriteBack)
// ISA: RV32I base integer instruction set
// Performance: ~0.82 DMIPS/MHz
//==============================================================================

module vexriscv_top
    import vexriscv_pkg::*;
(
    input  logic        clk,
    input  logic        reset,
    
    // External interrupts
    input  logic        externalInterrupt,
    input  logic        timerInterrupt,
    input  logic        softwareInterrupt,
    
    // Instruction Bus (AXI4-Lite compatible signals)
    output logic        iBus_cmd_valid,
    input  logic        iBus_cmd_ready,
    output logic [31:0] iBus_cmd_payload_pc,
    input  logic        iBus_rsp_valid,
    input  logic        iBus_rsp_payload_error,
    input  logic [31:0] iBus_rsp_payload_inst,
    
    // Data Bus (AXI4-Lite compatible signals)
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
    
    // Debug outputs
    output logic [31:0] debug_pc,
    output logic [31:0] debug_instruction,
    output logic        debug_writeBack_regWrite,
    output logic [4:0]  debug_writeBack_regAddr,
    output logic [31:0] debug_writeBack_regData
);

    //==========================================================================
    // Internal Signals - Decode Stage
    //==========================================================================
    
    logic        decode_arbitration_isValid;
    logic        decode_arbitration_isStuck;
    logic        decode_arbitration_removeIt;
    logic        decode_arbitration_haltByOther;
    logic        decode_arbitration_flushNext;
    logic [31:0] decode_INSTRUCTION;
    logic [31:0] decode_PC;
    logic [31:0] decode_RS1;
    logic [31:0] decode_RS2;
    
    // Decode control signals (simplified)
    logic [1:0]  decode_BRANCH_CTRL;
    logic [1:0]  decode_SHIFT_CTRL;
    logic [1:0]  decode_ALU_BITWISE_CTRL;
    logic [1:0]  decode_ALU_CTRL;
    logic [1:0]  decode_SRC1_CTRL;
    logic [1:0]  decode_SRC2_CTRL;
    logic        decode_MEMORY_ENABLE;
    logic        decode_MEMORY_STORE;
    logic        decode_IS_CSR;
    logic        decode_CSR_WRITE_OPCODE;
    logic        decode_CSR_READ_OPCODE;
    logic        decode_RS1_USE;
    logic        decode_RS2_USE;
    logic        decode_REGFILE_WRITE_VALID;
    
    //==========================================================================
    // Internal Signals - Execute Stage
    //==========================================================================
    
    logic        execute_arbitration_isValid;
    logic        execute_arbitration_isStuck;
    logic        execute_arbitration_isStuckByOthers;
    logic        execute_arbitration_isFlushed;
    logic        execute_arbitration_flushNext;
    logic        execute_arbitration_haltItself;
    logic [31:0] execute_PC;
    logic [31:0] execute_INSTRUCTION;
    logic [31:0] execute_RS1;
    logic [31:0] execute_RS2;
    logic [31:0] execute_SRC1;
    logic [31:0] execute_SRC2;
    logic [31:0] execute_SRC_ADD_SUB;
    logic        execute_SRC_LESS;
    logic [31:0] execute_REGFILE_WRITE_DATA;
    logic        execute_REGFILE_WRITE_VALID;
    logic        execute_BYPASSABLE_EXECUTE_STAGE;
    
    // Execute control signals
    logic [1:0]  execute_BRANCH_CTRL;
    logic        execute_PREDICTION_HAD_BRANCHED1;
    logic [31:0] execute_BRANCH_CALC;
    logic        execute_BRANCH_DO;
    
    //==========================================================================
    // Internal Signals - Memory Stage
    //==========================================================================
    
    logic        memory_arbitration_isValid;
    logic        memory_arbitration_isStuck;
    logic        memory_arbitration_flushNext;
    logic [31:0] memory_PC;
    logic [31:0] memory_INSTRUCTION;
    logic [31:0] memory_REGFILE_WRITE_DATA;
    logic        memory_REGFILE_WRITE_VALID;
    logic        memory_MEMORY_ENABLE;
    logic        memory_MEMORY_STORE;
    logic        memory_BYPASSABLE_MEMORY_STAGE;
    logic [1:0]  memory_MEMORY_ADDRESS_LOW;
    logic [31:0] memory_MEMORY_READ_DATA;
    
    //==========================================================================
    // Internal Signals - WriteBack Stage
    //==========================================================================
    
    logic        writeBack_arbitration_isValid;
    logic        writeBack_arbitration_isFiring;
    logic        writeBack_arbitration_isStuck;
    logic        writeBack_arbitration_flushNext;
    logic [31:0] writeBack_PC;
    logic [31:0] writeBack_INSTRUCTION;
    logic [31:0] writeBack_REGFILE_WRITE_DATA;
    logic        writeBack_REGFILE_WRITE_VALID;
    logic        writeBack_MEMORY_ENABLE;
    logic [1:0]  writeBack_MEMORY_ADDRESS_LOW;
    logic [31:0] writeBack_MEMORY_READ_DATA;
    logic [31:0] writeBack_DBusSimplePlugin_rspFormated;
    
    //==========================================================================
    // Internal Signals - Branch/Jump Control
    //==========================================================================
    
    logic        BranchPlugin_jumpInterface_valid;
    logic [31:0] BranchPlugin_jumpInterface_payload;
    logic        CsrPlugin_jumpInterface_valid;
    logic [31:0] CsrPlugin_jumpInterface_payload;
    
    //==========================================================================
    // Internal Signals - Register File
    //==========================================================================
    
    logic [4:0]  RegFilePlugin_regFileReadAddress1;
    logic [4:0]  RegFilePlugin_regFileReadAddress2;
    logic [31:0] RegFilePlugin_rs1Data;
    logic [31:0] RegFilePlugin_rs2Data;
    logic        RegFilePlugin_regFileWrite_valid;
    logic [4:0]  RegFilePlugin_regFileWrite_payload_address;
    logic [31:0] RegFilePlugin_regFileWrite_payload_data;
    
    //==========================================================================
    // Module Instantiations
    //==========================================================================
    
    // Register File
    vexriscv_regfile u_regfile (
        .clk                    (clk),
        .reset                  (reset),
        .read_addr1             (RegFilePlugin_regFileReadAddress1),
        .read_data1             (RegFilePlugin_rs1Data),
        .read_addr2             (RegFilePlugin_regFileReadAddress2),
        .read_data2             (RegFilePlugin_rs2Data),
        .write_valid            (RegFilePlugin_regFileWrite_valid),
        .write_addr             (RegFilePlugin_regFileWrite_payload_address),
        .write_data             (RegFilePlugin_regFileWrite_payload_data)
    );
    
    // Instruction Bus Plugin
    vexriscv_ibus_simple u_ibus (
        .clk                            (clk),
        .reset                          (reset),
        .iBus_cmd_valid                 (iBus_cmd_valid),
        .iBus_cmd_ready                 (iBus_cmd_ready),
        .iBus_cmd_payload_pc            (iBus_cmd_payload_pc),
        .iBus_rsp_valid                 (iBus_rsp_valid),
        .iBus_rsp_payload_error         (iBus_rsp_payload_error),
        .iBus_rsp_payload_inst          (iBus_rsp_payload_inst),
        .branchPlugin_jump_valid        (BranchPlugin_jumpInterface_valid),
        .branchPlugin_jump_payload      (BranchPlugin_jumpInterface_payload),
        .csrPlugin_jump_valid           (CsrPlugin_jumpInterface_valid),
        .csrPlugin_jump_payload         (CsrPlugin_jumpInterface_payload),
        .decode_arbitration_isValid     (decode_arbitration_isValid),
        .decode_arbitration_isStuck     (decode_arbitration_isStuck),
        .decode_arbitration_removeIt    (decode_arbitration_removeIt),
        .decode_instruction             (decode_INSTRUCTION),
        .decode_pc                      (decode_PC),
        .decode_branch_ctrl             (decode_BRANCH_CTRL),
        .decode_instruction_for_prediction (decode_INSTRUCTION),
        .prediction_jump_valid          (),
        .prediction_jump_payload        (),
        .decode_prediction_had_branched (execute_PREDICTION_HAD_BRANCHED1),
        .execute_arbitration_flushNext  (execute_arbitration_flushNext),
        .memory_arbitration_flushNext   (memory_arbitration_flushNext),
        .writeBack_arbitration_flushNext(writeBack_arbitration_flushNext),
        .decode_arbitration_flushNext   (decode_arbitration_flushNext),
        .execute_arbitration_isStuck    (execute_arbitration_isStuck),
        .memory_arbitration_isStuck     (memory_arbitration_isStuck),
        .writeBack_arbitration_isStuck  (writeBack_arbitration_isStuck),
        .fetcher_halt                   (1'b0),
        .force_no_decode_cond           (1'b0),
        .incoming_instruction           ()
    );
    
    // Data Bus Plugin
    vexriscv_dbus_simple u_dbus (
        .clk                            (clk),
        .reset                          (reset),
        .dBus_cmd_valid                 (dBus_cmd_valid),
        .dBus_cmd_ready                 (dBus_cmd_ready),
        .dBus_cmd_payload_wr            (dBus_cmd_payload_wr),
        .dBus_cmd_payload_mask          (dBus_cmd_payload_mask),
        .dBus_cmd_payload_address       (dBus_cmd_payload_address),
        .dBus_cmd_payload_data          (dBus_cmd_payload_data),
        .dBus_cmd_payload_size          (dBus_cmd_payload_size),
        .dBus_rsp_ready                 (dBus_rsp_ready),
        .dBus_rsp_error                 (dBus_rsp_error),
        .dBus_rsp_data                  (dBus_rsp_data),
        .execute_arbitration_isValid    (execute_arbitration_isValid),
        .execute_arbitration_isStuckByOthers (execute_arbitration_isStuckByOthers),
        .execute_arbitration_isFlushed  (execute_arbitration_isFlushed),
        .execute_MEMORY_ENABLE          (decode_MEMORY_ENABLE),
        .execute_MEMORY_STORE           (decode_MEMORY_STORE),
        .execute_ALIGNEMENT_FAULT       (1'b0),
        .execute_INSTRUCTION            (execute_INSTRUCTION),
        .execute_RS2                    (execute_RS2),
        .execute_SRC_ADD                (execute_SRC_ADD_SUB),
        .memory_arbitration_isValid     (memory_arbitration_isValid),
        .memory_MEMORY_ENABLE           (memory_MEMORY_ENABLE),
        .memory_MEMORY_STORE            (memory_MEMORY_STORE),
        .writeBack_arbitration_isValid  (writeBack_arbitration_isValid),
        .writeBack_MEMORY_ENABLE        (writeBack_MEMORY_ENABLE),
        .writeBack_INSTRUCTION          (writeBack_INSTRUCTION),
        .writeBack_MEMORY_ADDRESS_LOW   (writeBack_MEMORY_ADDRESS_LOW),
        .writeBack_MEMORY_READ_DATA     (writeBack_MEMORY_READ_DATA),
        .writeBack_DBusSimplePlugin_rspFormated (writeBack_DBusSimplePlugin_rspFormated)
    );
    
    // Hazard Detection & Forwarding
    vexriscv_hazard_simple u_hazard (
        .clk                            (clk),
        .reset                          (reset),
        .decode_arbitration_isValid     (decode_arbitration_isValid),
        .decode_RS1_USE                 (decode_RS1_USE),
        .decode_RS2_USE                 (decode_RS2_USE),
        .decode_INSTRUCTION_rs1         (decode_INSTRUCTION[19:15]),
        .decode_INSTRUCTION_rs2         (decode_INSTRUCTION[24:20]),
        .decode_RegFilePlugin_rs1Data   (RegFilePlugin_rs1Data),
        .decode_RegFilePlugin_rs2Data   (RegFilePlugin_rs2Data),
        .execute_arbitration_isValid    (execute_arbitration_isValid),
        .execute_REGFILE_WRITE_VALID    (execute_REGFILE_WRITE_VALID),
        .execute_BYPASSABLE_EXECUTE_STAGE (execute_BYPASSABLE_EXECUTE_STAGE),
        .execute_INSTRUCTION_rd         (execute_INSTRUCTION[11:7]),
        .execute_REGFILE_WRITE_DATA     (execute_REGFILE_WRITE_DATA),
        .memory_arbitration_isValid     (memory_arbitration_isValid),
        .memory_REGFILE_WRITE_VALID     (memory_REGFILE_WRITE_VALID),
        .memory_BYPASSABLE_MEMORY_STAGE (memory_BYPASSABLE_MEMORY_STAGE),
        .memory_INSTRUCTION_rd          (memory_INSTRUCTION[11:7]),
        .memory_REGFILE_WRITE_DATA      (memory_REGFILE_WRITE_DATA),
        .writeBack_arbitration_isValid  (writeBack_arbitration_isValid),
        .writeBack_REGFILE_WRITE_VALID  (writeBack_REGFILE_WRITE_VALID),
        .writeBack_INSTRUCTION_rd       (writeBack_INSTRUCTION[11:7]),
        .writeBack_REGFILE_WRITE_DATA   (writeBack_REGFILE_WRITE_DATA),
        .decode_RS1                     (decode_RS1),
        .decode_RS2                     (decode_RS2),
        .decode_arbitration_haltByOther_hazard (decode_arbitration_haltByOther)
    );
    
    // Branch Plugin
    vexriscv_branch u_branch (
        .clk                            (clk),
        .reset                          (reset),
        .execute_arbitration_isValid    (execute_arbitration_isValid),
        .execute_PC                     (execute_PC),
        .execute_INSTRUCTION            (execute_INSTRUCTION),
        .execute_BRANCH_CTRL            (execute_BRANCH_CTRL),
        .execute_PREDICTION_HAD_BRANCHED1 (execute_PREDICTION_HAD_BRANCHED1),
        .execute_RS1                    (execute_RS1),
        .execute_SRC1                   (execute_SRC1),
        .execute_SRC2                   (execute_SRC2),
        .execute_SRC_LESS               (execute_SRC_LESS),
        .BranchPlugin_jumpInterface_valid (BranchPlugin_jumpInterface_valid),
        .BranchPlugin_jumpInterface_payload (BranchPlugin_jumpInterface_payload),
        .execute_BRANCH_DO              (execute_BRANCH_DO),
        .execute_BRANCH_CALC            (execute_BRANCH_CALC)
    );
    
    // CSR Plugin
    vexriscv_csr u_csr (
        .clk                            (clk),
        .reset                          (reset),
        .externalInterrupt              (externalInterrupt),
        .timerInterrupt                 (timerInterrupt),
        .softwareInterrupt              (softwareInterrupt),
        .execute_arbitration_isValid    (execute_arbitration_isValid),
        .execute_arbitration_isStuck    (execute_arbitration_isStuck),
        .execute_INSTRUCTION            (execute_INSTRUCTION),
        .execute_IS_CSR                 (decode_IS_CSR),
        .execute_CSR_WRITE_OPCODE       (decode_CSR_WRITE_OPCODE),
        .execute_CSR_READ_OPCODE        (decode_CSR_READ_OPCODE),
        .execute_SRC1                   (execute_SRC1),
        .execute_ENV_CTRL_isXRET        (1'b0),
        .memory_arbitration_isValid     (memory_arbitration_isValid),
        .writeBack_arbitration_isValid  (writeBack_arbitration_isValid),
        .writeBack_arbitration_isFiring (writeBack_arbitration_isFiring),
        .writeBack_INSTRUCTION          (writeBack_INSTRUCTION),
        .writeBack_PC                   (writeBack_PC),
        .decode_arbitration_isValid     (decode_arbitration_isValid),
        .decode_arbitration_removeIt    (decode_arbitration_removeIt),
        .decode_arbitration_haltByOther_csr (),
        .execute_arbitration_isStuckByOthers (execute_arbitration_isStuckByOthers),
        .memory_arbitration_isStuck     (memory_arbitration_isStuck),
        .writeBack_arbitration_isStuck  (writeBack_arbitration_isStuck),
        .CsrPlugin_jumpInterface_valid  (CsrPlugin_jumpInterface_valid),
        .CsrPlugin_jumpInterface_payload (CsrPlugin_jumpInterface_payload),
        .CsrPlugin_interruptJump        (),
        .CsrPlugin_hadException         (),
        .CsrPlugin_csrMapping_readDataSignal (),
        .execute_CsrPlugin_illegalAccess (),
        .execute_CsrPlugin_illegalInstruction ()
    );
    
    // Execute Stage
    vexriscv_execute u_execute (
        .clk                            (clk),
        .reset                          (reset),
        .execute_arbitration_isValid    (execute_arbitration_isValid),
        .execute_arbitration_isStuck    (execute_arbitration_isStuck),
        .execute_arbitration_isStuckByOthers (execute_arbitration_isStuckByOthers),
        .execute_PC                     (execute_PC),
        .execute_INSTRUCTION            (execute_INSTRUCTION),
        .execute_RS1                    (execute_RS1),
        .execute_RS2                    (execute_RS2),
        .execute_ALU_CTRL               (decode_ALU_CTRL),
        .execute_ALU_BITWISE_CTRL       (decode_ALU_BITWISE_CTRL),
        .execute_SHIFT_CTRL             (decode_SHIFT_CTRL),
        .execute_SRC1_CTRL              (decode_SRC1_CTRL),
        .execute_SRC2_CTRL              (decode_SRC2_CTRL),
        .execute_SRC_USE_SUB_LESS       (1'b0),
        .execute_SRC_LESS_UNSIGNED      (1'b0),
        .execute_SRC2_FORCE_ZERO        (1'b0),
        .memory_REGFILE_WRITE_DATA      (memory_REGFILE_WRITE_DATA),
        .execute_REGFILE_WRITE_DATA     (execute_REGFILE_WRITE_DATA),
        .execute_SRC1                   (execute_SRC1),
        .execute_SRC2                   (execute_SRC2),
        .execute_SRC_ADD_SUB            (execute_SRC_ADD_SUB),
        .execute_SRC_LESS               (execute_SRC_LESS),
        .execute_arbitration_haltItself_shifter (execute_arbitration_haltItself)
    );
    
    //==========================================================================
    // Simplified Pipeline Control (Placeholder)
    //==========================================================================
    
    // Note: Full decoder ROM and pipeline arbitration logic would go here
    // This is a simplified version for module integration testing
    
    assign decode_arbitration_isStuck = execute_arbitration_isStuck;
    assign execute_arbitration_isStuckByOthers = memory_arbitration_isStuck;
    assign execute_arbitration_isFlushed = execute_arbitration_flushNext;
    
    assign RegFilePlugin_regFileReadAddress1 = decode_INSTRUCTION[19:15];
    assign RegFilePlugin_regFileReadAddress2 = decode_INSTRUCTION[24:20];
    
    assign RegFilePlugin_regFileWrite_valid = (writeBack_REGFILE_WRITE_VALID && writeBack_arbitration_isValid);
    assign RegFilePlugin_regFileWrite_payload_address = writeBack_INSTRUCTION[11:7];
    assign RegFilePlugin_regFileWrite_payload_data = writeBack_REGFILE_WRITE_DATA;
    
    assign writeBack_arbitration_isFiring = (writeBack_arbitration_isValid && (!writeBack_arbitration_isStuck));
    
    // Simplified control signal defaults
    assign decode_RS1_USE = 1'b1;
    assign decode_RS2_USE = 1'b1;
    assign decode_REGFILE_WRITE_VALID = 1'b1;
    assign execute_REGFILE_WRITE_VALID = 1'b1;
    assign memory_REGFILE_WRITE_VALID = 1'b1;
    assign writeBack_REGFILE_WRITE_VALID = 1'b1;
    assign execute_BYPASSABLE_EXECUTE_STAGE = 1'b1;
    assign memory_BYPASSABLE_MEMORY_STAGE = 1'b1;
    
    //==========================================================================
    // Debug Outputs
    //==========================================================================
    
    assign debug_pc = writeBack_PC;
    assign debug_instruction = writeBack_INSTRUCTION;
    assign debug_writeBack_regWrite = RegFilePlugin_regFileWrite_valid;
    assign debug_writeBack_regAddr = RegFilePlugin_regFileWrite_payload_address;
    assign debug_writeBack_regData = RegFilePlugin_regFileWrite_payload_data;

endmodule : vexriscv_top
