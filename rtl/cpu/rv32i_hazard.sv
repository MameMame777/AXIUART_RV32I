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
    // Control Flow Change Detection (for FSM override)
    //==========================================================================
    // Detect control flow changes that should reset FSM
    
    logic control_flow_change_ex;   // Branch/Jump from EX
    logic control_flow_change_mem;  // Exception/MRET from MEM
    
    assign control_flow_change_ex  = branch_taken;
    assign control_flow_change_mem = exception_trap || mret_req;
    
    //==========================================================================
    // Load-Use Hazard FSM
    //==========================================================================
    // State machine to manage load-use hazard stalls with proper release mechanism
    // States:
    //   IDLE: No hazard, normal operation
    //   DETECTED: Hazard detected, assert stall signals
    //   WAIT_MEM: Waiting for load to reach WB stage (1 cycle)
    //   RELEASE: Release stall, allow pipeline to advance
    
    typedef enum logic [1:0] {
        HAZARD_IDLE     = 2'b00,
        HAZARD_DETECTED = 2'b01,
        HAZARD_WAIT_MEM = 2'b10,
        HAZARD_RELEASE  = 2'b11
    } hazard_state_t;
    
    hazard_state_t hazard_state, hazard_next_state;
    
    // State register
    always_ff @(posedge clk) begin
        if (rst) begin
            hazard_state <= HAZARD_IDLE;
        end else begin
            hazard_state <= hazard_next_state;
        end
    end
    
    // Next-state logic
    always_comb begin
        hazard_next_state = hazard_state;
        
        case (hazard_state)
            HAZARD_IDLE: begin
                // Detect new load-use hazard
                if (load_use_hazard) begin
                    hazard_next_state = HAZARD_DETECTED;
                end
            end
            
            HAZARD_DETECTED: begin
                // Load in EX: needs 2 cycles to reach WB
                if (load_use_hazard_ex) begin
                    hazard_next_state = HAZARD_WAIT_MEM;
                end
                // Load in MEM: needs 1 cycle to reach WB
                else if (load_use_hazard_mem) begin
                    hazard_next_state = HAZARD_RELEASE;
                end
                // Hazard resolved by forwarding or flush
                else begin
                    hazard_next_state = HAZARD_RELEASE;
                end
            end
            
            HAZARD_WAIT_MEM: begin
                // Wait for load to move from EX to MEM to WB
                // After 1 cycle, load is in MEM stage
                hazard_next_state = HAZARD_RELEASE;
            end
            
            HAZARD_RELEASE: begin
                // Release stall for 1 cycle to let pipeline advance
                hazard_next_state = HAZARD_IDLE;
            end
            
            default: begin
                hazard_next_state = HAZARD_IDLE;
            end
        endcase
        
        // Override: flush always returns to IDLE
        if (control_flow_change_ex || control_flow_change_mem) begin
            hazard_next_state = HAZARD_IDLE;
        end
    end
    
    //==========================================================================
    // Stall Control
    //==========================================================================
    // Assert stall when FSM is in stall states (DETECTED or WAIT_MEM)
    // Release stall when FSM enters RELEASE or IDLE state
    
    logic fsm_stall_active;
    assign fsm_stall_active = (hazard_state == HAZARD_DETECTED) || 
                              (hazard_state == HAZARD_WAIT_MEM);
    
    assign if_stall = fsm_stall_active;
    assign id_stall = fsm_stall_active;
    
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
    
    // IF stage flush: On any control flow change
    assign if_flush = control_flow_change_ex || control_flow_change_mem;
    
    // ID stage flush: On any control flow change
    assign id_flush = control_flow_change_ex || control_flow_change_mem;
    
    // EX stage flush: Only on MEM stage control flow change (exception/MRET)
    assign ex_flush = control_flow_change_mem;
    
    //==========================================================================
    // Debug Monitoring (optional, enabled with +define+STALL_DEBUG)
    //==========================================================================
`ifdef STALL_DEBUG
    // State duration counter
    logic [15:0] state_duration;
    logic [31:0] total_stall_cycles;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            state_duration <= 16'b0;
            total_stall_cycles <= 32'b0;
        end else begin
            // Increment state duration
            if (hazard_state == hazard_next_state) begin
                state_duration <= state_duration + 1'b1;
            end else begin
                state_duration <= 16'b0;
            end
            
            // Count total stall cycles
            if (fsm_stall_active) begin
                total_stall_cycles <= total_stall_cycles + 1'b1;
            end
            
            // Timeout detection (100 cycles in same state)
            if (state_duration > 100) begin
                $display("[HAZARD TIMEOUT] State=%0d stuck for %0d cycles at time %0t",
                         hazard_state, state_duration, $time);
                $display("  load_use_hazard_ex=%b, load_use_hazard_mem=%b",
                         load_use_hazard_ex, load_use_hazard_mem);
                $display("  ex_is_load=%b, mem_is_load=%b",
                         ex_is_load, mem_is_load);
            end
        end
    end
    
    // State transition monitoring
    always_ff @(posedge clk) begin
        if (!rst && (hazard_state != hazard_next_state)) begin
            $display("[HAZARD FSM] Transition: %0s -> %0s at time %0t",
                     hazard_state.name(), hazard_next_state.name(), $time);
        end
    end
`endif
    
endmodule : rv32i_hazard
