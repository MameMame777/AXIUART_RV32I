`timescale 1ns / 1ps

//==============================================================================
// Bind Register File Debug Module to rv32i_top
//==============================================================================

bind rv32i_top rv32i_regfile_forward_debug_spec u_regfile_debug (
    .clk                (clk),
    .rst                (rst || soft_reset_active),
    
    // ID Stage
    .id_pc              (id_pc_out),
    .id_insn            (id_insn_out),
    .id_valid           (id_valid_out),
    .id_rs1_addr        (id_ctrl.rs1_addr),
    .id_rs2_addr        (id_ctrl.rs2_addr),
    .id_rd_addr         (id_ctrl.rd_addr),
    .id_rs1_data        (id_rs1_data),
    .id_rs2_data        (id_rs2_data),
    
    // Forwarding control
    .forward_rs1_sel    (forward_rs1_sel),
    .forward_rs2_sel    (forward_rs2_sel),
    
    // EX Stage
    .ex_pc              (id_ex_reg.pc),
    .ex_insn            (id_ex_reg.insn),
    .ex_valid           (id_ex_reg.valid),
    .ex_rs1_addr        (id_ex_reg.ctrl.rs1_addr),
    .ex_rs2_addr        (id_ex_reg.ctrl.rs2_addr),
    .ex_rs1_forwarded   (ex_rs1_forwarded),
    .ex_rs2_forwarded   (ex_rs2_forwarded),
    .ex_alu_result      (ex_alu_result),
    
    // Hazard detection
    .id_rs1_match_ex    (u_hazard.id_rs1_match_ex),
    .id_rs1_match_mem   (u_hazard.id_rs1_match_mem),
    .id_rs1_match_wb    (u_hazard.id_rs1_match_wb),
    .id_rs2_match_ex    (u_hazard.id_rs2_match_ex),
    .id_rs2_match_mem   (u_hazard.id_rs2_match_mem),
    .id_rs2_match_wb    (u_hazard.id_rs2_match_wb),
    
    // Producer stages
    .ex_rd_addr         (id_ex_reg.ctrl.rd_addr),
    .ex_rf_wen          (id_ex_reg.ctrl.rf_wen),
    .mem_rd_addr        (ex_mem_reg.ctrl.rd_addr),
    .mem_rf_wen         (ex_mem_reg.ctrl.rf_wen),
    .wb_rd_addr         (mem_wb_reg.ctrl.rd_addr),
    .wb_rf_wen          (mem_wb_reg.ctrl.rf_wen),
    
    // WB Stage
    .wb_waddr           (wb_rf_waddr),
    .wb_wdata           (wb_rf_wdata),
    .wb_wen             (wb_rf_wen),
    
    // Register file values
    .regfile_x23        (u_id.regfile[23]),
    .regfile_x24        (u_id.regfile[24])
);
