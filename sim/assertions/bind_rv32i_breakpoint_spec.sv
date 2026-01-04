// Bind file for RV32I Hardware Breakpoint Specification
// Connects assertion module to rv32i_core DUT

bind rv32i_core rv32i_breakpoint_spec u_bp_spec (
    .clk(clk),
    .rst_n(rst_n),
    
    // CPU state
    .running(running),
    .cpu_halted(cpu_halted),
    .cpu_break(cpu_break),
    .pc_if(pc_if),
    
    // Breakpoint interface
    .dbg_bp_enable(dbg_bp_enable),
    .dbg_bp_addr(dbg_bp_addr),
    .dbg_bp_hit(dbg_bp_hit),
    
    // Internal signals
    .bp_match(bp_match),
    .cpu_break_reg(cpu_break_reg),
    .bp_skip_once(bp_skip_once),
    .bp_just_resumed(bp_just_resumed),
    .if_valid(if_valid),
    .at_any_bp_addr(at_any_bp_addr),
    
    // Pipeline state
    .id_ex_reg_valid(id_ex_reg.valid),
    .ex_mem_reg_valid(ex_mem_reg.valid),
    .mem_wb_reg_valid(mem_wb_reg.valid),
    
    // Flush signals
    .if_flush(if_flush),
    .id_flush(id_flush),
    .ex_flush(ex_flush),
    .bp_flush(bp_flush),
    
    // Register file monitoring
    .rf_waddr(rf_waddr),
    .rf_wdata(rf_wdata),
    .rf_write_en(rf_write_en),
    .regfile_x3(regfile[3])
);
