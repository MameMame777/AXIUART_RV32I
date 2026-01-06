`timescale 1ns / 1ps

//==============================================================================
// Bind Debug Memory Specification Assertions to CPU Core
//==============================================================================

bind td4cpu_core td4cpu_debug_mem_spec spec_checker (
    .clk(clk),
    .rst(rst),
    
    // Debug interface
    .dbg_mem_read_req(dbg_mem_read_req),
    .dbg_mem_write_req(dbg_mem_write_req),
    .dbg_mem_addr(dbg_mem_addr),
    .dbg_mem_wdata(dbg_mem_wdata),
    .dbg_mem_rdata(dbg_mem_rdata),
    .dbg_mem_err(dbg_mem_err),
    
    // CPU state
    .halted(halted),
    .running(running),
    
    // Internal signals
    .mem_busy_q(mem_busy_q),
    .ram_rd_en(ram_rd_en),
    .ram_wr_en(ram_wr_en),
    .ram_read_phase(ram_read_phase),
    .mem_data_valid(mem_data_valid),
    .ram_rd_data(ram_rd_data)
);

//==============================================================================
// Bind Flag Hazard Detection Assertions
//==============================================================================
bind td4cpu_core td4cpu_flag_hazard_assertions flag_hazard_checker (
    .clk(clk),
    .rst(rst),
    
    // Pipeline control signals
    .insn_decoded_reg(insn_decoded_reg),
    .insn_decoded_valid(insn_decoded_valid),
    .insn_fetched(insn_fetched),
    .insn_valid(insn_valid),
    
    // ALU pipeline stages
    .alu_valid_stage1(alu_valid_stage1),
    .alu_flags_update_en_stage2(alu_flags_update_en_stage2),
    .alu_flags_update_en_hold(alu_flags_update_en_hold),
    .alu_flags_hold(alu_flags_hold),
    
    // Register write forwarding
    .reg_write_pending(reg_write_pending),
    
    // CPU state
    .running(running),
    .halted(halted),
    .flags(flags)
);

//==============================================================================
// Bind Fetch Address Specification Assertions
//==============================================================================
bind td4cpu_core td4cpu_fetch_spec fetch_spec_checker (
    .clk(clk),
    .rst(rst),
    
    // CPU state
    .running(running),
    .pc(pc),
    
    // RAM fetch signals
    .ram_addr_next(ram_addr_next),
    .ram_rd_en(ram_rd_en),
    
    // Branch control
    .branch_pending(branch_pending),
    .branch_target_pending(branch_target_pending),
    
    // Fetched instruction
    .insn_fetched(insn_fetched),
    
    // RAM array (for data verification)
    .ram(ram)
);
