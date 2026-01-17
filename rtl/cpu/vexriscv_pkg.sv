`timescale 1ns/1ps
//==============================================================================
// VexRiscv SystemVerilog Package
// 
// Type definitions and constants for modular VexRiscv implementation
// Extracted from SpinalHDL-generated VexRiscv_GenSmallAndProductive
//==============================================================================

package vexriscv_pkg;

    //==========================================================================
    // Control Enumerations
    //==========================================================================
    
    typedef enum logic [1:0] {
        BRANCH_INC  = 2'd0,
        BRANCH_B    = 2'd1,
        BRANCH_JAL  = 2'd2,
        BRANCH_JALR = 2'd3
    } branch_ctrl_t;
    
    typedef enum logic [1:0] {
        SHIFT_DISABLE = 2'd0,
        SHIFT_SLL     = 2'd1,
        SHIFT_SRL     = 2'd2,
        SHIFT_SRA     = 2'd3
    } shift_ctrl_t;
    
    typedef enum logic [1:0] {
        ALU_BITWISE_XOR = 2'd0,
        ALU_BITWISE_OR  = 2'd1,
        ALU_BITWISE_AND = 2'd2
    } alu_bitwise_ctrl_t;
    
    typedef enum logic [1:0] {
        ALU_ADD_SUB  = 2'd0,
        ALU_SLT_SLTU = 2'd1,
        ALU_BITWISE  = 2'd2
    } alu_ctrl_t;
    
    typedef enum logic {
        ENV_NONE = 1'd0,
        ENV_XRET = 1'd1
    } env_ctrl_t;
    
    typedef enum logic [1:0] {
        SRC2_RS  = 2'd0,
        SRC2_IMI = 2'd1,
        SRC2_IMS = 2'd2,
        SRC2_PC  = 2'd3
    } src2_ctrl_t;
    
    typedef enum logic [1:0] {
        SRC1_RS           = 2'd0,
        SRC1_IMU          = 2'd1,
        SRC1_PC_INCREMENT = 2'd2,
        SRC1_URS1         = 2'd3
    } src1_ctrl_t;

    //==========================================================================
    // Arbitration Control Structure
    //==========================================================================
    
    typedef struct packed {
        logic isValid;
        logic isStuck;
        logic isStuckByOthers;
        logic isFlushed;
        logic isMoving;
        logic isFiring;
        logic haltItself;
        logic haltByOther;
        logic removeIt;
        logic flushIt;
        logic flushNext;
    } arbitration_t;

    //==========================================================================
    // Register File Write Port Structure
    //==========================================================================
    
    typedef struct packed {
        logic        valid;
        logic [4:0]  address;
        logic [31:0] data;
    } regfile_write_t;

    //==========================================================================
    // Bus Interface Structures
    //==========================================================================
    
    // Instruction Bus Command
    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
    } ibus_cmd_t;
    
    // Instruction Bus Response
    typedef struct packed {
        logic        valid;
        logic        error;
        logic [31:0] inst;
    } ibus_rsp_t;
    
    // Data Bus Command
    typedef struct packed {
        logic        valid;
        logic        wr;
        logic [3:0]  mask;
        logic [31:0] address;
        logic [31:0] data;
        logic [1:0]  size;
    } dbus_cmd_t;
    
    // Data Bus Response
    typedef struct packed {
        logic        ready;
        logic        error;
        logic [31:0] data;
    } dbus_rsp_t;

endpackage : vexriscv_pkg
