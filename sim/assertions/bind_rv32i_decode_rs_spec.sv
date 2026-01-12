`timescale 1ns / 1ps

// Bind rs1/rs2 decode and forwarding assertions to rv32i_top

bind rv32i_top rv32i_decode_rs_spec u_rv32i_decode_rs_spec (
    .clk               (clk),
    .rst               (rst),
    .soft_reset_active (soft_reset_active),
    .id_ex_valid       (id_ex_reg.valid),
    .id_ex_insn        (id_ex_reg.insn),
    .id_ex_rs1_addr    (id_ex_reg.ctrl.rs1_addr),
    .id_ex_rs2_addr    (id_ex_reg.ctrl.rs2_addr),
    .id_ex_rs1_data    (id_ex_reg.rs1_data),
    .id_ex_rs2_data    (id_ex_reg.rs2_data),
    .id_ex_forward_rs1 (id_ex_reg.forward_rs1),
    .id_ex_forward_rs2 (id_ex_reg.forward_rs2),
    .ex_rs1_forwarded  (ex_rs1_forwarded),
    .ex_rs2_forwarded  (ex_rs2_forwarded),
    .ex_mem_alu_result (ex_mem_reg.alu_result),
    .mem_forward_data  (mem_forward_data_mux),
    .wb_result         (wb_result)
);
