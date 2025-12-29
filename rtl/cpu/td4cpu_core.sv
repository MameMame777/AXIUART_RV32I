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
    output logic [7:0]  trace_write_ptr_out, // Write pointer for readback
    
    // Memory-Mapped IO: LED output (direct connection to top-level pins)
    output logic [3:0]  led_out             // 4-bit LED control via MMIO
);

    localparam logic [7:0] HALT_REASON_NONE          = 8'h00;
    localparam logic [7:0] HALT_REASON_RESET_HALT    = 8'h01;
    localparam logic [7:0] HALT_REASON_EXTERNAL_HALT = 8'h02;
    localparam logic [7:0] HALT_REASON_STEP_DONE     = 8'h03;
    localparam logic [7:0] HALT_REASON_BREAKPOINT    = 8'h04;
    localparam logic [7:0] HALT_REASON_BRK           = 8'h05;
    localparam logic [7:0] HALT_REASON_PC_OOB        = 8'h06;
    
    // Memory-Mapped IO address map
    localparam logic [15:0] MMIO_BASE = 16'h1000;
    localparam logic [15:0] MMIO_LED  = 16'h1044;  // LED register address (MMIO space)

    logic [15:0] regfile [0:7];
    
    // Memory-Mapped IO: LED register (CPU-writable, separate from UART-accessible registers)
    logic [3:0] led_reg;
    assign led_out = led_reg;  // Direct output to top-level pins
    
    // LD/ST instruction execution variables (declared at module level for proper synthesis)
    logic [2:0] ld_rD_idx, ld_rB_idx;
    logic [5:0] ld_offset6;
    logic [15:0] ld_base_addr, ld_effective_addr;
    logic ld_is_ram, ld_is_led;  // Address decode flags (pre-computed)
    
    logic [2:0] st_rD_idx, st_rB_idx;
    logic [5:0] st_offset6;
    logic [15:0] st_base_addr, st_effective_addr, st_store_data;
    logic st_is_ram, st_is_led;  // Address decode flags (pre-computed)
    
    // LDI instruction execution variables
    logic [2:0] ldi_rd_idx;
    logic [8:0] ldi_imm9;

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
    
    // Data forwarding: track last register write in same cycle
    logic        reg_write_pending;     // Register write scheduled this cycle
    logic [2:0]  reg_write_idx;         // Index of register being written
    logic [15:0] reg_write_data;        // Data being written to register
    
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
    
    // CRITICAL FIX BUG#5: Use read pulse instead of write pulse for latching
    // Previous bug: Edge detection (dbg_reg_index != prev) fails when same address read repeatedly
    // Example: Test reads R1 multiple times → index stays 1 → latch never triggers → returns 0x0000
    // Solution: Latch on EVERY write to CPU_REG_INDEX (using dbg_reg_read_pulse from Register_Block)
    // This ensures atomic capture even for repeated reads of same register
    // FIXED BUG#6: Use dbg_reg_read_pulse (CPU_REG_INDEX write), NOT dbg_reg_write_pulse (CPU_REG_DATA write)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            dbg_reg_rdata_latched <= 16'h0000;
        end else begin
            // Latch register value whenever CPU_REG_INDEX is written
            // This handles repeated reads from same address correctly
            // Captures atomically, remains stable during ~1ms UART read transaction
            if (dbg_reg_read_pulse) begin
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
            reg_write_pending <= 1'b0;
            reg_write_idx <= 3'b000;
            reg_write_data <= 16'h0000;

            for (int i = 0; i < 8; i++) begin
                regfile[i] <= 16'h0000;
            end
            
            // Reset LED register
            led_reg <= 4'h0;
            
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
            if (running && !insn_valid) begin
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
                    $display("[%t] FETCH: PC=0x%04x insn=0x%04x -> insn_valid=1 (was %0d)", $time, pc, ram[pc], insn_valid);
                end
            end else if (!running) begin
                insn_valid <= 1'b0;
            end
            
            // Decode/Execute stage: Process fetched instruction
            if (insn_valid) begin
                logic [3:0]  insn_opcode;
                insn_opcode = insn_fetched[15:12];
                
                // Clear forwarding at start of decode
                reg_write_pending <= 1'b0;
                
                // DEBUG: Instruction decode trace
                $display("[%t] DECODE: PC=0x%04x insn=0x%04x opcode=0x%01x", $time, fetch_pc, insn_fetched, insn_opcode);
                
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

                        debug_alu_flags_update <= 1'b1;
                    end
                    
                    OP_LDI: begin
                        // LDI Rd, #imm9 - Load immediate (unsigned)
                        // Use module-level variables
                        ldi_rd_idx = insn_fetched[11:9];
                        ldi_imm9 = insn_fetched[8:0];
                        regfile[ldi_rd_idx] <= {7'b0000000, ldi_imm9};
                        $display("[%t] LDI: Scheduled R%0d <= 0x%04x (NBA update at end of timestep)", $time, ldi_rd_idx, {7'b0000000, ldi_imm9});
                        $display("[%t] LDI: Before NBA - regfile[%0d] = 0x%04x", $time, ldi_rd_idx, regfile[ldi_rd_idx]);
                        
                        // Data forwarding
                        reg_write_pending <= 1'b1;
                        reg_write_idx <= ldi_rd_idx;
                        reg_write_data <= {7'b0000000, ldi_imm9};
                        insn_valid <= 1'b0;
                    end
                    
                    OP_ADDI: begin
                        // ADDI Rd, #imm9 - Add immediate (unsigned for address construction)
                        logic [2:0] addi_rd_idx;
                        logic [8:0] addi_imm9;
                        logic [15:0] addi_imm_zext;
                        logic [16:0] addi_result;
                        
                        addi_rd_idx = insn_fetched[11:9];
                        addi_imm9 = insn_fetched[8:0];
                        // Zero-extend 9-bit immediate to 16-bit (unsigned)
                        addi_imm_zext = {7'b0000000, addi_imm9};
                        // Perform addition with carry detection
                        addi_result = {1'b0, regfile[addi_rd_idx]} + {1'b0, addi_imm_zext};
                        
                        $display("[%t] ADDI: R%0d = 0x%04x + 0x%04x = 0x%04x", 
                                 $time, addi_rd_idx, regfile[addi_rd_idx], addi_imm_zext, addi_result[15:0]);
                        
                        regfile[addi_rd_idx] <= addi_result[15:0];
                        $display("[%t] ADDI: Scheduled R%0d <= 0x%04x (NBA update at end of timestep)", $time, addi_rd_idx, addi_result[15:0]);
                        // Update flags (Z=bit0, N=bit1, C=bit2)
                        flags[0] <= (addi_result[15:0] == 16'h0000);  // Zero flag
                        flags[1] <= addi_result[15];                   // Negative flag
                        flags[2] <= addi_result[16];                   // Carry flag
                        
                        // Data forwarding: track this write for same-cycle reads
                        reg_write_pending <= 1'b1;
                        reg_write_idx <= addi_rd_idx;
                        reg_write_data <= addi_result[15:0];
                        insn_valid <= 1'b0;
                    end
                    
                    OP_LD: begin
                        // LD rD, [rB + off6] - Load from memory
                        // Use module-level variables for proper RAM inference
                        ld_rD_idx = insn_fetched[11:9];
                        ld_rB_idx = insn_fetched[8:6];
                        ld_offset6 = insn_fetched[5:0];
                        ld_base_addr = regfile[ld_rB_idx];
                        
                        // Sign-extend 6-bit offset to 16-bit
                        ld_effective_addr = ld_base_addr + {{10{ld_offset6[5]}}, ld_offset6};
                        
                        // Pre-compute address decode flags (optimize critical path)
                        ld_is_ram = (ld_effective_addr < MMIO_BASE);
                        ld_is_led = (ld_effective_addr == MMIO_LED);
                        
                        // Address space decode (optimized with pre-computed flags)
                        if (ld_is_ram) begin
                            // RAM access (0x0000-0x0FFF)
                            if (is_ram_addr_valid(ld_effective_addr)) begin
                                regfile[ld_rD_idx] <= ram[ld_effective_addr];
                            end else begin
                                // Out of bounds - load zero
                                regfile[ld_rD_idx] <= 16'h0000;
                            end
                        end else if (ld_is_led) begin
                            // LED register read (MMIO: 0x1044)
                            regfile[ld_rD_idx] <= {12'h000, led_reg};
                        end else begin
                            // Invalid MMIO address - load zero
                            regfile[ld_rD_idx] <= 16'h0000;
                        end
                        
                        // Data forwarding: track this write (optimized with pre-computed flags)
                        reg_write_pending <= 1'b1;
                        reg_write_idx <= ld_rD_idx;
                        reg_write_data <= (ld_is_ram && is_ram_addr_valid(ld_effective_addr)) ? ram[ld_effective_addr] :
                                         ld_is_led ? {12'h000, led_reg} : 16'h0000;
                        insn_valid <= 1'b0;
                    end
                    
                    OP_ST: begin
                        // ST rD, [rB + off6] - Store to memory
                        // Use module-level variables for proper RAM inference
                        st_rD_idx = insn_fetched[11:9];
                        st_rB_idx = insn_fetched[8:6];
                        st_offset6 = insn_fetched[5:0];
                        
                        // Data forwarding: check if we just wrote to the register we're reading
                        if (reg_write_pending && (st_rB_idx == reg_write_idx)) begin
                            st_base_addr = reg_write_data;  // Forward from pending write
                            $display("[%t] ST: FORWARDED regfile[%0d] (R%0d) = 0x%04x", $time, st_rB_idx, st_rB_idx, reg_write_data);
                        end else begin
                            st_base_addr = regfile[st_rB_idx];
                            $display("[%t] ST: Reading regfile[%0d] (R%0d) = 0x%04x", $time, st_rB_idx, st_rB_idx, regfile[st_rB_idx]);
                        end
                        
                        if (reg_write_pending && (st_rD_idx == reg_write_idx)) begin
                            st_store_data = reg_write_data;  // Forward from pending write
                            $display("[%t] ST: FORWARDED regfile[%0d] (R%0d, store data) = 0x%04x", $time, st_rD_idx, st_rD_idx, reg_write_data);
                        end else begin
                            st_store_data = regfile[st_rD_idx];
                            $display("[%t] ST: Reading regfile[%0d] (R%0d, store data) = 0x%04x", $time, st_rD_idx, st_rD_idx, regfile[st_rD_idx]);
                        end
                        
                        // Sign-extend 6-bit offset to 16-bit
                        st_effective_addr = st_base_addr + {{10{st_offset6[5]}}, st_offset6};
                        
                        // Pre-compute address decode flags (optimize critical path)
                        st_is_ram = (st_effective_addr < MMIO_BASE);
                        st_is_led = (st_effective_addr == MMIO_LED);
                        
                        // DEBUG: ST instruction execution trace
                        $display("[%t] ST EXEC: insn=0x%04x rD=%0d rB=%0d off=%0d base=0x%04x data=0x%04x eff_addr=0x%04x", 
                                 $time, insn_fetched, st_rD_idx, st_rB_idx, st_offset6, 
                                 st_base_addr, st_store_data, st_effective_addr);
                        
                        // Address space decode (optimized with pre-computed flags)
                        if (st_is_ram) begin
                            // RAM access (0x0000-0x0FFF)
                            if (is_ram_addr_valid(st_effective_addr)) begin
                                ram[st_effective_addr] <= st_store_data;
                                $display("[%t] ST -> RAM[0x%04x] = 0x%04x", $time, st_effective_addr, st_store_data);
                            end
                            // else: out of bounds - ignore write
                        end else if (st_is_led) begin
                            // LED register write (MMIO: 0x1044)
                            $display("[%t] ST -> LED: data=0x%01x (from 0x%04x, addr=0x%04x, MMIO_LED=0x%04x)", 
                                     $time, st_store_data[3:0], st_store_data, st_effective_addr, MMIO_LED);
                            led_reg <= st_store_data[3:0];  // Only lower 4 bits
                        end else begin
                            $display("[%t] ST -> INVALID MMIO: addr=0x%04x", $time, st_effective_addr);
                        end
                        // else: invalid MMIO address - ignore write
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
                
                // Check step_pending immediately after instruction execution
                // For immediate instructions (LDI/LD/ST), we halt right after execution
                if (step_pending) begin
                    halted <= 1'b1;
                    running <= 1'b0;
                    halt_reason <= HALT_REASON_STEP_DONE;
                    step_pending <= 1'b0;
                    insn_valid <= 1'b0;  // Clear to prevent re-execution
                end
            end else if (step_pending && !alu_writeback_en_hold) begin
                // For ALU instructions with pipeline, halt after writeback completes
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
    end  // always_ff
    
    // Monitor regfile updates for debugging
    always @(regfile[0]) begin
        if ($time > 0) begin  // Skip initial reset
            $display("[%t] REGFILE UPDATE: R0 changed to 0x%04x", $time, regfile[0]);
        end
    end
    always @(regfile[1]) begin
        if ($time > 0) begin
            $display("[%t] REGFILE UPDATE: R1 changed to 0x%04x", $time, regfile[1]);
        end
    end

    // Trace buffer read port (combinational, for Register_Block)
    assign trace_buf_rdata = trace_buffer[trace_buf_addr];
    assign trace_write_ptr_out = trace_write_ptr;
    
endmodule
