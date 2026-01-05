`timescale 1ns / 1ps
//==============================================================================
// RV32I Hazard Detection Stage Timing Assertions
//==============================================================================
// SystemVerilog Assertions for Hazard Detection Unit
// Verifies RAW hazard detection, forwarding priority, load-use stall, and
// pipeline flush control according to rv32i_hazard_spec.md
//
// Bind this module to rv32i_hazard instance:
//   bind rv32i_hazard rv32i_hazard_timing_spec u_hazard_assertions (.*);
//==============================================================================

module rv32i_hazard_timing_spec
    import rv32i_isa_pkg::*;
(
    // Clock and reset
    input logic        clk,
    input logic        rst_n,
    
    // ID stage inputs
    input logic [4:0]  id_rs1_addr,
    input logic [4:0]  id_rs2_addr,
    input logic        id_rs1_used,
    input logic        id_rs2_used,
    input logic        id_valid,
    
    // EX stage status
    input logic [4:0]  ex_rd_addr,
    input logic        ex_rf_wen,
    input logic        ex_is_load,
    input logic        ex_valid,
    
    // MEM stage status
    input logic [4:0]  mem_rd_addr,
    input logic        mem_rf_wen,
    input logic        mem_valid,
    
    // WB stage status
    input logic [4:0]  wb_rd_addr,
    input logic        wb_rf_wen,
    input logic        wb_valid,
    
    // Control inputs
    input logic        branch_taken,
    input logic        exception_trap,
    input logic        mret_req,
    
    // Forwarding control outputs
    input logic [1:0]  forward_rs1,
    input logic [1:0]  forward_rs2,
    
    // Stall/flush outputs
    input logic        if_stall,
    input logic        id_stall,
    input logic        if_flush,
    input logic        id_flush,
    input logic        ex_flush,
    input logic        load_use_stall
);

    //==========================================================================
    // SPEC-HAZ-1: RAW Hazard Detection for RS1
    //==========================================================================
    // Verify that RAW hazards on RS1 are detected when:
    // - ID stage instruction uses RS1 (id_rs1_used=1)
    // - EX/MEM/WB stage writes to matching register (rd_addr == rs1_addr)
    // - RS1 is not x0 (x0 never causes hazards)
    
    property raw_hazard_rs1_detection;
        @(posedge clk) disable iff (!rst_n)
        (id_valid && id_rs1_used && (id_rs1_addr != 5'b0) &&
         ex_valid && ex_rf_wen && (ex_rd_addr == id_rs1_addr))
        |-> (forward_rs1 == 2'b01);  // Forward from EX stage
    endproperty
    
    assert_raw_rs1: assert property (raw_hazard_rs1_detection)
        else $error("[SPEC-HAZ-1] RAW hazard RS1 not forwarded: rs1=x%0d ex_rd=x%0d forward=%b",
                    id_rs1_addr, ex_rd_addr, forward_rs1);

    //==========================================================================
    // SPEC-HAZ-2: Forwarding Priority (EX > MEM > WB)
    //==========================================================================
    // Verify forwarding priority when multiple stages write same register:
    // EX stage has highest priority (2'b01), then MEM (2'b10), then WB (2'b11)
    
    property forwarding_priority_ex_over_mem;
        @(posedge clk) disable iff (!rst_n)
        (id_valid && id_rs1_used && (id_rs1_addr != 5'b0) &&
         ex_valid && ex_rf_wen && (ex_rd_addr == id_rs1_addr) &&
         mem_valid && mem_rf_wen && (mem_rd_addr == id_rs1_addr))
        |-> (forward_rs1 == 2'b01);  // EX has priority over MEM
    endproperty
    
    assert_priority_ex: assert property (forwarding_priority_ex_over_mem)
        else $error("[SPEC-HAZ-2] Forwarding priority violation: EX should have priority over MEM, forward=%b",
                    forward_rs1);

    //==========================================================================
    // SPEC-HAZ-3: Load-Use Stall Detection
    //==========================================================================
    // Verify 1-cycle stall when load result needed immediately:
    // - EX stage is executing load (ex_is_load=1)
    // - ID stage needs the load result (RAW hazard on load destination)
    // Expected: if_stall=1, id_stall=1, load_use_stall=1
    
    property load_use_stall_detection;
        @(posedge clk) disable iff (!rst_n)
        (ex_valid && ex_is_load && ex_rf_wen && (ex_rd_addr != 5'b0) &&
         id_valid && 
         ((id_rs1_used && (id_rs1_addr == ex_rd_addr)) ||
          (id_rs2_used && (id_rs2_addr == ex_rd_addr))))
        |-> (load_use_stall && if_stall && id_stall);
    endproperty
    
    assert_load_use: assert property (load_use_stall_detection)
        else $error("[SPEC-HAZ-3] Load-use stall not asserted: ex_rd=x%0d id_rs1=x%0d id_rs2=x%0d stall=%b",
                    ex_rd_addr, id_rs1_addr, id_rs2_addr, load_use_stall);

    //==========================================================================
    // SPEC-HAZ-4: Branch Flush Control
    //==========================================================================
    // Verify pipeline flush on branch taken:
    // - Branch decision made in EX stage
    // - Flush IF and ID stages (wrong-path instructions)
    // Expected: if_flush=1, id_flush=1
    
    property branch_flush_if_id;
        @(posedge clk) disable iff (!rst_n)
        branch_taken |-> (if_flush && id_flush);
    endproperty
    
    assert_branch_flush: assert property (branch_flush_if_id)
        else $error("[SPEC-HAZ-4] Branch flush incomplete: branch_taken=1 but if_flush=%b id_flush=%b",
                    if_flush, id_flush);

    //==========================================================================
    // SPEC-HAZ-5: x0 Never Causes Hazard
    //==========================================================================
    // Verify that x0 reads never trigger forwarding:
    // - Reading x0 always returns zero (no need to forward)
    // - forward_rs1 should be 2'b00 (RF) when rs1_addr=0
    
    property x0_no_forwarding_rs1;
        @(posedge clk) disable iff (!rst_n)
        (id_valid && (id_rs1_addr == 5'b0)) |-> (forward_rs1 == 2'b00);
    endproperty
    
    assert_x0_rs1: assert property (x0_no_forwarding_rs1)
        else $error("[SPEC-HAZ-5] x0 triggered forwarding: rs1=x0 but forward_rs1=%b (expected 00)",
                    forward_rs1);
    
    property x0_no_forwarding_rs2;
        @(posedge clk) disable iff (!rst_n)
        (id_valid && (id_rs2_addr == 5'b0)) |-> (forward_rs2 == 2'b00);
    endproperty
    
    assert_x0_rs2: assert property (x0_no_forwarding_rs2)
        else $error("[SPEC-HAZ-5] x0 triggered forwarding: rs2=x0 but forward_rs2=%b (expected 00)",
                    forward_rs2);

    //==========================================================================
    // SPEC-HAZ-6: WB Stage Forwarding Detection
    //==========================================================================
    // Verify WB stage forwarding is detected when:
    // - ID stage instruction uses RS2 (id_rs2_used=1)
    // - WB stage writes to matching register (wb_rd_addr == id_rs2_addr)
    // - No higher priority forwarding from EX or MEM stages
    // - RS2 is not x0 (x0 never causes hazards)
    // Expected: forward_rs2 == 2'b11 (WB forwarding)
    //
    // This assertion catches the race condition where WB stage metadata
    // has already advanced to the next instruction when hazard detection runs.
    
    property wb_forwarding_rs2_detection;
        @(posedge clk) disable iff (!rst_n)
        (id_valid && id_rs2_used && (id_rs2_addr != 5'b0) &&
         wb_valid && wb_rf_wen && (wb_rd_addr == id_rs2_addr) &&
         !(ex_valid && ex_rf_wen && (ex_rd_addr == id_rs2_addr)) &&  // No EX forwarding
         !(mem_valid && mem_rf_wen && (mem_rd_addr == id_rs2_addr))) // No MEM forwarding
        |-> (forward_rs2 == 2'b11);  // Forward from WB stage
    endproperty
    
    assert_wb_rs2: assert property (wb_forwarding_rs2_detection)
        else $error("[SPEC-HAZ-6] WB forwarding RS2 failed: rs2=x%0d wb_rd=x%0d wb_wen=%b wb_valid=%b forward_rs2=%b (expected 2'b11)",
                    id_rs2_addr, wb_rd_addr, wb_rf_wen, wb_valid, forward_rs2);
    
    property wb_forwarding_rs1_detection;
        @(posedge clk) disable iff (!rst_n)
        (id_valid && id_rs1_used && (id_rs1_addr != 5'b0) &&
         wb_valid && wb_rf_wen && (wb_rd_addr == id_rs1_addr) &&
         !(ex_valid && ex_rf_wen && (ex_rd_addr == id_rs1_addr)) &&  // No EX forwarding
         !(mem_valid && mem_rf_wen && (mem_rd_addr == id_rs1_addr))) // No MEM forwarding
        |-> (forward_rs1 == 2'b11);  // Forward from WB stage
    endproperty
    
    assert_wb_rs1: assert property (wb_forwarding_rs1_detection)
        else $error("[SPEC-HAZ-6] WB forwarding RS1 failed: rs1=x%0d wb_rd=x%0d wb_wen=%b wb_valid=%b forward_rs1=%b (expected 2'b11)",
                    id_rs1_addr, wb_rd_addr, wb_rf_wen, wb_valid, forward_rs1);

    //==========================================================================
    // SPEC-HAZ-7: Exception/MRET Flush Control
    //==========================================================================
    // Verify pipeline flush on exception or MRET:
    // - Exception/MRET detected in MEM stage
    // - Flush IF, ID, and EX stages
    // Expected: if_flush=1, id_flush=1, ex_flush=1
    
    property exception_flush_all;
        @(posedge clk) disable iff (!rst_n)
        (exception_trap || mret_req) |-> (if_flush && id_flush && ex_flush);
    endproperty
    
    assert_exception_flush: assert property (exception_flush_all)
        else $error("[SPEC-HAZ-7] Exception flush incomplete: trap=%b mret=%b but if_flush=%b id_flush=%b ex_flush=%b",
                    exception_trap, mret_req, if_flush, id_flush, ex_flush);

    //==========================================================================
    // Coverage: Forwarding Path Coverage
    //==========================================================================
    
    covergroup forwarding_path_cg @(posedge clk);
        option.per_instance = 1;
        option.name = "hazard_forwarding_paths";
        
        rs1_forward: coverpoint forward_rs1 {
            bins rf_path  = {2'b00};
            bins ex_path  = {2'b01};
            bins mem_path = {2'b10};
            bins wb_path  = {2'b11};
        }
        
        rs2_forward: coverpoint forward_rs2 {
            bins rf_path  = {2'b00};
            bins ex_path  = {2'b01};
            bins mem_path = {2'b10};
            bins wb_path  = {2'b11};
        }
        
        hazard_type: coverpoint {ex_is_load, load_use_stall} {
            bins no_hazard       = {2'b00};
            bins normal_forward  = {2'b01};
            bins load_use_hazard = {2'b11};
        }
        
        // Cross coverage: forwarding conflicts
        rs1_rs2_forward: cross rs1_forward, rs2_forward;
    endgroup
    
    forwarding_path_cg forwarding_cov = new();
    
    //==========================================================================
    // Coverage: Flush Scenarios
    //==========================================================================
    
    covergroup flush_scenario_cg @(posedge clk);
        option.per_instance = 1;
        option.name = "hazard_flush_scenarios";
        
        flush_cause: coverpoint {branch_taken, exception_trap, mret_req} {
            bins no_flush   = {3'b000};
            bins branch     = {3'b100};
            bins exception  = {3'b010};
            bins mret       = {3'b001};
        }
        
        flush_extent: coverpoint {if_flush, id_flush, ex_flush} {
            bins no_flush      = {3'b000};
            bins if_id_flush   = {3'b110};  // Branch
            bins all_flush     = {3'b111};  // Exception/MRET
        }
    endgroup
    
    flush_scenario_cg flush_cov = new();

endmodule : rv32i_hazard_timing_spec
