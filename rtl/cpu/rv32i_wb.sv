`timescale 1ns / 1ps

//==============================================================================
// RV32I Write Back (WB) Stage Module
//==============================================================================
// Combinational logic for result multiplexing, register file write control,
// and CSR write control. Implements x0 write suppression per RISC-V spec.
//
// See: rtl/cpu/rv32i_wb_spec.md for detailed specification
//==============================================================================

module rv32i_wb
    import rv32i_isa_pkg::*;
    import rv32i_pipeline_pkg::*;
(
    // MEM/WB pipeline register inputs
    input  logic [31:0]   pc,
    input  logic [31:0]   insn,
    input  logic [31:0]   mem_data,
    input  logic [31:0]   alu_result,
    input  logic [31:0]   csr_rdata,
    input  decode_ctrl_t  ctrl,
    input  logic          valid,
    
    // Pre-calculated PC+4 for timing optimization
    input  logic [31:0]   pc_plus4_precalc,
    
    // Register file write interface
    output logic          rf_wen,
    output logic [4:0]    rf_waddr,
    output logic [31:0]   rf_wdata,
    
    // CSR write interface
    output logic          csr_wen,
    output logic [11:0]   csr_waddr,
    output logic [31:0]   csr_wdata,
    
    // Forwarding output (to hazard unit)
    output logic [31:0]   wb_result
);

    //==========================================================================
    // Result Multiplexer (4-way)
    //==========================================================================
    // Select final writeback value based on instruction type
    // Sources: ALU result, Memory data, PC+4, CSR read value
    
    always_comb begin
        case (ctrl.wb_src)
            WB_ALU:  wb_result = alu_result;       // ALU operations, LUI, AUIPC
            WB_MEM:  wb_result = mem_data;         // Load instructions
            WB_PC4:  wb_result = pc_plus4_precalc; // JAL, JALR (pre-calculated, breaks CARRY4 chain)
            WB_CSR:  wb_result = csr_rdata;        // CSR instructions
            default: wb_result = alu_result;
        endcase
    end
    
    //==========================================================================
    // Register File Write Control
    //==========================================================================
    // Generate register file write signals with x0 suppression
    // x0 is hardwired to zero and cannot be written (RISC-V spec requirement)
    
    logic [4:0] rd_addr;
    assign rd_addr = ctrl.rd_addr;
    
    assign rf_wen   = valid && ctrl.rf_wen && (rd_addr != 5'b0);
    assign rf_waddr = rd_addr;
    assign rf_wdata = wb_result;
    
    //==========================================================================
    // CSR Write Control
    //==========================================================================
    // Generate CSR write signals for CSRRW/CSRRS/CSRRC instructions
    
    assign csr_wen   = valid && ctrl.is_csr && ctrl.csr_op[1];  // CSR write bit
    assign csr_waddr = ctrl.csr_addr;
    assign csr_wdata = wb_result;
    
endmodule : rv32i_wb
