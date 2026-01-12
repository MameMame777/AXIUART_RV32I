`timescale 1ns / 1ps

//==============================================================================
// Bind Pipeline Monitor to rv32i_top
//==============================================================================
// Connects monitor module to internal DUT signals
// Non-invasive observation for debugging
//==============================================================================

bind rv32i_top rv32i_pipeline_monitor u_pipeline_monitor (
    .clk (clk),
    .rst (rst || soft_reset_active),
    
    // ID Stage direct connections
    .id_pc (id_pc_out),
    .id_insn (id_insn_out),
    .id_valid (id_valid_out),
    .insn_opcode (id_insn_out[6:0]),
    .insn_funct3 (id_insn_out[14:12]),
    .insn_funct7 (id_insn_out[31:25]),
    .insn_rs1_bits (id_insn_out[19:15]),
    .insn_rs2_bits (id_insn_out[24:20]),
    .insn_rd_bits (id_insn_out[11:7]),
    .id_rs1_addr (id_ctrl.rs1_addr),
    .id_rs2_addr (id_ctrl.rs2_addr),
    .id_rd_addr (id_ctrl.rd_addr),
    .id_rs1_data (id_rs1_data),
    .id_rs2_data (id_rs2_data),
    .id_imm (id_imm),
    .forward_rs1_sel (forward_rs1_sel),
    .forward_rs2_sel (forward_rs2_sel),
    
    // EX Stage direct connections
    .ex_pc (id_ex_reg.pc),
    .ex_insn (id_ex_reg.insn),
    .ex_valid (id_ex_reg.valid),
    .ex_rs1_data (id_ex_reg.rs1_data),
    .ex_rs2_data (id_ex_reg.rs2_data),
    .ex_forward_rs1 (id_ex_reg.forward_rs1),
    .ex_forward_rs2 (id_ex_reg.forward_rs2),
    .ex_forward_data (ex_mem_reg.alu_result),
    .mem_forward_data (mem_forward_data_mux),
    .wb_forward_data (wb_result),
    .ex_rs1_forwarded (ex_rs1_forwarded),
    .ex_rs2_forwarded (ex_rs2_forwarded),
    .ex_alu_src1 (u_ex.alu_src1),
    .ex_alu_src2 (u_ex.alu_src2),
    .ex_alu_result (ex_alu_result),
    
    // Pipeline control
    .ex_rd_addr (id_ex_reg.ctrl.rd_addr),
    .mem_rd_addr (ex_mem_reg.ctrl.rd_addr),
    .wb_rd_addr (mem_wb_reg.ctrl.rd_addr),
    .ex_rf_wen (id_ex_reg.ctrl.rf_wen),
    .mem_rf_wen (ex_mem_reg.ctrl.rf_wen),
    .wb_rf_wen (mem_wb_reg.ctrl.rf_wen)
);
