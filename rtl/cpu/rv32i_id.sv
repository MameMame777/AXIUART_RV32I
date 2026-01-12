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
    
    // Debug: Internal signals for waveform visibility (all 32 registers)
    logic [31:0] dbg_x0,  dbg_x1,  dbg_x2,  dbg_x3,  dbg_x4,  dbg_x5,  dbg_x6,  dbg_x7;
    logic [31:0] dbg_x8,  dbg_x9,  dbg_x10, dbg_x11, dbg_x12, dbg_x13, dbg_x14, dbg_x15;
    logic [31:0] dbg_x16, dbg_x17, dbg_x18, dbg_x19, dbg_x20, dbg_x21, dbg_x22, dbg_x23;
    logic [31:0] dbg_x24, dbg_x25, dbg_x26, dbg_x27, dbg_x28, dbg_x29, dbg_x30, dbg_x31;
    
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
    //
    // CRITICAL FIX: Internal forwarding (write-through) for WB-to-ID hazards
    // When WB stage writes to regfile at posedge, ID stage may read the same
    // register in the SAME cycle. Without forwarding, ID gets stale value.
    // Solution: Bypass WB write data directly to read ports when addresses match.
    //==========================================================================
    
    logic [31:0] rf_rdata1_raw, rf_rdata2_raw;
    
    // Raw register file reads (without forwarding)
    assign rf_rdata1_raw = (rs1_addr == 5'b0) ? 32'h0 : regfile[rs1_addr];
    assign rf_rdata2_raw = (rs2_addr == 5'b0) ? 32'h0 : regfile[rs2_addr];
    
    // Internal forwarding from WB stage (write-through)
    // If WB is writing to the same register we're reading, bypass the write data
    logic wb_to_id_fwd_rs1, wb_to_id_fwd_rs2;
    assign wb_to_id_fwd_rs1 = rf_wen && (rf_waddr != 5'b0) && (rf_waddr == rs1_addr);
    assign wb_to_id_fwd_rs2 = rf_wen && (rf_waddr != 5'b0) && (rf_waddr == rs2_addr);
    
    // Final read data with internal forwarding
    assign rf_rdata1 = wb_to_id_fwd_rs1 ? rf_wdata : rf_rdata1_raw;
    assign rf_rdata2 = wb_to_id_fwd_rs2 ? rf_wdata : rf_rdata2_raw;
    
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
    
    // Debug: Assign register file to named signals for waveform visibility
    assign dbg_x0  = regfile[0];  assign dbg_x1  = regfile[1];  assign dbg_x2  = regfile[2];  assign dbg_x3  = regfile[3];
    assign dbg_x4  = regfile[4];  assign dbg_x5  = regfile[5];  assign dbg_x6  = regfile[6];  assign dbg_x7  = regfile[7];
    assign dbg_x8  = regfile[8];  assign dbg_x9  = regfile[9];  assign dbg_x10 = regfile[10]; assign dbg_x11 = regfile[11];
    assign dbg_x12 = regfile[12]; assign dbg_x13 = regfile[13]; assign dbg_x14 = regfile[14]; assign dbg_x15 = regfile[15];
    assign dbg_x16 = regfile[16]; assign dbg_x17 = regfile[17]; assign dbg_x18 = regfile[18]; assign dbg_x19 = regfile[19];
    assign dbg_x20 = regfile[20]; assign dbg_x21 = regfile[21]; assign dbg_x22 = regfile[22]; assign dbg_x23 = regfile[23];
    assign dbg_x24 = regfile[24]; assign dbg_x25 = regfile[25]; assign dbg_x26 = regfile[26]; assign dbg_x27 = regfile[27];
    assign dbg_x28 = regfile[28]; assign dbg_x29 = regfile[29]; assign dbg_x30 = regfile[30]; assign dbg_x31 = regfile[31];

endmodule : rv32i_id
