`timescale 1ns / 1ps
//==============================================================================
// RV32I Instruction Decode Stage Timing Assertions
//==============================================================================
// SystemVerilog Assertions for Instruction Decode Stage
// Verifies x0 hardwire, register file write visibility, immediate generation,
// control signal correctness, and illegal instruction detection
//
// Bind this module to rv32i_id instance:
//   bind rv32i_id rv32i_id_timing_spec u_id_assertions (.*);
//==============================================================================

module rv32i_id_timing_spec
    import rv32i_isa_pkg::*;
    import rv32i_pipeline_pkg::*;
(
    input logic        clk,
    input logic        rst_n,
    
    // Pipeline inputs
    input logic [31:0] pc_in,
    input logic [31:0] insn_in,
    input logic        valid_in,
    
    // Register file interface
    input logic        rf_wen,
    input logic [4:0]  rf_waddr,
    input logic [31:0] rf_wdata,
    
    // CSR read
    input logic [31:0] csr_rdata,
    
    // Forwarding control
    input logic [1:0]  forward_rs1,
    input logic [1:0]  forward_rs2,
    
    // Outputs
    input logic [31:0] rs1_data_out,
    input logic [31:0] rs2_data_out,
    input logic [31:0] imm_out,
    input decode_ctrl_t ctrl_out,
    input logic        valid_out,
    input logic [11:0] csr_raddr,
    
    // Internal signals for checking
    input logic [31:0] regfile [0:31],
    input logic [4:0]  rs1_addr,
    input logic [4:0]  rs2_addr
);

    //==========================================================================
    // SPEC-ID-1: x0 Always Reads Zero
    //==========================================================================
    // Verify reads from x0 always return 0x00000000
    
    property x0_reads_zero_rs1;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && (rs1_addr == 5'b0))
        |-> (rs1_data_out == 32'h00000000);
    endproperty
    
    assert_x0_rs1: assert property (x0_reads_zero_rs1)
        else $error("[SPEC-ID-1] x0 read returned non-zero for RS1: rs1_addr=x0 rs1_data=0x%08h (expected 0)",
                    rs1_data_out);
    
    property x0_reads_zero_rs2;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && (rs2_addr == 5'b0))
        |-> (rs2_data_out == 32'h00000000);
    endproperty
    
    assert_x0_rs2: assert property (x0_reads_zero_rs2)
        else $error("[SPEC-ID-1] x0 read returned non-zero for RS2: rs2_addr=x0 rs2_data=0x%08h (expected 0)",
                    rs2_data_out);

    //==========================================================================
    // SPEC-ID-2: Register File Write Visibility
    //==========================================================================
    // Verify RF write is visible on next cycle read
    
    property rf_write_visible;
        logic [4:0] write_reg;
        logic [31:0] write_data;
        @(posedge clk) disable iff (!rst_n)
        (rf_wen && (rf_waddr != 5'b0), write_reg = rf_waddr, write_data = rf_wdata)
        |-> ##1 (regfile[write_reg] == write_data);
    endproperty
    
    assert_rf_visible: assert property (rf_write_visible)
        else $error("[SPEC-ID-2] RF write not visible: wrote x%0d=0x%08h but regfile[x%0d]=0x%08h",
                    rf_waddr, rf_wdata, rf_waddr, regfile[rf_waddr]);

    //==========================================================================
    // SPEC-ID-3: I-Type Immediate Sign Extension
    //==========================================================================
    // Verify I-type instructions have 12-bit immediate sign-extended to 32 bits
    
    logic [6:0] opcode;
    assign opcode = insn_in[6:0];
    
    property i_type_imm_sign_ext;
        logic [31:0] expected_imm;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && ((opcode == OPC_OP_IMM) || (opcode == OPC_LOAD) || (opcode == OPC_JALR)),
         expected_imm = {{20{insn_in[31]}}, insn_in[31:20]})
        |-> (imm_out == expected_imm);
    endproperty
    
    assert_i_imm: assert property (i_type_imm_sign_ext)
        else $error("[SPEC-ID-3] I-type immediate wrong: insn=0x%08h expected_imm=0x%08h got_imm=0x%08h",
                    insn_in, {{20{insn_in[31]}}, insn_in[31:20]}, imm_out);

    //==========================================================================
    // SPEC-ID-4: ADDI Control Signal Correctness
    //==========================================================================
    // Verify ADDI instruction generates correct control signals
    
    logic is_addi;
    assign is_addi = (opcode == OPC_OP_IMM) && (insn_in[14:12] == 3'b000);
    
    property addi_control_signals;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && is_addi)
        |-> (ctrl_out.rf_wen && 
             (ctrl_out.alu_op == ALU_ADD) && 
             ctrl_out.alu_src2_imm &&
             !ctrl_out.mem_read && 
             !ctrl_out.mem_write);
    endproperty
    
    assert_addi_ctrl: assert property (addi_control_signals)
        else $error("[SPEC-ID-4] ADDI control signals wrong: insn=0x%08h rf_wen=%b alu_op=%0d alu_src2_imm=%b",
                    insn_in, ctrl_out.rf_wen, ctrl_out.alu_op, ctrl_out.alu_src2_imm);

    //==========================================================================
    // SPEC-ID-5: Illegal Instruction Detection
    //==========================================================================
    // Verify illegal instructions set illegal flag and invalidate output
    
    property illegal_insn_detected;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && ctrl_out.illegal)
        |-> !valid_out;
    endproperty
    
    assert_illegal: assert property (illegal_insn_detected)
        else $error("[SPEC-ID-5] Illegal instruction not invalidated: insn=0x%08h illegal=%b valid_out=%b",
                    insn_in, ctrl_out.illegal, valid_out);

    //==========================================================================
    // SPEC-ID-6: CSR Address Extraction
    //==========================================================================
    // Verify CSR instructions extract correct CSR address
    
    property csr_addr_extraction;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && (opcode == OPC_SYSTEM) && (insn_in[14:12] != 3'b000))
        |-> (csr_raddr == insn_in[31:20]);
    endproperty
    
    assert_csr_addr: assert property (csr_addr_extraction)
        else $error("[SPEC-ID-6] CSR address wrong: insn=0x%08h expected_addr=0x%03h got_addr=0x%03h",
                    insn_in, insn_in[31:20], csr_raddr);

    //==========================================================================
    // Coverage: Instruction Opcode Coverage
    //==========================================================================
    
    covergroup opcode_cg @(posedge clk);
        option.per_instance = 1;
        option.name = "id_opcode_coverage";
        
        opcode_type: coverpoint opcode iff (valid_in) {
            bins lui      = {OPC_LUI};
            bins auipc    = {OPC_AUIPC};
            bins jal      = {OPC_JAL};
            bins jalr     = {OPC_JALR};
            bins branch   = {OPC_BRANCH};
            bins load     = {OPC_LOAD};
            bins store    = {OPC_STORE};
            bins op_imm   = {OPC_OP_IMM};
            bins op       = {OPC_OP};
            bins misc_mem = {OPC_MISC_MEM};
            bins system   = {OPC_SYSTEM};
        }
    endgroup
    
    opcode_cg opcode_cov = new();
    
    //==========================================================================
    // Coverage: Register Address Coverage
    //==========================================================================
    
    covergroup register_cg @(posedge clk);
        option.per_instance = 1;
        option.name = "id_register_access";
        
        rs1_register: coverpoint rs1_addr iff (valid_in) {
            bins x0  = {5'd0};
            bins x1  = {5'd1};   // ra
            bins x2  = {5'd2};   // sp
            bins x10_x17 = {[5'd10:5'd17]}; // a0-a7
            bins others = default;
        }
        
        rs2_register: coverpoint rs2_addr iff (valid_in) {
            bins x0  = {5'd0};
            bins x1  = {5'd1};
            bins x2  = {5'd2};
            bins x10_x17 = {[5'd10:5'd17]};
            bins others = default;
        }
        
        rd_register: coverpoint ctrl_out.rd_addr iff (valid_in && ctrl_out.rf_wen) {
            bins x0  = {5'd0};   // Should be suppressed in WB
            bins x1  = {5'd1};
            bins x2  = {5'd2};
            bins x10_x17 = {[5'd10:5'd17]};
            bins others = default;
        }
    endgroup
    
    register_cg register_cov = new();
    
    //==========================================================================
    // Coverage: Immediate Format Coverage
    //==========================================================================
    
    covergroup immediate_cg @(posedge clk);
        option.per_instance = 1;
        option.name = "id_immediate_format";
        
        imm_format: coverpoint opcode iff (valid_in) {
            bins i_type = {OPC_OP_IMM, OPC_LOAD, OPC_JALR};
            bins s_type = {OPC_STORE};
            bins b_type = {OPC_BRANCH};
            bins u_type = {OPC_LUI, OPC_AUIPC};
            bins j_type = {OPC_JAL};
        }
        
        // Check immediate sign bit coverage
        imm_sign: coverpoint imm_out[31] iff (valid_in && ctrl_out.alu_src2_imm) {
            bins positive = {1'b0};
            bins negative = {1'b1};
        }
    endgroup
    
    immediate_cg immediate_cov = new();

endmodule : rv32i_id_timing_spec
