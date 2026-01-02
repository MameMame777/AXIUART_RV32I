`timescale 1ns / 1ps

//==============================================================================
// RV32I 5-Stage Pipeline Architecture Specification (SVA)
//==============================================================================
// 
// This module defines the RISC-V RV32I pipeline architecture as executable 
// SystemVerilog Assertions. These assertions ARE the specification, not 
// documentation.
//
// Pipeline Stages: IF → ID → EX → MEM → WB
// Hazards: Data (RAW with forwarding), Control (branch/jump flush), Structural (none)
// Branch Prediction: Static predict-not-taken
//
// Usage: Bind this module to rv32i_core for runtime verification
//
//==============================================================================

module rv32i_pipeline_spec
    import rv32i_isa_pkg::*;
(
    input logic clk,
    input logic rst_n,
    
    // Pipeline stage valid signals
    input logic if_valid,
    input logic id_valid,
    input logic ex_valid,
    input logic mem_valid,
    input logic wb_valid,
    
    // Pipeline control signals
    input logic if_stall,
    input logic id_stall,
    input logic if_flush,
    input logic id_flush,
    input logic ex_flush,
    
    // Program Counter
    input logic [31:0] pc_if,
    input logic [31:0] pc_id,
    input logic [31:0] pc_ex,
    input logic [31:0] pc_mem,
    input logic [31:0] pc_wb,
    
    // Instructions in each stage
    input logic [31:0] insn_if,
    input logic [31:0] insn_id,
    input logic [31:0] insn_ex,
    input logic [31:0] insn_mem,
    input logic [31:0] insn_wb,
    
    // Register file
    input logic [4:0]  rf_rs1_addr,
    input logic [4:0]  rf_rs2_addr,
    input logic [4:0]  rf_rd_addr_wb,
    input logic        rf_wen_wb,
    input logic [31:0] rf_wdata_wb,
    input logic [31:0] rf_x0,  // Must always be 0
    
    // Hazard detection
    input logic        hazard_raw_ex,   // RAW hazard with EX stage
    input logic        hazard_raw_mem,  // RAW hazard with MEM stage
    input logic        hazard_load_use, // Load-use hazard (requires stall)
    
    // Branch/Jump control
    input logic        branch_taken_ex,
    input logic        jump_ex,
    input logic [31:0] branch_target_ex,
    
    // Forwarding paths
    input logic [1:0]  forward_rs1,  // 00=RF, 01=EX, 10=MEM
    input logic [1:0]  forward_rs2
);

    //==========================================================================
    // Reset Behavior
    //==========================================================================
    
    // SPEC-RESET-1: All pipeline stages invalid after reset
    assert_reset_clears_pipeline: assert property (
        @(posedge clk) disable iff (!rst_n)
        $fell(rst_n) |=> (!if_valid && !id_valid && !ex_valid && !mem_valid && !wb_valid)
    ) else $error("[SPEC-RESET-1] Pipeline not cleared after reset");
    
    // SPEC-RESET-2: PC starts at 0x00000000 after reset
    assert_reset_pc_zero: assert property (
        @(posedge clk) disable iff (!rst_n)
        $fell(rst_n) |=> (pc_if == 32'h00000000)
    ) else $error("[SPEC-RESET-2] PC not zero after reset");

    //==========================================================================
    // Register File Constraints
    //==========================================================================
    
    // SPEC-RF-1: x0 is hardwired to zero (CRITICAL RISC-V requirement)
    assert_x0_hardwired_zero: assert property (
        @(posedge clk) disable iff (!rst_n)
        rf_x0 == 32'h00000000
    ) else $error("[SPEC-RF-1] x0 not hardwired to zero!");
    
    // SPEC-RF-2: Writes to x0 are ignored (no write enable assertion)
    assert_x0_write_ignored: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rf_wen_wb && rf_rd_addr_wb == 5'b00000) |=> (rf_x0 == 32'h00000000)
    ) else $error("[SPEC-RF-2] Write to x0 not ignored!");

    //==========================================================================
    // Pipeline Progression
    //==========================================================================
    
    // SPEC-PIPE-1: Without stalls, instruction progresses through pipeline
    assert_pipeline_progression_if_id: assert property (
        @(posedge clk) disable iff (!rst_n)
        (if_valid && !if_stall && !if_flush) |=> 
            (id_valid && $past(pc_if) == pc_id && $past(insn_if) == insn_id)
    ) else $error("[SPEC-PIPE-1] IF→ID progression failed");
    
    assert_pipeline_progression_id_ex: assert property (
        @(posedge clk) disable iff (!rst_n)
        (id_valid && !id_stall && !id_flush) |=> 
            (ex_valid && $past(pc_id) == pc_ex && $past(insn_id) == insn_ex)
    ) else $error("[SPEC-PIPE-1] ID→EX progression failed");
    
    assert_pipeline_progression_ex_mem: assert property (
        @(posedge clk) disable iff (!rst_n)
        (ex_valid && !ex_flush) |=> 
            (mem_valid && $past(pc_ex) == pc_mem && $past(insn_ex) == insn_mem)
    ) else $error("[SPEC-PIPE-1] EX→MEM progression failed");
    
    assert_pipeline_progression_mem_wb: assert property (
        @(posedge clk) disable iff (!rst_n)
        mem_valid |=> 
            (wb_valid && $past(pc_mem) == pc_wb && $past(insn_mem) == insn_wb)
    ) else $error("[SPEC-PIPE-1] MEM→WB progression failed");

    //==========================================================================
    // PC Management
    //==========================================================================
    
    // SPEC-PC-1: PC increments by 4 in sequential execution (byte addressing)
    assert_pc_sequential: assert property (
        @(posedge clk) disable iff (!rst_n)
        (if_valid && !if_stall && !if_flush && !branch_taken_ex && !jump_ex) |=>
            (pc_if == $past(pc_if) + 4)
    ) else $error("[SPEC-PC-1] PC not incrementing by 4 in sequential mode");
    
    // SPEC-PC-2: PC must be 4-byte aligned (LSB 2 bits = 0)
    assert_pc_aligned: assert property (
        @(posedge clk) disable iff (!rst_n)
        if_valid |-> (pc_if[1:0] == 2'b00)
    ) else $error("[SPEC-PC-2] PC not 4-byte aligned");
    
    // SPEC-PC-3: Branch taken updates PC to target address
    assert_pc_branch_target: assert property (
        @(posedge clk) disable iff (!rst_n)
        (branch_taken_ex && !if_stall) |=> (pc_if == $past(branch_target_ex))
    ) else $error("[SPEC-PC-3] PC not updated to branch target");
    
    // SPEC-PC-4: Jump updates PC to target address
    assert_pc_jump_target: assert property (
        @(posedge clk) disable iff (!rst_n)
        (jump_ex && !if_stall) |=> (pc_if == $past(branch_target_ex))
    ) else $error("[SPEC-PC-4] PC not updated to jump target");

    //==========================================================================
    // Pipeline Flush on Control Hazards
    //==========================================================================
    
    // SPEC-FLUSH-1: Branch taken flushes IF and ID stages
    assert_branch_flush: assert property (
        @(posedge clk) disable iff (!rst_n)
        branch_taken_ex |=> (if_flush && id_flush)
    ) else $error("[SPEC-FLUSH-1] IF/ID not flushed on branch taken");
    
    // SPEC-FLUSH-2: Jump flushes IF and ID stages
    assert_jump_flush: assert property (
        @(posedge clk) disable iff (!rst_n)
        jump_ex |=> (if_flush && id_flush)
    ) else $error("[SPEC-FLUSH-2] IF/ID not flushed on jump");
    
    // SPEC-FLUSH-3: Flushed stage becomes invalid (bubble)
    assert_flush_invalidates: assert property (
        @(posedge clk) disable iff (!rst_n)
        if_flush |=> !$past(if_valid)
    ) else $error("[SPEC-FLUSH-3] Flushed IF stage not invalidated");

    //==========================================================================
    // Data Hazard Detection (RAW - Read After Write)
    //==========================================================================
    
    // SPEC-HAZ-1: RAW hazard detected when ID reads register written by EX
    // (EX stage writes to rd, ID stage reads rs1 or rs2)
    property raw_hazard_ex;
        logic [4:0] ex_rd;
        logic ex_rf_wen;
        @(posedge clk) disable iff (!rst_n)
        (ex_valid && ex_rf_wen && ex_rd != 5'b0, ex_rd = ex_rd) |->
            (id_valid && ((rf_rs1_addr == ex_rd) || (rf_rs2_addr == ex_rd))) 
            |-> hazard_raw_ex;
    endproperty
    
    // Note: Full implementation requires access to ex_rd and ex_rf_wen signals
    // This is a template - actual signals must be connected
    
    // SPEC-HAZ-2: Load-use hazard causes 1-cycle stall
    assert_load_use_stall: assert property (
        @(posedge clk) disable iff (!rst_n)
        hazard_load_use |-> (id_stall && if_stall)
    ) else $error("[SPEC-HAZ-2] Load-use hazard not causing stall");

    //==========================================================================
    // Forwarding Paths
    //==========================================================================
    
    // SPEC-FWD-1: Forwarding from EX stage when RAW hazard detected
    assert_forward_from_ex: assert property (
        @(posedge clk) disable iff (!rst_n)
        hazard_raw_ex && !hazard_load_use |-> 
            ((forward_rs1 == 2'b01) || (forward_rs2 == 2'b01))
    ) else $error("[SPEC-FWD-1] EX forwarding not enabled for RAW hazard");
    
    // SPEC-FWD-2: Forwarding from MEM stage when RAW hazard detected
    assert_forward_from_mem: assert property (
        @(posedge clk) disable iff (!rst_n)
        hazard_raw_mem && !hazard_raw_ex |-> 
            ((forward_rs1 == 2'b10) || (forward_rs2 == 2'b10))
    ) else $error("[SPEC-FWD-2] MEM forwarding not enabled for RAW hazard");

    //==========================================================================
    // Branch Prediction (Static Predict-Not-Taken)
    //==========================================================================
    
    // SPEC-PRED-1: Sequential fetch continues until branch resolves in EX
    // (Predict-not-taken means we speculatively fetch PC+4 during ID stage)
    assert_predict_not_taken: assert property (
        @(posedge clk) disable iff (!rst_n)
        (id_valid && is_branch_insn(insn_id) && !id_stall) |=>
            (!branch_taken_ex || (pc_if == $past(pc_id) + 4))
    ) else $error("[SPEC-PRED-1] Branch prediction not following predict-not-taken");
    
    function automatic logic is_branch_insn(logic [31:0] insn);
        return (insn[6:0] == OPC_BRANCH);
    endfunction

    //==========================================================================
    // Memory Access Constraints
    //==========================================================================
    
    // SPEC-MEM-1: Memory address must be within valid range (0x0000_0000 - 0x0000_7FFF)
    // 0x0000-0x1FFF: RAM (8KB)
    // 0x4000-0x7FFF: MMIO
    // (Actual address checking requires mem_addr signal - template only)
    
    // SPEC-MEM-2: Byte/halfword accesses must respect alignment
    // LH/LHU/SH: address[0] == 0
    // LW/SW: address[1:0] == 2'b00
    // (Requires mem_addr and mem_width signals)

    //==========================================================================
    // Writeback Stage
    //==========================================================================
    
    // SPEC-WB-1: Writeback only occurs for valid WB stage with rf_wen
    assert_writeback_valid: assert property (
        @(posedge clk) disable iff (!rst_n)
        rf_wen_wb |-> wb_valid
    ) else $error("[SPEC-WB-1] Register write without valid WB stage");
    
    // SPEC-WB-2: No double writeback to same register in consecutive cycles
    // (Structural hazard check - should not occur in properly designed pipeline)
    assert_no_double_writeback: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rf_wen_wb && rf_rd_addr_wb != 5'b0) |=>
            (!rf_wen_wb || (rf_rd_addr_wb != $past(rf_rd_addr_wb)))
    ) else $warning("[SPEC-WB-2] Consecutive writes to same register detected");

    //==========================================================================
    // System Instructions
    //==========================================================================
    
    // SPEC-SYS-1: EBREAK halts the pipeline (debug breakpoint)
    // (Requires cpu_halted signal - template only)
    
    // SPEC-SYS-2: ECALL triggers software interrupt
    // (Requires interrupt handling - not implemented in minimal core)

    //==========================================================================
    // Coverage: Pipeline Scenarios
    //==========================================================================
    
    // Cover: All 5 stages simultaneously valid (full pipeline)
    cover_full_pipeline: cover property (
        @(posedge clk) disable iff (!rst_n)
        if_valid && id_valid && ex_valid && mem_valid && wb_valid
    );
    
    // Cover: Branch taken (misprediction)
    cover_branch_taken: cover property (
        @(posedge clk) disable iff (!rst_n)
        branch_taken_ex
    );
    
    // Cover: Load-use hazard with stall
    cover_load_use_hazard: cover property (
        @(posedge clk) disable iff (!rst_n)
        hazard_load_use && id_stall
    );
    
    // Cover: EX forwarding
    cover_ex_forwarding: cover property (
        @(posedge clk) disable iff (!rst_n)
        (forward_rs1 == 2'b01) || (forward_rs2 == 2'b01)
    );
    
    // Cover: MEM forwarding
    cover_mem_forwarding: cover property (
        @(posedge clk) disable iff (!rst_n)
        (forward_rs1 == 2'b10) || (forward_rs2 == 2'b10)
    );

    //==========================================================================
    // Performance Counters (Optional Monitoring)
    //==========================================================================
    
    // Count total cycles
    logic [63:0] cycle_count;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cycle_count <= 64'h0;
        else
            cycle_count <= cycle_count + 1;
    end
    
    // Count instructions retired (WB stage valid with non-flushed instruction)
    logic [63:0] insn_count;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            insn_count <= 64'h0;
        else if (wb_valid)
            insn_count <= insn_count + 1;
    end
    
    // Count pipeline stalls
    logic [63:0] stall_count;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            stall_count <= 64'h0;
        else if (id_stall || if_stall)
            stall_count <= stall_count + 1;
    end
    
    // Count pipeline flushes (mispredictions)
    logic [63:0] flush_count;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            flush_count <= 64'h0;
        else if (if_flush || id_flush || ex_flush)
            flush_count <= flush_count + 1;
    end
    
    // Report performance metrics at end of simulation
    final begin
        real ipc;
        ipc = (cycle_count > 0) ? (real'(insn_count) / real'(cycle_count)) : 0.0;
        $display("===== RV32I Pipeline Performance =====");
        $display("Cycles:        %0d", cycle_count);
        $display("Instructions:  %0d", insn_count);
        $display("IPC:           %0.3f", ipc);
        $display("Stalls:        %0d (%0.1f%%)", stall_count, 
                 (cycle_count > 0) ? (100.0 * real'(stall_count) / real'(cycle_count)) : 0.0);
        $display("Flushes:       %0d (%0.1f%%)", flush_count,
                 (cycle_count > 0) ? (100.0 * real'(flush_count) / real'(cycle_count)) : 0.0);
        $display("=======================================");
    end

endmodule : rv32i_pipeline_spec

//==============================================================================
// Bind Statement (to be placed in testbench or separate bind file)
//==============================================================================
// 
// bind rv32i_core rv32i_pipeline_spec rv32i_pipe_assertions (
//     .clk(clk),
//     .rst_n(rst_n),
//     .if_valid(if_valid),
//     .id_valid(id_valid),
//     .ex_valid(ex_valid),
//     .mem_valid(mem_valid),
//     .wb_valid(wb_valid),
//     .if_stall(if_stall),
//     .id_stall(id_stall),
//     .if_flush(if_flush),
//     .id_flush(id_flush),
//     .ex_flush(ex_flush),
//     .pc_if(pc_if),
//     .pc_id(pc_id),
//     .pc_ex(pc_ex),
//     .pc_mem(pc_mem),
//     .pc_wb(pc_wb),
//     .insn_if(insn_if),
//     .insn_id(insn_id),
//     .insn_ex(insn_ex),
//     .insn_mem(insn_mem),
//     .insn_wb(insn_wb),
//     .rf_rs1_addr(id_rs1_addr),
//     .rf_rs2_addr(id_rs2_addr),
//     .rf_rd_addr_wb(wb_rd_addr),
//     .rf_wen_wb(wb_rf_wen),
//     .rf_wdata_wb(wb_rf_wdata),
//     .rf_x0(regfile.regs[0]),
//     .hazard_raw_ex(hazard_raw_ex),
//     .hazard_raw_mem(hazard_raw_mem),
//     .hazard_load_use(hazard_load_use),
//     .branch_taken_ex(branch_taken_ex),
//     .jump_ex(jump_ex),
//     .branch_target_ex(branch_target_ex),
//     .forward_rs1(forward_rs1),
//     .forward_rs2(forward_rs2)
// );
//
//==============================================================================
