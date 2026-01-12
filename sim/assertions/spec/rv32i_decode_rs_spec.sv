`timescale 1ns / 1ps

//==============================================================================
// RV32I Decode/Forwarding Assertions
//==============================================================================
// Checks R-type decode fields and EX-stage operand selection for rs1/rs2.
//==============================================================================

module rv32i_decode_rs_spec (
    input  logic        clk,
    input  logic        rst,
    input  logic        soft_reset_active,
    input  logic        id_ex_valid,
    input  logic [31:0] id_ex_insn,
    input  logic [4:0]  id_ex_rs1_addr,
    input  logic [4:0]  id_ex_rs2_addr,
    input  logic [31:0] id_ex_rs1_data,
    input  logic [31:0] id_ex_rs2_data,
    input  logic [1:0]  id_ex_forward_rs1,
    input  logic [1:0]  id_ex_forward_rs2,
    input  logic [31:0] ex_rs1_forwarded,
    input  logic [31:0] ex_rs2_forwarded,
    input  logic [31:0] ex_mem_alu_result,
    input  logic [31:0] mem_forward_data,
    input  logic [31:0] wb_result
);

    localparam logic [6:0] OPCODE_RTYPE = 7'h33;

    // R-type decode fields must match instruction bits
    property p_rtype_decode_addrs;
        @(posedge clk) disable iff (rst || soft_reset_active)
        (id_ex_valid && (id_ex_insn[6:0] == OPCODE_RTYPE))
        |-> ((id_ex_rs1_addr == id_ex_insn[19:15]) &&
             (id_ex_rs2_addr == id_ex_insn[24:20]));
    endproperty

    assert_rtype_decode_addrs: assert property (p_rtype_decode_addrs)
        else $error("[RS_DECODE] R-type rs addr mismatch: insn=0x%08h rs1_addr=%0d rs2_addr=%0d",
                    id_ex_insn, id_ex_rs1_addr, id_ex_rs2_addr);

    // R-type operands presented to ALU must reflect forwarding selection
    property p_rtype_forward_mux;
        logic [31:0] exp_rs1;
        logic [31:0] exp_rs2;
        @(posedge clk) disable iff (rst || soft_reset_active)
        (id_ex_valid && (id_ex_insn[6:0] == OPCODE_RTYPE),
         exp_rs1 = (id_ex_forward_rs1 == 2'b00) ? id_ex_rs1_data :
                   (id_ex_forward_rs1 == 2'b01) ? ex_mem_alu_result :
                   (id_ex_forward_rs1 == 2'b10) ? mem_forward_data :
                                                 wb_result,
         exp_rs2 = (id_ex_forward_rs2 == 2'b00) ? id_ex_rs2_data :
                   (id_ex_forward_rs2 == 2'b01) ? ex_mem_alu_result :
                   (id_ex_forward_rs2 == 2'b10) ? mem_forward_data :
                                                 wb_result)
        |-> ((ex_rs1_forwarded == exp_rs1) && (ex_rs2_forwarded == exp_rs2));
    endproperty

    assert_rtype_forward_mux: assert property (p_rtype_forward_mux)
        else $error("[RS_FORWARD] R-type operand mismatch: insn=0x%08h rs1_sel=%b rs2_sel=%b exp_rs1=0x%08h got_rs1=0x%08h exp_rs2=0x%08h got_rs2=0x%08h",
                    id_ex_insn, id_ex_forward_rs1, id_ex_forward_rs2,
                    exp_rs1, ex_rs1_forwarded, exp_rs2, ex_rs2_forwarded);

endmodule
