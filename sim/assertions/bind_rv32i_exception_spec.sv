`timescale 1ns / 1ps

//=============================================================================
// Bind File: rv32i_exception_spec
// Description: Binds CSR timing and exception trap assertion modules to DUT
//=============================================================================

bind rv32i_top rv32i_csr_timing_spec csr_timing_assertions (
    .clk(clk),
    .rst(rst),
    
    // CSR write interface (from CSR module)
    .csr_wen(u_csr.csr_wen),
    .csr_waddr(u_csr.csr_waddr),
    .csr_wdata(u_csr.csr_wdata),
    
    // CSR registers (from CSR module)
    .mtvec_reg(u_csr.mtvec_reg),
    .mepc_reg(u_csr.mepc_reg),
    .mcause_reg(u_csr.mcause_reg),
    .mtval_reg(u_csr.mtval_reg),
    
    // CSR outputs (from CSR module)
    .trap_vector(trap_vector),
    .mret_pc(mret_pc),
    
    // Pipeline stage information
    .mem_wb_valid(mem_wb_reg.valid),
    .mem_wb_is_csr(mem_wb_reg.ctrl.is_csr),
    
    // Exception signals
    .exception_trap(exception_trap),
    .exception_pc(exception_pc)
);

bind rv32i_top rv32i_debug_state_spec debug_state_assertions (
    .clk(clk),
    .rst(rst),
    
    // CPU state
    .running(running),
    .cpu_halted(cpu_halted),
    .cpu_break(cpu_break),
    .bp_hit(bp_hit_reg),
    .step_mode(step_mode),
    
    // Pipeline valid
    .if_valid(if_valid),
    .id_valid(id_valid),
    .ex_valid(ex_valid),
    .mem_valid(mem_valid),
    .wb_valid(wb_valid),
    
    // CSR write
    .csr_wen(csr_wen),
    .csr_waddr(csr_waddr),
    .csr_wdata(csr_wdata),
    .mem_wb_is_csr(mem_wb_reg.ctrl.is_csr),
    
    // Instructions
    .insn_if(insn_if),
    .insn_id(insn_id),
    .insn_ex(insn_ex),
    .insn_mem(insn_mem),
    .insn_wb(insn_wb),
    
    // PCs
    .pc_if(pc_if),
    .pc_id(pc_id),
    .pc_ex(pc_ex),
    .pc_mem(pc_mem),
    .pc_wb(pc_wb),
    
    // CSR state
    .mtvec_reg(u_csr.mtvec_reg)
);

bind rv32i_top rv32i_exception_trap_spec exception_trap_assertions (
    .clk(clk),
    .rst(rst),
    
    // Program Counter (all pipeline stages)
    .pc_if(pc_if),
    .pc_id(if_id_reg.pc),
    .pc_ex(id_ex_reg.pc),
    .pc_mem(ex_mem_reg.pc),
    
    // Exception signals
    .exception_trap(exception_trap),
    .exception_pc(exception_pc),
    .exception_code(exception_code),
    .exception_tval(exception_tval),
    .trap_vector(trap_vector),
    
    // MRET signals
    .mret_detected(mret_detected),
    .mret_pc(mret_pc),
    
    // Pipeline flush signals
    .if_flush(if_flush),
    .id_flush(id_flush),
    .ex_flush(ex_flush),
    
    // Pipeline stage valid signals
    .if_id_valid(if_id_reg.valid),
    .id_ex_valid(id_ex_reg.valid),
    .ex_mem_valid(ex_mem_reg.valid),
    .mem_wb_valid(mem_wb_reg.valid),
    
    // Debug mode
    .debug_mode_enable(debug_mode_enable)
);
