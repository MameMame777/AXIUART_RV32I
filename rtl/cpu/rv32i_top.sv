`timescale 1ns / 1ps
//==============================================================================
// RV32I Top-Level Integration Module
//==============================================================================
// 
// Architecture: 5-stage pipeline (IF/ID/EX/MEM/WB) with modular design
// ISA: RV32I Base Integer Instruction Set (40 instructions)
// Registers: 32 x 32-bit (x0 hardwired to zero)
// Memory: 8KB internal RAM, byte-addressed, unified architecture
// Hazards: Data forwarding, load-use stall, branch/jump flush
// 
// Module Hierarchy:
//   rv32i_if       - Instruction Fetch (PC management, breakpoint)
//   rv32i_id       - Instruction Decode (decoder, register file, immediate)
//   rv32i_hazard   - Hazard Detection (RAW, forwarding, stall/flush)
//   rv32i_ex       - Execute (ALU, branch, forwarding muxes)
//   rv32i_mem      - Memory Access (load/store, MMIO, exceptions)
//   rv32i_wb       - Write Back (result mux, RF/CSR write)
//   rv32i_csr      - Control and Status Registers
//
//==============================================================================

module rv32i_top
    import rv32i_isa_pkg::*;
    import rv32i_pipeline_pkg::*;
(
    input  logic        clk,
    input  logic        rst,
    
    // Debug interface (compatible with Register_Block.sv)
    input  logic        cpu_run,        // Start/resume execution
    input  logic        cpu_halt,       // Halt execution
    input  logic        cpu_step,       // Single-step execution (W1P)
    output logic        cpu_halted,     // CPU halted status
    output logic        cpu_break,      // Breakpoint hit (EBREAK)
    
    // Debug memory interface (Port B - external access when CPU halted)
    input  logic [10:0] dbg_mem_addr,   // Word address for debug access
    input  logic [31:0] dbg_mem_wdata,  // Write data
    output logic [31:0] dbg_mem_rdata,  // Read data
    input  logic [3:0]  dbg_mem_we,     // Byte write enables (active when cpu_halted)
    input  logic        dbg_mem_re,     // Read enable
    
    // Hardware breakpoint interface (4 breakpoints)
    input  logic [3:0]  dbg_bp_enable,  // Breakpoint enable mask
    input  logic [31:0] dbg_bp_addr[0:3], // Breakpoint addresses
    output logic [3:0]  dbg_bp_hit,     // Breakpoint hit flags (latched)
    
    // Performance counter interface
    output logic [31:0] perf_cycle_count,   // Total cycles executed
    output logic [31:0] perf_insn_count,    // Total instructions committed
    output logic [31:0] perf_stall_count,   // Total pipeline stalls
    output logic [31:0] perf_flush_count,   // Total pipeline flushes
    
    // Register file snapshot interface (read when halted)
    input  logic [4:0]  dbg_rf_addr,    // Register address to read
    output logic [31:0] dbg_rf_rdata,   // Register data output
    
    // Trace buffer read interface (UART accessible) - Updated to 192-bit format
    input  logic [5:0]   dbg_trace_addr,   // Trace entry index to read
    output logic [191:0] dbg_trace_data,   // Trace entry: [191:160]=PC [159:128]=insn [127:96]=rd_value [95:64]=rs1 [63:32]=rs2 [31:0]=control_flags
    output logic [5:0]   dbg_trace_wptr,   // Current write pointer
    output logic [5:0]   dbg_trace_count,  // Number of valid entries
    
    // Software reset interface
    input  logic        dbg_soft_reset,   // Software reset request (W1P)
    output logic        dbg_reset_done,   // Reset completion flag
    
    // MMIO interface (LED register)
    output logic [3:0]  led_out,
    
    // Trace buffer interface (UVM direct access)
    output logic        trace_valid,
    output logic [31:0] trace_pc,
    output logic [31:0] trace_insn,
    output logic [4:0]  trace_rd_addr,
    output logic [31:0] trace_rd_data,
    
    // CSR debug interface
    input  logic [11:0] dbg_csr_addr,
    output logic [31:0] dbg_csr_rdata
);

    //==========================================================================
    // PIPELINE CONTROL SIGNALS
    //==========================================================================
    
    logic if_stall;
    logic id_stall;
    logic mem_stall;  // MEM stage structural stall for multi-cycle LOAD
    logic if_flush;
    logic id_flush;
    logic ex_flush;
    
    //==========================================================================
    // PIPELINE VALID SIGNALS
    //==========================================================================
    
    logic if_valid;
    logic id_valid;
    logic ex_valid;
    logic mem_valid;
    logic wb_valid;
    
    //==========================================================================
    // CPU CONTROL SIGNALS
    //==========================================================================
    
    logic running;
    logic bram_ready;  // BRAM data valid (1 cycle after running)
    logic step_mode;
    logic step_done;
    logic bp_skip_once;
    logic bp_just_resumed;
    logic soft_reset_active;
    logic reset_done_reg;
    logic ebreak_detected;
    logic ecall_detected;
    logic cpu_break_reg;
    logic [3:0] bp_hit_reg;
    logic debug_mode_enable;
    
    assign debug_mode_enable = 1'b1;  // Always enable debug mode for EBREAK
    
    //==========================================================================
    // PIPELINE REGISTERS
    //==========================================================================
    
    if_id_reg_t  if_id_reg;
    id_ex_reg_t  id_ex_reg;
    ex_mem_reg_t ex_mem_reg;
    mem_wb_reg_t mem_wb_reg;
    
    //==========================================================================
    // INTERNAL RAM (8KB BLOCK RAM)
    //==========================================================================
    // 2048 x 32-bit = 8KB unified architecture
    // Port A: Instruction fetch (IF stage) - Read only
    // Port B: Data memory (MEM stage) + Debug access - Read/Write
    //==========================================================================
    
    (* RAM_STYLE = "block" *) logic [31:0] ram [0:2047];
    
    logic [10:0] ram_addr_if;
    logic        ram_ena_a;
    logic [31:0] ram_rdata_if;
    
    logic [10:0] ram_addr_mem;
    logic        ram_ena_b;
    logic [31:0] ram_rdata_mem;
    logic [3:0]  ram_we_byte;
    logic [31:0] ram_wdata_mem;
    
    // Port A - Instruction fetch (read only)
    assign ram_ena_a = 1'b1;
    
    always_ff @(posedge clk) begin
        if (ram_ena_a) begin
            ram_rdata_if <= ram[ram_addr_if];
        end
    end
    
    // BRAM ready flag: Set 1 cycle after running to account for registered output latency
    always_ff @(posedge clk) begin
        if (rst || soft_reset_active) begin
            bram_ready <= 1'b0;
        end else begin
            bram_ready <= running;
        end
    end
    
    // Port B - Data memory + Debug access (read/write)
    assign ram_ena_b = 1'b1;
    logic [10:0] ram_addr_b;
    logic [3:0]  ram_we_b;
    logic [31:0] ram_wdata_b;
    
    // Multiplex between MEM stage and debug access
    assign ram_addr_b  = cpu_halted ? dbg_mem_addr : ram_addr_mem;
    assign ram_we_b    = cpu_halted ? dbg_mem_we   : ram_we_byte;
    assign ram_wdata_b = cpu_halted ? dbg_mem_wdata : ram_wdata_mem;
    
    // Memory Protection: Instruction region boundary (first 256 words = 1KB)
    localparam INSN_REGION_END = 11'h100;  // 0x100 words = 0x400 bytes = 1KB
    
    logic mem_protection_violation;
    assign mem_protection_violation = (|ram_we_b) && !cpu_halted && (ram_addr_b < INSN_REGION_END);
    
    // Write-forwarding registers to detect read-after-write hazard
    logic [10:0] ram_write_addr_prev;
    logic [31:0] ram_write_data_prev;
    logic [3:0]  ram_write_en_prev;
    logic        ram_write_valid_prev;
    
    // BRAM read-during-write: when writing AND reading same address in same cycle,
    // the read gets old data (before write). Forward write data to get correct behavior.
    always_ff @(posedge clk) begin
        if (rst || soft_reset_active) begin
            ram_write_addr_prev  <= 11'h0;
            ram_write_data_prev  <= 32'h0;
            ram_write_en_prev    <= 4'h0;
            ram_write_valid_prev <= 1'b0;
        end else if (ram_ena_b) begin
            // Register write information for next cycle forwarding
            ram_write_addr_prev  <= ram_addr_b;
            ram_write_data_prev  <= ram_wdata_b;
            ram_write_en_prev    <= mem_protection_violation ? 4'h0 : ram_we_b;
            ram_write_valid_prev <= |ram_we_b && !mem_protection_violation;
        end else begin
            ram_write_valid_prev <= 1'b0;
        end
    end
    
    // BRAM write and read logic with forwarding
    logic [31:0] ram_rdata_raw;
    logic        forward_write_data;
    
    always_ff @(posedge clk) begin
        if (ram_ena_b) begin
            // Memory Protection Check
            if (mem_protection_violation) begin
                $error("[MEM_PROTECT] CPU write to instruction region blocked: PC=0x%08h, target_addr=0x%03h (byte 0x%04h), we=%04b, data=0x%08h",
                       ex_mem_reg.pc, ram_addr_b, {ram_addr_b, 2'b00}, ram_we_b, ram_wdata_b);
            end else begin
                // Write with byte enables (only if not protected)
                if (ram_we_b[0]) ram[ram_addr_b][ 7: 0] <= ram_wdata_b[ 7: 0];
                if (ram_we_b[1]) ram[ram_addr_b][15: 8] <= ram_wdata_b[15: 8];
                if (ram_we_b[2]) ram[ram_addr_b][23:16] <= ram_wdata_b[23:16];
                if (ram_we_b[3]) ram[ram_addr_b][31:24] <= ram_wdata_b[31:24];
            end
            
            // Read: Normal BRAM read gets data BEFORE this cycle's write
            ram_rdata_raw <= ram[ram_addr_b];
            
            // Detect if current read address matches previous write address
            forward_write_data <= ram_write_valid_prev && (ram_addr_b == ram_write_addr_prev);
        end
    end
    
    // Forward logic: merge previous write data with raw RAM data based on byte enables
    // TEMPORARILY DISABLED for debugging
    always_comb begin
        ram_rdata_mem = ram_rdata_raw;
        // Forwarding disabled - let writes settle to RAM naturally
        /*
        if (forward_write_data) begin
            if (ram_write_en_prev[0]) ram_rdata_mem[ 7: 0] = ram_write_data_prev[ 7: 0];
            if (ram_write_en_prev[1]) ram_rdata_mem[15: 8] = ram_write_data_prev[15: 8];
            if (ram_write_en_prev[2]) ram_rdata_mem[23:16] = ram_write_data_prev[23:16];
            if (ram_write_en_prev[3]) ram_rdata_mem[31:24] = ram_write_data_prev[31:24];
        end
        */
    end
    
    assign dbg_mem_rdata = ram_rdata_mem;
    
    //==========================================================================
    // IF STAGE WIRING
    //==========================================================================
    
    logic [31:0] if_pc_current;
    logic [31:0] if_pc_next;
    logic [31:0] if_pc_out;
    logic [31:0] if_pc_delayed;    // PC delayed by 1 cycle to match BRAM latency
    logic [31:0] if_insn_out;
    logic        if_valid_out;
    logic [3:0]  if_bp_hit;
    logic        if_bp_match;      // Raw breakpoint match signal
    logic        if_cpu_break;     // Processed cpu_break signal (match && !skip)
    
    // Exception/MRET signals from MEM stage
    logic        exception_trap;
    logic [31:0] trap_vector;
    logic        mret_req;
    logic [31:0] mret_pc;
    
    // Branch signals from EX stage (pipelined to MEM)
    logic        branch_taken;
    logic [31:0] branch_target;
    
    // Debug signals for branch control investigation
    (* mark_debug = "true" *) logic dbg_ex_is_branch;
    (* mark_debug = "true" *) logic dbg_ex_is_jump;
    (* mark_debug = "true" *) logic dbg_ex_branch_taken;
    (* mark_debug = "true" *) logic [31:0] dbg_ex_branch_target;
    (* mark_debug = "true" *) logic dbg_exmem_branch_taken;
    
    //==========================================================================
    // DEBUG SIGNALS FOR LB x19 INVESTIGATION
    //==========================================================================
    (* mark_debug = "true" *) logic [31:0] dbg_ram_rdata_if;
    (* mark_debug = "true" *) logic [31:0] dbg_if_insn_out;
    (* mark_debug = "true" *) logic [31:0] dbg_if_id_pc;
    (* mark_debug = "true" *) logic [31:0] dbg_if_id_insn;
    (* mark_debug = "true" *) logic        dbg_if_id_valid;
    
    (* mark_debug = "true" *) logic [31:0] dbg_id_ex_pc;
    (* mark_debug = "true" *) logic [31:0] dbg_id_ex_insn;
    (* mark_debug = "true" *) logic [4:0]  dbg_id_ex_rd_addr;
    (* mark_debug = "true" *) logic        dbg_id_ex_rf_wen;
    (* mark_debug = "true" *) logic        dbg_id_ex_mem_read;
    (* mark_debug = "true" *) logic        dbg_id_ex_valid;
    
    (* mark_debug = "true" *) logic [31:0] dbg_ex_mem_pc;
    (* mark_debug = "true" *) logic [4:0]  dbg_ex_mem_rd_addr;
    (* mark_debug = "true" *) logic        dbg_ex_mem_rf_wen;
    (* mark_debug = "true" *) logic        dbg_ex_mem_mem_read;
    (* mark_debug = "true" *) logic        dbg_ex_mem_valid;
    
    (* mark_debug = "true" *) logic [31:0] dbg_mem_wb_pc;
    (* mark_debug = "true" *) logic [4:0]  dbg_mem_wb_rd_addr;
    (* mark_debug = "true" *) logic        dbg_mem_wb_rf_wen;
    (* mark_debug = "true" *) logic [31:0] dbg_mem_wb_mem_data;
    (* mark_debug = "true" *) logic        dbg_mem_wb_valid;
    
    (* mark_debug = "true" *) logic [4:0]  dbg_rf_waddr_actual;
    (* mark_debug = "true" *) logic [31:0] dbg_rf_wdata_actual;
    (* mark_debug = "true" *) logic        dbg_rf_wen_actual;
    
    (* mark_debug = "true" *) logic [1:0]  dbg_mem_state_enum;
    
    rv32i_if u_if (
        .pc_current      (if_pc_current),
        .if_valid        (if_valid),
        .if_stall        (if_stall),
        .if_flush        (if_flush),
        .branch_taken    (ex_mem_reg.branch_taken),
        .branch_target   (ex_mem_reg.branch_target),
        .exception_trap  (exception_trap),
        .trap_vector     (trap_vector),
        .mret_req        (mret_req),
        .mret_pc         (mret_pc),
        .insn_ram_addr   (ram_addr_if),
        .insn_ram_rdata  (ram_rdata_if),
        .dbg_bp_enable   (dbg_bp_enable),
        .dbg_bp_addr     (dbg_bp_addr),
        .dbg_bp_hit      (if_bp_hit),
        .cpu_break       (if_cpu_break),      // FIXED: Use separate signal for cpu_break output
        .running         (running),
        .cpu_run         (cpu_run),
        .cpu_halted      (cpu_halted),
        .bp_skip_once    (bp_skip_once),
        .bp_match        (if_bp_match),       // Keep bp_match as raw match signal
        .pc_next         (if_pc_next),
        .pc_out          (if_pc_out),
        .insn_out        (if_insn_out),
        .valid_out       (if_valid_out)
    );
    
    // PC register
    always_ff @(posedge clk) begin
        if (rst || soft_reset_active) begin
            if_pc_current <= 32'h00000000;
        end else if (cpu_run && cpu_halted && if_pc_current == 32'h00000000) begin
            if_pc_current <= 32'h00000000;  // Reset PC to 0 on initial start
        end else if (running && !cpu_halt && (!if_bp_match || bp_skip_once) && !mem_stall && !id_stall) begin
            if_pc_current <= if_pc_next;
        end
    end
    
    // CRITICAL FIX: Delay PC by 1 cycle to match BRAM output latency
    // BRAM has 1-cycle registered output, so instruction data arrives 1 cycle
    // after address is presented. This delay ensures PC and instruction encoding
    // are correctly synchronized in the IF/ID pipeline register.
    //
    // BRANCH FLUSH PROTECTION: During branch/jump flush, capture the correct
    // target PC (if_pc_next) instead of the speculative PC (if_pc_out).
    // This prevents "zombie" instructions from entering the pipeline after flush.
    always_ff @(posedge clk) begin
        if (rst || soft_reset_active) begin
            if_pc_delayed <= 32'h00000000;
        end else if (if_flush) begin
            // Capture correct branch/jump target during flush to prevent
            // speculative PC from propagating through the pipeline.
            // NOTE: Remove bram_ready condition here to ensure flush always updates!
            if_pc_delayed <= if_pc_next;
        end else if (!mem_stall && !id_stall && bram_ready) begin
            if_pc_delayed <= if_pc_out;
        end
    end
    
    assign if_valid = running;
    
    //==========================================================================
    // IF/ID PIPELINE REGISTER
    //==========================================================================
    // Critical Fix #3: Explicit priority order for pipeline control
    // Priority: reset → mem_stall → id_stall → bram_ready
    // Rationale: MEM stall is highest priority structural hazard, must freeze entire pipeline
    always_ff @(posedge clk) begin
        if (rst || soft_reset_active) begin
            // Priority 1: Reset
            if_id_reg <= if_id_bubble();
        end else if (mem_stall) begin
            // Priority 2: MEM stall - highest priority, freeze IF/ID register
            if_id_reg <= if_id_reg;
        end else if (id_stall) begin
            // Priority 3: ID stall (load-use hazard)
            if_id_reg <= if_id_reg;
        end else if (bram_ready) begin
            // Priority 4: Normal pipeline advance
            if_id_reg.pc    <= if_pc_delayed;
            if_id_reg.insn  <= if_insn_out;
            if_id_reg.valid <= if_valid_out;
        end
        
        // Synchronous invalidation: Clear valid AFTER capture if flush active
        if (id_flush && !rst && !soft_reset_active) begin
            if_id_reg.valid <= 1'b0;  // Invalidate but keep pc/insn stable
        end
    end
    
    //==========================================================================
    // ID STAGE WIRING
    //==========================================================================
    
    logic [31:0] id_pc_out;
    logic [31:0] id_insn_out;
    logic [31:0] id_rs1_data;
    logic [31:0] id_rs2_data;
    logic [31:0] id_imm;
    logic [31:0] id_csr_rdata;
    logic [1:0]  id_forward_rs1;
    logic [1:0]  id_forward_rs2;
    decode_ctrl_t id_ctrl;
    logic        id_valid_out;
    logic [11:0] csr_raddr;
    logic [31:0] csr_rdata;
    
    // Forwarding control from hazard unit
    logic [1:0]  forward_rs1_sel;
    logic [1:0]  forward_rs2_sel;
    
    // Register file write from WB stage
    logic        rf_wen;
    logic [4:0]  rf_waddr;
    logic [31:0] rf_wdata;
    
    rv32i_id u_id (
        .clk             (clk),
        .rst             (rst || soft_reset_active),
        .pc_in           (if_id_reg.pc),
        .insn_in         (if_id_reg.insn),
        .valid_in        (if_id_reg.valid),
        .rf_wen          (rf_wen),
        .rf_waddr        (rf_waddr),
        .rf_wdata        (rf_wdata),
        .csr_rdata       (csr_rdata),
        .forward_rs1     (forward_rs1_sel),
        .forward_rs2     (forward_rs2_sel),
        .pc_out          (id_pc_out),
        .insn_out        (id_insn_out),
        .rs1_data_out    (id_rs1_data),
        .rs2_data_out    (id_rs2_data),
        .imm_out         (id_imm),
        .csr_rdata_out   (id_csr_rdata),
        .forward_rs1_out (id_forward_rs1),
        .forward_rs2_out (id_forward_rs2),
        .ctrl_out        (id_ctrl),
        .valid_out       (id_valid_out),
        .csr_raddr       (csr_raddr)
    );
    
    assign id_valid = id_valid_out;
    
    // Debug register file read
    assign dbg_rf_rdata = (dbg_rf_addr == 5'b0) ? 32'h0 : u_id.regfile[dbg_rf_addr];
    
    //==========================================================================
    // HAZARD DETECTION UNIT
    //==========================================================================
    
    logic load_use_stall;
    logic [4:0] wb_rd_addr_delayed;   // WB delayed metadata from hazard unit
    logic       wb_rf_wen_delayed;    // WB delayed write enable from hazard unit
    
    rv32i_hazard u_hazard (
        .clk             (clk),
        .rst             (rst || soft_reset_active),
        .id_rs1_addr     (id_ctrl.rs1_addr),
        .id_rs2_addr     (id_ctrl.rs2_addr),
        .id_valid        (id_valid),
        .id_ctrl         (id_ctrl),
        .ex_rd_addr      (id_ex_reg.ctrl.rd_addr),
        .ex_rf_wen       (id_ex_reg.ctrl.rf_wen),
        .ex_is_load      (id_ex_reg.ctrl.mem_read),
        .ex_valid        (id_ex_reg.valid),
        .mem_rd_addr     (ex_mem_reg.ctrl.rd_addr),
        .mem_rf_wen      (ex_mem_reg.ctrl.rf_wen),
        .mem_valid       (ex_mem_reg.valid),
        .mem_is_load     (ex_mem_reg.ctrl.mem_read),
        .wb_rd_addr      (mem_wb_reg.ctrl.rd_addr),
        .wb_rf_wen       (mem_wb_reg.ctrl.rf_wen),
        .wb_valid        (mem_wb_reg.valid),
        .branch_taken    (ex_mem_reg.branch_taken),
        .exception_trap  (exception_trap),
        .mret_req        (mret_req),
        .forward_rs1_sel (forward_rs1_sel),
        .forward_rs2_sel (forward_rs2_sel),
        .wb_rd_addr_delayed_out (wb_rd_addr_delayed),  // Debug output
        .wb_rf_wen_delayed_out  (wb_rf_wen_delayed),   // Debug output
        .if_stall        (if_stall),
        .id_stall        (id_stall),
        .if_flush        (if_flush),
        .id_flush        (id_flush),
        .ex_flush        (ex_flush)
    );
    
    //==========================================================================
    // ID/EX PIPELINE REGISTER
    //==========================================================================
    
    always_ff @(posedge clk) begin
        if (rst || soft_reset_active) begin
            id_ex_reg <= id_ex_bubble();
        end else if (id_flush) begin
            id_ex_reg <= id_ex_bubble();
        end else if (mem_stall) begin
            // MEM stall: Hold ID/EX register (freeze pipeline upstream of MEM)
            id_ex_reg <= id_ex_reg;
        end else if (!id_stall) begin
            id_ex_reg.pc          <= id_pc_out;
            id_ex_reg.insn        <= id_insn_out;
            id_ex_reg.rs1_data    <= id_rs1_data;
            id_ex_reg.rs2_data    <= id_rs2_data;
            id_ex_reg.imm         <= id_imm;
            id_ex_reg.csr_rdata   <= id_csr_rdata;
            id_ex_reg.forward_rs1 <= id_forward_rs1;
            id_ex_reg.forward_rs2 <= id_forward_rs2;
            id_ex_reg.ctrl        <= id_ctrl;
            id_ex_reg.valid       <= id_valid;
        end
    end
    
    //==========================================================================
    // EX STAGE WIRING
    //==========================================================================
    
    logic [31:0] ex_alu_result;
    logic [31:0] ex_rs2_forwarded;
    logic        ex_branch_taken;
    logic [31:0] ex_branch_target;
    logic        ex_valid_out;
    logic [31:0] ex_rs1_forwarded;  // For trace debug
    logic [31:0] ex_rs2_forwarded_trace;  // For trace debug
    
    // Forwarding sources
    logic [31:0] wb_result;       // Combinational from WB stage
    logic [31:0] mem_forward_data_mux; // MEM forward: select between ALU result or mem data
    logic [31:0] mem_mem_data_out;    // MEM stage load data output (for forwarding)
    logic [31:0] wb_result_delayed;   // CRITICAL FIX: Registered WB result aligned with hazard metadata
    logic [31:0] wb_pc_plus4_reg; // Pre-calculated PC+4 for timing (breaks CARRY4 chain)
    logic [4:0]  wb_rf_waddr;
    
    // Debug: WB forwarding path visibility (waveform inspection)
    (* mark_debug = "true" *) logic [31:0] dbg_wb_result_current;
    (* mark_debug = "true" *) logic [31:0] dbg_wb_result_delayed;
    (* mark_debug = "true" *) logic [4:0]  dbg_wb_rd_delayed;
    (* mark_debug = "true" *) logic [4:0]  dbg_wb_rd_current;
    (* mark_debug = "true" *) logic        dbg_wb_skew_detected;
    (* mark_debug = "true" *) logic [1:0]  dbg_id_ex_fwd_rs1;
    (* mark_debug = "true" *) logic [1:0]  dbg_id_ex_fwd_rs2;
    
    assign dbg_wb_result_current = wb_result;
    assign dbg_wb_result_delayed = wb_result_delayed;
    assign dbg_wb_rd_delayed = wb_rd_addr_delayed;
    assign dbg_wb_rd_current = mem_wb_reg.ctrl.rd_addr;
    assign dbg_id_ex_fwd_rs1 = id_ex_reg.forward_rs1;
    assign dbg_id_ex_fwd_rs2 = id_ex_reg.forward_rs2;
    
    // WB skew detector: Detect when WB forward selector points to wrong data
    // This catches the bug where selector uses delayed metadata but data is current cycle
    assign dbg_wb_skew_detected = ((id_ex_reg.forward_rs1 == 2'b11) || (id_ex_reg.forward_rs2 == 2'b11)) &&
                                  (wb_rd_addr_delayed != mem_wb_reg.ctrl.rd_addr) &&
                                  wb_rf_wen_delayed && id_ex_reg.valid;
    
    // MEM forward data mux: choose between ALU result and memory data for load instructions
    // Use ex_mem_reg.ctrl for forwarding decision (current MEM cycle), not mem_ctrl_out (delayed for WB)
    // mem_ctrl_out is delayed to match BRAM and used only for MEM/WB register
    assign mem_forward_data_mux = ex_mem_reg.ctrl.mem_read ? mem_mem_data_out : ex_mem_reg.alu_result;
    
    // CRITICAL FIX: Register wb_result to align with delayed WB metadata used in hazard detection
    // Bug: Hazard unit uses wb_rd_addr_delayed (1 cycle old) but forwarding mux used wb_result (current)
    // Fix: Forward wb_result_delayed so selector metadata and data are synchronized
    // This prevents forwarding stale/wrong values when WB register changes between cycles
    always_ff @(posedge clk) begin
        if (rst || soft_reset_active) begin
            wb_result_delayed <= 32'h0;
            wb_pc_plus4_reg   <= 32'h0;
        end else begin
            wb_result_delayed <= wb_result;  // Align with wb_rd_addr_delayed timing
            wb_pc_plus4_reg   <= mem_wb_reg.pc + 32'd4;  // Pre-calculate for WB stage
        end
    end
    
    rv32i_ex u_ex (
        .pc              (id_ex_reg.pc),
        .insn            (id_ex_reg.insn),
        .rs1_data        (id_ex_reg.rs1_data),
        .rs2_data        (id_ex_reg.rs2_data),
        .imm             (id_ex_reg.imm),
        .forward_rs1     (id_ex_reg.forward_rs1),
        .forward_rs2     (id_ex_reg.forward_rs2),
        .ctrl            (id_ex_reg.ctrl),
        .valid           (id_ex_reg.valid),
        .ex_forward_data (ex_mem_reg.alu_result),      // EX forward: from EX/MEM ALU result
        .mem_forward_data(mem_forward_data_mux),       // MEM forward: from MEM/WB (ALU or load data)
        .wb_forward_data (wb_result_delayed),          // CRITICAL FIX: WB forward with delayed result (aligned with metadata)
        .ex_flush        (ex_flush),
        .alu_result      (ex_alu_result),
        .rs2_forwarded_out(ex_rs2_forwarded),
        .branch_taken    (ex_branch_taken),
        .branch_target   (ex_branch_target),
        .valid_out       (ex_valid_out),
        .rs1_forwarded_out(ex_rs1_forwarded),
        .rs2_forwarded_out_trace(ex_rs2_forwarded_trace)
    );
    
    assign ex_valid = ex_valid_out;
    
    // Debug signal assignments for branch control investigation
    assign dbg_ex_is_branch = id_ex_reg.ctrl.is_branch;
    assign dbg_ex_is_jump = id_ex_reg.ctrl.is_jump;
    assign dbg_ex_branch_taken = ex_branch_taken;
    assign dbg_ex_branch_target = ex_branch_target;
    assign dbg_exmem_branch_taken = ex_mem_reg.branch_taken;
    
    //==========================================================================
    // EX/MEM PIPELINE REGISTER
    //==========================================================================
    
    always_ff @(posedge clk) begin
        if (rst || soft_reset_active) begin
            ex_mem_reg <= ex_mem_bubble();
        end else if (ex_flush) begin
            ex_mem_reg <= ex_mem_bubble();
        end else if (mem_stall) begin
            // MEM stall: Hold EX/MEM register to preserve LOAD instruction in MEM stage
            ex_mem_reg <= ex_mem_reg;
        end else begin
            ex_mem_reg.pc            <= id_ex_reg.pc;
            ex_mem_reg.insn          <= id_ex_reg.insn;
            ex_mem_reg.alu_result    <= ex_alu_result;
            ex_mem_reg.byte_offset   <= ex_alu_result[1:0];  // Capture address LSBs for load alignment
            ex_mem_reg.rs2_data      <= ex_rs2_forwarded;
            ex_mem_reg.csr_rdata     <= id_ex_reg.csr_rdata;
            ex_mem_reg.branch_taken  <= ex_branch_taken;
            ex_mem_reg.branch_target <= ex_branch_target;
            ex_mem_reg.ctrl          <= id_ex_reg.ctrl;
            ex_mem_reg.valid         <= ex_valid;
            // Debug trace fields - capture EX stage operands
            ex_mem_reg.rs1_value_debug   <= ex_rs1_forwarded;
            ex_mem_reg.rs2_value_debug   <= ex_rs2_forwarded_trace;
            ex_mem_reg.rs1_addr_debug    <= id_ex_reg.ctrl.rs1_addr;
            ex_mem_reg.rs2_addr_debug    <= id_ex_reg.ctrl.rs2_addr;
            ex_mem_reg.forward_rs1_debug <= id_ex_reg.forward_rs1;
            ex_mem_reg.forward_rs2_debug <= id_ex_reg.forward_rs2;
        end
    end
    
    //==========================================================================
    // MEM STAGE WIRING
    //==========================================================================
    // Note: mem_mem_data_out declared earlier with forwarding signals
    
    decode_ctrl_t mem_ctrl_out;
    logic        mem_valid_out;
    logic [3:0]  mem_led_out;
    logic [31:0] mem_exception_pc;
    logic [3:0]  mem_exception_code;
    logic [31:0] mem_exception_tval;
    
    //==========================================================================
    // MEM STAGE STATE MACHINE (2-CYCLE LOAD CONTROL)
    //==========================================================================
    // Purpose: Hold LOAD instructions in MEM stage for 2 cycles to account for
    //          BRAM registered output latency (address at N → data at N+1)
    // Design:  MEM_IDLE      - Normal single-cycle operation (ALU, STORE, etc.)
    //          MEM_LOAD_WAIT - LOAD instruction waiting for BRAM data (cycle 2)
    // Critical Fix #1: Explicit bram_data_ready condition prevents fragile assumptions
    //==========================================================================
    
    typedef enum logic {
        MEM_IDLE      = 1'b0,
        MEM_LOAD_WAIT = 1'b1
    } mem_state_t;
    
    mem_state_t mem_state, mem_state_next;
    logic       bram_data_ready;  // BRAM data valid for current LOAD
    
    // BRAM data ready: For synchronous BRAM with 1-cycle registered output,
    // data is ready 1 cycle after address presentation (fixed latency).
    // Critical Fix #1: Making this explicit enables future AXI/cache integration.
    always_comb begin
        // Current implementation: Fixed 1-cycle BRAM latency
        // Future-proof: Can be replaced with handshake signal for variable latency
        bram_data_ready = (mem_state == MEM_LOAD_WAIT);
    end
    
    // State transition logic
    always_comb begin
        mem_state_next = mem_state;
        
        case (mem_state)
            MEM_IDLE: begin
                // Enter LOAD_WAIT state when LOAD instruction is about to enter MEM stage
                // Must check ID/EX register (not EX/MEM) to detect entering LOAD before stall freezes pipeline
                if (id_ex_reg.valid && id_ex_reg.ctrl.mem_read && !id_flush && !ex_flush) begin
                    mem_state_next = MEM_LOAD_WAIT;
                end
            end
            
            MEM_LOAD_WAIT: begin
                // Critical Fix #1: Explicit data ready condition instead of
                // unconditional transition. Prevents assumptions about timing.
                if (bram_data_ready) begin
                    mem_state_next = MEM_IDLE;
                end
            end
        endcase
    end
    
    // State register
    always_ff @(posedge clk) begin
        if (rst || soft_reset_active) begin
            mem_state <= MEM_IDLE;
        end else begin
            mem_state <= mem_state_next;
        end
    end
    
    // MEM stall signal: Asserted when MEM stage is occupied by multi-cycle LOAD
    // This is a structural hazard (resource conflict), separate from data hazards
    assign mem_stall = (mem_state == MEM_LOAD_WAIT);
    
    rv32i_mem u_mem (
        .clk             (clk),
        .rst             (rst || soft_reset_active),
        .pc              (ex_mem_reg.pc),
        .insn            (ex_mem_reg.insn),
        .alu_result      (ex_mem_reg.alu_result),
        .byte_offset     (ex_mem_reg.byte_offset),  // Address LSBs synchronized with BRAM latency
        .rs2_data        (ex_mem_reg.rs2_data),
        .csr_rdata       (ex_mem_reg.csr_rdata),
        .ctrl            (ex_mem_reg.ctrl),
        .valid           (ex_mem_reg.valid),
        .debug_mode_enable (debug_mode_enable),
        .mem_stall       (mem_stall),  // Hold ctrl_final during LOAD wait
        .data_ram_rdata  (ram_rdata_mem),
        .data_ram_addr   (ram_addr_mem),
        .data_ram_wdata  (ram_wdata_mem),
        .data_ram_we     (ram_we_byte),
        .led_out         (mem_led_out),
        .exception_trap  (exception_trap),
        .exception_pc    (mem_exception_pc),
        .exception_code  (mem_exception_code),
        .exception_tval  (mem_exception_tval),
        .mem_data_out    (mem_mem_data_out),
        .valid_out       (mem_valid_out),
        .ctrl_out        (mem_ctrl_out)
    );
    
    assign mem_valid = mem_valid_out;
    assign led_out = mem_led_out;
    
    // MRET detection
    assign mret_req = ex_mem_reg.valid && ex_mem_reg.ctrl.is_mret;
    
    // EBREAK/ECALL detection
    assign ebreak_detected = ex_mem_reg.valid && ex_mem_reg.ctrl.is_ebreak;
    assign ecall_detected  = ex_mem_reg.valid && ex_mem_reg.ctrl.is_ecall;
    
    //==========================================================================
    // MEM/WB PIPELINE REGISTER
    //==========================================================================
    // Critical Fix #2: MEM/WB holds during mem_stall, does NOT bubble
    // Semantic meaning: When LOAD is not complete, MEM/WB preserves the previous
    //                   instruction, and WB stage continues executing it.
    //                   This prevents creating pipeline bubbles and maintains
    //                   architectural correctness (no lost instructions).
    
    always_ff @(posedge clk) begin
        if (rst || soft_reset_active) begin
            mem_wb_reg <= mem_wb_bubble();
        end else if (mem_stall) begin
            // LOAD instruction not yet complete in MEM stage.
            // Hold MEM/WB register: WB stage continues with previous instruction.
            // This is NOT a bubble - the previous instruction remains active in WB.
            mem_wb_reg <= mem_wb_reg;
        end else begin
            mem_wb_reg.pc          <= ex_mem_reg.pc;
            mem_wb_reg.insn        <= ex_mem_reg.insn;
            mem_wb_reg.mem_data    <= mem_mem_data_out;
            mem_wb_reg.alu_result  <= ex_mem_reg.alu_result;
            mem_wb_reg.csr_rdata   <= ex_mem_reg.csr_rdata;
            mem_wb_reg.ctrl        <= mem_ctrl_out;
            mem_wb_reg.valid       <= mem_valid;
            mem_wb_reg.branch_taken <= ex_mem_reg.branch_taken;
            // Debug trace fields - propagate from EX/MEM to align with WB stage
            mem_wb_reg.rs1_value_debug   <= ex_mem_reg.rs1_value_debug;
            mem_wb_reg.rs2_value_debug   <= ex_mem_reg.rs2_value_debug;
            mem_wb_reg.rs1_addr_debug    <= ex_mem_reg.rs1_addr_debug;
            mem_wb_reg.rs2_addr_debug    <= ex_mem_reg.rs2_addr_debug;
            mem_wb_reg.forward_rs1_debug <= ex_mem_reg.forward_rs1_debug;
            mem_wb_reg.forward_rs2_debug <= ex_mem_reg.forward_rs2_debug;
        end
    end
    
    //==========================================================================
    // WB STAGE WIRING
    //==========================================================================
    
    logic [31:0] wb_rf_wdata;
    logic        wb_rf_wen;
    logic [11:0] wb_csr_waddr;
    logic [31:0] wb_csr_wdata;
    logic        wb_csr_wen;
    
    rv32i_wb u_wb (
        .pc              (mem_wb_reg.pc),
        .insn            (mem_wb_reg.insn),
        .mem_data        (mem_wb_reg.mem_data),
        .alu_result      (mem_wb_reg.alu_result),
        .csr_rdata       (mem_wb_reg.csr_rdata),
        .ctrl            (mem_wb_reg.ctrl),
        .valid           (mem_wb_reg.valid),
        .pc_plus4_precalc(wb_pc_plus4_reg),  // Pre-calculated PC+4 for timing
        .wb_result       (wb_result),
        .rf_wen          (wb_rf_wen),
        .rf_waddr        (wb_rf_waddr),
        .rf_wdata        (wb_rf_wdata),
        .csr_wen         (wb_csr_wen),
        .csr_waddr       (wb_csr_waddr),
        .csr_wdata       (wb_csr_wdata)
    );
    
    assign wb_valid = mem_wb_reg.valid;
    assign rf_wen   = wb_rf_wen;
    assign rf_waddr = wb_rf_waddr;
    assign rf_wdata = wb_rf_wdata;
    
    //==========================================================================
    // CSR MODULE
    //==========================================================================
    
    rv32i_csr u_csr (
        .clk             (clk),
        .rst             (rst || soft_reset_active),
        .csr_raddr       (csr_raddr),
        .csr_rdata       (csr_rdata),
        .csr_waddr       (wb_csr_waddr),
        .csr_wdata       (wb_csr_wdata),
        .csr_wen         (wb_csr_wen),
        .exception_trap  (exception_trap),
        .exception_pc    (mem_exception_pc),
        .exception_code  ({1'b0, mem_exception_code}),  // Extend 4-bit to 5-bit
        .exception_tval  (mem_exception_tval),
        .trap_vector     (trap_vector),
        .mret_req        (mret_req),
        .mret_pc         (mret_pc),
        .dbg_csr_addr    (dbg_csr_addr),
        .dbg_csr_rdata   (dbg_csr_rdata)
    );
    
    //==========================================================================
    // CPU CONTROL STATE MACHINE
    //==========================================================================
    
    always_ff @(posedge clk) begin
        if (rst || soft_reset_active) begin
            running         <= 1'b0;
            cpu_halted      <= 1'b1;
            cpu_break_reg   <= 1'b0;
            step_mode       <= 1'b0;
            step_done       <= 1'b0;
            bp_hit_reg      <= 4'h0;
            bp_skip_once    <= 1'b0;
            bp_just_resumed <= 1'b0;
        end else begin
            // Clear skip flag one cycle after resuming
            // CRITICAL: Only clear bp_skip_once when bp_just_resumed is NOT set this cycle
            // This ensures the skip flag persists for one full instruction fetch
            if (bp_just_resumed && !if_bp_match) begin
                bp_skip_once    <= 1'b0;
                bp_just_resumed <= 1'b0;
            end
            
            // Hardware breakpoint detection
            // Use if_cpu_break which already combines bp_match && !bp_skip_once
            if (if_cpu_break && running && !step_mode) begin
                running       <= 1'b0;
                cpu_halted    <= 1'b1;
                cpu_break_reg <= 1'b1;
                bp_hit_reg    <= if_bp_hit;
            end
            // Single-step mode
            else if (cpu_step && cpu_halted) begin
                step_mode  <= 1'b1;
                step_done  <= 1'b0;
                running    <= 1'b1;
                cpu_halted <= 1'b0;
                bp_skip_once <= 1'b0;
            end else if (step_mode && wb_valid) begin
                step_mode  <= 1'b0;
                step_done  <= 1'b1;
                running    <= 1'b0;
                cpu_halted <= 1'b1;
            end
            // Normal run/halt control
            else if (cpu_run) begin
                running         <= 1'b1;
                cpu_halted      <= 1'b0;
                cpu_break_reg   <= 1'b0;
                step_done       <= 1'b0;
                bp_skip_once    <= (bp_hit_reg != 4'h0) ? 1'b1 : 1'b0;
                bp_just_resumed <= (bp_hit_reg != 4'h0) ? 1'b1 : 1'b0;
                bp_hit_reg      <= 4'h0;
            end else if (cpu_halt || (ebreak_detected && debug_mode_enable)) begin
                running    <= 1'b0;
                cpu_halted <= 1'b1;
                bp_skip_once <= 1'b0;
                if (ebreak_detected) begin
                    cpu_break_reg <= 1'b1;
                end
            end
        end
    end
    
    assign cpu_break  = cpu_break_reg;
    assign dbg_bp_hit = bp_hit_reg;
    
    //==========================================================================
    // PERFORMANCE COUNTERS
    //==========================================================================
    
    logic [31:0] cycle_counter;
    logic [31:0] insn_counter;
    logic [31:0] stall_counter;
    logic [31:0] flush_counter;
    
    always_ff @(posedge clk) begin
        if (rst || soft_reset_active) begin
            cycle_counter <= 32'h0;
            insn_counter  <= 32'h0;
            stall_counter <= 32'h0;
            flush_counter <= 32'h0;
        end else if (running) begin
            cycle_counter <= cycle_counter + 32'd1;
            if (wb_valid) insn_counter <= insn_counter + 32'd1;
            if (mem_stall || if_stall || id_stall) stall_counter <= stall_counter + 32'd1;
            if (if_flush || id_flush || ex_flush) flush_counter <= flush_counter + 32'd1;
        end
    end
    
    assign perf_cycle_count = cycle_counter;
    assign perf_insn_count  = insn_counter;
    assign perf_stall_count = stall_counter;
    assign perf_flush_count = flush_counter;
    
    //==========================================================================
    // SOFTWARE RESET CONTROL
    //==========================================================================
    
    always_ff @(posedge clk) begin
        if (rst) begin
            soft_reset_active <= 1'b0;
            reset_done_reg    <= 1'b0;
        end else begin
            if (dbg_soft_reset && !soft_reset_active) begin
                soft_reset_active <= 1'b1;
                reset_done_reg    <= 1'b0;
            end else if (soft_reset_active) begin
                soft_reset_active <= 1'b0;
                reset_done_reg    <= 1'b1;
            end else if (!dbg_soft_reset) begin
                reset_done_reg <= 1'b0;
            end
        end
    end
    
    assign dbg_reset_done = reset_done_reg;
    
    //==========================================================================
    // TRACE BUFFER INSTANTIATION
    //==========================================================================
    
    assign trace_valid   = wb_valid;
    assign trace_pc      = mem_wb_reg.pc;
    assign trace_insn    = mem_wb_reg.insn;
    assign trace_rd_addr = mem_wb_reg.ctrl.rd_addr;
    assign trace_rd_data = wb_result;
    
    // Extended trace signals for enhanced debugging
    logic [31:0] trace_rs1_value;
    logic [31:0] trace_rs2_value;
    logic [4:0]  trace_rs1_addr;
    logic [4:0]  trace_rs2_addr;
    logic [1:0]  trace_forward_rs1;
    logic [1:0]  trace_forward_rs2;
    logic        trace_stall;
    logic        trace_flush;
    logic        trace_branch_taken;
    
    // Route signals from EX stage to trace buffer (delayed to WB stage timing)
    // Capture the actual values that were used during EX stage execution
    //
    // IMPORTANT: Trace Debug Field Pipeline Delay
    // --------------------------------------------
    // The rs1_addr/rs2_addr fields in trace output may show the
    // PREVIOUS instruction's operands due to pipeline register propagation.
    // This is a TRACE DISPLAY artifact, NOT an RTL functional bug.
    //
    // The hazard unit (rv32i_hazard.sv) correctly checks `id_rs1_addr != 5'b0`
    // and generates proper forwarding signals. The actual instruction execution
    // is correct; only the debug metadata fields lag behind by one stage.
    //
    // Example: When ADDI x1, x0, 10 executes in WB, the trace may show
    // rs1_addr=x31 (from the previous CSRRW instruction) instead of x0.
    //
    // To verify correct operation, check:
    // 1. Destination register writeback values (rd_value)
    // 2. Forwarding control signals (forward_rs1/rs2)
    // 3. Final register file state after execution
    always_ff @(posedge clk) begin
        if (rst || soft_reset_active) begin
            trace_rs1_value     <= 32'h0;
            trace_rs2_value     <= 32'h0;
            trace_rs1_addr      <= 5'h0;
            trace_rs2_addr      <= 5'h0;
            trace_forward_rs1   <= 2'b00;
            trace_forward_rs2   <= 2'b00;
            trace_stall         <= 1'b0;
            trace_flush         <= 1'b0;
            trace_branch_taken  <= 1'b0;
        end else begin
            // Pipeline: EX → MEM → WB (2-stage delay)
            // Trace signals need to align with WB stage instruction
            // Store EX stage values in EX/MEM, then MEM/WB, finally to trace
            trace_rs1_value     <= mem_wb_reg.rs1_value_debug;
            trace_rs2_value     <= mem_wb_reg.rs2_value_debug;
            trace_rs1_addr      <= mem_wb_reg.rs1_addr_debug;
            trace_rs2_addr      <= mem_wb_reg.rs2_addr_debug;
            trace_forward_rs1   <= mem_wb_reg.forward_rs1_debug;
            trace_forward_rs2   <= mem_wb_reg.forward_rs2_debug;
            trace_stall         <= id_stall;  // Current stall state
            trace_flush         <= id_flush || ex_flush;  // Any flush active
            trace_branch_taken  <= mem_wb_reg.branch_taken;
        end
    end
    
    Rv32i_Trace_Buffer #(
        .DEPTH(64)
    ) u_trace_buffer (
        .clk             (clk),
        .rst             (rst || soft_reset_active),
        .insn_valid      (trace_valid),
        .insn            (trace_insn),
        .pc              (trace_pc),
        .rd_addr         (trace_rd_addr),
        .rd_value        (trace_rd_data),
        .rs1_value       (trace_rs1_value),
        .rs2_value       (trace_rs2_value),
        .rs1_addr        (trace_rs1_addr),
        .rs2_addr        (trace_rs2_addr),
        .forward_rs1     (trace_forward_rs1),
        .forward_rs2     (trace_forward_rs2),
        .stall           (trace_stall),
        .flush           (trace_flush),
        .branch_taken    (trace_branch_taken),
        .dbg_read_addr   (dbg_trace_addr),
        .dbg_read_data   (dbg_trace_data),
        .dbg_write_ptr   (dbg_trace_wptr),
        .dbg_entry_count (dbg_trace_count),
        .trace_buffer    (),
        .write_ptr       (),
        .entry_count     ()
    );
    
    //==========================================================================
    // DEBUG SIGNAL ASSIGNMENTS FOR LB x19 INVESTIGATION
    //==========================================================================
    assign dbg_ram_rdata_if     = ram_rdata_if;
    assign dbg_if_insn_out      = if_insn_out;
    assign dbg_if_id_pc         = if_id_reg.pc;
    assign dbg_if_id_insn       = if_id_reg.insn;
    assign dbg_if_id_valid      = if_id_reg.valid;
    
    assign dbg_id_ex_pc         = id_ex_reg.pc;
    assign dbg_id_ex_insn       = id_ex_reg.insn;
    assign dbg_id_ex_rd_addr    = id_ex_reg.ctrl.rd_addr;
    assign dbg_id_ex_rf_wen     = id_ex_reg.ctrl.rf_wen;
    assign dbg_id_ex_mem_read   = id_ex_reg.ctrl.mem_read;
    assign dbg_id_ex_valid      = id_ex_reg.valid;
    
    assign dbg_ex_mem_pc        = ex_mem_reg.pc;
    assign dbg_ex_mem_rd_addr   = ex_mem_reg.ctrl.rd_addr;
    assign dbg_ex_mem_rf_wen    = ex_mem_reg.ctrl.rf_wen;
    assign dbg_ex_mem_mem_read  = ex_mem_reg.ctrl.mem_read;
    assign dbg_ex_mem_valid     = ex_mem_reg.valid;
    
    assign dbg_mem_wb_pc        = mem_wb_reg.pc;
    assign dbg_mem_wb_rd_addr   = mem_wb_reg.ctrl.rd_addr;
    assign dbg_mem_wb_rf_wen    = mem_wb_reg.ctrl.rf_wen;
    assign dbg_mem_wb_mem_data  = mem_wb_reg.mem_data;
    assign dbg_mem_wb_valid     = mem_wb_reg.valid;
    
    assign dbg_rf_waddr_actual  = rf_waddr;
    assign dbg_rf_wdata_actual  = rf_wdata;
    assign dbg_rf_wen_actual    = rf_wen;
    
    assign dbg_mem_state_enum   = mem_state;

endmodule : rv32i_top
