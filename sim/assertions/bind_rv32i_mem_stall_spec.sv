	imescale 1ns / 1ps

//==============================================================================
// Bind Statement for MEM Stage Stall Assertions
//==============================================================================

bind rv32i_top rv32i_mem_stage_stall_assertions u_mem_stall_assert (
    .clk                 (clk),
    .rst                 (rst),
    .soft_reset_active   (soft_reset_active),
    .mem_stall           (mem_stall),
    .mem_state           (mem_state),
    .bram_data_ready     (bram_data_ready),
    .if_id_valid         (if_id_reg.valid),
    .id_ex_valid         (id_ex_reg.valid),
    .ex_mem_valid        (ex_mem_reg.valid),
    .mem_wb_valid        (mem_wb_reg.valid),
    .if_stall            (if_stall),
    .id_stall            (id_stall),
    .if_flush            (if_flush),
    .id_flush            (id_flush),
    .ex_flush            (ex_flush),
    .ex_mem_ctrl         (ex_mem_reg.ctrl),
    .ex_mem_valid_sig    (ex_mem_reg.valid),
    .ex_mem_pc           (ex_mem_reg.pc),
    .mem_wb_ctrl         (mem_wb_reg.ctrl),
    .mem_wb_mem_data     (mem_wb_reg.mem_data),
    .mem_wb_alu_result   (mem_wb_reg.alu_result),
    .if_pc_current       (if_pc_current),
    .if_id_pc            (if_id_reg.pc),
    .id_ex_pc            (id_ex_reg.pc),
    .ex_mem_pc_reg       (ex_mem_reg.pc)
);
