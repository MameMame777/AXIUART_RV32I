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
    input  logic        rst_n,
    
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
    
    // Trace buffer read interface (UART accessible)
    input  logic [5:0]  dbg_trace_addr,   // Trace entry index to read
    output logic [127:0] dbg_trace_data,  // Trace entry data [127:96]=PC [95:64]=insn [63:32]=rd_value [31:27]=rd_addr
    output logic [5:0]  dbg_trace_wptr,   // Current write pointer
    output logic [5:0]  dbg_trace_count,  // Number of valid entries
    
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
    
    // Port B - Data memory + Debug access (read/write)
    assign ram_ena_b = 1'b1;
    logic [10:0] ram_addr_b;
    logic [3:0]  ram_we_b;
    logic [31:0] ram_wdata_b;
    
    // Multiplex between MEM stage and debug access
    assign ram_addr_b  = cpu_halted ? dbg_mem_addr : ram_addr_mem;
    assign ram_we_b    = cpu_halted ? dbg_mem_we   : ram_we_byte;
    assign ram_wdata_b = cpu_halted ? dbg_mem_wdata : ram_wdata_mem;
    
    always_ff @(posedge clk) begin
        if (ram_ena_b) begin
            // Write with byte enables
            if (ram_we_b[0]) ram[ram_addr_b][ 7: 0] <= ram_wdata_b[ 7: 0];
            if (ram_we_b[1]) ram[ram_addr_b][15: 8] <= ram_wdata_b[15: 8];
            if (ram_we_b[2]) ram[ram_addr_b][23:16] <= ram_wdata_b[23:16];
            if (ram_we_b[3]) ram[ram_addr_b][31:24] <= ram_wdata_b[31:24];
            // Read
            ram_rdata_mem <= ram[ram_addr_b];
        end
    end
    
    assign dbg_mem_rdata = ram_rdata_mem;
    
    //==========================================================================
    // IF STAGE WIRING
    //==========================================================================
    
    logic [31:0] if_pc_current;
    logic [31:0] if_pc_next;
    logic [31:0] if_pc_out;
    logic [31:0] if_insn_out;
    logic        if_valid_out;
    logic [3:0]  if_bp_hit;
    logic        if_bp_match;
    
    // Exception/MRET signals from MEM stage
    logic        exception_trap;
    logic [31:0] trap_vector;
    logic        mret_req;
    logic [31:0] mret_pc;
    
    // Branch signals from EX stage (pipelined to MEM)
    logic        branch_taken;
    logic [31:0] branch_target;
    
    rv32i_if u_if (
        .pc_current      (if_pc_current),
        .if_stall        (if_stall),
        .if_flush        (if_flush),
        .branch_taken    (ex_mem_reg.branch_taken),
        .branch_target   (ex_mem_reg.branch_target),
        .exception_trap  (exception_trap),
        .trap_vector     (trap_vector),
        .mret_req        (mret_req),
        .mret_pc         (mret_pc),
        .insn_in         (ram_rdata_if),
        .dbg_bp_enable   (dbg_bp_enable),
        .dbg_bp_addr     (dbg_bp_addr),
        .bp_skip_once    (bp_skip_once),
        .running         (running),
        .pc_next         (if_pc_next),
        .pc_out          (if_pc_out),
        .insn_out        (if_insn_out),
        .valid_out       (if_valid_out),
        .dbg_bp_hit      (if_bp_hit),
        .cpu_break       (if_bp_match),
        .insn_ram_addr   (ram_addr_if)
    );
    
    // PC register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || soft_reset_active) begin
            if_pc_current <= 32'h00000000;
        end else if (cpu_run && cpu_halted && if_pc_current == 32'h00000000) begin
            if_pc_current <= 32'h00000000;  // Reset PC to 0 on initial start
        end else if (running && !cpu_halt && (!if_bp_match || bp_skip_once)) begin
            if_pc_current <= if_pc_next;
        end
    end
    
    assign if_valid = running;
    
    //==========================================================================
    // IF/ID PIPELINE REGISTER
    //==========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || soft_reset_active) begin
            if_id_reg <= if_id_bubble();
        end else if (if_flush) begin
            if_id_reg <= if_id_bubble();
        end else if (!id_stall) begin
            if_id_reg.pc    <= if_pc_out;
            if_id_reg.insn  <= if_insn_out;
            if_id_reg.valid <= if_valid_out && running;
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
    logic [1:0]  forward_rs1_next;
    logic [1:0]  forward_rs2_next;
    
    // Register file write from WB stage
    logic        rf_wen;
    logic [4:0]  rf_waddr;
    logic [31:0] rf_wdata;
    
    rv32i_id u_id (
        .clk             (clk),
        .rst_n           (rst_n && !soft_reset_active),
        .pc_in           (if_id_reg.pc),
        .insn_in         (if_id_reg.insn),
        .valid_in        (if_id_reg.valid),
        .rf_wen          (rf_wen),
        .rf_waddr        (rf_waddr),
        .rf_wdata        (rf_wdata),
        .csr_rdata       (csr_rdata),
        .forward_rs1     (forward_rs1_next),
        .forward_rs2     (forward_rs2_next),
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
    
    rv32i_hazard u_hazard (
        .id_rs1_addr     (id_ctrl.rs1_addr),
        .id_rs2_addr     (id_ctrl.rs2_addr),
        .id_rs1_used     (id_ctrl.alu_src1_pc ? 1'b0 : 1'b1),  // RS1 not used if ALU src is PC
        .id_rs2_used     (id_ctrl.alu_src2_imm ? 1'b0 : 1'b1), // RS2 not used if ALU src is immediate
        .id_valid        (id_valid),
        .ex_rd_addr      (id_ex_reg.ctrl.rd_addr),
        .ex_rf_wen       (id_ex_reg.ctrl.rf_wen),
        .ex_is_load      (id_ex_reg.ctrl.mem_read),
        .ex_valid        (id_ex_reg.valid),
        .mem_rd_addr     (ex_mem_reg.ctrl.rd_addr),
        .mem_rf_wen      (ex_mem_reg.ctrl.rf_wen),
        .mem_valid       (ex_mem_reg.valid),
        .wb_rd_addr      (mem_wb_reg.rd_addr),
        .wb_rf_wen       (mem_wb_reg.rf_wen),
        .wb_valid        (mem_wb_reg.valid),
        .branch_taken    (ex_mem_reg.branch_taken),
        .exception_trap  (exception_trap),
        .mret_req        (mret_req),
        .forward_rs1     (forward_rs1_next),
        .forward_rs2     (forward_rs2_next),
        .if_stall        (if_stall),
        .id_stall        (id_stall),
        .if_flush        (if_flush),
        .id_flush        (id_flush),
        .ex_flush        (ex_flush),
        .load_use_stall  (load_use_stall)
    );
    
    //==========================================================================
    // ID/EX PIPELINE REGISTER
    //==========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || soft_reset_active) begin
            id_ex_reg <= id_ex_bubble();
        end else if (id_flush) begin
            id_ex_reg <= id_ex_bubble();
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
    
    logic [31:0] ex_pc_out;
    logic [31:0] ex_insn_out;
    logic [31:0] ex_alu_result;
    logic [31:0] ex_rs2_forwarded;
    logic [31:0] ex_csr_rdata_out;
    logic        ex_branch_taken;
    logic [31:0] ex_branch_target;
    decode_ctrl_t ex_ctrl_out;
    logic        ex_valid_out;
    
    // Forwarding sources
    logic [31:0] wb_result;
    
    rv32i_ex u_ex (
        .pc_in           (id_ex_reg.pc),
        .insn_in         (id_ex_reg.insn),
        .rs1_data_in     (id_ex_reg.rs1_data),
        .rs2_data_in     (id_ex_reg.rs2_data),
        .imm_in          (id_ex_reg.imm),
        .csr_rdata_in    (id_ex_reg.csr_rdata),
        .forward_rs1     (id_ex_reg.forward_rs1),
        .forward_rs2     (id_ex_reg.forward_rs2),
        .ctrl_in         (id_ex_reg.ctrl),
        .valid_in        (id_ex_reg.valid),
        .ex_forward_data (ex_mem_reg.alu_result),
        .mem_forward_data(wb_result),
        .wb_forward_data (wb_result),
        .pc_out          (ex_pc_out),
        .insn_out        (ex_insn_out),
        .alu_result      (ex_alu_result),
        .rs2_forwarded_out(ex_rs2_forwarded),
        .csr_rdata_out   (ex_csr_rdata_out),
        .branch_taken    (ex_branch_taken),
        .branch_target   (ex_branch_target),
        .ctrl_out        (ex_ctrl_out),
        .valid_out       (ex_valid_out)
    );
    
    assign ex_valid = ex_valid_out;
    
    //==========================================================================
    // EX/MEM PIPELINE REGISTER
    //==========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || soft_reset_active) begin
            ex_mem_reg <= ex_mem_bubble();
        end else if (ex_flush) begin
            ex_mem_reg <= ex_mem_bubble();
        end else begin
            ex_mem_reg.pc            <= ex_pc_out;
            ex_mem_reg.insn          <= ex_insn_out;
            ex_mem_reg.alu_result    <= ex_alu_result;
            ex_mem_reg.rs2_data      <= ex_rs2_forwarded;
            ex_mem_reg.csr_rdata     <= ex_csr_rdata_out;
            ex_mem_reg.branch_taken  <= ex_branch_taken;
            ex_mem_reg.branch_target <= ex_branch_target;
            ex_mem_reg.ctrl          <= ex_ctrl_out;
            ex_mem_reg.valid         <= ex_valid;
        end
    end
    
    //==========================================================================
    // MEM STAGE WIRING
    //==========================================================================
    
    logic [31:0] mem_pc_out;
    logic [31:0] mem_insn_out;
    logic [31:0] mem_alu_result_out;
    logic [31:0] mem_mem_data;
    logic [31:0] mem_csr_rdata_out;
    decode_ctrl_t mem_ctrl_out;
    logic        mem_valid_out;
    logic [3:0]  mem_led_out;
    logic [31:0] mem_exception_pc;
    logic [4:0]  mem_exception_code;
    logic [31:0] mem_exception_tval;
    
    rv32i_mem u_mem (
        .clk             (clk),
        .rst_n           (rst_n && !soft_reset_active),
        .pc_in           (ex_mem_reg.pc),
        .insn_in         (ex_mem_reg.insn),
        .alu_result_in   (ex_mem_reg.alu_result),
        .rs2_data_in     (ex_mem_reg.rs2_data),
        .csr_rdata_in    (ex_mem_reg.csr_rdata),
        .ctrl_in         (ex_mem_reg.ctrl),
        .valid_in        (ex_mem_reg.valid),
        .data_ram_rdata  (ram_rdata_mem),
        .pc_out          (mem_pc_out),
        .insn_out        (mem_insn_out),
        .alu_result_out  (mem_alu_result_out),
        .mem_data        (mem_mem_data),
        .csr_rdata_out   (mem_csr_rdata_out),
        .ctrl_out        (mem_ctrl_out),
        .valid_out       (mem_valid_out),
        .data_ram_addr   (ram_addr_mem),
        .data_ram_wdata  (ram_wdata_mem),
        .data_ram_we     (ram_we_byte),
        .led_out         (mem_led_out),
        .exception_trap  (exception_trap),
        .exception_pc    (mem_exception_pc),
        .exception_code  (mem_exception_code),
        .exception_tval  (mem_exception_tval)
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
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || soft_reset_active) begin
            mem_wb_reg <= mem_wb_bubble();
        end else begin
            mem_wb_reg.pc          <= mem_pc_out;
            mem_wb_reg.insn        <= mem_insn_out;
            mem_wb_reg.mem_data    <= mem_mem_data;
            mem_wb_reg.alu_result  <= mem_alu_result_out;
            mem_wb_reg.csr_rdata   <= mem_csr_rdata_out;
            mem_wb_reg.ctrl        <= mem_ctrl_out;
            mem_wb_reg.valid       <= mem_valid;
            mem_wb_reg.rd_addr     <= mem_ctrl_out.rd_addr;
            mem_wb_reg.rf_wen      <= mem_ctrl_out.rf_wen;
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
        .pc_in           (mem_wb_reg.pc),
        .insn_in         (mem_wb_reg.insn),
        .mem_data_in     (mem_wb_reg.mem_data),
        .alu_result_in   (mem_wb_reg.alu_result),
        .csr_rdata_in    (mem_wb_reg.csr_rdata),
        .ctrl_in         (mem_wb_reg.ctrl),
        .valid_in        (mem_wb_reg.valid),
        .rd_addr_in      (mem_wb_reg.rd_addr),
        .wb_result       (wb_result),
        .rf_wen          (wb_rf_wen),
        .csr_waddr       (wb_csr_waddr),
        .csr_wdata       (wb_csr_wdata),
        .csr_wen         (wb_csr_wen)
    );
    
    assign wb_valid = mem_wb_reg.valid;
    assign rf_wen   = wb_rf_wen;
    assign rf_waddr = mem_wb_reg.rd_addr;
    assign rf_wdata = wb_result;
    
    //==========================================================================
    // CSR MODULE
    //==========================================================================
    
    rv32i_csr u_csr (
        .clk             (clk),
        .rst_n           (rst_n && !soft_reset_active),
        .csr_raddr       (csr_raddr),
        .csr_rdata       (csr_rdata),
        .csr_waddr       (wb_csr_waddr),
        .csr_wdata       (wb_csr_wdata),
        .csr_wen         (wb_csr_wen),
        .exception_trap  (exception_trap),
        .exception_pc    (mem_exception_pc),
        .exception_code  ({27'b0, mem_exception_code}),  // Extend to 32-bit
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
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || soft_reset_active) begin
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
            if (bp_just_resumed && running) begin
                bp_skip_once    <= 1'b0;
                bp_just_resumed <= 1'b0;
            end
            
            // Hardware breakpoint detection
            if (if_bp_match && running && !step_mode && !bp_skip_once) begin
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
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || soft_reset_active) begin
            cycle_counter <= 32'h0;
            insn_counter  <= 32'h0;
            stall_counter <= 32'h0;
            flush_counter <= 32'h0;
        end else if (running) begin
            cycle_counter <= cycle_counter + 32'd1;
            if (wb_valid) insn_counter <= insn_counter + 32'd1;
            if (if_stall || id_stall) stall_counter <= stall_counter + 32'd1;
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
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
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
    assign trace_rd_addr = mem_wb_reg.rd_addr;
    assign trace_rd_data = wb_result;
    
    Rv32i_Trace_Buffer #(
        .DEPTH(64)
    ) u_trace_buffer (
        .clk             (clk),
        .rst_n           (rst_n && !soft_reset_active),
        .insn_valid      (trace_valid),
        .insn            (trace_insn),
        .pc              (trace_pc),
        .rd_addr         (trace_rd_addr),
        .rd_value        (trace_rd_data),
        .dbg_read_addr   (dbg_trace_addr),
        .dbg_read_data   (dbg_trace_data),
        .dbg_write_ptr   (dbg_trace_wptr),
        .dbg_entry_count (dbg_trace_count),
        .trace_buffer    (),
        .write_ptr       (),
        .entry_count     ()
    );

endmodule : rv32i_top
