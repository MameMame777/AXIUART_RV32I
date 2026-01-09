`timescale 1ns / 1ps

//==============================================================================
// RV32I Control and Status Register (CSR) Module
//==============================================================================
// Implements minimum RISC-V Machine Mode CSRs for exception handling:
//   - mepc (0x341):   Machine Exception Program Counter
//   - mcause (0x342): Machine Cause Register
//   - mtval (0x343):  Machine Trap Value
//   - mtvec (0x305):  Machine Trap Vector Base Address
//
// This module provides:
//   - CSR read/write interface for CSR instructions (CSRRW/CSRRS/CSRRC)
//   - Exception trap interface for automatic CSR updates on EBREAK
//   - mret interface for exception return (PC restoration)
//   - Debug read interface for external CSR inspection
//
// Features:
//   - Address-based CSR access with 12-bit addressing
//   - Atomic read-modify-write operations
//   - Exception trap causes immediate CSR update (synchronous)
//   - Reset values: all zeros (mtvec must be initialized by software)
//
// Author: GitHub Copilot
// Date: 2026-01-04
// License: MIT
//==============================================================================

module rv32i_csr (
    input  logic        clk,
    input  logic        rst,
    
    //==========================================================================
    // CSR Instruction Interface (from CPU pipeline)
    //==========================================================================
    // Read port (combinational - used in ID stage)
    input  logic [11:0] csr_raddr,      // CSR address to read
    output logic [31:0] csr_rdata,      // CSR read data (combinational)
    
    // Write port (synchronous - commits in WB stage)
    input  logic [11:0] csr_waddr,      // CSR address to write
    input  logic [31:0] csr_wdata,      // CSR write data
    input  logic        csr_wen,        // CSR write enable
    
    //==========================================================================
    // Exception Trap Interface
    //==========================================================================
    // Triggered by EBREAK or other exceptions in MEM stage
    input  logic        exception_trap,     // Exception occurred (1-cycle pulse)
    input  logic [31:0] exception_pc,       // PC value to save in mepc
    input  logic [4:0]  exception_code,     // Exception cause code (3=EBREAK)
    input  logic [31:0] exception_tval,     // Trap value (usually 0 for EBREAK)
    
    output logic [31:0] trap_vector,        // mtvec value for PC redirection
    
    //==========================================================================
    // MRET Instruction Interface
    //==========================================================================
    // Triggered by MRET instruction in MEM stage
    input  logic        mret_req,           // mret instruction detected
    output logic [31:0] mret_pc,            // mepc value for PC restoration
    
    //==========================================================================
    // Debug Interface (external CSR read when CPU halted)
    //==========================================================================
    input  logic [11:0] dbg_csr_addr,       // Debug CSR address
    output logic [31:0] dbg_csr_rdata       // Debug CSR read data (combinational)
);

    //==========================================================================
    // CSR Address Definitions (RISC-V Privileged Spec)
    //==========================================================================
    localparam logic [11:0] CSR_MTVEC  = 12'h305;  // Machine Trap Vector
    localparam logic [11:0] CSR_MEPC   = 12'h341;  // Machine Exception PC
    localparam logic [11:0] CSR_MCAUSE = 12'h342;  // Machine Cause
    localparam logic [11:0] CSR_MTVAL  = 12'h343;  // Machine Trap Value
    
    //==========================================================================
    // CSR Register Storage
    //==========================================================================
    logic [31:0] mepc_reg;      // Machine Exception Program Counter
    logic [31:0] mcause_reg;    // Machine Cause Register
    logic [31:0] mtval_reg;     // Machine Trap Value
    logic [31:0] mtvec_reg;     // Machine Trap Vector Base Address
    
    //==========================================================================
    // CSR Write Logic
    //==========================================================================
    // Priority: Exception trap (highest) > CSR instruction write
    // Exception trap writes are synchronous with trap event
    // CSR instruction writes commit in WB stage
    
    always_ff @(posedge clk) begin
        if (rst) begin
            mepc_reg   <= 32'h0000_0000;
            mcause_reg <= 32'h0000_0000;
            mtval_reg  <= 32'h0000_0000;
            mtvec_reg  <= 32'h0000_0200;  // Default handler at 0x200
        end else begin
            // Exception trap writes (highest priority)
            if (exception_trap) begin
                mepc_reg   <= exception_pc;
                mcause_reg <= {27'b0, exception_code};  // Bit 31=0 (exception, not interrupt)
                mtval_reg  <= exception_tval;
            end
            // CSR instruction writes (lower priority)
            else if (csr_wen) begin
                case (csr_waddr)
                    CSR_MTVEC:  mtvec_reg  <= csr_wdata;
                    CSR_MEPC:   mepc_reg   <= csr_wdata;
                    CSR_MCAUSE: mcause_reg <= csr_wdata;
                    CSR_MTVAL:  mtval_reg  <= csr_wdata;
                    default: ; // Ignore writes to non-existent CSRs
                endcase
            end
        end
    end
    
    //==========================================================================
    // CSR Read Logic (Combinational)
    //==========================================================================
    // Used by CSR instructions in ID stage
    // Returns current CSR value before any WB stage writes
    
    always_comb begin
        case (csr_raddr)
            CSR_MTVEC:  csr_rdata = mtvec_reg;
            CSR_MEPC:   csr_rdata = mepc_reg;
            CSR_MCAUSE: csr_rdata = mcause_reg;
            CSR_MTVAL:  csr_rdata = mtval_reg;
            default:    csr_rdata = 32'h0000_0000;  // Non-existent CSRs read as 0
        endcase
    end
    
    //==========================================================================
    // Debug CSR Read Logic (Combinational)
    //==========================================================================
    // External interface for debugging (UART access when CPU halted)
    
    always_comb begin
        case (dbg_csr_addr)
            CSR_MTVEC:  dbg_csr_rdata = mtvec_reg;
            CSR_MEPC:   dbg_csr_rdata = mepc_reg;
            CSR_MCAUSE: dbg_csr_rdata = mcause_reg;
            CSR_MTVAL:  dbg_csr_rdata = mtval_reg;
            default:    dbg_csr_rdata = 32'h0000_0000;
        endcase
    end
    
    //==========================================================================
    // Exception/MRET Output Interfaces
    //==========================================================================
    
    assign trap_vector = mtvec_reg;  // PC jumps here on exception
    assign mret_pc     = mepc_reg;   // PC restores here on mret
    
    //==========================================================================
    // Assertions for Verification
    //==========================================================================
    
    `ifdef FORMAL_VERIFICATION
    // Property: Exception trap updates mepc with correct PC
    property exception_updates_mepc;
        @(posedge clk) disable iff (rst)
        exception_trap |=> (mepc_reg == $past(exception_pc));
    endproperty
    assert_exception_mepc: assert property (exception_updates_mepc);
    
    // Property: Exception trap updates mcause with correct code
    property exception_updates_mcause;
        @(posedge clk) disable iff (rst)
        exception_trap |=> (mcause_reg[4:0] == $past(exception_code));
    endproperty
    assert_exception_mcause: assert property (exception_updates_mcause);
    
    // Property: CSR writes do not occur during exception trap
    property csr_write_blocked_during_trap;
        @(posedge clk) disable iff (rst)
        exception_trap |-> !csr_wen;
    endproperty
    assert_no_csr_write_on_trap: assert property (csr_write_blocked_during_trap);
    `endif

endmodule : rv32i_csr
