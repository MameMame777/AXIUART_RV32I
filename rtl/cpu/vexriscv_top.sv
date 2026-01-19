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
// Control Architecture (UART-Controlled System):
// - fetcher_halt: Prevents PC advancement until cpu_running=1
//   * Standard VexRiscv (GenSmallAndProductive.v) has NO external fetcher_halt port
//   * Used internally by DebugPlugin, CSR, cache operations
//   * THIS IMPLEMENTATION adds explicit control for UART-based run/halt commands
//   * Connected to !cpu_running to prevent PC advancement before explicit RUN
//
// - IBus cmd_ready: Additional backpressure mechanism (vexriscv_mem_crossbar.sv)
//   * Gates individual IBus requests when cpu_halted=1
//   * Provides fine-grained control during execution
//   * Redundant with fetcher_halt but kept for safety
//
// Architecture Deviation from Standard VexRiscv:
// - Standard: CPU starts executing immediately after reset
// - This Implementation: CPU waits for explicit RUN command via Register_Block
//
// Architecture: 4-stage pipeline (Fetch/Decode/Execute/Memory-WriteBack)
// ISA: RV32I base integer instruction set
// Performance: ~0.82 DMIPS/MHz
//
// Reference: VexRiscv SpinalHDL generated code (VexRiscv_GenSmallAndProductive.v)
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
    
    // Fetcher control (UART-controlled system specific)
    input  logic        fetcher_halt,  // Halt fetcher until explicit RUN command
    
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
    
    // Arbitration signals - Decode
    logic        decode_arbitration_haltItself;
    logic        decode_arbitration_haltByOther;
    logic        decode_arbitration_haltByOther_hazard;  // From hazard module
    logic        decode_arbitration_removeIt;
    logic        decode_arbitration_flushIt;
    logic        decode_arbitration_flushNext;
    logic        decode_arbitration_isValid;
    logic        decode_arbitration_isStuck;
    logic        decode_arbitration_isStuckByOthers;
    logic        decode_arbitration_isFlushed;
    logic        decode_arbitration_isMoving;
    logic        decode_arbitration_isFiring;
    
    logic [31:0] decode_INSTRUCTION;
    logic [31:0] decode_PC;
    logic [31:0] decode_RS1;
    logic [31:0] decode_RS2;
    
    // Decode control signals from decoder ROM
    logic [1:0]  decode_BRANCH_CTRL;
    logic [1:0]  decode_SHIFT_CTRL;
    logic [1:0]  decode_ALU_BITWISE_CTRL;
    logic [1:0]  decode_ALU_CTRL;
    logic [1:0]  decode_SRC1_CTRL;
    logic [1:0]  decode_SRC2_CTRL;
    logic [0:0]  decode_ENV_CTRL;
    logic        decode_MEMORY_ENABLE;
    logic        decode_MEMORY_STORE;
    logic        decode_IS_CSR;
    logic        decode_CSR_WRITE_OPCODE;
    logic        decode_CSR_READ_OPCODE;
    logic        decode_RS1_USE;
    logic        decode_RS2_USE;
    logic        decode_REGFILE_WRITE_VALID;
    logic        decode_BYPASSABLE_EXECUTE_STAGE;
    logic        decode_BYPASSABLE_MEMORY_STAGE;
    logic        decode_SRC_USE_SUB_LESS;
    logic        decode_SRC_LESS_UNSIGNED;
    logic        decode_SRC_ADD_ZERO;
    logic [31:0] decode_FORMAL_PC_NEXT;
    logic        decode_PREDICTION_HAD_BRANCHED1;
    logic        decode_SRC2_FORCE_ZERO;
    
    //==========================================================================
    // Internal Signals - Execute Stage
    //==========================================================================
    
    // Arbitration signals - Execute
    logic        execute_arbitration_haltItself;
    logic        execute_arbitration_haltItself_shifter;  // From execute module
    logic        execute_arbitration_haltByOther;
    logic        execute_arbitration_removeIt;
    logic        execute_arbitration_flushIt;
    logic        execute_arbitration_flushNext;
    logic        execute_arbitration_isValid;
    logic        execute_arbitration_isStuck;
    logic        execute_arbitration_isStuckByOthers;
    logic        execute_arbitration_isFlushed;
    logic        execute_arbitration_isMoving;
    logic        execute_arbitration_isFiring;
    
    logic [31:0] execute_PC;
    logic [31:0] execute_INSTRUCTION;
    logic [31:0] execute_RS1;
    logic [31:0] execute_RS2;
    logic [31:0] execute_SRC1;
    logic [31:0] execute_SRC2;
    logic [31:0] execute_SRC_ADD_SUB;
    logic        execute_SRC_LESS;
    logic [31:0] execute_IntAluPlugin_bitwise;
    logic [31:0] execute_REGFILE_WRITE_DATA;
    logic        execute_REGFILE_WRITE_VALID;
    logic        execute_BYPASSABLE_EXECUTE_STAGE;
    logic        execute_BYPASSABLE_MEMORY_STAGE;
    logic        execute_MEMORY_ENABLE;
    logic        execute_MEMORY_STORE;
    
    // Execute control signals
    logic [1:0]  execute_BRANCH_CTRL;
    logic [1:0]  execute_SHIFT_CTRL;
    logic [1:0]  execute_ALU_CTRL;
    logic [1:0]  execute_ALU_BITWISE_CTRL;
    logic [1:0]  execute_SRC1_CTRL;
    logic [1:0]  execute_SRC2_CTRL;
    logic [0:0]  execute_ENV_CTRL;
    logic        execute_IS_CSR;
    logic        execute_CSR_WRITE_OPCODE;
    logic        execute_CSR_READ_OPCODE;
    logic        execute_SRC_USE_SUB_LESS;
    logic        execute_SRC_LESS_UNSIGNED;
    logic [31:0] execute_FORMAL_PC_NEXT;
    logic        execute_PREDICTION_HAD_BRANCHED1;
    logic [31:0] execute_BRANCH_CALC;
    logic        execute_BRANCH_DO;
    logic        execute_SRC2_FORCE_ZERO;
    logic [1:0]  execute_MEMORY_ADDRESS_LOW;
    
    //==========================================================================
    // Internal Signals - Memory Stage
    //==========================================================================
    
    // Arbitration signals - Memory
    logic        memory_arbitration_haltItself;
    logic        memory_arbitration_haltByOther;
    logic        memory_arbitration_removeIt;
    logic        memory_arbitration_flushIt;
    logic        memory_arbitration_flushNext;
    logic        memory_arbitration_isValid;
    logic        memory_arbitration_isStuck;
    logic        memory_arbitration_isStuckByOthers;
    logic        memory_arbitration_isFlushed;
    logic        memory_arbitration_isMoving;
    logic        memory_arbitration_isFiring;
    
    logic [31:0] memory_PC;
    logic [31:0] memory_INSTRUCTION;
    logic [31:0] memory_REGFILE_WRITE_DATA;
    logic        memory_REGFILE_WRITE_VALID;
    logic        memory_MEMORY_ENABLE;
    logic        memory_MEMORY_STORE;
    logic        memory_BYPASSABLE_MEMORY_STAGE;
    logic [1:0]  memory_MEMORY_ADDRESS_LOW;
    logic [31:0] memory_MEMORY_READ_DATA;
    logic [0:0]  memory_ENV_CTRL;
    logic [31:0] memory_FORMAL_PC_NEXT;
    
    //==========================================================================
    // Internal Signals - WriteBack Stage
    //==========================================================================
    
    // Arbitration signals - WriteBack
    logic        writeBack_arbitration_haltItself;
    logic        writeBack_arbitration_haltByOther;
    logic        writeBack_arbitration_removeIt;
    logic        writeBack_arbitration_flushIt;
    logic        writeBack_arbitration_flushNext;
    logic        writeBack_arbitration_isValid;
    logic        writeBack_arbitration_isStuck;
    logic        writeBack_arbitration_isStuckByOthers;
    logic        writeBack_arbitration_isFlushed;
    logic        writeBack_arbitration_isMoving;
    logic        writeBack_arbitration_isFiring;
    
    logic [31:0] writeBack_PC;
    logic [31:0] writeBack_INSTRUCTION;
    logic [31:0] writeBack_REGFILE_WRITE_DATA;
    logic        writeBack_REGFILE_WRITE_VALID;
    logic        writeBack_MEMORY_ENABLE;
    logic [1:0]  writeBack_MEMORY_ADDRESS_LOW;
    logic [31:0] writeBack_MEMORY_READ_DATA;
    logic [31:0] writeBack_DBusSimplePlugin_rspFormated;
    logic [0:0]  writeBack_ENV_CTRL;
    logic [31:0] writeBack_FORMAL_PC_NEXT;
    
    //==========================================================================
    // Pipeline Registers (Decode→Execute→Memory→WriteBack)
    //==========================================================================
    
    // Decode to Execute pipeline registers
    logic [31:0] decode_to_execute_PC;
    logic [31:0] decode_to_execute_INSTRUCTION;
    logic [31:0] decode_to_execute_FORMAL_PC_NEXT;
    logic        decode_to_execute_CSR_WRITE_OPCODE;
    logic        decode_to_execute_CSR_READ_OPCODE;
    logic [1:0]  decode_to_execute_SRC1_CTRL;
    logic        decode_to_execute_SRC_USE_SUB_LESS;
    logic        decode_to_execute_MEMORY_ENABLE;
    logic [1:0]  decode_to_execute_SRC2_CTRL;
    logic        decode_to_execute_REGFILE_WRITE_VALID;
    logic        decode_to_execute_BYPASSABLE_EXECUTE_STAGE;
    logic        decode_to_execute_BYPASSABLE_MEMORY_STAGE;
    logic        decode_to_execute_MEMORY_STORE;
    logic        decode_to_execute_IS_CSR;
    logic [0:0]  decode_to_execute_ENV_CTRL;
    logic [1:0]  decode_to_execute_ALU_CTRL;
    logic        decode_to_execute_SRC_LESS_UNSIGNED;
    logic [1:0]  decode_to_execute_ALU_BITWISE_CTRL;
    logic [1:0]  decode_to_execute_SHIFT_CTRL;
    logic [1:0]  decode_to_execute_BRANCH_CTRL;
    logic [31:0] decode_to_execute_RS1;
    logic [31:0] decode_to_execute_RS2;
    logic        decode_to_execute_SRC2_FORCE_ZERO;
    logic        decode_to_execute_PREDICTION_HAD_BRANCHED1;
    
    // Execute to Memory pipeline registers
    logic [31:0] execute_to_memory_PC;
    logic [31:0] execute_to_memory_INSTRUCTION;
    logic [31:0] execute_to_memory_FORMAL_PC_NEXT;
    logic        execute_to_memory_MEMORY_ENABLE;
    logic        execute_to_memory_REGFILE_WRITE_VALID;
    logic        execute_to_memory_BYPASSABLE_MEMORY_STAGE;
    logic        execute_to_memory_MEMORY_STORE;
    logic [0:0]  execute_to_memory_ENV_CTRL;
    logic [1:0]  execute_to_memory_MEMORY_ADDRESS_LOW;
    logic [31:0] execute_to_memory_REGFILE_WRITE_DATA;
    
    // Memory to WriteBack pipeline registers
    logic [31:0] memory_to_writeBack_PC;
    logic [31:0] memory_to_writeBack_INSTRUCTION;
    logic [31:0] memory_to_writeBack_FORMAL_PC_NEXT;
    logic        memory_to_writeBack_MEMORY_ENABLE;
    logic        memory_to_writeBack_REGFILE_WRITE_VALID;
    logic [0:0]  memory_to_writeBack_ENV_CTRL;
    logic [1:0]  memory_to_writeBack_MEMORY_ADDRESS_LOW;
    logic [31:0] memory_to_writeBack_REGFILE_WRITE_DATA;
    logic [31:0] memory_to_writeBack_MEMORY_READ_DATA;
    
    // Pipeline enable signals (when_Pipeline_l124_N)
    logic        when_Pipeline_l124;
    logic        when_Pipeline_l124_1;
    logic        when_Pipeline_l124_2;
    logic        when_Pipeline_l124_3;
    logic        when_Pipeline_l124_4;
    logic        when_Pipeline_l124_5;
    logic        when_Pipeline_l124_6;
    logic        when_Pipeline_l124_7;
    logic        when_Pipeline_l124_8;
    logic        when_Pipeline_l124_9;
    logic        when_Pipeline_l124_10;
    logic        when_Pipeline_l124_11;
    logic        when_Pipeline_l124_12;
    logic        when_Pipeline_l124_13;
    logic        when_Pipeline_l124_14;
    logic        when_Pipeline_l124_15;
    logic        when_Pipeline_l124_16;
    logic        when_Pipeline_l124_17;
    logic        when_Pipeline_l124_18;
    logic        when_Pipeline_l124_19;
    logic        when_Pipeline_l124_20;
    logic        when_Pipeline_l124_21;
    logic        when_Pipeline_l124_22;
    logic        when_Pipeline_l124_23;
    logic        when_Pipeline_l124_24;
    logic        when_Pipeline_l124_25;
    logic        when_Pipeline_l124_26;
    logic        when_Pipeline_l124_27;
    logic        when_Pipeline_l124_28;
    logic        when_Pipeline_l124_29;
    logic        when_Pipeline_l124_30;
    logic        when_Pipeline_l124_31;
    logic        when_Pipeline_l124_32;
    logic        when_Pipeline_l124_33;
    logic        when_Pipeline_l124_34;
    logic        when_Pipeline_l124_35;
    logic        when_Pipeline_l124_36;
    logic        when_Pipeline_l124_37;
    logic        when_Pipeline_l124_38;
    logic        when_Pipeline_l124_39;
    logic        when_Pipeline_l124_40;
    logic        when_Pipeline_l124_41;
    logic        when_Pipeline_l124_42;
    
    // Valid update conditions
    logic        when_Pipeline_l151;
    logic        when_Pipeline_l154;
    logic        when_Pipeline_l151_1;
    logic        when_Pipeline_l154_1;
    logic        when_Pipeline_l151_2;
    logic        when_Pipeline_l154_2;
    
    //==========================================================================
    // Decoder ROM Signals
    //==========================================================================
    
    // Decoder ROM control signal unpacking helpers (for pipeline stage pass-through)
    logic [1:0]  _zz_decode_BRANCH_CTRL;
    
    // Stage signal pass-through helpers
    logic [1:0]  _zz_decode_to_execute_SRC1_CTRL;
    logic [1:0]  _zz_decode_to_execute_SRC1_CTRL_1;
    logic [1:0]  _zz_execute_SRC1_CTRL;
    logic [1:0]  _zz_decode_to_execute_SRC2_CTRL;
    logic [1:0]  _zz_decode_to_execute_SRC2_CTRL_1;
    logic [1:0]  _zz_execute_SRC2_CTRL;
    logic [0:0]  _zz_decode_to_execute_ENV_CTRL;
    logic [0:0]  _zz_decode_to_execute_ENV_CTRL_1;
    logic [0:0]  _zz_execute_to_memory_ENV_CTRL;
    logic [0:0]  _zz_execute_to_memory_ENV_CTRL_1;
    logic [0:0]  _zz_memory_to_writeBack_ENV_CTRL;
    logic [0:0]  _zz_memory_to_writeBack_ENV_CTRL_1;
    logic [0:0]  _zz_execute_ENV_CTRL;
    logic [0:0]  _zz_memory_ENV_CTRL;
    logic [0:0]  _zz_writeBack_ENV_CTRL;
    logic [1:0]  _zz_decode_to_execute_ALU_CTRL;
    logic [1:0]  _zz_decode_to_execute_ALU_CTRL_1;
    logic [1:0]  _zz_decode_to_execute_ALU_BITWISE_CTRL;
    logic [1:0]  _zz_decode_to_execute_ALU_BITWISE_CTRL_1;
    logic [1:0]  _zz_decode_to_execute_SHIFT_CTRL;
    logic [1:0]  _zz_decode_to_execute_SHIFT_CTRL_1;
    logic [1:0]  _zz_decode_to_execute_BRANCH_CTRL;
    logic [1:0]  _zz_decode_to_execute_BRANCH_CTRL_1;
    logic [1:0]  _zz_decode_SRC1_CTRL;
    logic [1:0]  _zz_decode_SRC2_CTRL;
    logic [0:0]  _zz_decode_ENV_CTRL;
    logic [1:0]  _zz_decode_ALU_CTRL;
    logic [1:0]  _zz_decode_ALU_BITWISE_CTRL;
    logic [1:0]  _zz_decode_SHIFT_CTRL;
    
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
        .decode_prediction_had_branched (decode_PREDICTION_HAD_BRANCHED1),
        .execute_arbitration_flushNext  (execute_arbitration_flushNext),
        .memory_arbitration_flushNext   (memory_arbitration_flushNext),
        .writeBack_arbitration_flushNext(writeBack_arbitration_flushNext),
        .decode_arbitration_flushNext   (decode_arbitration_flushNext),
        .execute_arbitration_isStuck    (execute_arbitration_isStuck),
        .memory_arbitration_isStuck     (memory_arbitration_isStuck),
        .writeBack_arbitration_isStuck  (writeBack_arbitration_isStuck),
        .fetcher_halt                   (fetcher_halt),  // From wrapper: !cpu_running
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
        .execute_MEMORY_ENABLE          (execute_MEMORY_ENABLE),
        .execute_MEMORY_STORE           (execute_MEMORY_STORE),
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
        .decode_arbitration_haltByOther_hazard (decode_arbitration_haltByOther_hazard)
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
        .execute_ALU_CTRL               (execute_ALU_CTRL),
        .execute_ALU_BITWISE_CTRL       (execute_ALU_BITWISE_CTRL),
        .execute_SHIFT_CTRL             (execute_SHIFT_CTRL),
        .execute_SRC1_CTRL              (execute_SRC1_CTRL),
        .execute_SRC2_CTRL              (execute_SRC2_CTRL),
        .execute_SRC_USE_SUB_LESS       (execute_SRC_USE_SUB_LESS),
        .execute_SRC_LESS_UNSIGNED      (execute_SRC_LESS_UNSIGNED),
        .execute_SRC2_FORCE_ZERO        (execute_SRC2_FORCE_ZERO),
        .memory_REGFILE_WRITE_DATA      (memory_REGFILE_WRITE_DATA),
        .execute_SRC1                   (execute_SRC1),
        .execute_SRC2                   (execute_SRC2),
        .execute_SRC_ADD_SUB            (execute_SRC_ADD_SUB),
        .execute_SRC_LESS               (execute_SRC_LESS),
        .execute_IntAluPlugin_bitwise   (execute_IntAluPlugin_bitwise),
        .execute_arbitration_haltItself_shifter (execute_arbitration_haltItself_shifter)
    );
    
