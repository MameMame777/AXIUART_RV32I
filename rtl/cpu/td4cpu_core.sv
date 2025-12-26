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
    
    // ALU writeback holding registers (separate from automatic function variables)
    logic [15:0] alu_result_hold;
    logic [2:0]  alu_rd_hold;
    logic        alu_writeback_en_hold;
    logic        alu_flags_update_en_hold;  // Track flag updates (for CMP, etc.)
    logic [2:0]  alu_flags_hold;  // {c, n, z}
    
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

    // Instruction decoder signals
    logic [3:0]  opcode;
    logic [2:0]  rd_idx;
    logic [2:0]  rs_idx;
    logic [5:0]  funct;
    logic [15:0] rd_val;
    logic [15:0] rs_val;
    
    // ALU outputs
    logic [15:0] alu_result;
    logic        alu_flag_z;
    logic        alu_flag_n;
    logic        alu_flag_c;
    logic        alu_writeback_en;
    logic        alu_flags_update_en;

    // Decode instruction fields (combinational)
    always_comb begin
        opcode  = 4'h0;
        rd_idx  = 3'h0;
        rs_idx  = 3'h0;
        funct   = 6'h00;
        rd_val  = 16'h0000;
        rs_val  = 16'h0000;
        
        alu_result = 16'h0000;
        alu_flag_z = 1'b0;
        alu_flag_n = 1'b0;
        alu_flag_c = 1'b0;
        alu_writeback_en = 1'b0;
        alu_flags_update_en = 1'b0;
    end

    // ALU execution logic (combinational)
    function automatic void decode_and_execute_r_alu(
        input logic [15:0] insn,
        input logic [15:0] regfile_array [0:7],
        input logic [2:0]  current_flags,
        output logic [15:0] result,
        output logic        flag_z,
        output logic        flag_n,
        output logic        flag_c,
        output logic        writeback_en,
        output logic        flags_update_en
    );
        logic [2:0]  rd;
        logic [2:0]  rs;
        logic [5:0]  fn;
        logic [15:0] rd_value;
        logic [15:0] rs_value;
        logic [16:0] temp_sum;
        logic [16:0] temp_sub;
        
        rd = insn[11:9];
        rs = insn[8:6];
        fn = insn[5:0];
        rd_value = regfile_array[rd];
        rs_value = regfile_array[rs];
        
        // Default outputs
        result = 16'h0000;
        flag_z = 1'b0;
        flag_n = 1'b0;
        flag_c = current_flags[2]; // Preserve carry by default
        writeback_en = 1'b1;
        flags_update_en = 1'b1;
        
        case (fn)
            FUNCT_ADD: begin
                temp_sum = {1'b0, rd_value} + {1'b0, rs_value};
                result = temp_sum[15:0];
                flag_z = (result == 16'h0000);
                flag_n = result[15];
                flag_c = temp_sum[16];
            end
            
            FUNCT_SUB: begin
                temp_sub = {1'b0, rd_value} - {1'b0, rs_value};
                result = temp_sub[15:0];
                flag_z = (result == 16'h0000);
                flag_n = result[15];
                flag_c = ~temp_sub[16]; // C=1 if no borrow (rd >= rs)
            end
            
            FUNCT_AND: begin
                result = rd_value & rs_value;
                flag_z = (result == 16'h0000);
                flag_n = result[15];
                // flag_c preserved
            end
            
            FUNCT_OR: begin
                result = rd_value | rs_value;
                flag_z = (result == 16'h0000);
                flag_n = result[15];
                // flag_c preserved
            end
            
            FUNCT_XOR: begin
                result = rd_value ^ rs_value;
                flag_z = (result == 16'h0000);
                flag_n = result[15];
                // flag_c preserved
            end
            
            FUNCT_CMP: begin
                temp_sub = {1'b0, rd_value} - {1'b0, rs_value};
                result = temp_sub[15:0];
                flag_z = (result == 16'h0000);
                flag_n = result[15];
                flag_c = ~temp_sub[16];
                writeback_en = 1'b0; // CMP does not write back
            end
            
            FUNCT_SHL1: begin
                result = {rd_value[14:0], 1'b0};
                flag_z = (result == 16'h0000);
                flag_n = result[15];
                flag_c = rd_value[15]; // Shift-out bit
            end
            
            FUNCT_SHR1: begin
                result = {1'b0, rd_value[15:1]};
                flag_z = (result == 16'h0000);
                flag_n = result[15];
                flag_c = rd_value[0]; // Shift-out bit
            end
            
            FUNCT_MOV: begin
                result = rs_value;
                flags_update_en = 1'b0; // MOV does not update flags
            end
            
            default: begin
                result = 16'h0000;
                writeback_en = 1'b0;
                flags_update_en = 1'b0;
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
            
            alu_result_hold <= 16'd0;
            alu_rd_hold <= 3'd0;
            alu_writeback_en_hold <= 1'b0;            alu_flags_update_en_hold <= 1'b0;            alu_flags_hold <= 3'd0;

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
            
            // ALU writeback stage (uses holding registers from previous cycle)
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
            end

            if (dbg_run_req_pulse) begin
                halted <= 1'b0;
                running <= 1'b1;
                step_pending <= 1'b0;
            end

            // Debug writes into state are accepted only while halted
            if (halted) begin
                if (dbg_wr_pc_pulse) pc <= dbg_wr_pc_data;
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
                // Breakpoint at fetch boundary
                if (pc_matches_breakpoint(pc)) begin
                    halted <= 1'b1;
                    running <= 1'b0;
                    break_hit <= 1'b1;
                    halt_reason <= HALT_REASON_BREAKPOINT;
                    step_pending <= 1'b0;
                end else if (!is_ram_addr_valid(pc)) begin
                    halted <= 1'b1;
                    running <= 1'b0;
                    halt_reason <= HALT_REASON_PC_OOB;
                    step_pending <= 1'b0;
                end else begin
                    logic [15:0] insn;
                    logic [3:0]  insn_opcode;
                    insn = ram[pc];
                    insn_opcode = insn[15:12];
                    
                    // Debug: Capture current instruction
                    debug_current_insn <= insn;
                    debug_current_opcode <= insn_opcode;

                    // Default: increment PC
                    pc <= pc + 16'd1;

                    // Execute instruction based on opcode
                    case (insn_opcode)
                        OP_R_ALU: begin
                            logic [15:0] r_result;
                            logic        r_flag_z, r_flag_n, r_flag_c;
                            logic        r_writeback_en, r_flags_update_en;
                            
                            // Debug: Capture operands and operation
                            debug_current_rd <= insn[11:9];
                            debug_current_rs <= insn[8:6];
                            debug_current_funct <= insn[5:0];
                            debug_alu_operand_a <= regfile[insn[11:9]];
                            debug_alu_operand_b <= regfile[insn[8:6]];
                            
                            decode_and_execute_r_alu(
                                insn,
                                regfile,
                                flags,
                                r_result,
                                r_flag_z,
                                r_flag_n,
                                r_flag_c,
                                r_writeback_en,
                                r_flags_update_en
                            );
                            
                            // Store to holding registers (writeback happens next cycle)
                            alu_result_hold <= r_result;
                            alu_rd_hold <= insn[11:9];
                            alu_writeback_en_hold <= r_writeback_en;
                            alu_flags_update_en_hold <= r_flags_update_en;
                            if (r_flags_update_en) begin
                                alu_flags_hold <= {r_flag_c, r_flag_n, r_flag_z};
                            end
                            
                            // Debug: Capture ALU result
                            debug_alu_result <= r_result;
                            debug_alu_writeback <= r_writeback_en;
                            debug_alu_flags_update <= r_flags_update_en;
                        end
                        
                        OP_SYS: begin
                            if (is_brk_insn(insn)) begin
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

                    // If we were stepping, halt AFTER next cycle (allows writeback)
                    // Don't halt immediately - let writeback happen first
                    // (Halt will occur in next cycle when step_pending is still set
                    //  but alu_writeback_en_hold becomes 0)
                end
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
                trace_insn <= debug_current_insn;
                trace_pc <= pc - 1;  // PC already incremented, show original
                trace_rd_idx <= alu_rd_hold;
                trace_rd_value <= alu_result_hold;
                trace_rs_idx <= debug_current_rs;
                trace_rs_value <= debug_alu_operand_b;
                trace_flags <= flags;
                
                // Store in trace buffer for UVM readback
                // Format: [31:16]=insn, [15:0]=result
                trace_buffer[trace_write_ptr] <= {debug_current_insn, alu_result_hold};
                trace_write_ptr <= trace_write_ptr + 1;
            end
        end
    end
    
    // Trace buffer read port (combinational, for Register_Block)
    assign trace_buf_rdata = trace_buffer[trace_buf_addr];
    assign trace_write_ptr_out = trace_write_ptr;
    
endmodule
