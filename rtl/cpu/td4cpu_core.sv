`timescale 1ns / 1ps

import td4cpu_isa_pkg::*;

module td4cpu_core #(
    parameter int RAM_WORDS = 4096
) (
    input  logic        clk,
    input  logic        rst,

    // Debug control inputs (one-cycle pulses)
    input  logic        dbg_halt_req_pulse,
    input  logic        dbg_run_req_pulse,
    input  logic        dbg_step_req_pulse,
    input  logic        dbg_clr_halt_reason_pulse,
    input  logic        dbg_halt_on_reset,

    input  logic        dbg_bp_global_en,
    input  logic        dbg_bp0_en,
    input  logic        dbg_bp1_en,
    input  logic        dbg_bp_match_fetch,
    input  logic [15:0] dbg_bp0_pc,
    input  logic [15:0] dbg_bp1_pc,

    // CPU state outputs for debug readback
    output logic        halted,
    output logic        running,
    output logic        break_hit,
    output logic        brk_hit,
    output logic [7:0]  halt_reason,

    output logic [15:0] pc,
    output logic [15:0] sp,
    output logic [2:0]  flags,

    // Debug write-back into CPU state (honored only while halted)
    input  logic        dbg_wr_pc_pulse,
    input  logic [15:0] dbg_wr_pc_data,
    input  logic        dbg_wr_sp_pulse,
    input  logic [15:0] dbg_wr_sp_data,
    input  logic        dbg_wr_flags_pulse,
    input  logic [2:0]  dbg_wr_flags_data,

    input  logic [2:0]  dbg_reg_index,
    output logic [15:0] dbg_reg_rdata,
    input  logic        dbg_reg_read_pulse,   // Changed: Trigger on READ, not write
    input  logic        dbg_reg_write_pulse,  // Kept for actual register write
    input  logic [15:0] dbg_reg_wdata,

    // Debug memory access (honored only while halted)
    input  logic [15:0] dbg_mem_addr,
    input  logic [15:0] dbg_mem_wdata,
    output logic [15:0] dbg_mem_rdata,
    input  logic        dbg_mem_read_req_pulse,
    input  logic        dbg_mem_write_req_pulse,
    output logic        dbg_mem_busy,
    output logic        dbg_mem_err,
    
    // Trace buffer outputs for fast UVM verification
    output logic        trace_valid,        // Instruction executed (1 cycle pulse)
    output logic [15:0] trace_insn,         // Executed instruction
    output logic [15:0] trace_pc,           // PC of executed instruction
    output logic [2:0]  trace_rd_idx,       // Destination register index
    output logic [15:0] trace_rd_value,     // Result written to rd
    output logic [2:0]  trace_rs_idx,       // Source register index
    output logic [15:0] trace_rs_value,     // Value from rs
    output logic [2:0]  trace_flags,        // Flags after execution (Z,N,C)
    
    // Trace buffer memory interface (for UVM readback)
    input  logic [7:0]  trace_buf_addr,     // Read address
    output logic [31:0] trace_buf_rdata,    // Read data
    output logic [7:0]  trace_write_ptr_out // Write pointer for readback
);

    localparam logic [7:0] HALT_REASON_NONE          = 8'h00;
    localparam logic [7:0] HALT_REASON_RESET_HALT    = 8'h01;
    localparam logic [7:0] HALT_REASON_EXTERNAL_HALT = 8'h02;
    localparam logic [7:0] HALT_REASON_STEP_DONE     = 8'h03;
    localparam logic [7:0] HALT_REASON_BREAKPOINT    = 8'h04;
    localparam logic [7:0] HALT_REASON_BRK           = 8'h05;
    localparam logic [7:0] HALT_REASON_PC_OOB        = 8'h06;

    logic [15:0] regfile [0:7];

    // RAM: Infer Block RAM with output register for timing
    (* ram_style = "block" *)
    (* rw_addr_collision = "yes" *)
    logic [15:0] ram [0:RAM_WORDS-1];
    
    // Trace buffer: 256 entries for capturing instruction execution
    logic [7:0]  trace_write_ptr;
    logic [31:0] trace_buffer [0:255];
    
    // ========================================
    // DEBUG SIGNALS FOR WAVEFORM ANALYSIS
    // ========================================
    // Export critical internal signals for waveform debugging
    
    // Register file values (for easy waveform viewing)
    (* keep = "true" *) logic [15:0] debug_r0, debug_r1, debug_r2, debug_r3;
    (* keep = "true" *) logic [15:0] debug_r4, debug_r5, debug_r6, debug_r7;
    
    // Debug control state
    (* keep = "true" *) logic debug_step_pending;
    (* keep = "true" *) logic debug_step_executing;
    (* keep = "true" *) logic debug_reg_write_active;
    (* keep = "true" *) logic [2:0] debug_reg_write_index;
    (* keep = "true" *) logic [15:0] debug_reg_write_data;
    
    // Current instruction decode
    (* keep = "true" *) logic [15:0] debug_current_insn;
    (* keep = "true" *) logic [3:0]  debug_current_opcode;
    (* keep = "true" *) logic [2:0]  debug_current_rd;
    (* keep = "true" *) logic [2:0]  debug_current_rs;
    (* keep = "true" *) logic [5:0]  debug_current_funct;
    
    // ALU operation tracking
    (* keep = "true" *) logic [15:0] debug_alu_result;
    (* keep = "true" *) logic [15:0] debug_alu_operand_a;
    (* keep = "true" *) logic [15:0] debug_alu_operand_b;
    (* keep = "true" *) logic debug_alu_writeback;
    (* keep = "true" *) logic debug_alu_flags_update;
    
    // Debug register read
    (* keep = "true" *) logic [15:0] debug_dbg_reg_rdata;
    (* keep = "true" *) logic [2:0]  debug_dbg_reg_index;
    
    // Execution state tracking
    (* keep = "true" *) logic debug_halted;
    (* keep = "true" *) logic debug_running;
    (* keep = "true" *) logic [7:0] debug_halt_reason;
    
    // Instruction Fetch/Decode Pipeline Stage
    // Break critical path: PC→RAM fetch (cycle N) → decode (cycle N+1)
    logic [15:0] insn_fetched;          // Fetched instruction from RAM
    logic        insn_valid;            // Valid instruction fetched
    logic [15:0] fetch_pc;              // PC of fetched instruction
    
    // ALU Pipeline Stage 1: Operand Fetch + Simple Decode
    // Break critical path: PC→RAM→decode→operand_fetch (no ALU computation yet)
    logic [15:0] alu_operand_a_stage1;    // Operand A from register file
    logic [15:0] alu_operand_b_stage1;    // Operand B from register file
    logic [5:0]  alu_funct_stage1;        // ALU function code
    logic [2:0]  alu_rd_stage1;           // Destination register
    logic [2:0]  alu_input_flags_stage1;  // Input flags for operations
    logic        alu_valid_stage1;        // Valid ALU operation
    logic [15:0] alu_insn_stage1;         // Instruction code (for trace)
    
    // ALU Pipeline Stage 2: Arithmetic Computation
    // Complex operations (ADD/SUB/CMP) happen here with carry chains
    logic [15:0] alu_result_stage2;
    logic [2:0]  alu_rd_stage2;
    logic        alu_writeback_en_stage2;
    logic        alu_flags_update_en_stage2;
    logic [2:0]  alu_input_flags_stage2;  // For flag computation
    logic [15:0] alu_operand_a_stage2;    // Forwarded for flag calc
    logic [15:0] alu_operand_b_stage2;    // Forwarded for flag calc
    logic [5:0]  alu_funct_stage2;        // Forwarded function code
    logic [15:0] alu_insn_stage2;         // Instruction code (for trace)
    
    // ALU Pipeline Stage 3 (writeback holding registers)
    // Timing optimization: Enable register replication and balancing
    (* max_fanout = 50 *)
    logic [15:0] alu_result_hold;
    logic [2:0]  alu_rd_hold;
    (* max_fanout = 20 *)
    logic        alu_writeback_en_hold;
    (* max_fanout = 20 *)
    logic        alu_flags_update_en_hold;  // Track flag updates (for CMP, etc.)
    (* max_fanout = 30 *)
    logic [2:0]  alu_flags_hold;  // {c, n, z}
    logic [15:0] alu_insn_hold;   // Instruction code (for trace)
    
    // Additional debug signals for writeback tracking
    (* keep = "true" *) logic [15:0] debug_alu_result_hold;
    (* keep = "true" *) logic [2:0]  debug_alu_rd_hold;
    (* keep = "true" *) logic        debug_alu_writeback_en_hold;
    (* keep = "true" *) logic        debug_writeback_active;
    (* keep = "true" *) logic [15:0] debug_writeback_value;
    (* keep = "true" *) logic [2:0]  debug_writeback_target;
    
    // Latched debug register read data (to prevent race with UART read timing)
    logic [15:0] dbg_reg_rdata_latched;

    // Combinational debug mirrors (for waveform viewing only)
    always_comb begin
        // Update debug mirrors
        debug_r0 = regfile[0];
        debug_r1 = regfile[1];
        debug_r2 = regfile[2];
        debug_r3 = regfile[3];
        debug_r4 = regfile[4];
        debug_r5 = regfile[5];
        debug_r6 = regfile[6];
        debug_r7 = regfile[7];
        
        debug_dbg_reg_rdata = dbg_reg_rdata;
        debug_dbg_reg_index = dbg_reg_index;
        
        debug_halted = halted;
        debug_running = running;
        debug_halt_reason = halt_reason;
        
        // Writeback tracking
        debug_alu_result_hold = alu_result_hold;
        debug_alu_rd_hold = alu_rd_hold;
        debug_alu_writeback_en_hold = alu_writeback_en_hold;
        debug_writeback_active = alu_writeback_en_hold;
        debug_writeback_value = alu_result_hold;
        debug_writeback_target = alu_rd_hold;
    end
    
    // CRITICAL FIX BUG#5: Use write pulse instead of edge detection
    // Previous bug: Edge detection (dbg_reg_index != prev) fails when same address read repeatedly
    // Example: Test reads R1 multiple times → index stays 1 → latch never triggers → returns 0x0000
    // Solution: Latch on EVERY write to CPU_DBG_ADDR (using dbg_reg_write_pulse from Register_Block)
    // This ensures atomic capture even for repeated reads of same register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            dbg_reg_rdata_latched <= 16'h0000;
        end else begin
            // Latch register value whenever CPU_DBG_ADDR is written (any value)
            // This handles repeated reads from same address correctly
            // Captures atomically, remains stable during ~1ms UART read transaction
            if (dbg_reg_write_pulse) begin
                dbg_reg_rdata_latched <= regfile[dbg_reg_index];
            end
        end
    end
    
    // Output the latched value (not direct regfile connection)
    assign dbg_reg_rdata = dbg_reg_rdata_latched;

    // Debug memory busy is a one-cycle pulse after request
    logic mem_busy_q;
    assign dbg_mem_busy = mem_busy_q;

    function automatic bit pc_matches_breakpoint(input logic [15:0] pc_in);
        bit hit;
        hit = 1'b0;
        if (dbg_bp_global_en && dbg_bp_match_fetch) begin
            if (dbg_bp0_en && (pc_in == dbg_bp0_pc)) hit = 1'b1;
            if (dbg_bp1_en && (pc_in == dbg_bp1_pc)) hit = 1'b1;
        end
        return hit;
    endfunction

    function automatic bit is_ram_addr_valid(input logic [15:0] a);
        return (a < RAM_WORDS);
    endfunction

    // Minimal instruction handling for bring-up:
    // - BRK causes HALT
    // - everything else treated as NOP (PC increments)
    function automatic bit is_brk_insn(input logic [15:0] insn);
        bit is_sys;
        bit z_ok;
        is_sys = (insn[15:12] == OP_SYS);
        z_ok = (insn[11:3] == 9'h000);
        return is_sys && z_ok && (insn[2:0] == SYSOP_BRK);
    endfunction

    // ========================================
    // ALU Stage 2: Arithmetic Computation Only
    // ========================================
    // Simplified function that only does arithmetic - no decode, no flag compute
    function automatic logic [15:0] alu_compute_stage2(
        input logic [5:0]  funct,
        input logic [15:0] operand_a,
        input logic [15:0] operand_b
    );
        logic [16:0] temp_sum, temp_sub;
        logic [15:0] result;
        
        case (funct)
            FUNCT_ADD: begin
                temp_sum = {1'b0, operand_a} + {1'b0, operand_b};
                result = temp_sum[15:0];
            end
            
            FUNCT_SUB, FUNCT_CMP: begin
                temp_sub = {1'b0, operand_a} - {1'b0, operand_b};
                result = temp_sub[15:0];
            end
            
            FUNCT_AND: result = operand_a & operand_b;
            FUNCT_OR:  result = operand_a | operand_b;
            FUNCT_XOR: result = operand_a ^ operand_b;
            FUNCT_SHL1: result = {operand_a[14:0], 1'b0};
            FUNCT_SHR1: result = {1'b0, operand_a[15:1]};
            FUNCT_MOV: result = operand_b;
            
            default: result = 16'h0000;
        endcase
        
        return result;
    endfunction
    
    // ========================================
    // ALU Flag Computation (Pipeline Stage 3)
    // ========================================
    // Separated flag generation for timing optimization
    function automatic void compute_alu_flags(
        input  logic [5:0]  funct,
        input  logic [15:0] alu_result,
        input  logic [15:0] operand_a,
        input  logic [15:0] operand_b,
        input  logic [2:0]  input_flags,
        output logic        flag_z,
        output logic        flag_n,
        output logic        flag_c
    );
        logic [16:0] temp_add, temp_sub;
        
        // Initialize with input flags (preserved for non-flag-updating ops)
        flag_c = input_flags[2];
        flag_z = input_flags[0];
        flag_n = input_flags[1];
        
        case (funct)
            FUNCT_ADD: begin
                temp_add = {1'b0, operand_a} + {1'b0, operand_b};
                flag_z = (alu_result == 16'h0000);
                flag_n = alu_result[15];
                flag_c = temp_add[16];
            end
            
            FUNCT_SUB, FUNCT_CMP: begin
                temp_sub = {1'b0, operand_a} - {1'b0, operand_b};
                flag_z = (alu_result == 16'h0000);
                flag_n = alu_result[15];
                flag_c = ~temp_sub[16];
            end
            
            FUNCT_AND, FUNCT_OR, FUNCT_XOR: begin
                flag_z = (alu_result == 16'h0000);
                flag_n = alu_result[15];
                // flag_c preserved from input
            end
            
            FUNCT_SHL1: begin
                flag_z = (alu_result == 16'h0000);
                flag_n = alu_result[15];
                flag_c = operand_a[15];
            end
            
            FUNCT_SHR1: begin
                flag_z = (alu_result == 16'h0000);
                flag_n = alu_result[15];
                flag_c = operand_a[0];
            end
            
            default: begin
                // Preserve input flags
            end
        endcase
    endfunction

    logic step_pending;

    always_ff @(posedge clk) begin
        if (rst) begin
            pc <= 16'h0000;
            sp <= 16'hFFFE;
            flags <= 3'b000;

            halted <= 1'b1;
            running <= 1'b0;
            break_hit <= 1'b0;
            brk_hit <= 1'b0;
            halt_reason <= HALT_REASON_RESET_HALT;

            dbg_mem_rdata <= 16'h0000;
            dbg_mem_err <= 1'b0;
            mem_busy_q <= 1'b0;
            step_pending <= 1'b0;

            for (int i = 0; i < 8; i++) begin
                regfile[i] <= 16'h0000;
            end
            
            // Reset debug signals
            debug_step_pending <= 1'b0;
            debug_step_executing <= 1'b0;
            debug_reg_write_active <= 1'b0;
            debug_reg_write_index <= 3'h0;
            debug_reg_write_data <= 16'h0000;
            debug_current_insn <= 16'h0000;
            debug_current_opcode <= 4'h0;
            debug_current_rd <= 3'h0;
            debug_current_rs <= 3'h0;
            debug_current_funct <= 6'h00;
            debug_alu_result <= 16'h0000;
            debug_alu_operand_a <= 16'h0000;
            debug_alu_operand_b <= 16'h0000;
            debug_alu_writeback <= 1'b0;
            debug_alu_flags_update <= 1'b0;
            
            // Instruction fetch pipeline reset
            insn_fetched <= 16'h0000;
            insn_valid <= 1'b0;
            fetch_pc <= 16'h0000;
            
            // ALU Pipeline Stage 1 reset (operand fetch)
            alu_operand_a_stage1 <= 16'd0;
            alu_operand_b_stage1 <= 16'd0;
            alu_funct_stage1 <= 6'd0;
            alu_rd_stage1 <= 3'd0;
            alu_input_flags_stage1 <= 3'd0;
            alu_valid_stage1 <= 1'b0;
            alu_insn_stage1 <= 16'd0;
            
            // ALU Pipeline Stage 2 reset (arithmetic)
            alu_result_stage2 <= 16'd0;
            alu_rd_stage2 <= 3'd0;
            alu_writeback_en_stage2 <= 1'b0;
            alu_flags_update_en_stage2 <= 1'b0;
            alu_input_flags_stage2 <= 3'd0;
            alu_operand_a_stage2 <= 16'd0;
            alu_operand_b_stage2 <= 16'd0;
            alu_funct_stage2 <= 6'd0;
            alu_insn_stage2 <= 16'd0;
            
            // ALU Pipeline Stage 3 reset (writeback)
            alu_result_hold <= 16'd0;
            alu_rd_hold <= 3'd0;
            alu_writeback_en_hold <= 1'b0;
            alu_flags_update_en_hold <= 1'b0;
            alu_flags_hold <= 3'd0;
            alu_insn_hold <= 16'd0;

            // RAM contents are left uninitialized by default.
            // In simulation, use $readmemh from a testbench if needed.
        end else begin
            mem_busy_q <= 1'b0;
            
            // Update step tracking
            debug_step_pending <= step_pending;
            debug_step_executing <= (running && step_pending);
            
            // Track register writes
            debug_reg_write_active <= (halted && dbg_reg_write_pulse);
            if (halted && dbg_reg_write_pulse) begin
                debug_reg_write_index <= dbg_reg_index;
                debug_reg_write_data <= dbg_reg_wdata;
            end
            
            // ========================================
            // ALU Pipeline Stage 2: Arithmetic Computation
            // ========================================
            // Take operands from Stage 1 and compute result
            if (alu_valid_stage1) begin
                alu_result_stage2 <= alu_compute_stage2(
                    alu_funct_stage1,
                    alu_operand_a_stage1,
                    alu_operand_b_stage1
                );
                alu_rd_stage2 <= alu_rd_stage1;
                alu_input_flags_stage2 <= alu_input_flags_stage1;
                alu_operand_a_stage2 <= alu_operand_a_stage1;
                alu_operand_b_stage2 <= alu_operand_b_stage1;
                alu_funct_stage2 <= alu_funct_stage1;
                alu_insn_stage2 <= alu_insn_stage1;  // Propagate instruction
                
                // Determine writeback/flags enable
                case (alu_funct_stage1)
                    FUNCT_CMP: begin
                        alu_writeback_en_stage2 <= 1'b0;
                        alu_flags_update_en_stage2 <= 1'b1;
                    end
                    FUNCT_MOV: begin
                        alu_writeback_en_stage2 <= 1'b1;
                        alu_flags_update_en_stage2 <= 1'b0;
                    end
                    default: begin
                        alu_writeback_en_stage2 <= 1'b1;
                        alu_flags_update_en_stage2 <= 1'b1;
                    end
                endcase
                
                alu_valid_stage1 <= 1'b0;  // Clear valid
            end
            
            // ========================================
            // ALU Pipeline Stage 3: Flag Generation & Hold
            // ========================================
            // Move stage 2 results to holding registers and generate flags
            if (alu_writeback_en_stage2 || alu_flags_update_en_stage2) begin
                alu_result_hold <= alu_result_stage2;
                alu_rd_hold <= alu_rd_stage2;
                alu_writeback_en_hold <= alu_writeback_en_stage2;
                alu_flags_update_en_hold <= alu_flags_update_en_stage2;
                alu_insn_hold <= alu_insn_stage2;  // Propagate instruction for trace
                alu_insn_hold <= alu_insn_stage2;  // Propagate instruction for trace
                
                // Generate flags from stage 2 data
                if (alu_flags_update_en_stage2) begin
                    logic flag_z, flag_n, flag_c;
                    compute_alu_flags(
                        alu_funct_stage2,
                        alu_result_stage2,
                        alu_operand_a_stage2,
                        alu_operand_b_stage2,
                        alu_input_flags_stage2,
                        flag_z,
                        flag_n,
                        flag_c
                    );
                    alu_flags_hold <= {flag_c, flag_n, flag_z};
                end
                
                // Clear stage 2 enables
                alu_writeback_en_stage2 <= 1'b0;
                alu_flags_update_en_stage2 <= 1'b0;
            end
            
            // ========================================
            // ALU Pipeline Stage 4: Writeback
            // ========================================
            // This must complete BEFORE halt for step execution
            if (alu_writeback_en_hold) begin
                regfile[alu_rd_hold] <= alu_result_hold;
                alu_writeback_en_hold <= 1'b0;  // Clear after writeback
            end
            
            // Update flags separately (CMP updates flags but not registers)
            if (alu_flags_update_en_hold) begin
                flags <= alu_flags_hold;
                alu_flags_update_en_hold <= 1'b0;  // Clear after update
            end

            if (dbg_clr_halt_reason_pulse) begin
                break_hit <= 1'b0;
                brk_hit <= 1'b0;
                halt_reason <= HALT_REASON_NONE;
            end

            // External state changes: halt/run/step
            if (dbg_halt_req_pulse) begin
                halted <= 1'b1;
                running <= 1'b0;
                halt_reason <= HALT_REASON_EXTERNAL_HALT;
                step_pending <= 1'b0;
                // Flush fetch pipeline on halt
                insn_valid <= 1'b0;
            end

            if (dbg_run_req_pulse) begin
                halted <= 1'b0;
                running <= 1'b1;
                step_pending <= 1'b0;
                // Flush fetch pipeline on run
                insn_valid <= 1'b0;
            end

            // Debug writes into state are accepted only while halted
            if (halted) begin
                if (dbg_wr_pc_pulse) begin
                    pc <= dbg_wr_pc_data;
                    // Flush fetch pipeline on PC write
                    insn_valid <= 1'b0;
                end
                if (dbg_wr_sp_pulse) sp <= dbg_wr_sp_data;
                if (dbg_wr_flags_pulse) flags <= dbg_wr_flags_data;
                if (dbg_reg_write_pulse) regfile[dbg_reg_index] <= dbg_reg_wdata;

                // Debug memory access (single-cycle)
                if (dbg_mem_read_req_pulse || dbg_mem_write_req_pulse) begin
                    mem_busy_q <= 1'b1;
                    dbg_mem_err <= 1'b0;

                    if (!is_ram_addr_valid(dbg_mem_addr)) begin
                        dbg_mem_err <= 1'b1;
                    end else begin
                        if (dbg_mem_write_req_pulse) begin
                            ram[dbg_mem_addr] <= dbg_mem_wdata;
                        end
                        if (dbg_mem_read_req_pulse) begin
                            dbg_mem_rdata <= ram[dbg_mem_addr];
                        end
                    end
                end
            end else begin
                // If a debug mem op is attempted while running, flag error.
                if (dbg_mem_read_req_pulse || dbg_mem_write_req_pulse) begin
                    mem_busy_q <= 1'b1;
                    dbg_mem_err <= 1'b1;
                end
            end

            // One-instruction step request: halt after next instruction completes
            if (dbg_step_req_pulse) begin
                step_pending <= 1'b1;
                halted <= 1'b0;
                running <= 1'b1;
            end

            // Execution (minimal bring-up): advance PC and stop on BRK/breakpoints
            if (running) begin
                // Fetch stage: Read instruction from RAM
                // Breakpoint/validity checks happen here (simplified)
                if (pc_matches_breakpoint(pc)) begin
                    halted <= 1'b1;
                    running <= 1'b0;
                    break_hit <= 1'b1;
                    halt_reason <= HALT_REASON_BREAKPOINT;
                    step_pending <= 1'b0;
                    insn_valid <= 1'b0;
                end else if (!is_ram_addr_valid(pc)) begin
                    halted <= 1'b1;
                    running <= 1'b0;
                    halt_reason <= HALT_REASON_PC_OOB;
                    step_pending <= 1'b0;
                    insn_valid <= 1'b0;
                end else begin
                    // Fetch instruction - decode happens next cycle
                    insn_fetched <= ram[pc];
                    insn_valid <= 1'b1;
                    fetch_pc <= pc;
                    pc <= pc + 16'd1;
                end
            end else begin
                insn_valid <= 1'b0;
            end
            
            // Decode/Execute stage: Process fetched instruction
            if (insn_valid) begin
                logic [3:0]  insn_opcode;
                insn_opcode = insn_fetched[15:12];
                
                // Debug: Capture current instruction
                debug_current_insn <= insn_fetched;
                debug_current_opcode <= insn_opcode;

                // Execute instruction based on opcode
                case (insn_opcode)
                    OP_R_ALU: begin
                        // Debug: Capture operands and operation
                        debug_current_rd <= insn_fetched[11:9];
                        debug_current_rs <= insn_fetched[8:6];
                        debug_current_funct <= insn_fetched[5:0];
                        debug_alu_operand_a <= regfile[insn_fetched[11:9]];
                        debug_alu_operand_b <= regfile[insn_fetched[8:6]];
                        
                        // ALU Pipeline Stage 1: Fetch operands only
                        // No arithmetic computation - just decode and register read
                        alu_operand_a_stage1 <= regfile[insn_fetched[11:9]];
                        alu_operand_b_stage1 <= regfile[insn_fetched[8:6]];
                        alu_funct_stage1 <= insn_fetched[5:0];
                        alu_rd_stage1 <= insn_fetched[11:9];
                        alu_input_flags_stage1 <= flags;
                        alu_valid_stage1 <= 1'b1;
                        alu_insn_stage1 <= insn_fetched;  // Propagate instruction
                        alu_insn_stage1 <= insn_fetched;  // Propagate instruction
                        
                        // Debug: Mark as ALU operation
                        debug_alu_writeback <= 1'b1;
                        debug_alu_flags_update <= 1'b1;
                    end
                    
                    OP_SYS: begin
                        if (is_brk_insn(insn_fetched)) begin
                            halted <= 1'b1;
                            running <= 1'b0;
                            brk_hit <= 1'b1;
                            halt_reason <= HALT_REASON_BRK;
                            step_pending <= 1'b0;
                        end
                    end
                    
                    default: begin
                        // Unimplemented opcodes treated as NOP
                    end
                endcase
            end
            
            // Check step_pending AFTER potential writeback completes
            // This ensures register writes from ALU finish before halt
            if (step_pending && !alu_writeback_en_hold) begin
                halted <= 1'b1;
                running <= 1'b0;
                halt_reason <= HALT_REASON_STEP_DONE;
                step_pending <= 1'b0;
            end
        end
    end
    
    // ========================================
    // Generate trace signals for UVM direct monitoring
    always_ff @(posedge clk) begin
        if (rst) begin
            trace_valid <= 1'b0;
            trace_insn <= '0;
            trace_pc <= '0;
            trace_rd_idx <= '0;
            trace_rd_value <= '0;
            trace_rs_idx <= '0;
            trace_rs_value <= '0;
            trace_flags <= '0;
            trace_write_ptr <= '0;
        end else begin
            // Default: no trace
            trace_valid <= 1'b0;
            
            // Capture trace when instruction completes (writeback or flag update)
            // This captures both register-writing instructions (ADD, SUB, etc.)
            // and flag-only instructions (CMP)
            if (alu_writeback_en_hold || alu_flags_update_en_hold) begin
                trace_valid <= 1'b1;
                trace_insn <= alu_insn_hold;  // Use pipelined instruction
                trace_pc <= pc - 1;  // PC already incremented, show original
                trace_rd_idx <= alu_rd_hold;
                trace_rd_value <= alu_result_hold;
                trace_rs_idx <= debug_current_rs;
                trace_rs_value <= debug_alu_operand_b;
                trace_flags <= flags;
                
                // Store in trace buffer for UVM readback
                // Format: [31:16]=insn, [15:0]=result
                trace_buffer[trace_write_ptr] <= {alu_insn_hold, alu_result_hold};
                trace_write_ptr <= trace_write_ptr + 1;
            end
        end
    end
    
    // Trace buffer read port (combinational, for Register_Block)
    assign trace_buf_rdata = trace_buffer[trace_buf_addr];
    assign trace_write_ptr_out = trace_write_ptr;
    
endmodule