`ifdef DEBUG
    // Debug: Monitor decode stage control signals
    always @(posedge clk) begin
        if (decode_arbitration_isValid) begin
            $display("[%0t] DECODE_CTRL: inst=0x%08x REGFILE_WR=%0b REGFILE_WR_VALID=%0b RS1_USE=%0b RS2_USE=%0b", 
                     $time, decode_INSTRUCTION, (decode_INSTRUCTION[11:7] != 5'h0), decode_REGFILE_WRITE_VALID,
                     decode_RS1_USE, decode_RS2_USE);
        end
    end
`endif
    
    //==========================================================================
    // Execute Stage ALU Result Mux (From original VexRiscv lines 2678-2690)
    //==========================================================================
    
    // Execute register write data mux
    always_comb begin
        case(execute_ALU_CTRL)
            2'd2:     execute_REGFILE_WRITE_DATA = execute_IntAluPlugin_bitwise;  // BITWISE
            2'd1:     execute_REGFILE_WRITE_DATA = {31'd0, execute_SRC_LESS};     // SLT_SLTU
            default:  execute_REGFILE_WRITE_DATA = execute_SRC_ADD_SUB;           // ADD_SUB
        endcase
    end
    
    //==========================================================================
    // Instruction Decoder Module Instantiation
    //==========================================================================
    
    vexriscv_decoder u_decoder (
        .decode_INSTRUCTION              (decode_INSTRUCTION),
        .decoder_output                  (/* unused packed output */),
        .decode_SRC1_CTRL                (decode_SRC1_CTRL),
        .decode_SRC_USE_SUB_LESS         (decode_SRC_USE_SUB_LESS),
        .decode_MEMORY_ENABLE            (decode_MEMORY_ENABLE),
        .decode_RS1_USE                  (decode_RS1_USE),
        .decode_SRC2_CTRL                (decode_SRC2_CTRL),
        .decode_REGFILE_WRITE_VALID      (decode_REGFILE_WRITE_VALID),
        .decode_BYPASSABLE_EXECUTE_STAGE (decode_BYPASSABLE_EXECUTE_STAGE),
        .decode_BYPASSABLE_MEMORY_STAGE  (decode_BYPASSABLE_MEMORY_STAGE),
        .decode_MEMORY_STORE             (decode_MEMORY_STORE),
        .decode_RS2_USE                  (decode_RS2_USE),
        .decode_IS_CSR                   (decode_IS_CSR),
        .decode_ENV_CTRL                 (decode_ENV_CTRL),
        .decode_ALU_CTRL                 (decode_ALU_CTRL),
        .decode_SRC_LESS_UNSIGNED        (decode_SRC_LESS_UNSIGNED),
        .decode_ALU_BITWISE_CTRL         (decode_ALU_BITWISE_CTRL),
        .decode_SRC_ADD_ZERO             (decode_SRC_ADD_ZERO),
        .decode_SHIFT_CTRL               (decode_SHIFT_CTRL),
        .decode_BRANCH_CTRL              (_zz_decode_BRANCH_CTRL)
    );
    
    //==========================================================================
    // TEMPORARY FIX: Decoder ROM Bug Workaround
    //==========================================================================
    // The decoder ROM incorrectly outputs REGFILE_WRITE_VALID=0 for I-type ALU instructions
    // This workaround overrides the decoder output to set the flag correctly.
    // TODO: Regenerate decoder ROM table from SpinalHDL with correct settings
    
    logic decode_REGFILE_WRITE_VALID_rom_output;
    logic decode_REGFILE_WRITE_VALID_corrected;
    logic [1:0] decode_SRC2_CTRL_rom_output;
    logic [1:0] decode_SRC2_CTRL_corrected;
    
    assign decode_REGFILE_WRITE_VALID_rom_output = decode_REGFILE_WRITE_VALID;
    assign decode_SRC2_CTRL_rom_output = decode_SRC2_CTRL;
    
    // Override for I-type ALU instructions (opcode=0010011) with non-zero rd
    assign decode_REGFILE_WRITE_VALID_corrected = 
        ((decode_INSTRUCTION[6:0] == 7'b0010011) && (decode_INSTRUCTION[11:7] != 5'h0)) ? 1'b1 :
        decode_REGFILE_WRITE_VALID_rom_output;
    
    // Override SRC2_CTRL for I-type ALU instructions (should select IMI=0x01 for immediate)
    assign decode_SRC2_CTRL_corrected = 
        (decode_INSTRUCTION[6:0] == 7'b0010011) ? 2'b01 :  // I-type ALU: use immediate (IMI)
        decode_SRC2_CTRL_rom_output;
    
    // Decode stage control signal assignments
    // Decode stage control signal pass-through assignments
    assign _zz_decode_to_execute_SHIFT_CTRL = _zz_decode_to_execute_SHIFT_CTRL_1;
    assign _zz_decode_to_execute_ALU_BITWISE_CTRL = _zz_decode_to_execute_ALU_BITWISE_CTRL_1;
    assign _zz_decode_to_execute_ALU_CTRL = _zz_decode_to_execute_ALU_CTRL_1;
    assign _zz_memory_to_writeBack_ENV_CTRL = _zz_memory_to_writeBack_ENV_CTRL_1;
    assign _zz_execute_to_memory_ENV_CTRL = _zz_execute_to_memory_ENV_CTRL_1;
    assign _zz_decode_to_execute_ENV_CTRL = _zz_decode_to_execute_ENV_CTRL_1;
    assign _zz_decode_to_execute_SRC2_CTRL = _zz_decode_to_execute_SRC2_CTRL_1;
    assign _zz_decode_to_execute_SRC1_CTRL = _zz_decode_to_execute_SRC1_CTRL_1;
    assign decode_CSR_READ_OPCODE = (decode_INSTRUCTION[13 : 7] != 7'h20);
    assign decode_CSR_WRITE_OPCODE = (! (((decode_INSTRUCTION[14 : 13] == 2'b01) && (decode_INSTRUCTION[19 : 15] == 5'h0)) || ((decode_INSTRUCTION[14 : 13] == 2'b11) && (decode_INSTRUCTION[19 : 15] == 5'h0))));
    assign decode_SRC2_FORCE_ZERO = (decode_SRC_ADD_ZERO && (! decode_SRC_USE_SUB_LESS));
    assign _zz_decode_to_execute_BRANCH_CTRL = _zz_decode_to_execute_BRANCH_CTRL_1;
    assign decode_BRANCH_CTRL = _zz_decode_BRANCH_CTRL;
    
    // Stage signal pass-through helpers (simplified - decoder provides direct outputs)
    assign _zz_decode_to_execute_SRC1_CTRL_1 = decode_SRC1_CTRL;
    assign _zz_execute_SRC1_CTRL = decode_to_execute_SRC1_CTRL;
    assign _zz_decode_to_execute_SRC2_CTRL_1 = decode_SRC2_CTRL_corrected;  // Use corrected SRC2_CTRL
    assign _zz_execute_SRC2_CTRL = decode_to_execute_SRC2_CTRL;
    assign _zz_decode_to_execute_ENV_CTRL_1 = decode_ENV_CTRL;
    assign _zz_execute_to_memory_ENV_CTRL_1 = execute_ENV_CTRL;
    assign _zz_memory_to_writeBack_ENV_CTRL_1 = memory_ENV_CTRL;
    assign _zz_execute_ENV_CTRL = decode_to_execute_ENV_CTRL;
    assign _zz_memory_ENV_CTRL = execute_to_memory_ENV_CTRL;
    assign _zz_writeBack_ENV_CTRL = memory_to_writeBack_ENV_CTRL;
    assign _zz_decode_to_execute_ALU_CTRL_1 = decode_ALU_CTRL;
    assign _zz_decode_to_execute_ALU_BITWISE_CTRL_1 = decode_ALU_BITWISE_CTRL;
    assign _zz_decode_to_execute_SHIFT_CTRL_1 = decode_SHIFT_CTRL;
    assign _zz_decode_to_execute_BRANCH_CTRL_1 = decode_BRANCH_CTRL;
    
    // Stage data propagation
    assign execute_PC = decode_to_execute_PC;
    assign execute_INSTRUCTION = decode_to_execute_INSTRUCTION;
    assign execute_ENV_CTRL = _zz_execute_ENV_CTRL;
    assign execute_BRANCH_CTRL = decode_to_execute_BRANCH_CTRL;
    assign execute_SHIFT_CTRL = decode_to_execute_SHIFT_CTRL;
    assign execute_ALU_BITWISE_CTRL = decode_to_execute_ALU_BITWISE_CTRL;
    assign execute_SRC_LESS_UNSIGNED = decode_to_execute_SRC_LESS_UNSIGNED;
    assign execute_ALU_CTRL = decode_to_execute_ALU_CTRL;
    assign execute_IS_CSR = decode_to_execute_IS_CSR;
    assign execute_MEMORY_STORE = decode_to_execute_MEMORY_STORE;
    assign execute_BYPASSABLE_MEMORY_STAGE = decode_to_execute_BYPASSABLE_MEMORY_STAGE;
    assign execute_BYPASSABLE_EXECUTE_STAGE = decode_to_execute_BYPASSABLE_EXECUTE_STAGE;
    assign execute_SRC2_CTRL = _zz_execute_SRC2_CTRL;
    assign execute_MEMORY_ENABLE = decode_to_execute_MEMORY_ENABLE;
    assign execute_SRC_USE_SUB_LESS = decode_to_execute_SRC_USE_SUB_LESS;
    assign execute_SRC1_CTRL = _zz_execute_SRC1_CTRL;
    assign execute_CSR_READ_OPCODE = decode_to_execute_CSR_READ_OPCODE;
    assign execute_CSR_WRITE_OPCODE = decode_to_execute_CSR_WRITE_OPCODE;
    assign execute_FORMAL_PC_NEXT = decode_to_execute_FORMAL_PC_NEXT;
    assign execute_RS1 = decode_to_execute_RS1;
    assign execute_RS2 = decode_to_execute_RS2;
    assign execute_SRC2_FORCE_ZERO = decode_to_execute_SRC2_FORCE_ZERO;
    assign execute_PREDICTION_HAD_BRANCHED1 = decode_to_execute_PREDICTION_HAD_BRANCHED1;
    assign execute_REGFILE_WRITE_VALID = decode_to_execute_REGFILE_WRITE_VALID;
    assign execute_MEMORY_ADDRESS_LOW = dBus_cmd_payload_address[1 : 0];
    
    assign memory_PC = execute_to_memory_PC;
    assign memory_INSTRUCTION = execute_to_memory_INSTRUCTION;
    assign memory_FORMAL_PC_NEXT = execute_to_memory_FORMAL_PC_NEXT;
    assign memory_MEMORY_ENABLE = execute_to_memory_MEMORY_ENABLE;
    assign memory_REGFILE_WRITE_VALID = execute_to_memory_REGFILE_WRITE_VALID;
    assign memory_BYPASSABLE_MEMORY_STAGE = execute_to_memory_BYPASSABLE_MEMORY_STAGE;
    assign memory_MEMORY_STORE = execute_to_memory_MEMORY_STORE;
    assign memory_ENV_CTRL = _zz_memory_ENV_CTRL;
    assign memory_MEMORY_ADDRESS_LOW = execute_to_memory_MEMORY_ADDRESS_LOW;
    assign memory_REGFILE_WRITE_DATA = execute_to_memory_REGFILE_WRITE_DATA;
    assign memory_MEMORY_READ_DATA = dBus_rsp_data;  // From original VexRiscv line 1698
    
    assign writeBack_PC = memory_to_writeBack_PC;
    assign writeBack_INSTRUCTION = memory_to_writeBack_INSTRUCTION;
    assign writeBack_FORMAL_PC_NEXT = memory_to_writeBack_FORMAL_PC_NEXT;
    assign writeBack_MEMORY_ENABLE = memory_to_writeBack_MEMORY_ENABLE;
    assign writeBack_REGFILE_WRITE_VALID = memory_to_writeBack_REGFILE_WRITE_VALID;
    assign writeBack_ENV_CTRL = _zz_writeBack_ENV_CTRL;
    assign writeBack_MEMORY_ADDRESS_LOW = memory_to_writeBack_MEMORY_ADDRESS_LOW;
    assign writeBack_REGFILE_WRITE_DATA = memory_to_writeBack_REGFILE_WRITE_DATA;
    assign writeBack_MEMORY_READ_DATA = memory_to_writeBack_MEMORY_READ_DATA;
    
    //==========================================================================
    // Pipeline Enable Signal Generation
    //==========================================================================
    
    assign when_Pipeline_l124 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_1 = (! memory_arbitration_isStuck);
    assign when_Pipeline_l124_2 = (! writeBack_arbitration_isStuck);
    assign when_Pipeline_l124_3 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_4 = (! memory_arbitration_isStuck);
    assign when_Pipeline_l124_5 = (! writeBack_arbitration_isStuck);
    assign when_Pipeline_l124_6 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_7 = (! memory_arbitration_isStuck);
    assign when_Pipeline_l124_8 = (! writeBack_arbitration_isStuck);
    assign when_Pipeline_l124_9 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_10 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_11 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_12 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_13 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_14 = (! memory_arbitration_isStuck);
    assign when_Pipeline_l124_15 = (! writeBack_arbitration_isStuck);
    assign when_Pipeline_l124_16 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_17 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_18 = (! memory_arbitration_isStuck);
    assign when_Pipeline_l124_19 = (! writeBack_arbitration_isStuck);
    assign when_Pipeline_l124_20 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_21 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_22 = (! memory_arbitration_isStuck);
    assign when_Pipeline_l124_23 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_24 = (! memory_arbitration_isStuck);
    assign when_Pipeline_l124_25 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_26 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_27 = (! memory_arbitration_isStuck);
    assign when_Pipeline_l124_28 = (! writeBack_arbitration_isStuck);
    assign when_Pipeline_l124_29 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_30 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_31 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_32 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_33 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_34 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_35 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_36 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_37 = (! execute_arbitration_isStuck);
    assign when_Pipeline_l124_38 = (! memory_arbitration_isStuck);
    assign when_Pipeline_l124_39 = (! writeBack_arbitration_isStuck);
    assign when_Pipeline_l124_40 = ((! memory_arbitration_isStuck) && (! execute_arbitration_isStuckByOthers));
    assign when_Pipeline_l124_41 = (! writeBack_arbitration_isStuck);
    assign when_Pipeline_l124_42 = (! writeBack_arbitration_isStuck);
    
    //==========================================================================
    // Arbitration Logic - Flush/Stall Propagation
    //==========================================================================
    
    // Flush propagation (backward from writeBack to decode)
    assign decode_arbitration_isFlushed = ((|{writeBack_arbitration_flushNext,{memory_arbitration_flushNext,execute_arbitration_flushNext}}) || (|{writeBack_arbitration_flushIt,{memory_arbitration_flushIt,{execute_arbitration_flushIt,decode_arbitration_flushIt}}}));
    assign execute_arbitration_isFlushed = ((|{writeBack_arbitration_flushNext,memory_arbitration_flushNext}) || (|{writeBack_arbitration_flushIt,{memory_arbitration_flushIt,execute_arbitration_flushIt}}));
    assign memory_arbitration_isFlushed = ((|writeBack_arbitration_flushNext) || (|{writeBack_arbitration_flushIt,memory_arbitration_flushIt}));
    assign writeBack_arbitration_isFlushed = (1'b0 || (|writeBack_arbitration_flushIt));
    
    // Stall propagation (forward from decode to writeBack)
    assign decode_arbitration_isStuckByOthers = (decode_arbitration_haltByOther || (((1'b0 || execute_arbitration_isStuck) || memory_arbitration_isStuck) || writeBack_arbitration_isStuck));
    assign decode_arbitration_isStuck = (decode_arbitration_haltItself || decode_arbitration_isStuckByOthers);
    assign decode_arbitration_isMoving = ((! decode_arbitration_isStuck) && (! decode_arbitration_removeIt));
    assign decode_arbitration_isFiring = ((decode_arbitration_isValid && (! decode_arbitration_isStuck)) && (! decode_arbitration_removeIt));
    
    assign execute_arbitration_isStuckByOthers = (execute_arbitration_haltByOther || ((1'b0 || memory_arbitration_isStuck) || writeBack_arbitration_isStuck));
    assign execute_arbitration_isStuck = (execute_arbitration_haltItself || execute_arbitration_isStuckByOthers);
    assign execute_arbitration_isMoving = ((! execute_arbitration_isStuck) && (! execute_arbitration_removeIt));
    assign execute_arbitration_isFiring = ((execute_arbitration_isValid && (! execute_arbitration_isStuck)) && (! execute_arbitration_removeIt));
    
    assign memory_arbitration_isStuckByOthers = (memory_arbitration_haltByOther || (1'b0 || writeBack_arbitration_isStuck));
    assign memory_arbitration_isStuck = (memory_arbitration_haltItself || memory_arbitration_isStuckByOthers);
    assign memory_arbitration_isMoving = ((! memory_arbitration_isStuck) && (! memory_arbitration_removeIt));
    assign memory_arbitration_isFiring = ((memory_arbitration_isValid && (! memory_arbitration_isStuck)) && (! memory_arbitration_removeIt));
    
    assign writeBack_arbitration_isStuckByOthers = (writeBack_arbitration_haltByOther || 1'b0);
    assign writeBack_arbitration_isStuck = (writeBack_arbitration_haltItself || writeBack_arbitration_isStuckByOthers);
    assign writeBack_arbitration_isMoving = ((! writeBack_arbitration_isStuck) && (! writeBack_arbitration_removeIt));
    assign writeBack_arbitration_isFiring = ((writeBack_arbitration_isValid && (! writeBack_arbitration_isStuck)) && (! writeBack_arbitration_removeIt));
    
    // Valid update conditions
    assign when_Pipeline_l151 = ((! execute_arbitration_isStuck) || execute_arbitration_removeIt);
    assign when_Pipeline_l154 = ((! decode_arbitration_isStuck) && (! decode_arbitration_removeIt));
    assign when_Pipeline_l151_1 = ((! memory_arbitration_isStuck) || memory_arbitration_removeIt);
    assign when_Pipeline_l154_1 = ((! execute_arbitration_isStuck) && (! execute_arbitration_removeIt));
    assign when_Pipeline_l151_2 = ((! writeBack_arbitration_isStuck) || writeBack_arbitration_removeIt);
    assign when_Pipeline_l154_2 = ((! memory_arbitration_isStuck) && (! memory_arbitration_removeIt));
    
    // Debug: Monitor stall conditions
    always @(posedge clk) begin
        if (decode_arbitration_isValid && decode_arbitration_isStuck) begin
            $display("[%0t] STALL: Decode stuck (haltItself=%0b, haltByOther=%0b, exec_stuck=%0b, mem_stuck=%0b, wb_stuck=%0b)", 
                     $time, decode_arbitration_haltItself, decode_arbitration_haltByOther,
                     execute_arbitration_isStuck, memory_arbitration_isStuck, writeBack_arbitration_isStuck);
        end
        if (!when_Pipeline_l154 && decode_arbitration_isValid) begin
            $display("[%0t] BLOCK: Execute NOT accepting from Decode (decode_stuck=%0b, decode_removeIt=%0b)", 
                     $time, decode_arbitration_isStuck, decode_arbitration_removeIt);
        end
    end
    
    //==========================================================================
    // Arbitration Control - Halt/Flush Conditions (Combinational)
    //==========================================================================
    
    // Decode stage arbitration
    assign decode_arbitration_haltItself = 1'b0;
    
    always_comb begin
        decode_arbitration_haltByOther = decode_arbitration_haltByOther_hazard;
        // CsrPlugin halt conditions can be OR'd here
    end
    
    always_comb begin
        decode_arbitration_removeIt = 1'b0;
        if(decode_arbitration_isFlushed) begin
            decode_arbitration_removeIt = 1'b1;
        end
    end
    
    assign decode_arbitration_flushIt = 1'b0;
    
    always_comb begin
        decode_arbitration_flushNext = 1'b0;
        // IBusSimplePlugin prediction jump would set this
    end
    
    // Execute stage arbitration
    always_comb begin
        execute_arbitration_haltItself = execute_arbitration_haltItself_shifter;
        // DBusSimplePlugin halt can be OR'd here
        // CsrPlugin blocked by side effects can be OR'd here
    end
    
    assign execute_arbitration_haltByOther = 1'b0;
    
    always_comb begin
        execute_arbitration_removeIt = 1'b0;
        if(execute_arbitration_isFlushed) begin
            execute_arbitration_removeIt = 1'b1;
        end
    end
    
    assign execute_arbitration_flushIt = 1'b0;
    
    always_comb begin
        execute_arbitration_flushNext = 1'b0;
        if(BranchPlugin_jumpInterface_valid) begin
            execute_arbitration_flushNext = 1'b1;
        end
    end
    
    // Memory stage arbitration
    always_comb begin
        memory_arbitration_haltItself = 1'b0;
        // DBusSimplePlugin memory wait would go here
    end
    
    assign memory_arbitration_haltByOther = 1'b0;
    
    always_comb begin
        memory_arbitration_removeIt = 1'b0;
        if(memory_arbitration_isFlushed) begin
            memory_arbitration_removeIt = 1'b1;
        end
    end
    
    assign memory_arbitration_flushIt = 1'b0;
    assign memory_arbitration_flushNext = 1'b0;
    
    // WriteBack stage arbitration
    assign writeBack_arbitration_haltItself = 1'b0;
    assign writeBack_arbitration_haltByOther = 1'b0;
    
    always_comb begin
        writeBack_arbitration_removeIt = 1'b0;
        if(writeBack_arbitration_isFlushed) begin
            writeBack_arbitration_removeIt = 1'b1;
        end
    end
    
    assign writeBack_arbitration_flushIt = 1'b0;
    assign writeBack_arbitration_flushNext = 1'b0;
    
    //==========================================================================
    // Register File Interface
    //==========================================================================
    
    assign RegFilePlugin_regFileReadAddress1 = decode_INSTRUCTION[19:15];
    assign RegFilePlugin_regFileReadAddress2 = decode_INSTRUCTION[24:20];
    // NOTE: decode_RS1/RS2 are driven by hazard module (includes forwarding logic)
    
    assign RegFilePlugin_regFileWrite_valid = (writeBack_REGFILE_WRITE_VALID && writeBack_arbitration_isFiring);
    assign RegFilePlugin_regFileWrite_payload_address = writeBack_INSTRUCTION[11:7];
    assign RegFilePlugin_regFileWrite_payload_data = writeBack_REGFILE_WRITE_DATA;
    
`ifdef DEBUG
    // Debug: Monitor register writes
    always @(posedge clk) begin
        if (writeBack_arbitration_isValid) begin
            $display("[%0t] WRITEBACK: isValid=%0b isFiring=%0b isStuck=%0b removeIt=%0b REGFILE_WRITE_VALID=%0b", 
                     $time, writeBack_arbitration_isValid, writeBack_arbitration_isFiring, 
                     writeBack_arbitration_isStuck, writeBack_arbitration_removeIt, writeBack_REGFILE_WRITE_VALID);
        end
        if (RegFilePlugin_regFileWrite_valid) begin
            $display("[%0t] REGFILE_WRITE: addr=x%0d data=0x%08x (inst=0x%08x)", 
                     $time, RegFilePlugin_regFileWrite_payload_address, 
                     RegFilePlugin_regFileWrite_payload_data, writeBack_INSTRUCTION);
        end
    end
`endif
    
    // Additional decode stage signal assignments
    assign decode_FORMAL_PC_NEXT = (decode_PC + 32'h00000004);
    // NOTE: decode_PREDICTION_HAD_BRANCHED1 is driven by IBus module
    
    //==========================================================================
    // Pipeline Register Sequential Logic
    //==========================================================================
    
    always_ff @(posedge clk) begin
        if(reset) begin
            // Reset downstream pipeline stage isValid signals
            // NOTE: decode_arbitration_isValid is managed by IBus module (vexriscv_ibus_simple.sv)
            execute_arbitration_isValid <= 1'b0;
            memory_arbitration_isValid <= 1'b0;
            writeBack_arbitration_isValid <= 1'b0;
        end else begin
            if(when_Pipeline_l124) begin
                decode_to_execute_PC <= decode_PC;
            end
            if(when_Pipeline_l124_1) begin
                execute_to_memory_PC <= execute_PC;
            end
            if(when_Pipeline_l124_2) begin
                memory_to_writeBack_PC <= memory_PC;
            end
            if(when_Pipeline_l124_3) begin
                decode_to_execute_INSTRUCTION <= decode_INSTRUCTION;
            end
            if(when_Pipeline_l124_4) begin
                execute_to_memory_INSTRUCTION <= execute_INSTRUCTION;
            end
            if(when_Pipeline_l124_5) begin
                memory_to_writeBack_INSTRUCTION <= memory_INSTRUCTION;
            end
            if(when_Pipeline_l124_6) begin
                decode_to_execute_FORMAL_PC_NEXT <= decode_FORMAL_PC_NEXT;
            end
            if(when_Pipeline_l124_7) begin
                execute_to_memory_FORMAL_PC_NEXT <= execute_FORMAL_PC_NEXT;
            end
            if(when_Pipeline_l124_8) begin
                memory_to_writeBack_FORMAL_PC_NEXT <= memory_FORMAL_PC_NEXT;
            end
            if(when_Pipeline_l124_9) begin
                decode_to_execute_CSR_WRITE_OPCODE <= decode_CSR_WRITE_OPCODE;
            end
            if(when_Pipeline_l124_10) begin
                decode_to_execute_CSR_READ_OPCODE <= decode_CSR_READ_OPCODE;
            end
            if(when_Pipeline_l124_11) begin
                decode_to_execute_SRC1_CTRL <= _zz_decode_to_execute_SRC1_CTRL;
            end
            if(when_Pipeline_l124_12) begin
                decode_to_execute_SRC_USE_SUB_LESS <= decode_SRC_USE_SUB_LESS;
            end
            if(when_Pipeline_l124_13) begin
                decode_to_execute_MEMORY_ENABLE <= decode_MEMORY_ENABLE;
            end
            if(when_Pipeline_l124_14) begin
                execute_to_memory_MEMORY_ENABLE <= execute_MEMORY_ENABLE;
            end
            if(when_Pipeline_l124_15) begin
                memory_to_writeBack_MEMORY_ENABLE <= memory_MEMORY_ENABLE;
            end
            if(when_Pipeline_l124_16) begin
                decode_to_execute_SRC2_CTRL <= _zz_decode_to_execute_SRC2_CTRL;
            end
            if(when_Pipeline_l124_17) begin
                decode_to_execute_REGFILE_WRITE_VALID <= decode_REGFILE_WRITE_VALID_corrected;
`ifdef DEBUG
                if (decode_REGFILE_WRITE_VALID_corrected) $display("[%0t] PIPE_REG: decode→execute REGFILE_WRITE_VALID=1 (inst=0x%08x)", $time, decode_INSTRUCTION);
`endif
            end
            if(when_Pipeline_l124_18) begin
                execute_to_memory_REGFILE_WRITE_VALID <= execute_REGFILE_WRITE_VALID;
`ifdef DEBUG
                if (execute_REGFILE_WRITE_VALID) $display("[%0t] PIPE_REG: execute→memory REGFILE_WRITE_VALID=1 (inst=0x%08x)", $time, execute_INSTRUCTION);
`endif
            end
            if(when_Pipeline_l124_19) begin
                memory_to_writeBack_REGFILE_WRITE_VALID <= memory_REGFILE_WRITE_VALID;
`ifdef DEBUG
                if (memory_REGFILE_WRITE_VALID) $display("[%0t] PIPE_REG: memory→writeBack REGFILE_WRITE_VALID=1 (inst=0x%08x)", $time, memory_INSTRUCTION);
`endif
            end
            if(when_Pipeline_l124_20) begin
                decode_to_execute_BYPASSABLE_EXECUTE_STAGE <= decode_BYPASSABLE_EXECUTE_STAGE;
            end
            if(when_Pipeline_l124_21) begin
                decode_to_execute_BYPASSABLE_MEMORY_STAGE <= decode_BYPASSABLE_MEMORY_STAGE;
            end
            if(when_Pipeline_l124_22) begin
                execute_to_memory_BYPASSABLE_MEMORY_STAGE <= execute_BYPASSABLE_MEMORY_STAGE;
            end
            if(when_Pipeline_l124_23) begin
                decode_to_execute_MEMORY_STORE <= decode_MEMORY_STORE;
            end
            if(when_Pipeline_l124_24) begin
                execute_to_memory_MEMORY_STORE <= execute_MEMORY_STORE;
            end
            if(when_Pipeline_l124_25) begin
                decode_to_execute_IS_CSR <= decode_IS_CSR;
            end
            if(when_Pipeline_l124_26) begin
                decode_to_execute_ENV_CTRL <= _zz_decode_to_execute_ENV_CTRL;
            end
            if(when_Pipeline_l124_27) begin
                execute_to_memory_ENV_CTRL <= _zz_execute_to_memory_ENV_CTRL;
            end
            if(when_Pipeline_l124_28) begin
                memory_to_writeBack_ENV_CTRL <= _zz_memory_to_writeBack_ENV_CTRL;
            end
            if(when_Pipeline_l124_29) begin
                decode_to_execute_ALU_CTRL <= _zz_decode_to_execute_ALU_CTRL;
            end
            if(when_Pipeline_l124_30) begin
                decode_to_execute_SRC_LESS_UNSIGNED <= decode_SRC_LESS_UNSIGNED;
            end
            if(when_Pipeline_l124_31) begin
                decode_to_execute_ALU_BITWISE_CTRL <= _zz_decode_to_execute_ALU_BITWISE_CTRL;
            end
            if(when_Pipeline_l124_32) begin
                decode_to_execute_SHIFT_CTRL <= _zz_decode_to_execute_SHIFT_CTRL;
            end
            if(when_Pipeline_l124_33) begin
                decode_to_execute_BRANCH_CTRL <= _zz_decode_to_execute_BRANCH_CTRL;
            end
            if(when_Pipeline_l124_34) begin
                decode_to_execute_RS1 <= decode_RS1;
            end
            if(when_Pipeline_l124_35) begin
                decode_to_execute_RS2 <= decode_RS2;
            end
            if(when_Pipeline_l124_36) begin
                decode_to_execute_SRC2_FORCE_ZERO <= decode_SRC2_FORCE_ZERO;
            end
            if(when_Pipeline_l124_37) begin
                decode_to_execute_PREDICTION_HAD_BRANCHED1 <= decode_PREDICTION_HAD_BRANCHED1;
            end
            if(when_Pipeline_l124_38) begin
                execute_to_memory_MEMORY_ADDRESS_LOW <= execute_MEMORY_ADDRESS_LOW;
            end
            if(when_Pipeline_l124_39) begin
                memory_to_writeBack_MEMORY_ADDRESS_LOW <= memory_MEMORY_ADDRESS_LOW;
            end
            if(when_Pipeline_l124_40) begin
                execute_to_memory_REGFILE_WRITE_DATA <= execute_REGFILE_WRITE_DATA;
            end
            if(when_Pipeline_l124_41) begin
                memory_to_writeBack_REGFILE_WRITE_DATA <= memory_REGFILE_WRITE_DATA;
            end
            if(when_Pipeline_l124_42) begin
                memory_to_writeBack_MEMORY_READ_DATA <= memory_MEMORY_READ_DATA;
            end
            
            // Valid propagation
            if(when_Pipeline_l151) begin
                execute_arbitration_isValid <= 1'b0;
`ifdef DEBUG
                if (execute_arbitration_isValid) $display("[%0t] PIPELINE: Execute cleared (removeIt or !isStuck)", $time);
`endif
            end
            if(when_Pipeline_l154) begin
                execute_arbitration_isValid <= decode_arbitration_isValid;
`ifdef DEBUG
                if (decode_arbitration_isValid) begin
                    $display("[%0t] PIPELINE: Execute gets valid from Decode (inst=0x%08x, pc=0x%08x)", 
                             $time, decode_INSTRUCTION, decode_PC);
                end
`endif
            end
            if(when_Pipeline_l151_1) begin
                memory_arbitration_isValid <= 1'b0;
`ifdef DEBUG
                if (memory_arbitration_isValid) $display("[%0t] PIPELINE: Memory cleared", $time);
`endif
            end
            if(when_Pipeline_l154_1) begin
                memory_arbitration_isValid <= execute_arbitration_isValid;
`ifdef DEBUG
                if (execute_arbitration_isValid) begin
                    $display("[%0t] PIPELINE: Memory gets valid from Execute (inst=0x%08x)", 
                             $time, execute_INSTRUCTION);
                end
`endif
            end
            if(when_Pipeline_l151_2) begin
                writeBack_arbitration_isValid <= 1'b0;
`ifdef DEBUG
                if (writeBack_arbitration_isValid) $display("[%0t] PIPELINE: WriteBack cleared", $time);
`endif
            end
            if(when_Pipeline_l154_2) begin
                writeBack_arbitration_isValid <= memory_arbitration_isValid;
`ifdef DEBUG
                if (memory_arbitration_isValid) begin
                    $display("[%0t] PIPELINE: WriteBack gets valid from Memory (inst=0x%08x)", 
                             $time, memory_INSTRUCTION);
                end
`endif
            end
        end
    end
    
    //==========================================================================
    // Debug Outputs
    //==========================================================================
    
    assign debug_pc = writeBack_PC;
    assign debug_instruction = writeBack_INSTRUCTION;
    assign debug_writeBack_regWrite = RegFilePlugin_regFileWrite_valid;
    assign debug_writeBack_regAddr = RegFilePlugin_regFileWrite_payload_address;
    assign debug_writeBack_regData = RegFilePlugin_regFileWrite_payload_data;

endmodule : vexriscv_top
