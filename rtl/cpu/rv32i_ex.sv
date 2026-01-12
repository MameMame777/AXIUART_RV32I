`timescale 1ns / 1ps

//==============================================================================
// RV32I Execute (EX) Stage Module
//==============================================================================
// Combinational logic for ALU operations, branch condition evaluation,
// and jump target calculation. Forwarding muxes select operands based on
// pre-computed forwarding control from ID stage.
//
// See: rtl/cpu/rv32i_ex_spec.md for detailed specification
//==============================================================================

module rv32i_ex
    import rv32i_isa_pkg::*;
    import rv32i_pipeline_pkg::*;
(
    // ID/EX pipeline register inputs
    input  logic [31:0]   pc,
    input  logic [31:0]   insn,
    input  logic [31:0]   rs1_data,
    input  logic [31:0]   rs2_data,
    input  logic [31:0]   imm,
    input  logic [1:0]    forward_rs1,
    input  logic [1:0]    forward_rs2,
    input  decode_ctrl_t  ctrl,
    input  logic          valid,
    
    // Forwarding data inputs
    input  logic [31:0]   ex_forward_data,   // From EX/MEM register
    input  logic [31:0]   mem_forward_data,  // From MEM/WB register
    input  logic [31:0]   wb_forward_data,   // From WB stage
    
    // Flush control
    input  logic          ex_flush,
    
    // Outputs to EX/MEM register
    output logic [31:0]   alu_result,
    output logic [31:0]   rs2_forwarded_out,  // For stores
    output logic          branch_taken,
    output logic [31:0]   branch_target,
    output logic          valid_out,
    
    // Debug outputs for trace buffer
    output logic [31:0]   rs1_forwarded_out,  // Forwarded rs1 value (for trace)
    output logic [31:0]   rs2_forwarded_out_trace  // Forwarded rs2 value (for trace, same as rs2_forwarded_out)
);

    //==========================================================================
    // Forwarding Multiplexers (4:1)
    //==========================================================================
    // Pre-computed forwarding control from ID stage (registered in ID/EX)
    // Encoding: 00=RF, 01=EX, 10=MEM, 11=WB
    
    logic [31:0] rs1_forwarded;
    logic [31:0] rs2_forwarded;
    
    always_comb begin
        case (forward_rs1)
            2'b00:   rs1_forwarded = rs1_data;         // Register file
            2'b01:   rs1_forwarded = ex_forward_data;  // EX stage forward
            2'b10:   rs1_forwarded = mem_forward_data; // MEM stage forward
            2'b11:   rs1_forwarded = wb_forward_data;  // WB stage forward
            default: rs1_forwarded = rs1_data;
        endcase
        
        case (forward_rs2)
            2'b00:   rs2_forwarded = rs2_data;         // Register file
            2'b01:   rs2_forwarded = ex_forward_data;  // EX stage forward
            2'b10:   rs2_forwarded = mem_forward_data; // MEM stage forward
            2'b11:   rs2_forwarded = wb_forward_data;  // WB stage forward
            default: rs2_forwarded = rs2_data;
        endcase
    end
    
    assign rs2_forwarded_out = rs2_forwarded;  // Pass to MEM stage for stores
    
    // Debug outputs for trace buffer
    assign rs1_forwarded_out = rs1_forwarded;
    assign rs2_forwarded_out_trace = rs2_forwarded;
    
    //==========================================================================
    // ALU Operand Selection
    //==========================================================================
    logic [31:0] alu_src1;
    logic [31:0] alu_src2;
    
    // Operand 1: PC or rs1
    assign alu_src1 = ctrl.alu_src1_pc ? pc : rs1_forwarded;
    
    // Operand 2: immediate or rs2
    assign alu_src2 = ctrl.alu_src2_imm ? imm : rs2_forwarded;
    
    //==========================================================================
    // 32-bit ALU Implementation
    //==========================================================================
    logic [31:0] alu_add_sub_result;
    logic [31:0] alu_shift_result;
    logic [31:0] alu_compare_result;
    logic [31:0] alu_logic_result;
    
    // Adder/Subtractor with DSP48 hint
    (* use_dsp = "yes" *) logic [32:0] add_sub_temp;
    assign add_sub_temp = (ctrl.alu_op == ALU_SUB) ?
                          {1'b0, alu_src1} + {1'b0, ~alu_src2} + 33'd1 :  // SUB: A + ~B + 1
                          {1'b0, alu_src1} + {1'b0, alu_src2};             // ADD: A + B
    assign alu_add_sub_result = add_sub_temp[31:0];
    
    // Shifter
    logic [4:0] shift_amount;
    assign shift_amount = alu_src2[4:0];
    
    always_comb begin
        case (ctrl.alu_op)
            ALU_SLL: alu_shift_result = alu_src1 << shift_amount;
            ALU_SRL: alu_shift_result = alu_src1 >> shift_amount;
            ALU_SRA: alu_shift_result = $signed(alu_src1) >>> shift_amount;
            default: alu_shift_result = 32'h0;
        endcase
    end
    
    // Comparator
    logic signed_less_than;
    logic unsigned_less_than;
    
    assign signed_less_than   = $signed(alu_src1) < $signed(alu_src2);
    assign unsigned_less_than = alu_src1 < alu_src2;
    
    always_comb begin
        case (ctrl.alu_op)
            ALU_SLT:  alu_compare_result = {31'h0, signed_less_than};
            ALU_SLTU: alu_compare_result = {31'h0, unsigned_less_than};
            default:  alu_compare_result = 32'h0;
        endcase
    end
    
    // Logic operations
    always_comb begin
        case (ctrl.alu_op)
            ALU_AND: alu_logic_result = alu_src1 & alu_src2;
            ALU_OR:  alu_logic_result = alu_src1 | alu_src2;
            ALU_XOR: alu_logic_result = alu_src1 ^ alu_src2;
            default: alu_logic_result = 32'h0;
        endcase
    end
    
    // ALU result multiplexer
    always_comb begin
        case (ctrl.alu_op)
            ALU_ADD, ALU_SUB:          alu_result = alu_add_sub_result;
            ALU_SLL, ALU_SRL, ALU_SRA: alu_result = alu_shift_result;
            ALU_SLT, ALU_SLTU:         alu_result = alu_compare_result;
            ALU_AND, ALU_OR, ALU_XOR:  alu_result = alu_logic_result;
            ALU_COPY_RS1:              alu_result = alu_src1;  // For AUIPC
            ALU_COPY_IMM:              alu_result = alu_src2;  // For LUI
            default:                   alu_result = alu_add_sub_result;
        endcase
    end
    
    //==========================================================================
    // Branch Condition Evaluation
    //==========================================================================
    logic branch_eq, branch_ne;
    logic branch_lt, branch_ge;
    logic branch_ltu, branch_geu;
    logic branch_condition_met;
    
    // Branch comparisons (use forwarded operands)
    assign branch_eq  = (rs1_forwarded == rs2_forwarded);
    assign branch_ne  = (rs1_forwarded != rs2_forwarded);
    assign branch_lt  = $signed(rs1_forwarded) < $signed(rs2_forwarded);
    assign branch_ge  = $signed(rs1_forwarded) >= $signed(rs2_forwarded);
    assign branch_ltu = rs1_forwarded < rs2_forwarded;
    assign branch_geu = rs1_forwarded >= rs2_forwarded;
    
    // Branch condition multiplexer
    always_comb begin
        case (ctrl.branch_op)
            BR_EQ:   branch_condition_met = branch_eq;
            BR_NE:   branch_condition_met = branch_ne;
            BR_LT:   branch_condition_met = branch_lt;
            BR_GE:   branch_condition_met = branch_ge;
            BR_LTU:  branch_condition_met = branch_ltu;
            BR_GEU:  branch_condition_met = branch_geu;
            default: branch_condition_met = 1'b0;
        endcase
    end
    
    // Branch taken signal
    assign branch_taken = (ctrl.is_branch && branch_condition_met) || ctrl.is_jump;
    
    //==========================================================================
    // Jump and Branch Target Calculation
    //==========================================================================
    logic [31:0] jump_target_jal;
    logic [31:0] jump_target_jalr;
    
    // JAL: PC + immediate (PC-relative)
    assign jump_target_jal = pc + imm;
    
    // JALR: (rs1 + immediate) & ~1 (clear LSB for alignment)
    assign jump_target_jalr = (rs1_forwarded + imm) & 32'hFFFF_FFFE;
    
    // Branch/jump target selection
    always_comb begin
        if (ctrl.is_jump) begin
            if (ctrl.is_jalr)
                branch_target = jump_target_jalr;
            else
                branch_target = jump_target_jal;
        end else if (ctrl.is_branch) begin
            branch_target = pc + imm;  // Branch: PC-relative
        end else begin
            branch_target = 32'h0;
        end
    end
    
    //==========================================================================
    // Valid Output (flushed on ex_flush)
    //==========================================================================
    assign valid_out = valid && !ex_flush;
    
endmodule : rv32i_ex
