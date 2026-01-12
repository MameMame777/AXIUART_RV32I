`timescale 1ns / 1ps

//==============================================================================
// RV32I Hazard Detection and Forwarding Control Module
//==============================================================================
// Combinational logic for RAW hazard detection, load-use stall generation,
// and forwarding control signal computation. This module implements Phase 2B
// pre-computed forwarding (computed in ID stage, registered in ID/EX).
//
// See: rtl/cpu/rv32i_hazard_spec.md for detailed specification
//==============================================================================

module rv32i_hazard
    import rv32i_isa_pkg::*;
    import rv32i_pipeline_pkg::*;
(
    // Clock and reset (added for WB metadata delay register)
    input  logic        clk,
    input  logic        rst,
    
    // ID stage inputs (for forwarding pre-computation)
    input  logic [4:0]  id_rs1_addr,
    input  logic [4:0]  id_rs2_addr,
    input  logic        id_valid,
    input  decode_ctrl_t id_ctrl,
    
    // EX stage inputs
    input  logic [4:0]  ex_rd_addr,
    input  logic        ex_rf_wen,
    input  logic        ex_valid,
    input  logic        ex_is_load,
    
    // MEM stage inputs
    input  logic [4:0]  mem_rd_addr,
    input  logic        mem_rf_wen,
    input  logic        mem_valid,
    input  logic        mem_is_load,
    
    // WB stage inputs
    input  logic [4:0]  wb_rd_addr,
    input  logic        wb_rf_wen,
    input  logic        wb_valid,
    
    // Control flow inputs
    input  logic        branch_taken,
    input  logic        exception_trap,
    input  logic        mret_req,
    
    // Forwarding control outputs (pre-computed for ID/EX register)
    output logic [1:0]  forward_rs1_sel,
    output logic [1:0]  forward_rs2_sel,
    
    // Debug outputs (WB metadata timing for assertions)
    output logic [4:0]  wb_rd_addr_delayed_out,
    output logic        wb_rf_wen_delayed_out,
    
    // Stall and flush outputs
    output logic        if_stall,
    output logic        id_stall,
    output logic        if_flush,
    output logic        id_flush,
    output logic        ex_flush
);

    //==========================================================================
    // WB Stage Metadata Delay Register (Fix for Race Condition)
    //==========================================================================
    // The WB forwarding race condition occurs because when an instruction is
    // in ID stage, the MEM/WB pipeline register has already advanced to the
    // next instruction. To detect WB hazards correctly, we need to hold the
    // previous WB stage metadata for one additional cycle.
    //
    // Example: ADDI x27 -> LUI x15 -> SW x27
    // - Cycle N:   ADDI in WB, SW in ID
    // - At posedge: MEM/WB updates ADDI->LUI
    // - Hazard check: sees wb_rd_addr=15 (LUI), not 27 (ADDI)
    // - Fix: Use delayed metadata showing previous WB instruction (ADDI)
    
    logic [4:0]  wb_rd_addr_delayed;
    logic        wb_rf_wen_delayed;
    logic        wb_valid_delayed;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            wb_rd_addr_delayed <= 5'b0;
            wb_rf_wen_delayed  <= 1'b0;
            wb_valid_delayed   <= 1'b0;
        end else begin
            wb_rd_addr_delayed <= wb_rd_addr;
            wb_rf_wen_delayed  <= wb_rf_wen;
            wb_valid_delayed   <= wb_valid;
        end
    end
    
    // Expose delayed signals for debug/assertions
    assign wb_rd_addr_delayed_out = wb_rd_addr_delayed;
    assign wb_rf_wen_delayed_out  = wb_rf_wen_delayed;
    
    //==========================================================================
    // RAW Hazard Detection
    //==========================================================================
    // Detect Read-After-Write hazards for RS1 and RS2
    // Exclude x0 (always reads as zero, never written)
    
    logic ex_writes_rd, mem_writes_rd, wb_writes_rd;
    logic id_rs1_match_ex, id_rs1_match_mem, id_rs1_match_wb;
    logic id_rs2_match_ex, id_rs2_match_mem, id_rs2_match_wb;
    
    // Write detection (stage produces valid register write)
    // NOTE: MEM stage excludes loads because with 2-stage pipeline, load results
    //       are not available until WB stage. Only non-load MEM results can forward.
    assign ex_writes_rd  = ex_rf_wen && (ex_rd_addr != 5'b0) && ex_valid;
    assign mem_writes_rd = mem_rf_wen && (mem_rd_addr != 5'b0) && mem_valid && !mem_is_load;
    // Use current WB signals for hazard detection (checked combinationally during ID stage)
    assign wb_writes_rd  = wb_rf_wen && (wb_rd_addr != 5'b0) && wb_valid;
    
    // RS1 hazard detection
    assign id_rs1_match_ex  = (id_rs1_addr != 5'b0) && ex_writes_rd  && (ex_rd_addr == id_rs1_addr);
    assign id_rs1_match_mem = (id_rs1_addr != 5'b0) && mem_writes_rd && (mem_rd_addr == id_rs1_addr);
    // Check against current WB instruction (combinational during ID stage)
    assign id_rs1_match_wb  = (id_rs1_addr != 5'b0) && wb_writes_rd  && (wb_rd_addr == id_rs1_addr);
    
    // RS2 hazard detection
    assign id_rs2_match_ex  = (id_rs2_addr != 5'b0) && ex_writes_rd  && (ex_rd_addr == id_rs2_addr);
    assign id_rs2_match_mem = (id_rs2_addr != 5'b0) && mem_writes_rd && (mem_rd_addr == id_rs2_addr);
    // Check against current WB instruction (combinational during ID stage)
    assign id_rs2_match_wb  = (id_rs2_addr != 5'b0) && wb_writes_rd  && (wb_rd_addr == id_rs2_addr);
    
    //==========================================================================
    // Forwarding Control (Pre-computed for ID/EX Register)
    //==========================================================================
    // Priority: EX > MEM > WB > RF (newest data has highest priority)
    // Encoding: 00=RF, 01=EX, 10=MEM, 11=WB
    
    assign forward_rs1_sel = id_rs1_match_ex  ? 2'b01 :  // Forward from EX (highest priority)
                             id_rs1_match_mem ? 2'b10 :  // Forward from MEM
                             id_rs1_match_wb  ? 2'b11 :  // Forward from WB
                                                2'b00;   // Register file (no hazard)
    
    assign forward_rs2_sel = id_rs2_match_ex  ? 2'b01 :  // Forward from EX (highest priority)
                             id_rs2_match_mem ? 2'b10 :  // Forward from MEM
                             id_rs2_match_wb  ? 2'b11 :  // Forward from WB
                                                2'b00;   // Register file (no hazard)
    
    //==========================================================================
    // Load-Use Hazard Detection
    //==========================================================================
    // CRITICAL: With 2-stage LOAD pipeline, result is available in WB stage (not MEM)
    // Load in EX → result ready in WB (2 cycles later)
    // Load in MEM → result ready in WB (1 cycle later)
    // Must stall if ID needs result from LOAD in EX or MEM
    
    logic load_use_hazard_ex;   // ID needs result from LOAD in EX
    logic load_use_hazard_mem;  // ID needs result from LOAD in MEM
    logic load_use_hazard;
    
    // Hazard: LOAD in EX, ID needs result (2-cycle stall needed)
    assign load_use_hazard_ex = ex_is_load && ex_valid &&
                                ((id_rs1_match_ex && (id_ctrl.rs1_addr != 5'b0)) ||
                                 (id_rs2_match_ex && (id_ctrl.rs2_addr != 5'b0)));
    
    // Hazard: LOAD in MEM, ID needs result (1-cycle stall needed)
    assign load_use_hazard_mem = mem_is_load && mem_valid &&
                                 ((id_rs1_match_mem && (id_ctrl.rs1_addr != 5'b0)) ||
                                  (id_rs2_match_mem && (id_ctrl.rs2_addr != 5'b0)));
    
    assign load_use_hazard = load_use_hazard_ex || load_use_hazard_mem;
    
    //==========================================================================
    // Stall Control
    //==========================================================================
    // Stall IF and ID stages when load-use hazard detected
    // EX stage continues with bubble (NOP) inserted
    
    assign if_stall = load_use_hazard;
    assign id_stall = load_use_hazard;
    
    //==========================================================================
    // Flush Control
    //==========================================================================
    // Flush pipeline stages on control flow change
    //
    // Branch taken (EX stage):
    //   - Flush IF and ID stages (2 bubbles)
    //   - Incorrect speculative instructions discarded
    //
    // Exception trap (MEM stage):
    //   - Flush IF, ID, and EX stages (3 bubbles)
    //   - Redirect to trap vector (mtvec)
    //
    // MRET (MEM stage):
    //   - Flush IF, ID, and EX stages (3 bubbles)
    //   - Restore PC from mepc
    
    logic control_flow_change_ex;   // Branch/Jump from EX
    logic control_flow_change_mem;  // Exception/MRET from MEM
    
    assign control_flow_change_ex  = branch_taken;
    assign control_flow_change_mem = exception_trap || mret_req;
    
    // IF stage flush: On any control flow change
    assign if_flush = control_flow_change_ex || control_flow_change_mem;
    
    // ID stage flush: On any control flow change
    assign id_flush = control_flow_change_ex || control_flow_change_mem;
    
    // EX stage flush: Only on MEM stage control flow change (exception/MRET)
    assign ex_flush = control_flow_change_mem;
    
endmodule : rv32i_hazard
