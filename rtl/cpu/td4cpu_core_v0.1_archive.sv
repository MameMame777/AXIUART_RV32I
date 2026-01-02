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
    localparam logic [15:0] MMIO_LED  = 16'h101F;  // LED register address (MMIO space)

    logic [15:0] regfile [0:7];
    
    // Memory-Mapped IO: LED register (CPU-writable, separate from UART-accessible registers)
    logic [3:0] led_reg;
    assign led_out = led_reg;  // Direct output to top-level pins
    
    // LD/ST instruction execution - TWO-STAGE PIPELINE
    // Stage 1: Address calculation and decode (registered)
    logic        mem_op_pending;        // Memory operation in pipeline
    logic        mem_op_is_load;        // 1=LD, 0=ST
    logic [2:0]  mem_op_rd_idx;         // Destination register (for LD)
    logic [15:0] mem_op_effective_addr; // Calculated address
    logic [15:0] mem_op_store_data;     // Data to store (for ST)
    logic        mem_op_is_ram;         // Address decode: RAM access
    logic        mem_op_is_led;         // Address decode: LED MMIO access
    logic        mem_op_executing;      // Set during STAGE 1 to block next fetch
    
    // LDI instruction execution variables
    logic [2:0] ldi_rd_idx;
    logic [8:0] ldi_imm9;

    // RAM: Infer Block RAM with output register for timing
    // Critical attributes for Xilinx synthesis:
    // - ram_style="block" forces BRAM (not distributed RAM)
    // - ram_decomp="power" for efficient packing
    // - read_first mode for pipeline-friendly behavior
    (* ram_style = "block" *)
    (* ram_decomp = "power" *)
    logic [15:0] ram [0:RAM_WORDS-1];
    
    // RAM address registers for proper BRAM inference
    logic [15:0] ram_addr_reg;      // Registered address (for debug visibility)
    logic [15:0] ram_addr_next;     // Next address wire (set before clock edge)
    logic        ram_rd_en;
    
    // Branch delay slot state machine
    logic        branch_delay_slot_active;  // Set when delay slot should execute next cycle
    logic [15:0] ram_rd_data;
    logic        ram_wr_en;
    logic [15:0] ram_wr_addr;
    logic [15:0] ram_wr_data;
    
    // Trace buffer: 256 entries for capturing instruction execution
    // Force BRAM inference with registered output
    (* ram_style = "block" *)
    (* ram_decomp = "power" *)
    logic [7:0]  trace_write_ptr;
    logic [31:0] trace_buffer [0:255];
    logic [31:0] trace_buffer_rd_q;  // Registered output
    
    // ========================================
    // DEBUG SIGNALS FOR WAVEFORM ANALYSIS
    // ========================================
    // Export critical internal signals for waveform debugging
    
    // Register file values (for easy waveform viewing)
     logic [15:0] debug_r0, debug_r1, debug_r2, debug_r3;
     logic [15:0] debug_r4, debug_r5, debug_r6, debug_r7;
    
    // Debug control state
     logic debug_step_pending;
     logic debug_step_executing;
     logic debug_reg_write_active;
     logic [2:0] debug_reg_write_index;
     logic [15:0] debug_reg_write_data;
    
    // Current instruction decode
     logic [15:0] debug_current_insn;
     logic [3:0]  debug_current_opcode;
     logic [2:0]  debug_current_rd;
     logic [2:0]  debug_current_rs;
     logic [5:0]  debug_current_funct;
    
    // ALU operation tracking
     logic [15:0] debug_alu_result;
     logic [15:0] debug_alu_operand_a;
     logic [15:0] debug_alu_operand_b;
     logic debug_alu_writeback;
     logic debug_alu_flags_update;
    
    // Debug register read
     logic [15:0] debug_dbg_reg_rdata;
     logic [2:0]  debug_dbg_reg_index;
    
    // Execution state tracking
     logic debug_halted;
     logic debug_running;
     logic [7:0] debug_halt_reason;
    
    // Branch delay slot handling (MIPS/SPARC style)
    logic [15:0] branch_target_pending; // Target PC to apply after delay slot
    logic        branch_pending;        // Branch target is pending (delay slot executing)
    logic [15:0] br_insn_pc;            // Captured PC of BR instruction (for target calculation)
    
    // Instruction Fetch/Decode Pipeline Stage
    // Break critical path: PC→RAM fetch (cycle N) → decode (cycle N+1) → execute (cycle N+2)
    logic [15:0] insn_fetched;          // Fetched instruction from RAM
    logic        insn_valid;            // Valid instruction fetched
    logic [15:0] exec_pc;               // PC of instruction to be executed (next cycle)
    logic [15:0] insn_fetched_pc;       // PC of instruction in insn_fetched register
    logic [15:0] pending_insn_pc;       // PC saved at fetch request (preserved until fetch completion)
    logic        pc_updated_by_branch;  // Flag to skip PC increment after branch
    
    // Additional pipeline register to break timing path (insn_fetched → regfile CE)
    logic [15:0] insn_decoded_reg;      // Decoded instruction (registered for timing)
    logic        insn_decoded_valid;    // Valid decoded instruction
    logic [15:0] insn_decoded_pc;       // PC of decoded instruction
    
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
     logic [15:0] debug_alu_result_hold;
     logic [2:0]  debug_alu_rd_hold;
     logic        debug_alu_writeback_en_hold;
     logic        debug_writeback_active;
     logic [15:0] debug_writeback_value;
     logic [2:0]  debug_writeback_target;
    
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
        
        // ========================================
        // Branch Delay Slot Implementation (MIPS/SPARC style)
        // BR instruction uses 1-instruction delay slot
        // The instruction immediately after BR ALWAYS executes before branch taken
        // No pipeline interlock needed - delay slot flows naturally through pipeline
        // ========================================
    end
    
    // CRITICAL FIX BUG#5: Use read pulse instead of write pulse for latching
    // Previous bug: Edge detection (dbg_reg_index != prev) fails when same address read repeatedly
    // Example: Test reads R1 multiple times → index stays 1 → latch never triggers → returns 0x0000
    // Solution: Latch on EVERY write to CPU_REG_INDEX (using dbg_reg_read_pulse from Register_Block)
    // This ensures atomic capture even for repeated reads of same register
    // FIXED BUG#6: Use dbg_reg_read_pulse (CPU_REG_INDEX write), NOT dbg_reg_write_pulse (CPU_REG_DATA write)
    // ========================================
    // RAM Block - Separate for proper BRAM inference
    // CRITICAL: Must be in its own always_ff block
    // Single synchronous read-first operation per cycle  
    // TIMING-SAFE RAM FIX: Use ram_addr_next wire (set before clock edge)
    // instead of ram_addr_reg (registered, stale by 1 cycle).
    // This maintains BRAM registered output while reading correct address.
    // 
    // BUG#7 FIX: ram_rd_en timing issue
    // Problem: Lines 756 and 767 in same always_ff create assignment conflict.
    //   Cycle N:   dbg_mem_read_req_pulse=1 → ram_rd_en <= 1, mem_busy_q <= 1
    //   Cycle N+1: mem_busy_q becomes 1 → else-if branch executes → ram_rd_en <= 0 
    //              Result: ram_rd_en never actually outputs 1 (last write wins)
    // Solution: Add ram_read_phase flag to distinguish request (Cycle N+1) from capture (Cycle N+2)
    //   Cycle N:   Request  → ram_rd_en <= 1, ram_read_phase <= 1
    //   Cycle N+1: Access   → ram_rd_en stays 1 (condition prevents clear)
    //   Cycle N+2: Capture  → ram_rd_en <= 0, ram_read_phase <= 0
    // ========================================
    
    always_ff @(posedge clk) begin
        if (ram_wr_en) begin
            ram[ram_wr_addr] <= ram_wr_data;
        end 
        
        // Read using NEXT address (wire), then register for debug visibility
        if (ram_rd_en) begin
            ram_rd_data <= ram[ram_addr_next];  // FIXED: Use wire set THIS cycle
            ram_addr_reg <= ram_addr_next;      // Store for debug tracing
        end
    end

    // ========================================
    // Main CPU State Machine
    // ========================================
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
    logic mem_data_valid;  // NEW: Data valid flag (holds 1 cycle after capture, before busy clears)
    logic [15:0] dbg_mem_addr_latched;  // CRITICAL: Latch address at request time
    logic ram_read_phase;  // BUG#7 FIX: Track RAM read phase (0=idle/capture, 1=RAM access in progress)
    
    // Debug access uses registered RAM path (adds +1 cycle latency)
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
    logic step_insn_fetched;  // Track if step instruction has been fetched

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

            dbg_mem_rdata <= 16'hDEAD;  // Debug: Distinctive init pattern
            dbg_mem_err <= 1'b0;
            mem_busy_q <= 1'b0;
            mem_data_valid <= 1'b0;
            dbg_mem_addr_latched <= 16'h0000;
            ram_read_phase <= 1'b0;  // BUG#7 FIX: Initialize RAM read phase flag
            step_pending <= 1'b0;
            step_insn_fetched <= 1'b0;
            reg_write_pending <= 1'b0;
            reg_write_idx <= 3'b000;
            reg_write_data <= 16'h0000;
            
            // CRITICAL: Initialize pipeline valid flags
            insn_valid <= 1'b0;
            insn_decoded_valid <= 1'b0;
            ram_rd_en <= 1'b0;

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
            insn_fetched_pc <= 16'h0000;
            insn_valid <= 1'b0;
            exec_pc <= 16'h0000;
            
            // Pipeline decode register reset (timing optimization)
            insn_decoded_reg <= 16'h0000;
            insn_decoded_valid <= 1'b0;
            insn_decoded_pc <= 16'h0000;
            
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
            
            // RAM control signals
            ram_addr_reg <= 16'd0;
            ram_addr_next <= 16'd0;  // Initialize to prevent X propagation
            ram_rd_en <= 1'b0;
            ram_wr_en <= 1'b0;
            ram_wr_addr <= 16'd0;
            ram_wr_data <= 16'd0;
            alu_flags_update_en_hold <= 1'b0;
            alu_flags_hold <= 3'd0;
            alu_insn_hold <= 16'd0;
            branch_pending <= 1'b0;
            branch_target_pending <= 16'd0;
            br_insn_pc <= 16'd0;
            pending_insn_pc <= 16'd0;

            // RAM contents are left uninitialized by default.
            // In simulation, use $readmemh from a testbench if needed.
            // Initialize to NOP (0x0000) in simulation to prevent X-opcode runaway
            `ifndef SYNTHESIS
            for (int i = 0; i < RAM_WORDS; i++) begin
                ram[i] <= 16'h0000;  // NOP = all zeros
            end
            `endif
            
            mem_op_executing <= 1'b0;
            mem_op_pending <= 1'b0;
            mem_op_is_load <= 1'b0;
            mem_op_rd_idx <= 3'd0;
            mem_op_effective_addr <= 16'd0;
            mem_op_store_data <= 16'd0;
            mem_op_is_ram <= 1'b0;
            mem_op_is_led <= 1'b0;
        end else begin
            // BUG#7 FIX #12: Do NOT clear mem_busy_q unconditionally here!
            // It must hold across the 3-cycle debug read sequence.
            // Only clear it explicitly when operation completes (Lines 802, 810)
            // mem_busy_q <= 1'b0;  // ← REMOVED: This was clearing mem_busy_q every cycle!
            
            // BUG#7 FIX: Do NOT clear ram_read_phase here - it needs to hold across cycles!
            // Only clear it explicitly when read completes in Line 787
            mem_op_executing <= 1'b0;  // Clear by default
            
            // Default: Hold previous RAM address to prevent X propagation
            // DON'T restore from ram_addr_reg when halted (debug operations pollute it)
            // Just let ram_addr_next hold its value
            if (!ram_rd_en && !mem_busy_q && !halted) begin
                ram_addr_next <= ram_addr_reg;
            end else if (!ram_rd_en && halted) begin
                // During halted state, explicitly hold ram_addr_next
                // This prevents X when no operation is setting it
                ram_addr_next <= ram_addr_next;
            end
            
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
                step_insn_fetched <= 1'b0;
                // Flush fetch pipeline on halt
                insn_valid <= 1'b0;
                // BUG#7 FIX: Don't clear ram_rd_en if debug read is in progress
                if (!ram_read_phase) begin
                    ram_rd_en <= 1'b0;
                end
                pc_updated_by_branch <= 1'b0;
                branch_pending <= 1'b0;
            end

            if (dbg_run_req_pulse) begin
                halted <= 1'b0;
                running <= 1'b1;
                step_pending <= 1'b0;
                step_insn_fetched <= 1'b0;
                // CRITICAL: Flush BOTH pipeline stages on run
                insn_valid <= 1'b0;
                insn_decoded_valid <= 1'b0;
                // BUG#7 FIX: Don't clear ram_rd_en if debug read is in progress
                if (!ram_read_phase) begin
                    ram_rd_en <= 1'b0;
                end
                pc_updated_by_branch <= 1'b0;
                branch_pending <= 1'b0;
            end

            // Debug writes into state are accepted only while halted
            if (halted) begin
                if (dbg_wr_pc_pulse) begin
                    pc <= dbg_wr_pc_data;
                    // Flush BOTH pipeline stages on PC write
                    insn_valid <= 1'b0;
                    insn_decoded_valid <= 1'b0;
                    pc_updated_by_branch <= 1'b0;
                    branch_pending <= 1'b0;
                end
                if (dbg_wr_sp_pulse) sp <= dbg_wr_sp_data;
                if (dbg_wr_flags_pulse) flags <= dbg_wr_flags_data;
                if (dbg_reg_write_pulse) regfile[dbg_reg_index] <= dbg_reg_wdata;

                // Debug memory access (single-cycle request)
                if (dbg_mem_read_req_pulse || dbg_mem_write_req_pulse) begin
                    // CRITICAL: Latch address immediately at request time
                    dbg_mem_addr_latched <= dbg_mem_addr;
                    mem_busy_q <= 1'b1;
                    dbg_mem_err <= 1'b0;
                    mem_data_valid <= 1'b0;

                    if (!is_ram_addr_valid(dbg_mem_addr)) begin
                        dbg_mem_err <= 1'b1;
                        mem_data_valid <= 1'b1;  // Error completes immediately
                        ram_read_phase <= 1'b0;  // No RAM access for error case
                    end else begin
                        if (dbg_mem_write_req_pulse) begin
                            ram_wr_en <= 1'b1;
                            ram_wr_addr <= dbg_mem_addr;
                            ram_wr_data <= dbg_mem_wdata;
                            dbg_mem_rdata <= dbg_mem_wdata;  // Write-first forwarding
                            mem_data_valid <= 1'b1;  // Write completes immediately
                            ram_read_phase <= 1'b0;  // Write, not read
                        end
                        if (dbg_mem_read_req_pulse) begin
                            // BUG#7 FIX: Use registered RAM path (adds +1 cycle latency)
                            // Set ram_read_phase=1 for Cycle N+1 (address setup)
                            ram_addr_next <= dbg_mem_addr;  // Set address wire
                            ram_rd_en <= 1'b1;              // Trigger read
                            ram_read_phase <= 1'b1;         // Enter RAM access phase (wait for data)
                            // Data will be ready in Cycle N+2
                        end
                    end
                end else if (mem_busy_q) begin
                    // BUG#7 FIX: 2-stage read sequence for RAM latency
                    // Cycle N+1: ram_read_phase=1, hold for RAM access
                    // Cycle N+2: ram_read_phase=0, data ready, capture
                    if (ram_read_phase == 1'b1 && ram_rd_en && !dbg_mem_err) begin
                        // Cycle N+1: Hold for RAM data propagation
                        ram_addr_next <= ram_addr_next;  // Hold address
                        ram_rd_en <= 1'b1;               // Keep read enable
                        ram_read_phase <= 1'b0;          // Transition to capture phase
                    end else if (ram_read_phase == 1'b0 && ram_rd_en && !dbg_mem_err) begin
                        // Cycle N+2: Capture RAM data
                        dbg_mem_rdata <= ram_rd_data;    // Capture valid data
                        mem_data_valid <= 1'b1;          // Mark complete - but don't clear mem_busy_q yet
                        ram_rd_en <= 1'b0;               // Clear read enable
                        // mem_busy_q stays high this cycle to protect against clearing
                    end else if (mem_data_valid) begin
                        // Cycle N+3: Clear mem_busy_q one cycle after data captured
                        ram_wr_en <= 1'b0;
                        mem_busy_q <= 1'b0;              // Now safe to clear
                        mem_data_valid <= 1'b0;
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
                step_insn_fetched <= 1'b0;  // Reset fetch tracking
                halted <= 1'b0;
                running <= 1'b1;
                // CRITICAL: Flush pipeline on transition to running
                insn_valid <= 1'b0;
                insn_decoded_valid <= 1'b0;
            end

            // Execution (minimal bring-up): advance PC and stop on BRK/breakpoints
            // CRITICAL: Don't fetch new instruction while memory operation is executing (2-cycle LD/ST)
            // mem_op_executing prevents fetch during STAGE 1, mem_op_pending blocks during STAGE 2
            // CRITICAL: When step_pending, allow ONE fetch then block until halt
            // CRITICAL: Block fetch while ram_rd_en is active (prevents double-fetch)
            // NOTE: Delay slot architecture - PC increments naturally except after branch
            if (running && !insn_valid && !mem_op_executing && !mem_op_pending && !ram_rd_en && !(step_pending && step_insn_fetched)) begin
                // Two-stage branch delay slot state machine
                // STAGE 1: Delay slot wait - instruction already fetched, just wait for execution
                if (branch_delay_slot_active) begin
                    // CRITICAL: Delay slot instruction was already fetched when branch decoded
                    // During branch decode cycle, normal fetch logic ran: pc <= pc + 1
                    // So delay slot instruction is already in pipeline (or will complete this cycle)
                    // Do NOT issue another fetch - that would fetch PC+1 which should be skipped
                    // Simply transition to branch_pending and wait for delay slot to execute
                    branch_delay_slot_active <= 1'b0;  // Clear delay slot flag
                    branch_pending <= 1'b1;            // Set branch pending for next cycle
                    // No ram_rd_en, no PC change - just state transition
                    // Branch target will be fetched in next cycle when branch_pending applies
                    if (step_pending) step_insn_fetched <= 1'b1;
                    
                // STAGE 2: Branch application - apply target and fetch from target
                end else if (branch_pending) begin
                    // Branch delay slot completed - apply branch target and fetch immediately
                    branch_pending <= 1'b0;
                    // Fetch from branch target immediately (breakpoint/validity checks)
                    if (pc_matches_breakpoint(branch_target_pending)) begin
                        pc <= branch_target_pending;
                        halted <= 1'b1;
                        running <= 1'b0;
                        break_hit <= 1'b1;
                        halt_reason <= HALT_REASON_BREAKPOINT;
                        step_pending <= 1'b0;
                        step_insn_fetched <= 1'b0;
                        insn_valid <= 1'b0;
                    end else if (!is_ram_addr_valid(branch_target_pending)) begin
                        pc <= branch_target_pending;
                        halted <= 1'b1;
                        running <= 1'b0;
                        halt_reason <= HALT_REASON_PC_OOB;
                        step_pending <= 1'b0;
                        step_insn_fetched <= 1'b0;
                        insn_valid <= 1'b0;
                    end else begin
                        // Fetch from branch target
                        // CRITICAL: Set PC = target (absolute assignment, no increment)
                        ram_addr_next <= (branch_target_pending <= 16'd1) ? 16'd0 : (branch_target_pending - 16'd1);
                        ram_rd_en <= 1'b1;
                        exec_pc <= branch_target_pending;  // Instruction will execute at target PC
                        pending_insn_pc <= branch_target_pending;  // Save PC for fetch completion
                        pc <= branch_target_pending;  // Set PC = target
                        // Track step fetch
                        if (step_pending) step_insn_fetched <= 1'b1;
                    end
                    
                // Normal fetch operations (no branch active)
                end else begin
                    // Breakpoint/validity checks happen here (simplified)
                    if (pc_matches_breakpoint(pc)) begin
                        halted <= 1'b1;
                        running <= 1'b0;
                        break_hit <= 1'b1;
                        halt_reason <= HALT_REASON_BREAKPOINT;
                        step_pending <= 1'b0;
                        step_insn_fetched <= 1'b0;
                        insn_valid <= 1'b0;
                        branch_pending <= 1'b0;
                    end else if (!is_ram_addr_valid(pc)) begin
                        halted <= 1'b1;
                        running <= 1'b0;
                        halt_reason <= HALT_REASON_PC_OOB;
                        step_pending <= 1'b0;
                        step_insn_fetched <= 1'b0;
                        insn_valid <= 1'b0;
                        branch_pending <= 1'b0;
                    end else begin
                        // Fetch instruction - request RAM read
                        // CRITICAL: PC uses pre-increment, so current PC reads ram[PC-1]
                        // Label instruction with current PC (where it will execute)
                        ram_addr_next <= (pc <= 16'd1) ? 16'd0 : (pc - 16'd1);
                        ram_rd_en <= 1'b1;
                        exec_pc <= pc;  // Record current PC where instruction executes
                        pending_insn_pc <= pc;  // Save PC for fetch completion
                        pc <= pc + 16'd1;  // Increment PC for next cycle
                        
                        // Track that step instruction has been fetched
                        if (step_pending) step_insn_fetched <= 1'b1;
                    end
                end
            end else if (!running) begin
                insn_valid <= 1'b0;
                // BUG#7 FIX #11: Don't clear ram_rd_en during ANY debug read sequence state
                // CRITICAL: Check mem_busy_q to protect full 3-cycle debug read sequence
                // Without this guard, ram_rd_en gets cleared at +8ps after clock when mem_busy_q=0
                if (!ram_read_phase && !dbg_mem_read_req_pulse && !mem_busy_q) begin
                    ram_rd_en <= 1'b0;
                end
            end
            
            // Capture fetched instruction when RAM data is valid
            // CRITICAL: Only capture if CPU is still running (prevent halt-time fetch completion)
            if (ram_rd_en && running) begin
                insn_fetched <= ram_rd_data;
                insn_fetched_pc <= pending_insn_pc;  // Use saved PC from fetch request (NOT exec_pc)
                insn_valid <= 1'b1;
                ram_rd_en <= 1'b0;  // Clear enable
                
                // CRITICAL: Also capture decode pipeline immediately to prevent pending_insn_pc overwrite
                // insn_fetched_pc will be overwritten by next fetch before decode stage runs
                insn_decoded_reg <= ram_rd_data;
                insn_decoded_valid <= 1'b1;
                insn_decoded_pc <= pending_insn_pc;  // Capture atomically with fetch
                
                // BUG FIX: Capture br_insn_pc using pending_insn_pc (the PC saved at fetch request)
                // CRITICAL: exec_pc is global state that updates every fetch cycle and may have
                // already advanced to PC+1 by fetch completion. Use pending_insn_pc which was
                // saved atomically with the fetch request and represents the PC of THIS instruction.
                if (ram_rd_data[15:12] == OP_BR) begin
                    br_insn_pc <= pending_insn_pc;  // Use fetch-request PC, not stale exec_pc
                end
            end else if (ram_rd_en && !running && !ram_read_phase) begin
                // BUG#7 FIX: Discard fetch that completed during halt
                // ONLY clear if NOT in debug read phase
                ram_rd_en <= 1'b0;
            end
            
            // Pipeline register: insn_fetched → insn_decoded_reg (timing optimization)
            // NOTE: Now captured atomically at fetch completion (line ~950) to prevent overwrite
            // This breaks the critical path from insn_fetched[7] to regfile CE
            if (insn_valid) begin
                // Decode pipeline already captured at fetch completion
                // Just clear insn_valid flag here
                insn_valid <= 1'b0;  // Clear after decode
            end
            // NOTE: insn_decoded_valid is cleared after execution, not here
            
            // Decode/Execute stage: Process decoded instruction
            if (insn_decoded_valid) begin
                logic [3:0]  insn_opcode;
                insn_opcode = insn_decoded_reg[15:12];
                
                // NOTE: br_insn_pc is already captured at insn_valid time (when instruction first decoded)
                // Do not capture here - insn_decoded_pc has already been overwritten by later instructions
                
                // Execution trace for debugging (logs every instruction)
                $display("[EXEC] @%0t PC=%0d, OPCODE=0x%h, insn=0x%04h, branch_pending=%b", 
                         $time, insn_decoded_pc, insn_opcode, insn_decoded_reg, branch_pending);
                
                // Clear forwarding at start of decode
                reg_write_pending <= 1'b0;
                
                // Debug: Capture current instruction
                debug_current_insn <= insn_decoded_reg;
                debug_current_opcode <= insn_opcode;

                // Execute instruction based on opcode
                case (insn_opcode)
                    OP_R_ALU: begin
                        // Debug: Capture operands and operation
                        debug_current_rd <= insn_decoded_reg[11:9];
                        debug_current_rs <= insn_decoded_reg[8:6];
                        debug_current_funct <= insn_decoded_reg[5:0];
                        debug_alu_operand_a <= regfile[insn_decoded_reg[11:9]];
                        debug_alu_operand_b <= regfile[insn_decoded_reg[8:6]];
                        
                        // ALU Pipeline Stage 1: Fetch operands only
                        // No arithmetic computation - just decode and register read
                        alu_operand_a_stage1 <= regfile[insn_decoded_reg[11:9]];
                        alu_operand_b_stage1 <= regfile[insn_decoded_reg[8:6]];
                        alu_funct_stage1 <= insn_decoded_reg[5:0];
                        alu_rd_stage1 <= insn_decoded_reg[11:9];
                        alu_input_flags_stage1 <= flags;
                        alu_valid_stage1 <= 1'b1;
                        alu_insn_stage1 <= insn_decoded_reg;  // Propagate instruction

                        debug_alu_flags_update <= 1'b1;
                    end
                    
                    OP_LDI: begin
                        // LDI Rd, #imm9 - Load immediate (unsigned)
                        // Use module-level variables
                        ldi_rd_idx = insn_decoded_reg[11:9];
                        ldi_imm9 = insn_decoded_reg[8:0];
                        regfile[ldi_rd_idx] <= {7'b0000000, ldi_imm9};
                        
                        // Data forwarding
                        reg_write_pending <= 1'b1;
                        reg_write_idx <= ldi_rd_idx;
                        reg_write_data <= {7'b0000000, ldi_imm9};
                    end
                    
                    OP_ADDI: begin
                        // ADDI Rd, #imm9s - Add immediate (sign-extended per ISA spec)
                        logic [2:0] addi_rd_idx;
                        logic [8:0] addi_imm9;
                        logic [15:0] addi_imm_sext;
                        logic [16:0] addi_result;
                        
                        addi_rd_idx = insn_decoded_reg[11:9];
                        addi_imm9 = insn_decoded_reg[8:0];
                        // Sign-extend 9-bit immediate to 16-bit (signed per ISA)
                        addi_imm_sext = {{7{addi_imm9[8]}}, addi_imm9};
                        // Perform addition with carry detection
                        addi_result = {1'b0, regfile[addi_rd_idx]} + {1'b0, addi_imm_sext};
                        
                        regfile[addi_rd_idx] <= addi_result[15:0];
                        // Update flags (Z=bit0, N=bit1, C=bit2)
                        flags[0] <= (addi_result[15:0] == 16'h0000);  // Zero flag
                        flags[1] <= addi_result[15];                   // Negative flag
                        flags[2] <= addi_result[16];                   // Carry flag
                        
                        // Data forwarding: track this write for same-cycle reads
                        reg_write_pending <= 1'b1;
                        reg_write_idx <= addi_rd_idx;
                        reg_write_data <= addi_result[15:0];
                    end
                    
                    OP_LD: begin
                        // LD rD, [rB + off6] - STAGE 1: Address calculation
                        logic [2:0] rD_idx, rB_idx;
                        logic [5:0] offset6;
                        logic [15:0] base_addr, effective_addr;
                        
                        rD_idx = insn_decoded_reg[11:9];
                        rB_idx = insn_decoded_reg[8:6];
                        offset6 = insn_decoded_reg[5:0];
                        
                        // Data forwarding: check if base register was just written
                        if (reg_write_pending && (rB_idx == reg_write_idx)) begin
                            base_addr = reg_write_data;
                        end else begin
                            base_addr = regfile[rB_idx];
                        end
                        
                        // Sign-extend 6-bit offset to 16-bit
                        effective_addr = base_addr + {{10{offset6[5]}}, offset6};
                        
                        // Stage pipeline registers for STAGE 2 execution
                        mem_op_pending <= 1'b1;
                        mem_op_is_load <= 1'b1;
                        mem_op_rd_idx <= rD_idx;
                        mem_op_effective_addr <= effective_addr;
                        mem_op_is_ram <= (effective_addr < MMIO_BASE);
                        mem_op_is_led <= (effective_addr == MMIO_LED);
                        
                        // Block next fetch - STAGE 2 needs next cycle
                        mem_op_executing <= 1'b1;
                        
                        // STAGE 2 will execute in next cycle (handled separately below)
                    end
                    
                    OP_ST: begin
                        // ST rD, [rB + off6] - STAGE 1: Address calculation
                        logic [2:0] rB_idx, rD_idx;
                        logic [5:0] offset6;
                        logic [15:0] base_addr, effective_addr, store_data;
                        
                        rB_idx = insn_decoded_reg[8:6];
                        rD_idx = insn_decoded_reg[11:9];
                        offset6 = insn_decoded_reg[5:0];
                        
                        // Data forwarding: check if we just wrote to the registers we're reading
                        if (reg_write_pending && (rB_idx == reg_write_idx)) begin
                            base_addr = reg_write_data;  // Forward base address
                        end else begin
                            base_addr = regfile[rB_idx];
                        end
                        
                        if (reg_write_pending && (rD_idx == reg_write_idx)) begin
                            store_data = reg_write_data;  // Forward store data
                        end else begin
                            store_data = regfile[rD_idx];
                        end
                        
                        // Calculate effective address
                        effective_addr = base_addr + {{10{offset6[5]}}, offset6};
                        
                        // Stage pipeline registers for STAGE 2 execution
                        mem_op_pending <= 1'b1;
                        mem_op_is_load <= 1'b0;
                        mem_op_effective_addr <= effective_addr;
                        mem_op_store_data <= store_data;
                        mem_op_is_ram <= (effective_addr < MMIO_BASE);
                        mem_op_is_led <= (effective_addr == MMIO_LED);
                        
                        // Block next fetch - STAGE 2 needs next cycle
                        mem_op_executing <= 1'b1;
                        
                        // STAGE 2 will execute in next cycle (handled separately below)
                    end
                    
                    OP_SYS: begin
                        if (is_brk_insn(insn_decoded_reg)) begin
                            halted <= 1'b1;
                            running <= 1'b0;
                            brk_hit <= 1'b1;
                            halt_reason <= HALT_REASON_BRK;
                            step_pending <= 1'b0;
                            step_insn_fetched <= 1'b0;
                            pc_updated_by_branch <= 1'b0;  // Clear branch flag on halt
                            branch_pending <= 1'b0;         // Clear pending branch
                            insn_decoded_valid <= 1'b0;     // CRITICAL: Prevent re-execution
                        end
                    end
                    
                    OP_BR: begin
                        // BR cond, off9 - Branch instruction
                        logic [2:0] br_cond;
                        logic [8:0] br_offset9;
                        logic [15:0] br_offset_sext;
                        logic [15:0] br_target_pc;
                        logic br_taken;
                        logic [2:0] effective_flags;  // FLAG FORWARDING: Use ALU Stage 3 flags if pending
                        
                        br_cond = insn_decoded_reg[11:9];
                        br_offset9 = insn_decoded_reg[8:0];
                        
                        // Sign-extend 9-bit offset to 16-bit
                        br_offset_sext = {{7{br_offset9[8]}}, br_offset9};
                        
                        // Calculate target PC: PC-relative to BR instruction location
                        // Delay slot architecture (MIPS/SPARC style):
                        //   BR at PC_BR: calculates target = PC_BR + offset
                        //   Delay slot at PC_BR+1: executes (PC increments naturally)
                        //   After delay slot: PC = target
                        //
                        // Example: BR.AL +2 at PC=1
                        //   Target = 1 + 2 = 3
                        //   Delay slot at PC=2 executes
                        //   Then jump to PC=3
                        //
                        // Example: BR.AL -2 at PC=5
                        //   Target = 5 + (-2) = 3
                        //   Delay slot at PC=6 executes  
                        //   Then jump to PC=3
                        //
                        // CRITICAL FIX: Use br_insn_pc (captured at decode time) to prevent
                        // pipeline overwrites during multi-cycle execution.
                        // br_insn_pc is captured when BR first enters decode stage.
                        // Formula: target = PC_BR + offset (branch offset is relative to branch PC)
                        br_target_pc = br_insn_pc + br_offset_sext;
                        
                        // FLAG FORWARDING: Resolve 3-cycle data hazard for CMP→BR / ADDI→BR
                        // Problem: CMP/ADDI updates flags in ALU Stage 4 (writeback), but BR
                        //          reads flags in decode stage (3 cycles earlier).
                        // Solution: If ALU Stage 3 has pending flag update, forward those flags
                        //           instead of reading the committed (stale) flags register.
                        // Example timeline:
                        //   Cycle N:   CMP decoded
                        //   Cycle N+1: BR decoded ← reads effective_flags (forwarded from Stage 3)
                        //              CMP in ALU Stage 2
                        //   Cycle N+2: BR delay slot, CMP in Stage 3 (flags computed)
                        //   Cycle N+3: Branch taken, CMP flags written (no longer needed)
                        if (alu_flags_update_en_hold) begin
                            effective_flags = alu_flags_hold;  // Forward from ALU Stage 3
                            $display("[FLAG_FWD] @%0t PC=%0d: Forwarding flags from ALU Stage 3: Z=%b N=%b C=%b (committed: Z=%b N=%b C=%b)", 
                                    $time, pc, alu_flags_hold[0], alu_flags_hold[1], alu_flags_hold[2],
                                    flags[0], flags[1], flags[2]);
                        end else begin
                            effective_flags = flags;           // Use committed flags
                            $display("[FLAG_FWD] @%0t PC=%0d: Using committed flags: Z=%b N=%b C=%b", 
                                    $time, pc, flags[0], flags[1], flags[2]);
                        end
                        
                        // Evaluate branch condition using forwarded flags
                        case (br_cond)
                            COND_AL: br_taken = 1'b1;                    // Always
                            COND_Z:  br_taken = effective_flags[0];      // Zero flag
                            COND_NZ: br_taken = ~effective_flags[0];     // Not zero
                            COND_C:  br_taken = effective_flags[2];      // Carry flag
                            COND_NC: br_taken = ~effective_flags[2];     // Not carry
                            COND_N:  br_taken = effective_flags[1];      // Negative flag
                            COND_NN: br_taken = ~effective_flags[1];     // Not negative
                            default: br_taken = 1'b0;                    // Reserved (no branch)
                        endcase
                        
                        // Update PC if branch taken
                        // Two-stage branch delay slot architecture:
                        //   STAGE 1: Branch decodes at PC=N, set branch_delay_slot_active
                        //   STAGE 2: Delay slot at PC=N+1 executes, then set branch_pending
                        //   STAGE 3: Branch target applied at PC=T
                        if (br_taken) begin
                            branch_target_pending <= br_target_pc;      // Stage target
                            branch_delay_slot_active <= 1'b1;           // Flag delay slot for next cycle
                            $display("[BR_TARGET] @%0t PC=%0d: Branch taken to target=%0d (br_insn_pc=%0d, offset=%0d)", 
                                    $time, insn_decoded_pc, br_target_pc, br_insn_pc, $signed(br_offset_sext));
                            // Delay slot will execute in next fetch cycle
                            // After delay slot fetch, branch_pending will be set
                        end
                    end
                    
                    default: begin
                        // Unimplemented opcodes treated as NOP
                    end
                endcase
                
                // Check step_pending after instruction execution
                // CRITICAL: LD/ST are 2-cycle operations, don't halt until STAGE 2 completes
                // Check if current instruction is LD or ST
                // Use 4-state comparison (!==) to prevent X-opcode runaway
                if (step_pending && (insn_opcode !== OP_LD) && (insn_opcode !== OP_ST)) begin
                    halted <= 1'b1;
                    running <= 1'b0;
                    halt_reason <= HALT_REASON_STEP_DONE;
                    step_pending <= 1'b0;
                    step_insn_fetched <= 1'b0;
                end
                
                // CRITICAL: Clear decoded valid after execution (except for LD/ST which need 2 cycles)
                if ((insn_opcode !== OP_LD) && (insn_opcode !== OP_ST)) begin
                    insn_decoded_valid <= 1'b0;
                end
            end
            
            // ========================================
            // STAGE 2: Memory Operation Execution
            // ========================================
            // Execute pending LD/ST operations from previous cycle
            // This runs in parallel with instruction decode, NOT inside insn_decoded_valid block
            if (mem_op_pending && running) begin  // BUG#7 FIX: Only execute when running
                if (mem_op_is_load) begin
                    // LD instruction - STAGE 2: Execute memory read
                    if (mem_op_is_ram) begin
                        // RAM access
                        if (is_ram_addr_valid(mem_op_effective_addr)) begin
                            ram_addr_next <= mem_op_effective_addr;  // FIXED: Set wire
                            ram_rd_en <= 1'b1;
                        end else begin
                            // Out of bounds - load zero
                            regfile[mem_op_rd_idx] <= 16'h0000;
                        end
                    end else if (mem_op_is_led) begin
                        // LED MMIO read
                        regfile[mem_op_rd_idx] <= {12'h000, led_reg};
                    end else begin
                        // Invalid MMIO address - load zero
                        regfile[mem_op_rd_idx] <= 16'h0000;
                    end
                    
                    // Data forwarding for loads (RAM data available next cycle)
                    reg_write_pending <= 1'b1;
                    reg_write_idx <= mem_op_rd_idx;
                    reg_write_data <= mem_op_is_led ? {12'h000, led_reg} : ram_rd_data;  // FIXED: Use ram_rd_data
                end else begin
                    // ST instruction - STAGE 2: Execute memory write
                    if (mem_op_is_ram) begin
                        // RAM access
                        if (is_ram_addr_valid(mem_op_effective_addr)) begin
                            ram_wr_en <= 1'b1;
                            ram_wr_addr <= mem_op_effective_addr;
                            ram_wr_data <= mem_op_store_data;
                        end
                    end else if (mem_op_is_led) begin
                        // LED MMIO write - THIS WILL NOW WORK!
                        led_reg <= mem_op_store_data[3:0];
                    end
                    // else: invalid MMIO - ignore write
                end
                
                // Clear pipeline after execution
                mem_op_pending <= 1'b0;
                insn_decoded_valid <= 1'b0;  // Clear decoded instruction after LD/ST completes
                
                // For step mode: halt after memory operation completes
                if (step_pending) begin
                    halted <= 1'b1;
                    running <= 1'b0;
                    halt_reason <= HALT_REASON_STEP_DONE;
                    step_pending <= 1'b0;
                    step_insn_fetched <= 1'b0;
                end
            end
            
            // Handle step completion for ALU pipeline outside insn_decoded_valid
            if (step_pending && (alu_writeback_en_hold || alu_flags_update_en_hold)) begin
                // For ALU instructions with pipeline, halt after writeback/flag-update completes
                halted <= 1'b1;
                running <= 1'b0;
                halt_reason <= HALT_REASON_STEP_DONE;
                step_pending <= 1'b0;
                step_insn_fetched <= 1'b0;
            end
        end  // else (not rst)
    end  // always_ff @(posedge clk)
    
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
    
    // Trace buffer read port (combinational, for Register_Block)
    // Trace buffer readout (registered for timing)
    always_ff @(posedge clk) begin
        trace_buffer_rd_q <= trace_buffer[trace_buf_addr];
    end
    assign trace_buf_rdata = trace_buffer_rd_q;
    assign trace_write_ptr_out = trace_write_ptr;
    
endmodule
