`timescale 1ns / 1ps
//==============================================================================
// RV32I Instruction Decode Stage (ID)
//==============================================================================
// Combinational logic for instruction decoding and register file reads
// All pipeline registers instantiated in rv32i_top
//==============================================================================

module rv32i_id
    import rv32i_isa_pkg::*;
    import rv32i_pipeline_pkg::*;
(
    // Clock and reset (for sequential register file only)
    input  logic        clk,
    input  logic        rst,
    
    // Pipeline input from IF/ID register
    input  logic [31:0] pc_in,
    input  logic [31:0] insn_in,
    input  logic        valid_in,
    
    // Register file write interface (from WB stage)
    input  logic        rf_wen,
    input  logic [4:0]  rf_waddr,
    input  logic [31:0] rf_wdata,
    
    // CSR read interface (from CSR module)
    input  logic [31:0] csr_rdata,
    
    // Forwarding control inputs (from hazard unit)
    input  logic [1:0]  forward_rs1,
    input  logic [1:0]  forward_rs2,
    
    // Decode outputs
    output logic [31:0] pc_out,
    output logic [31:0] insn_out,
    output logic [31:0] rs1_data_out,
    output logic [31:0] rs2_data_out,
    output logic [31:0] imm_out,
    output logic [31:0] csr_rdata_out,
    output logic [1:0]  forward_rs1_out,
    output logic [1:0]  forward_rs2_out,
    output decode_ctrl_t ctrl_out,
    output logic        valid_out,
    
    // CSR address output for CSR module read
    output logic [11:0] csr_raddr
);

    //==========================================================================
    // REGISTER FILE IMPLEMENTATION
    //==========================================================================
    // 32x32-bit register file with x0 hardwired to zero
    // - Combinational read (2 read ports)
    // - Synchronous write on positive edge (1 write port)
    // - x0 writes are legal but ignored
    //==========================================================================
    
    logic [31:0] regfile [0:31];
    logic [31:0] rf_rdata1;
    logic [31:0] rf_rdata2;
    
    // Decode stage register addresses
    logic [4:0] rs1_addr;
    logic [4:0] rs2_addr;
    
    //==========================================================================
    // INSTRUCTION DECODER
    //==========================================================================
    // Uses decode_insn() function from rv32i_isa_pkg.sv
    // Generates all control signals for pipeline stages
    //==========================================================================
    
    decode_ctrl_t decoded_ctrl;
    
    // Decode instruction using ISA package function
    assign decoded_ctrl = decode_insn(insn_in);
    
    // Extract register addresses
    assign rs1_addr = decoded_ctrl.rs1_addr;
    assign rs2_addr = decoded_ctrl.rs2_addr;
    
    // CSR read address output
    assign csr_raddr = decoded_ctrl.csr_addr;
    
    //==========================================================================
    // REGISTER FILE READ
    //==========================================================================
    // Combinational read with x0 hardwire to zero
    // Critical RISC-V requirement: reads from x0 always return 0
    //==========================================================================
    
    assign rf_rdata1 = (rs1_addr == 5'b0) ? 32'h0 : regfile[rs1_addr];
    assign rf_rdata2 = (rs2_addr == 5'b0) ? 32'h0 : regfile[rs2_addr];
    
    //==========================================================================
    // REGISTER FILE WRITE
    //==========================================================================
    // Synchronous write on positive edge
    // x0 protection: writes to x0 are legal but ignored
    //==========================================================================
    
    always_ff @(posedge clk) begin
        if (rst) begin
            // Reset all registers to 0
            for (int i = 0; i < 32; i++) begin
                regfile[i] <= 32'h0;
            end
        end else begin
            // Write to register file (ignore writes to x0)
            if (rf_wen && rf_waddr != 5'b0) begin
                regfile[rf_waddr] <= rf_wdata;
            end
        end
    end
    
    //==========================================================================
    // OUTPUT ASSIGNMENTS
    //==========================================================================
    // Pass through pipeline data and decoded control signals
    //==========================================================================
    
    assign pc_out           = pc_in;
    assign insn_out         = insn_in;
    assign rs1_data_out     = rf_rdata1;
    assign rs2_data_out     = rf_rdata2;
    assign imm_out          = decoded_ctrl.immediate;
    assign csr_rdata_out    = csr_rdata;
    assign forward_rs1_out  = forward_rs1;
    assign forward_rs2_out  = forward_rs2;
    assign ctrl_out         = decoded_ctrl;
    assign valid_out        = valid_in && !decoded_ctrl.illegal;  // Invalidate on illegal instruction

endmodule : rv32i_id
