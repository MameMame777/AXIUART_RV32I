`timescale 1ns / 1ps

//==============================================================================
// RISC-V RV32I Core - Clean-Slate Implementation
//==============================================================================
// 
// Architecture: 5-stage pipeline (IF/ID/EX/MEM/WB)
// ISA: RV32I Base Integer Instruction Set (40 instructions)
// Registers: 32 x 32-bit (x0 hardwired to zero)
// Memory: 8KB internal RAM, byte-addressed
// Hazards: Data forwarding, load-use stall, branch/jump flush
// 
// Pipeline Stages:
//   IF  - Instruction Fetch (PC management, instruction memory)
//   ID  - Instruction Decode (decode, register read, immediate generation)
//   EX  - Execute (ALU, branch logic, jump target calculation)
//   MEM - Memory Access (load/store, byte addressing, MMIO)
//   WB  - Write Back (register file write, result multiplexing)
//
//==============================================================================

module rv32i_core
    import rv32i_isa_pkg::*;
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
    output logic [31:0] trace_rd_data
);

    //==========================================================================
    // Pipeline Stage Valid Signals
    //==========================================================================
    
    logic if_valid;
    logic id_valid;
    logic ex_valid;
    logic mem_valid;
    logic wb_valid;
    
    //==========================================================================
    // Pipeline Control Signals
    //==========================================================================
    
    logic if_stall;
    logic id_stall;
    logic if_flush;
    logic id_flush;
    logic ex_flush;
    
    //==========================================================================
    // Debug Internal Signals
    //==========================================================================
    
    // Hardware breakpoint signals
    logic bp_match;
    logic [3:0] bp_hit_reg;
    
    // Performance counters
    logic [31:0] cycle_counter;
    logic [31:0] insn_counter;
    logic [31:0] stall_counter;
    logic [31:0] flush_counter;
    
    // Software reset and single-step control
    logic soft_reset_active;
    logic reset_done_reg;
    logic step_mode;
    logic step_done;
    logic bp_skip_once;  // Skip breakpoint check for one instruction after resume
    logic bp_just_resumed;  // Track that we just resumed from breakpoint
    
    //==========================================================================
    // Program Counter
    //==========================================================================
    
    logic [31:0] pc_if;
    logic [31:0] pc_id;
    logic [31:0] pc_ex;
    logic [31:0] pc_mem;
    logic [31:0] pc_wb;
    
    logic [31:0] pc_next;
    logic [31:0] pc_branch_target;
    logic        pc_sel_branch;  // Select branch/jump target instead of PC+4
    
    //==========================================================================
    // Instruction Memory & Fetch
    //==========================================================================
    
    logic [31:0] insn_if;
    logic [31:0] insn_id;
    logic [31:0] insn_ex;
    logic [31:0] insn_mem;
    logic [31:0] insn_wb;
    
    // Internal RAM (2048 x 32-bit = 8KB) - True Dual-Port BlockRAM
    // Port A: Instruction fetch (IF) - Read only
    // Port B: Data memory (MEM) + Debug access - Read/Write
    (* RAM_STYLE = "block" *) logic [31:0] ram [0:2047];
    
    // Port A - Instruction Fetch
    logic [10:0] ram_addr_if;   // Word address for instruction fetch
    logic        ram_ena_a;     // Port A enable
    logic [31:0] ram_rdata_if;  // IF instruction data
    
    // Port B - Data Memory + Debug
    logic [10:0] ram_addr_mem;  // Word address for data access
    logic        ram_ena_b;     // Port B enable
    logic [31:0] ram_rdata_mem; // MEM data (unified for MEM and Debug)
    logic [3:0]  ram_we_byte;   // Byte write enable for SB/SH/SW
    
    //==========================================================================
    // Register File (32 x 32-bit)
    //==========================================================================
    
    logic [31:0] regfile [0:31];
    
    logic [4:0]  rf_raddr1;     // rs1 address (from ID)
    logic [4:0]  rf_raddr2;     // rs2 address (from ID)
    logic [31:0] rf_rdata1;     // rs1 data (combinational read)
    logic [31:0] rf_rdata2;     // rs2 data (combinational read)
    
    logic [4:0]  rf_waddr;      // rd address (from WB)
    logic        rf_wen;        // Write enable (from WB)
    logic [31:0] rf_wdata;      // Write data (from WB)
    
    //==========================================================================
    // IF/ID Pipeline Register
    //==========================================================================
    
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] insn;
        logic        valid;
    } if_id_reg_t;
    
    if_id_reg_t if_id_reg;
    
    //==========================================================================
    // ID/EX Pipeline Register
    //==========================================================================
    
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] insn;
        logic [31:0] rs1_data;
        logic [31:0] rs2_data;
        logic [31:0] csr_rdata;    // CSR read data (from ID stage)
        logic [1:0]  forward_rs1;  // Pre-computed forwarding control (Phase 2B)
        logic [1:0]  forward_rs2;  // Pre-computed forwarding control (Phase 2B)
        decode_ctrl_t ctrl;
        logic        valid;
    } id_ex_reg_t;
    
    id_ex_reg_t id_ex_reg;
    
    //==========================================================================
    // EX/MEM Pipeline Register
    //==========================================================================
    
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] insn;
        logic [31:0] alu_result;
        logic [31:0] rs2_data;      // For store operations
        logic [31:0] csr_rdata;     // CSR read data (forwarded from ID stage)
        logic        branch_taken;  // Branch decision (pipelined from EX)
        logic [31:0] branch_target; // Branch target address (pipelined from EX)
        decode_ctrl_t ctrl;
        logic        valid;
    } ex_mem_reg_t;
    
    ex_mem_reg_t ex_mem_reg;
    
    //==========================================================================
    // MEM/WB Pipeline Register
    //==========================================================================
    
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] insn;
        logic [31:0] result;        // ALU result or memory data or CSR data
        decode_ctrl_t ctrl;         // Decode control (for CSR write enable)
        logic [4:0]  rd_addr;
        logic        rf_wen;
        logic        valid;
    } mem_wb_reg_t;
    
    mem_wb_reg_t mem_wb_reg;
    
    //==========================================================================
    // Decode Stage Signals
    //==========================================================================
    
    decode_ctrl_t id_ctrl;
    
    //==========================================================================
    // Execute Stage Signals
    //==========================================================================
    
    logic [31:0] ex_alu_result;
    logic [31:0] ex_alu_op1;
    logic [31:0] ex_alu_op2;        // Assigned to ex_rs2_forwarded for stores
    logic        ex_branch_cond;    // Branch condition evaluation (EX stage)
    logic [31:0] ex_branch_target;  // Branch target calculation (EX stage)
    
    // MEM stage branch signals (pipelined)
    logic        mem_branch_taken;  // Actual branch taken decision (MEM stage)
    logic [31:0] mem_branch_target; // Branch target (MEM stage)
    
    //==========================================================================
    // Memory Stage Signals
    //==========================================================================
    
    logic [31:0] mem_load_data;
    logic [31:0] mem_addr;
    logic        mem_is_ram;
    logic        mem_is_mmio;
    
    //==========================================================================
    // Writeback Stage Signals
    //==========================================================================
    
    logic [31:0] wb_result;
    
    //==========================================================================
    // CSR (Control and Status Register) Signals
    //==========================================================================
    
    // CSR read interface (ID stage)
    logic [11:0] csr_raddr;
    logic [31:0] csr_rdata;
    
    // CSR write interface (WB stage)
    logic [11:0] csr_waddr;
    logic [31:0] csr_wdata;
    logic        csr_wen;
    
    // Exception trap interface (MEM stage - will be implemented in Step 4)
    logic        exception_trap;
    logic [31:0] exception_pc;
    logic [4:0]  exception_code;
    logic [31:0] exception_tval;
    logic [31:0] trap_vector;
    
    // MRET interface (MEM stage - will be implemented in Step 7)
    logic        mret_req;
    logic [31:0] mret_pc;
    
    // Debug CSR interface
    logic [11:0] dbg_csr_addr_int;
    logic [31:0] dbg_csr_rdata_int;
    
    //==========================================================================
    // Hazard Detection & Forwarding
    //==========================================================================
    
    logic [1:0]  forward_rs1;   // 00=RF, 01=EX, 10=MEM, 11=WB
    logic [1:0]  forward_rs2;
    logic        hazard_load_use;
    
    //==========================================================================
    // Debug & Control
    //==========================================================================
    
    logic running;              // CPU is executing
    logic step_pending;         // Single-step mode active
    
    //==========================================================================
    // MMIO Registers
    //==========================================================================
    
    logic [3:0] led_reg;
    assign led_out = led_reg;
    
    //==========================================================================
    // REGISTER FILE IMPLEMENTATION
    //==========================================================================
    // 
    // Critical RISC-V requirement: x0 is hardwired to zero
    // - Reads from x0 always return 0
    // - Writes to x0 are legal but ignored
    //
    //==========================================================================
    
    // Combinational read with x0 hardwire
    assign rf_rdata1 = (rf_raddr1 == 5'b0) ? 32'h0 : regfile[rf_raddr1];
    assign rf_rdata2 = (rf_raddr2 == 5'b0) ? 32'h0 : regfile[rf_raddr2];
    
    // Register file write (x0 protection)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all registers to 0
            for (int i = 0; i < 32; i++) begin
                regfile[i] <= 32'h0;
            end
        end else begin
            // Write to register file (ignore writes to x0)
            if (rf_wen && rf_waddr != 5'b0) begin
                regfile[rf_waddr] <= rf_wdata;
            end
        end
    end
    
    //==========================================================================
    // CSR MODULE INSTANTIATION
    //==========================================================================
    //
    // Control and Status Registers for RISC-V Privileged Architecture
    // - Implements Machine Mode CSRs (mepc, mcause, mtval, mtvec)
    // - Supports 6 CSR operations (CSRRW/CSRRS/CSRRC + immediate variants)
    // - Handles exception trap and MRET instruction
    //
    //==========================================================================
    
    rv32i_csr u_csr (
        .clk                (clk),
        .rst_n              (rst_n),
        
        // CSR read interface (ID stage)
        .csr_raddr          (csr_raddr),
        .csr_rdata          (csr_rdata),
        
        // CSR write interface (WB stage)
        .csr_waddr          (csr_waddr),
        .csr_wdata          (csr_wdata),
        .csr_wen            (csr_wen),
        
        // Exception trap interface (MEM stage)
        .exception_trap     (exception_trap),
        .exception_pc       (exception_pc),
        .exception_code     (exception_code),
        .exception_tval     (exception_tval),
        .trap_vector        (trap_vector),
        
        // MRET interface (MEM stage)
        .mret_req           (mret_req),
        .mret_pc            (mret_pc),
        
        // Debug CSR read interface
        .dbg_csr_addr       (dbg_csr_addr_int),
        .dbg_csr_rdata      (dbg_csr_rdata_int)
    );
    
    //==========================================================================
    // INSTRUCTION MEMORY (Dual-Port Block RAM)
    //==========================================================================
    // Port A: CPU instruction fetch + data access
    // Port B: Debug/external access (priority over Port A writes)
    //==========================================================================
    
    // Word address calculation (byte address [31:2] = word address)
    assign ram_addr_if = pc_if[12:2];  // IF stage fetch
    
    // Port A: Dedicated to IF (instruction fetch)
    // Port B: Dedicated to MEM (data memory) + Debug (multiplexed)
    // True Dual-Port BlockRAM: both ports operate independently (UG901)
    assign ram_ena_a = 1'b1;  // Always enabled
    assign ram_ena_b = 1'b1;  // Always enabled
    
    assign insn_if = ram_rdata_if;
    
    //==========================================================================
    // PROGRAM COUNTER MANAGEMENT
    //==========================================================================
    
    //==========================================================================
    // HARDWARE BREAKPOINT LOGIC
    //==========================================================================
    // Check if current PC matches any enabled breakpoint
    always_comb begin
        bp_match = 1'b0;
        for (int i = 0; i < 4; i++) begin
            if (dbg_bp_enable[i] && (pc_if == dbg_bp_addr[i]) && running) begin
                bp_match = 1'b1;
            end
        end
    end
    
    // Pure address comparison for bp_skip_once clearing logic (no running check)
    logic at_any_bp_addr;
    assign at_any_bp_addr = (dbg_bp_enable[0] && (pc_if == dbg_bp_addr[0])) ||
                            (dbg_bp_enable[1] && (pc_if == dbg_bp_addr[1])) ||
                            (dbg_bp_enable[2] && (pc_if == dbg_bp_addr[2])) ||
                            (dbg_bp_enable[3] && (pc_if == dbg_bp_addr[3]));
    
    // PC next-value logic
    always_comb begin
        if (exception_trap) begin
            // Exception trap: Redirect to trap handler (highest priority)
            pc_next = trap_vector;  // Jump to mtvec CSR value
        end else if (mret_detected) begin
            // MRET: Return from trap handler (second priority)
            pc_next = mret_pc;  // Return to mepc CSR value
        end else if (pc_sel_branch) begin
            // Branch or jump taken - use target address
            pc_next = pc_branch_target;
        end else if (!if_stall) begin
            // Sequential execution - increment by 4 (byte addressing)
            pc_next = pc_if + 32'd4;
        end else begin
            // Stall - hold current PC
            pc_next = pc_if;
        end
    end
    
    // PC register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_if <= 32'h00000000;
        end else if (cpu_run && cpu_halted && pc_if == 32'h00000000) begin
            // Reset PC to 0 only on initial start (when PC is already 0)
            // Don't reset when resuming from breakpoint (PC != 0)
            pc_if <= 32'h00000000;
        end else if (running && !cpu_halt && (!bp_match || bp_skip_once)) begin
            // Update PC during normal execution
            // When resuming from breakpoint:
            //   - bp_skip_once=1 allows PC update on resume
            //   - Pipeline preserves instruction from breakpoint address
            //   - Instruction completes quickly without re-fetching
            pc_if <= pc_next;
        end
    end
    
    //==========================================================================
    // IF/ID PIPELINE REGISTER
    //==========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_reg <= '0;
        end else if (if_flush) begin
            // Flush - insert bubble
            if_id_reg.valid <= 1'b0;
        end else if (!id_stall) begin
            // Normal progression
            if_id_reg.pc    <= pc_if;
            if_id_reg.insn  <= insn_if;
            if_id_reg.valid <= if_valid && running;
        end
        // Else: stall - hold current value
    end
    
    // ID stage inputs
    assign pc_id     = if_id_reg.pc;
    assign insn_id   = if_id_reg.insn;
    assign id_valid  = if_id_reg.valid;
    
    //==========================================================================
    // INSTRUCTION DECODE
    //==========================================================================
    
    // Decode instruction using ISA package function
    assign id_ctrl = decode_insn(insn_id);
    
    // Register file read addresses
    assign rf_raddr1 = id_ctrl.rs1_addr;
    assign rf_raddr2 = id_ctrl.rs2_addr;
    
    //==========================================================================
    // FORWARDING LOGIC - ID STAGE PRE-COMPUTATION (PHASE 2B OPTIMIZATION)
    //==========================================================================
    // Pre-compute forwarding control in ID stage to eliminate combinational
    // logic in critical path. Comparisons use ID-stage register addresses
    // (id_ctrl) against pipeline stage destinations.
    // Encoding: 2'b00=RF, 2'b01=EX, 2'b10=MEM, 2'b11=WB (unused)
    //==========================================================================
    
    logic [1:0] forward_rs1_next, forward_rs2_next;
    logic id_rs1_match_ex, id_rs1_match_mem, id_rs1_match_wb;
    logic id_rs2_match_ex, id_rs2_match_mem, id_rs2_match_wb;
    logic ex_writes_rd, mem_writes_rd, wb_writes_rd;
    
    // Forward write detection signals (reused from hazard detection)
    assign ex_writes_rd  = id_ex_reg.ctrl.rf_wen && (id_ex_reg.ctrl.rd_addr != 5'b0) && id_ex_reg.valid;
    assign mem_writes_rd = ex_mem_reg.ctrl.rf_wen && (ex_mem_reg.ctrl.rd_addr != 5'b0) && ex_mem_reg.valid;
    assign wb_writes_rd  = mem_wb_reg.rf_wen && (mem_wb_reg.rd_addr != 5'b0) && mem_wb_reg.valid;
    
    // RS1 forwarding pre-computation (ID stage)
    assign id_rs1_match_ex  = (id_ctrl.rs1_addr != 5'b0) && ex_writes_rd  && (id_ex_reg.ctrl.rd_addr == id_ctrl.rs1_addr);
    assign id_rs1_match_mem = (id_ctrl.rs1_addr != 5'b0) && mem_writes_rd && (ex_mem_reg.ctrl.rd_addr == id_ctrl.rs1_addr);
    assign id_rs1_match_wb  = (id_ctrl.rs1_addr != 5'b0) && wb_writes_rd  && (mem_wb_reg.rd_addr == id_ctrl.rs1_addr);
    
    assign forward_rs1_next = id_rs1_match_ex  ? 2'b01 :  // EX stage (highest priority)
                              id_rs1_match_mem ? 2'b10 :  // MEM stage
                              id_rs1_match_wb  ? 2'b11 :  // WB stage
                                                 2'b00;   // Register file
    
    // RS2 forwarding pre-computation (ID stage)
    assign id_rs2_match_ex  = (id_ctrl.rs2_addr != 5'b0) && ex_writes_rd  && (id_ex_reg.ctrl.rd_addr == id_ctrl.rs2_addr);
    assign id_rs2_match_mem = (id_ctrl.rs2_addr != 5'b0) && mem_writes_rd && (ex_mem_reg.ctrl.rd_addr == id_ctrl.rs2_addr);
    assign id_rs2_match_wb  = (id_ctrl.rs2_addr != 5'b0) && wb_writes_rd  && (mem_wb_reg.rd_addr == id_ctrl.rs2_addr);
    
    assign forward_rs2_next = id_rs2_match_ex  ? 2'b01 :  // EX stage (highest priority)
                              id_rs2_match_mem ? 2'b10 :  // MEM stage
                              id_rs2_match_wb  ? 2'b11 :  // WB stage
                                                 2'b00;   // Register file
    
    //==========================================================================
    // ID/EX PIPELINE REGISTER
    //==========================================================================
    
    // CSR read address from decoded instruction (ID stage)
    assign csr_raddr = id_ctrl.csr_addr;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_reg <= '0;
        end else if (id_flush) begin
            // Flush - insert bubble
            id_ex_reg.valid <= 1'b0;
        end else if (!id_stall) begin
            // Normal progression
            id_ex_reg.pc          <= pc_id;
            id_ex_reg.insn        <= insn_id;
            id_ex_reg.rs1_data    <= rf_rdata1;
            id_ex_reg.rs2_data    <= rf_rdata2;
            id_ex_reg.csr_rdata   <= csr_rdata;         // CSR read data
            id_ex_reg.forward_rs1 <= forward_rs1_next;  // Phase 2B: Register forwarding control
            id_ex_reg.forward_rs2 <= forward_rs2_next;  // Phase 2B: Register forwarding control
            id_ex_reg.ctrl        <= id_ctrl;
            id_ex_reg.valid       <= id_valid;
        end
        // Else: stall - hold current value
    end
    
    // EX stage inputs
    assign pc_ex    = id_ex_reg.pc;
    assign insn_ex  = id_ex_reg.insn;
    assign ex_valid = id_ex_reg.valid;
    
    //==========================================================================
    // EXECUTE STAGE - OPERAND SELECTION
    //==========================================================================
    
    logic [31:0] ex_rs1_forwarded;
    logic [31:0] ex_rs2_forwarded;
    logic [31:0] ex_alu_src1;
    logic [31:0] ex_alu_src2;
    
    // Forwarding multiplexers using pre-computed controls (Phase 2B)
    // Control signals are registered in id_ex_reg, eliminating combinational logic
    // Encoding: 2'b00=RF, 2'b01=EX/MEM forward, 2'b10=MEM/WB forward, 2'b11=MEM/WB forward
    always_comb begin
        (* parallel_case, full_case *)
        case (id_ex_reg.forward_rs1)
            2'b00:   ex_rs1_forwarded = id_ex_reg.rs1_data;      // Register file
            2'b01:   ex_rs1_forwarded = ex_mem_reg.alu_result;   // EX-to-EX forward (from EX/MEM)
            2'b10:   ex_rs1_forwarded = mem_wb_reg.result;       // MEM-to-EX forward (from MEM/WB)
            2'b11:   ex_rs1_forwarded = mem_wb_reg.result;       // WB-to-EX forward (from MEM/WB)
            default: ex_rs1_forwarded = id_ex_reg.rs1_data;
        endcase
        
        (* parallel_case, full_case *)
        case (id_ex_reg.forward_rs2)
            2'b00:   ex_rs2_forwarded = id_ex_reg.rs2_data;      // Register file
            2'b01:   ex_rs2_forwarded = ex_mem_reg.alu_result;   // EX-to-EX forward (from EX/MEM)
            2'b10:   ex_rs2_forwarded = mem_wb_reg.result;       // MEM-to-EX forward (from MEM/WB)
            2'b11:   ex_rs2_forwarded = mem_wb_reg.result;       // WB-to-EX forward (from MEM/WB)
            default: ex_rs2_forwarded = id_ex_reg.rs2_data;
        endcase
    end
    
    // ALU operand 1 selection: PC or rs1
    assign ex_alu_src1 = id_ex_reg.ctrl.alu_src1_pc ? pc_ex : ex_rs1_forwarded;
    
    // ALU operand 2 selection: immediate or rs2
    assign ex_alu_src2 = id_ex_reg.ctrl.alu_src2_imm ? id_ex_reg.ctrl.immediate : ex_rs2_forwarded;
    
    // Preserve forwarded rs2 for store operations (used in MEM stage)
    assign ex_alu_op2 = ex_rs2_forwarded;
    
    //==========================================================================
    // EXECUTE STAGE - 32-BIT ALU
    //==========================================================================
    
    logic [31:0] alu_add_sub_result;
    logic [31:0] alu_shift_result;
    logic [31:0] alu_compare_result;
    logic [31:0] alu_logic_result;
    
    // Adder/Subtractor with DSP48 optimization
    (* use_dsp = "yes" *) logic [32:0] add_sub_temp;  // Extra bit for carry
    assign add_sub_temp = (id_ex_reg.ctrl.alu_op == ALU_SUB) ?
                          {1'b0, ex_alu_src1} + {1'b0, ~ex_alu_src2} + 33'd1 :  // SUB: A + ~B + 1
                          {1'b0, ex_alu_src1} + {1'b0, ex_alu_src2};             // ADD: A + B
    assign alu_add_sub_result = add_sub_temp[31:0];
    
    // Shifter
    logic [4:0] shift_amount;
    assign shift_amount = ex_alu_src2[4:0];  // Lower 5 bits for shift amount
    
    always_comb begin
        case (id_ex_reg.ctrl.alu_op)
            ALU_SLL: alu_shift_result = ex_alu_src1 << shift_amount;                           // Logical left
            ALU_SRL: alu_shift_result = ex_alu_src1 >> shift_amount;                           // Logical right
            ALU_SRA: alu_shift_result = $signed(ex_alu_src1) >>> shift_amount;                 // Arithmetic right
            default: alu_shift_result = 32'h0;
        endcase
    end
    
    // Comparator (signed and unsigned)
    logic signed_less_than;
    logic unsigned_less_than;
    
    assign signed_less_than   = $signed(ex_alu_src1) < $signed(ex_alu_src2);
    assign unsigned_less_than = ex_alu_src1 < ex_alu_src2;
    
    always_comb begin
        case (id_ex_reg.ctrl.alu_op)
            ALU_SLT:  alu_compare_result = {31'h0, signed_less_than};    // Set if less than (signed)
            ALU_SLTU: alu_compare_result = {31'h0, unsigned_less_than};  // Set if less than (unsigned)
            default:  alu_compare_result = 32'h0;
        endcase
    end
    
    // Logic operations
    always_comb begin
        case (id_ex_reg.ctrl.alu_op)
            ALU_AND: alu_logic_result = ex_alu_src1 & ex_alu_src2;
            ALU_OR:  alu_logic_result = ex_alu_src1 | ex_alu_src2;
            ALU_XOR: alu_logic_result = ex_alu_src1 ^ ex_alu_src2;
            default: alu_logic_result = 32'h0;
        endcase
    end
    
    // ALU result multiplexer
    always_comb begin
        case (id_ex_reg.ctrl.alu_op)
            ALU_ADD, ALU_SUB:        ex_alu_result = alu_add_sub_result;
            ALU_SLL, ALU_SRL, ALU_SRA: ex_alu_result = alu_shift_result;
            ALU_SLT, ALU_SLTU:       ex_alu_result = alu_compare_result;
            ALU_AND, ALU_OR, ALU_XOR: ex_alu_result = alu_logic_result;
            ALU_COPY_RS1:            ex_alu_result = ex_alu_src1;  // For AUIPC base
            ALU_COPY_IMM:            ex_alu_result = ex_alu_src2;  // For LUI
            default:                 ex_alu_result = alu_add_sub_result;  // Default to ADD
        endcase
    end
    
    //==========================================================================
    // EXECUTE STAGE - BRANCH CONDITION EVALUATION
    //==========================================================================
    
    logic branch_eq;
    logic branch_ne;
    logic branch_lt;
    logic branch_ge;
    logic branch_ltu;
    logic branch_geu;
    logic branch_condition_met;
    
    // Branch comparisons
    assign branch_eq  = (ex_rs1_forwarded == ex_rs2_forwarded);
    assign branch_ne  = (ex_rs1_forwarded != ex_rs2_forwarded);
    assign branch_lt  = $signed(ex_rs1_forwarded) < $signed(ex_rs2_forwarded);
    assign branch_ge  = $signed(ex_rs1_forwarded) >= $signed(ex_rs2_forwarded);
    assign branch_ltu = ex_rs1_forwarded < ex_rs2_forwarded;
    assign branch_geu = ex_rs1_forwarded >= ex_rs2_forwarded;
    
    // Branch condition multiplexer
    always_comb begin
        case (id_ex_reg.ctrl.branch_op)
            BR_EQ:   branch_condition_met = branch_eq;
            BR_NE:   branch_condition_met = branch_ne;
            BR_LT:   branch_condition_met = branch_lt;
            BR_GE:   branch_condition_met = branch_ge;
            BR_LTU:  branch_condition_met = branch_ltu;
            BR_GEU:  branch_condition_met = branch_geu;
            default: branch_condition_met = 1'b0;
        endcase
    end
    
    // Branch condition evaluation (EX stage)
    // NOTE: This is only the condition check, not the final branch decision
    assign ex_branch_cond = id_ex_reg.ctrl.is_branch && branch_condition_met && ex_valid;
    
    //==========================================================================
    // MEMORY STAGE - BRANCH RESOLUTION (PIPELINED)
    //==========================================================================
    // Branch decision is made in MEM stage to break critical timing path
    // This adds 1-cycle branch latency but improves Fmax significantly
    
    assign mem_branch_taken = ex_mem_reg.branch_taken && ex_mem_reg.valid;
    assign mem_branch_target = ex_mem_reg.branch_target;
    
    //==========================================================================
    // EXECUTE STAGE - JUMP & BRANCH TARGET CALCULATION
    //==========================================================================
    
    logic [31:0] jump_target_jal;
    logic [31:0] jump_target_jalr;
    logic        is_jump;
    
    // JAL target: PC + immediate (PC-relative)
    assign jump_target_jal = pc_ex + id_ex_reg.ctrl.immediate;
    
    // JALR target: (rs1 + immediate) & ~1 (clear LSB for alignment)
    assign jump_target_jalr = (ex_rs1_forwarded + id_ex_reg.ctrl.immediate) & 32'hFFFF_FFFE;
    
    // Jump detection
    assign is_jump = id_ex_reg.ctrl.is_jump && ex_valid;
    
    // Branch/jump target selection (EX stage - will be registered to MEM)
    always_comb begin
        if (is_jump) begin
            // Jump instruction (JAL or JALR)
            if (id_ex_reg.ctrl.is_jalr)
                ex_branch_target = jump_target_jalr;
            else
                ex_branch_target = jump_target_jal;
        end else if (ex_branch_cond) begin
            // Branch instruction (taken)
            ex_branch_target = pc_ex + id_ex_reg.ctrl.immediate;
        end else begin
            // Sequential execution
            ex_branch_target = 32'h0;
        end
    end
    
    // Control hazard: flush pipeline on branch/jump
    // Branch decision now comes from MEM stage, jumps still in EX
    assign pc_sel_branch = mem_branch_taken || is_jump;
    assign pc_branch_target = is_jump ? ex_branch_target : mem_branch_target;
    
    //==========================================================================
    // EX/MEM PIPELINE REGISTER
    //==========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_reg <= '0;
        end else if (ex_flush) begin
            // Flush - insert bubble
            ex_mem_reg.valid <= 1'b0;
        end else begin
            // Normal progression
            ex_mem_reg.pc            <= pc_ex;
            ex_mem_reg.insn          <= insn_ex;
            ex_mem_reg.alu_result    <= ex_alu_result;
            ex_mem_reg.rs2_data      <= ex_alu_op2;  // Forwarded rs2 for stores
            ex_mem_reg.csr_rdata     <= id_ex_reg.csr_rdata;  // CSR data propagation
            ex_mem_reg.branch_taken  <= ex_branch_cond || is_jump;  // Pipeline branch/jump decision
            ex_mem_reg.branch_target <= ex_branch_target;            // Pipeline target address
            ex_mem_reg.ctrl          <= id_ex_reg.ctrl;
            ex_mem_reg.valid         <= ex_valid;
        end
    end
    
    // MEM stage inputs
    assign pc_mem    = ex_mem_reg.pc;
    assign insn_mem  = ex_mem_reg.insn;
    assign mem_valid = ex_mem_reg.valid;
    
    //==========================================================================
    // MEMORY ACCESS STAGE - BYTE-ADDRESSED MEMORY
    //==========================================================================
    
    assign mem_addr = ex_mem_reg.alu_result;
    assign mem_is_ram = (mem_addr < 32'h0000_2000);  // 0x0000-0x1FFF
    assign mem_is_mmio = (mem_addr >= 32'h0000_4000) && (mem_addr < 32'h0000_8000);
    
    // Word address and byte offset
    logic [9:0]  mem_word_addr;   // Word address within 2048-word RAM
    logic [1:0]  mem_byte_offset; // Byte offset within word (0-3)
    logic [31:0] mem_raw_data;    // Raw 32-bit word from RAM
    logic [31:0] mem_aligned_load;// Byte-aligned load result
    logic [31:0] mem_store_data;  // Store data with byte lane alignment
    logic [3:0]  mem_byte_enable; // Byte write enables
    
    assign mem_word_addr   = mem_addr[12:2];  // Byte address [12:2] = word address
    assign mem_byte_offset = mem_addr[1:0];   // Byte offset [1:0]
    assign ram_addr_mem    = mem_word_addr;
    
    //--------------------------------------------------------------------------
    // LOAD OPERATIONS: Byte Lane Selection and Sign/Zero Extension
    //--------------------------------------------------------------------------
    
    // Data memory read comes from Port A unified read (below in BlockRAM section)
    // ram_rdata_mem is populated by Port A when port_a_is_if=0
    
    assign mem_raw_data = ram_rdata_mem;
    
    // Byte lane extraction based on address offset
    logic [7:0]  load_byte;
    logic [15:0] load_halfword;
    logic [31:0] load_word;
    
    always_comb begin
        // Extract byte based on offset
        case (mem_byte_offset)
            2'b00: load_byte = mem_raw_data[7:0];   // Byte 0
            2'b01: load_byte = mem_raw_data[15:8];  // Byte 1
            2'b10: load_byte = mem_raw_data[23:16]; // Byte 2
            2'b11: load_byte = mem_raw_data[31:24]; // Byte 3
        endcase
        
        // Extract halfword based on offset (must be halfword-aligned)
        case (mem_byte_offset[1])
            1'b0: load_halfword = mem_raw_data[15:0];  // Lower halfword
            1'b1: load_halfword = mem_raw_data[31:16]; // Upper halfword
        endcase
        
        // Word is always the full 32-bit value
        load_word = mem_raw_data;
    end
    
    // Sign/zero extension based on load operation
    always_comb begin
        case (ex_mem_reg.ctrl.mem_width)
            MEM_BYTE: begin
                // Byte load: sign-extend or zero-extend based on mem_sign_ext
                mem_aligned_load = ex_mem_reg.ctrl.mem_sign_ext ? 
                                   {{24{load_byte[7]}}, load_byte} : 
                                   {24'h0, load_byte};
            end
            MEM_HALF: begin
                // Halfword load: sign-extend or zero-extend based on mem_sign_ext
                mem_aligned_load = ex_mem_reg.ctrl.mem_sign_ext ? 
                                   {{16{load_halfword[15]}}, load_halfword} : 
                                   {16'h0, load_halfword};
            end
            MEM_WORD: begin
                // Full word load
                mem_aligned_load = load_word;
            end
            default: mem_aligned_load = mem_raw_data;  // Default to raw data
        endcase
    end
    
    assign mem_load_data = mem_aligned_load;
    
    //--------------------------------------------------------------------------
    // STORE OPERATIONS: Byte Lane Alignment and Write Enable Generation
    //--------------------------------------------------------------------------
    
    // Store data alignment: replicate rs2_data to all byte lanes
    logic [31:0] rs2_replicated;
    assign rs2_replicated = {4{ex_mem_reg.rs2_data[7:0]}}; // Replicate byte to all lanes
    
    // Generate store data and byte enables based on operation
    always_comb begin
        // Default: no write
        mem_store_data  = ex_mem_reg.rs2_data;
        mem_byte_enable = 4'b0000;
        
        if (ex_mem_reg.ctrl.mem_write) begin
            case (ex_mem_reg.ctrl.mem_width)
                MEM_BYTE: begin
                    // Store byte: enable one byte lane
                    mem_store_data = rs2_replicated;
                    case (mem_byte_offset)
                        2'b00: mem_byte_enable = 4'b0001; // Byte 0
                        2'b01: mem_byte_enable = 4'b0010; // Byte 1
                        2'b10: mem_byte_enable = 4'b0100; // Byte 2
                        2'b11: mem_byte_enable = 4'b1000; // Byte 3
                    endcase
                end
                
                MEM_HALF: begin
                    // Store halfword: enable two byte lanes (must be halfword-aligned)
                    mem_store_data = {2{ex_mem_reg.rs2_data[15:0]}}; // Replicate halfword
                    case (mem_byte_offset[1])
                        1'b0: mem_byte_enable = 4'b0011; // Lower halfword
                        1'b1: mem_byte_enable = 4'b1100; // Upper halfword
                    endcase
                end
                
                MEM_WORD: begin
                    // Store word: enable all byte lanes (must be word-aligned)
                    mem_store_data  = ex_mem_reg.rs2_data;
                    mem_byte_enable = 4'b1111;
                end
                
                default: begin
                    mem_store_data  = ex_mem_reg.rs2_data;
                    mem_byte_enable = 4'b0000;
                end
            endcase
        end
    end
    
    //==========================================================================
    // BlockRAM: True-Dual-Port BRAM Inference (UG901 Strict Compliance)
    //==========================================================================
    // CRITICAL UG901 REQUIREMENTS:
    // 1. Exactly 2 physical ports (Port A + Port B)
    // 2. ONE address per port per cycle (no dynamic switching in always_ff)
    // 3. NO reset on read data registers
    // 4. Explicit byte-enable pattern (no for-loops)
    // 5. Static Read-First mode
    //
    // Port A: IF (instruction fetch) - Read-only
    // Port B: MEM/Debug MUTEX - Read/Write
    //   - running==1: MEM uses Port B (ram_addr_mem)
    //   - running==0: Debug uses Port B (dbg_mem_addr)
    //   - NEVER both in same cycle (enforced by running signal)
    //==========================================================================
    
    // Port B unified signals (MEM or Debug, mutually exclusive)
    logic [10:0] port_b_addr;
    logic [31:0] port_b_wdata;
    logic [3:0]  port_b_we;
    logic        port_b_re;
    
    // Port B multiplexer: MEM (running==1) vs Debug (running==0)
    always_comb begin
        if (running) begin
            // MEM active: Use MEM signals
            port_b_addr  = ram_addr_mem;
            port_b_wdata = mem_store_data;
            port_b_we    = (ex_mem_reg.ctrl.mem_write && mem_is_ram) ? mem_byte_enable : 4'b0000;
            port_b_re    = ex_mem_reg.ctrl.mem_read && mem_is_ram;
        end else begin
            // Debug active: Use Debug signals
            port_b_addr  = dbg_mem_addr;
            port_b_wdata = dbg_mem_wdata;
            port_b_we    = dbg_mem_we;
            port_b_re    = dbg_mem_re;
        end
    end
    
    // Port A: Instruction Fetch (IF) - Read Only, NO RESET (UG901)
    always_ff @(posedge clk) begin
        if (ram_ena_a) begin
            ram_rdata_if <= ram[ram_addr_if];
        end
    end
    
    // Port B: MEM/Debug Unified - Read/Write, NO RESET (UG901)
    always_ff @(posedge clk) begin
        if (ram_ena_b) begin
            // WRITE: Explicit byte-enable pattern (UG901 requirement, no for-loop)
            if (port_b_we[0]) ram[port_b_addr][7:0]   <= port_b_wdata[7:0];
            if (port_b_we[1]) ram[port_b_addr][15:8]  <= port_b_wdata[15:8];
            if (port_b_we[2]) ram[port_b_addr][23:16] <= port_b_wdata[23:16];
            if (port_b_we[3]) ram[port_b_addr][31:24] <= port_b_wdata[31:24];
            
            // READ: Read-First mode, NO RESET (UG901 requirement)
            if (port_b_re) begin
                ram_rdata_mem <= ram[port_b_addr];
            end
        end
    end
    
    // Debug read data output (unified with MEM)
    assign dbg_mem_rdata = ram_rdata_mem;
    
    //==========================================================================
    // MEM/WB PIPELINE REGISTER
    //==========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_reg <= '0;
        end else begin
            // Normal progression
            mem_wb_reg.pc     <= pc_mem;
            mem_wb_reg.insn   <= insn_mem;
            
            // Result selection based on writeback source
            case (ex_mem_reg.ctrl.wb_src)
                WB_ALU:  mem_wb_reg.result <= ex_mem_reg.alu_result;     // ALU result
                WB_MEM:  mem_wb_reg.result <= mem_load_data;             // Memory load
                WB_PC4:  mem_wb_reg.result <= pc_mem + 32'd4;            // PC+4 for JAL/JALR
                WB_CSR:  mem_wb_reg.result <= ex_mem_reg.csr_rdata;      // CSR old value
                default: mem_wb_reg.result <= ex_mem_reg.alu_result;
            endcase
            
            mem_wb_reg.rd_addr <= ex_mem_reg.ctrl.rd_addr;
            mem_wb_reg.rf_wen  <= ex_mem_reg.ctrl.rf_wen;
            mem_wb_reg.ctrl    <= ex_mem_reg.ctrl;                       // CSR instruction tracking
            mem_wb_reg.valid   <= mem_valid;
        end
    end
    
    // WB stage inputs
    assign pc_wb    = mem_wb_reg.pc;
    assign insn_wb  = mem_wb_reg.insn;
    assign wb_valid = mem_wb_reg.valid;
    
    //==========================================================================
    // WRITEBACK STAGE
    //==========================================================================
    
    assign wb_result = mem_wb_reg.result;
    
    // Register file write signals
    assign rf_waddr = mem_wb_reg.rd_addr;
    assign rf_wen   = mem_wb_reg.rf_wen && mem_wb_reg.valid;
    assign rf_wdata = wb_result;
    
    //==========================================================================
    // CSR WRITE LOGIC (WB STAGE)
    //==========================================================================
    //
    // CSR write operation:
    // - CSRRW:  wdata = rs1_data (or immediate),  rd = old_csr
    // - CSRRS:  wdata = old_csr | rs1_data,       rd = old_csr (set bits)
    // - CSRRC:  wdata = old_csr & ~rs1_data,      rd = old_csr (clear bits)
    //
    //==========================================================================
    
    logic [31:0] csr_operand;
    logic [31:0] csr_new_value;
    
    // Operand selection: immediate mode vs register mode
    assign csr_operand = mem_wb_reg.ctrl.csr_imm_mode ? 
                         mem_wb_reg.ctrl.immediate : 
                         wb_result;
    
    // CSR write data computation based on operation
    always_comb begin
        case (mem_wb_reg.ctrl.csr_op)
            CSR_RW, CSR_RWI: begin
                // CSRRW/CSRRWI: Write operand directly
                csr_new_value = csr_operand;
            end
            
            CSR_RS, CSR_RSI: begin
                // CSRRS/CSRRSI: Set bits (old_csr | rs1)
                csr_new_value = mem_wb_reg.result | csr_operand;
            end
            
            CSR_RC, CSR_RCI: begin
                // CSRRC/CSRRCI: Clear bits (old_csr & ~rs1)
                csr_new_value = mem_wb_reg.result & ~csr_operand;
            end
            
            default: begin
                csr_new_value = 32'h0;
            end
        endcase
    end
    
    // CSR write enable: valid CSR instruction in WB stage
    assign csr_waddr = mem_wb_reg.ctrl.csr_addr;
    assign csr_wen   = mem_wb_reg.ctrl.is_csr && mem_wb_reg.valid;
    assign csr_wdata = csr_new_value;
    
    //==========================================================================
    // EXCEPTION DETECTION LOGIC (MEM STAGE)
    //==========================================================================
    //
    // Synchronous exceptions detected in MEM stage:
    // - EBREAK: Breakpoint (CAUSE_BREAKPOINT = 3)
    // - ECALL: Environment call (CAUSE_ECALL_M_MODE = 11)
    // - Illegal instruction: Invalid opcode/encoding (CAUSE_ILLEGAL_INSN = 2)
    // - Instruction misalignment: PC[1:0] != 00 (CAUSE_INSN_MISALIGN = 0)
    // - Load misalignment: LH/LW unaligned (CAUSE_LOAD_MISALIGN = 4)
    // - Store misalignment: SH/SW unaligned (CAUSE_STORE_MISALIGN = 6)
    //
    //==========================================================================
    
    logic exception_ebreak;
    logic exception_ecall;
    logic exception_illegal_insn;
    logic exception_insn_misalign;
    logic exception_load_misalign;
    logic exception_store_misalign;
    
    // EBREAK detection (MEM stage)
    assign exception_ebreak = ex_mem_reg.valid && ex_mem_reg.ctrl.is_ebreak;
    
    // ECALL detection (MEM stage)
    assign exception_ecall = ex_mem_reg.valid && ex_mem_reg.ctrl.is_ecall;
    
    // Illegal instruction detection (MEM stage)
    assign exception_illegal_insn = ex_mem_reg.valid && ex_mem_reg.ctrl.illegal;
    
    // Instruction misalignment detection (IF stage - checked during fetch)
    assign exception_insn_misalign = if_valid && (pc_if[1:0] != 2'b00);
    
    // Load misalignment detection (MEM stage)
    assign exception_load_misalign = ex_mem_reg.valid && ex_mem_reg.ctrl.mem_read &&
        ((ex_mem_reg.ctrl.mem_width == MEM_HALF && mem_addr[0] != 1'b0) ||
         (ex_mem_reg.ctrl.mem_width == MEM_WORD && mem_addr[1:0] != 2'b00));
    
    // Store misalignment detection (MEM stage)
    assign exception_store_misalign = ex_mem_reg.valid && ex_mem_reg.ctrl.mem_write &&
        ((ex_mem_reg.ctrl.mem_width == MEM_HALF && mem_addr[0] != 1'b0) ||
         (ex_mem_reg.ctrl.mem_width == MEM_WORD && mem_addr[1:0] != 2'b00));
    
    //==========================================================================
    // EXCEPTION PRIORITY ENCODER (RISC-V Spec Table 3.7)
    //==========================================================================
    //
    // Priority order (highest to lowest):
    // 1. Instruction misalignment (during fetch)
    // 2. Illegal instruction (during decode/execute)
    // 3. Breakpoint (EBREAK)
    // 4. Load address misaligned
    // 5. Store address misaligned
    // 6. Environment call (ECALL)
    //
    // Exception trap outputs:
    // - exception_trap: 1-cycle pulse when exception occurs
    // - exception_pc: PC of faulting instruction (saved to mepc)
    // - exception_code: Cause code (saved to mcause[4:0])
    // - exception_tval: Trap value - faulting address or instruction (saved to mtval)
    //
    //==========================================================================
    
    // Debug mode control: When enabled, EBREAK halts CPU instead of trapping
    logic debug_mode_enable;
    assign debug_mode_enable = 1'b1;  // Default: Debug mode enabled for backward compatibility
    
    always_comb begin
        // Default: no exception
        exception_trap = 1'b0;
        exception_code = 5'h0;
        exception_pc   = 32'h0;
        exception_tval = 32'h0;
        
        // Priority 1: Instruction misalignment (highest priority for fetch exceptions)
        if (exception_insn_misalign) begin
            exception_trap = 1'b1;
            exception_code = CAUSE_INSN_MISALIGN;  // 0
            exception_pc   = pc_if;
            exception_tval = pc_if;  // Faulting PC address
        end
        
        // Priority 2: Illegal instruction
        else if (exception_illegal_insn) begin
            exception_trap = 1'b1;
            exception_code = CAUSE_ILLEGAL_INSN;  // 2
            exception_pc   = pc_mem;
            exception_tval = insn_mem;  // Faulting instruction encoding
        end
        
        // Priority 3: Breakpoint (EBREAK)
        // Only trap if debug mode is disabled; otherwise handled by debug state machine
        else if (exception_ebreak && !debug_mode_enable) begin
            exception_trap = 1'b1;
            exception_code = CAUSE_BREAKPOINT;  // 3
            exception_pc   = pc_mem;
            exception_tval = 32'h0;
        end
        
        // Priority 4: Load misalignment
        else if (exception_load_misalign) begin
            exception_trap = 1'b1;
            exception_code = CAUSE_LOAD_MISALIGN;  // 4
            exception_pc   = pc_mem;
            exception_tval = mem_addr;  // Faulting memory address
        end
        
        // Priority 5: Store misalignment
        else if (exception_store_misalign) begin
            exception_trap = 1'b1;
            exception_code = CAUSE_STORE_MISALIGN;  // 6
            exception_pc   = pc_mem;
            exception_tval = mem_addr;  // Faulting memory address
        end
        
        // Priority 6: Environment call (ECALL)
        else if (exception_ecall) begin
            exception_trap = 1'b1;
            exception_code = CAUSE_ECALL_M_MODE;  // 11
            exception_pc   = pc_mem;
            exception_tval = 32'h0;
        end
    end
    
    //==========================================================================
    // MRET (Machine Return) DETECTION & CONTROL
    //==========================================================================
    //
    // MRET instruction returns from trap handler to interrupted code:
    // - Detected in MEM stage (parallel to EBREAK/ECALL)
    // - Reads return address from mepc CSR (via mret_pc signal)
    // - Redirects PC to mepc value
    // - Flushes pipeline to prevent speculative execution
    //
    //==========================================================================
    
    logic mret_detected;
    assign mret_detected = ex_mem_reg.valid && ex_mem_reg.ctrl.is_mret;
    
    // Drive mret_req signal to CSR module
    assign mret_req = mret_detected;
    
    // Debug CSR interface (optional - not driven yet)
    assign dbg_csr_addr_int = 12'h0;
    
    //==========================================================================
    // HAZARD DETECTION & FORWARDING
    //==========================================================================
    
    // RAW (Read-After-Write) hazard detection:
    // - Occurs when an instruction reads a register that a previous instruction writes
    // - Forwarding paths: EX→EX, MEM→EX, WB→EX (priority: EX > MEM > WB)
    // - Forwarding control pre-computed in ID stage (Phase 2B optimization)
    // - Load-use hazard: Special case requiring 1-cycle stall (load result not ready)
    
    logic ex_is_load;     // EX stage is a load instruction
    
    // Detect if EX stage is a load (result not ready until MEM stage)
    assign ex_is_load = id_ex_reg.ctrl.mem_read && id_ex_reg.valid;
    
    //--------------------------------------------------------------------------
    // LOAD-USE HAZARD DETECTION
    //--------------------------------------------------------------------------
    // Load-use hazard: ID stage reads register that EX stage is loading
    // - Cannot forward load result before MEM stage completes
    // - Solution: Stall pipeline for 1 cycle (insert bubble in EX stage)
    
    logic load_use_rs1;  // rs1 has load-use hazard
    logic load_use_rs2;  // rs2 has load-use hazard
    
    assign load_use_rs1 = ex_is_load && (id_ex_reg.ctrl.rd_addr != 5'b0) && 
                          (id_ex_reg.ctrl.rd_addr == id_ctrl.rs1_addr);
    
    assign load_use_rs2 = ex_is_load && (id_ex_reg.ctrl.rd_addr != 5'b0) && 
                          (id_ex_reg.ctrl.rd_addr == id_ctrl.rs2_addr);
    
    assign hazard_load_use = load_use_rs1 || load_use_rs2;
    
    //==========================================================================
    // PIPELINE CONTROL
    //==========================================================================
    // True Dual-Port BlockRAM: Port A (IF) and Port B (MEM) operate independently
    // No serialization needed - both can access RAM simultaneously
    
    assign if_valid = running && !cpu_halt && (!bp_match || bp_skip_once);
    // IF stage stall on breakpoint or hazards
    // Stall on breakpoint match to prevent new instruction fetch while preserving pipeline
    assign if_stall = hazard_load_use || (bp_match && running && !bp_skip_once);
    assign id_stall = hazard_load_use;
    
    // Breakpoint handling: Don't flush pipeline on breakpoint
    // Instead, stall IF stage to preserve instruction in pipeline
    // When resumed, instruction continues from where it was
    logic bp_flush;
    assign bp_flush = 1'b0;  // Never flush on breakpoint - preserve pipeline state
    
    // Pipeline flush control: Flush on branch/jump OR exception trap OR MRET
    // - Exception flushes all stages to prevent committed side effects
    // - MRET flushes to start fresh execution at return address
    assign if_flush = pc_sel_branch || exception_trap || mret_detected;
    assign id_flush = pc_sel_branch || exception_trap || mret_detected;
    assign ex_flush = exception_trap || mret_detected;  // Flush EX on exception/MRET
    
    //==========================================================================
    // DEBUG CONTROL
    //==========================================================================
    
    // EBREAK/ECALL detection: Check if MEM stage is executing these instructions
    // Note: ebreak_detected is used for debug halt (when debug_mode_enable=1)
    //       Exception trap path is separate (controlled by exception_ebreak signal)
    logic ebreak_detected;
    logic ecall_detected;
    
    assign ebreak_detected = ex_mem_reg.valid && ex_mem_reg.ctrl.is_ebreak;
    assign ecall_detected  = ex_mem_reg.valid && ex_mem_reg.ctrl.is_ecall;
    
    // Debug state machine with hardware breakpoint, single-step, and soft reset support
    logic cpu_break_reg;  // Latched breakpoint signal
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || soft_reset_active) begin
            running <= 1'b0;
            cpu_halted <= 1'b1;
            cpu_break_reg <= 1'b0;
            step_mode <= 1'b0;
            step_done <= 1'b0;
            bp_hit_reg <= 4'h0;
            bp_skip_once <= 1'b0;
            bp_just_resumed <= 1'b0;
        end else begin
            // Clear skip flag one cycle after resuming (when bp_just_resumed is set)
            if (bp_just_resumed && running) begin
                bp_skip_once <= 1'b0;
                bp_just_resumed <= 1'b0;
            end
            
            // Hardware breakpoint detection - halt on PC match (unless skipping)
            if (bp_match && running && !step_mode && !bp_skip_once) begin
                running <= 1'b0;
                cpu_halted <= 1'b1;
                cpu_break_reg <= 1'b1;  // Set break signal for hardware breakpoint
                // Record which breakpoint(s) hit
                for (int i = 0; i < 4; i++) begin
                    if (dbg_bp_enable[i] && (pc_if == dbg_bp_addr[i])) begin
                        bp_hit_reg[i] <= 1'b1;
                    end
                end
            end
            // Single-step mode - execute one instruction then halt
            else if (cpu_step && cpu_halted) begin
                step_mode <= 1'b1;
                step_done <= 1'b0;
                running <= 1'b1;
                cpu_halted <= 1'b0;
                bp_skip_once <= 1'b0;  // Don't skip breakpoints in single-step mode
            end else if (step_mode && wb_valid) begin
                // One instruction committed in WB stage - halt
                step_mode <= 1'b0;
                step_done <= 1'b1;
                running <= 1'b0;
                cpu_halted <= 1'b1;
            end
            // Normal run/halt control
            else if (cpu_run) begin
                // Start/resume execution - set skip flag if resuming from breakpoint
                running <= 1'b1;
                cpu_halted <= 1'b0;
                cpu_break_reg <= 1'b0;
                step_done <= 1'b0;
                // If resuming from breakpoint (bp_hit_reg != 0), skip breakpoint check for one instruction
                bp_skip_once <= (bp_hit_reg != 4'h0) ? 1'b1 : 1'b0;
                bp_just_resumed <= (bp_hit_reg != 4'h0) ? 1'b1 : 1'b0;  // Mark that we're resuming
                bp_hit_reg <= 4'h0;  // Clear breakpoint hit flags
            end else if (cpu_halt || ebreak_detected) begin
                // Halt on external request or EBREAK instruction
                running <= 1'b0;
                cpu_halted <= 1'b1;
                bp_skip_once <= 1'b0;
                if (ebreak_detected) begin
                    cpu_break_reg <= 1'b1;  // Latch break signal
                end
            end else if (ecall_detected) begin
                // ECALL: System call (could halt or continue based on policy)
                // For now, treat as NOP (continue execution)
                // Future: Implement system call handler
            end
        end
    end
    
    // Breakpoint signals: Persist until cleared by cpu_run
    assign cpu_break = cpu_break_reg;
    assign dbg_bp_hit = bp_hit_reg;
    
    //==========================================================================
    // PERFORMANCE COUNTERS
    //==========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || soft_reset_active) begin
            cycle_counter <= 32'h0;
            insn_counter  <= 32'h0;
            stall_counter <= 32'h0;
            flush_counter <= 32'h0;
        end else if (running) begin
            // Count cycles when CPU is running
            cycle_counter <= cycle_counter + 32'd1;
            
            // Count committed instructions (WB stage)
            if (wb_valid) begin
                insn_counter <= insn_counter + 32'd1;
            end
            
            // Count pipeline stalls (IF or ID stall)
            if (if_stall || id_stall) begin
                stall_counter <= stall_counter + 32'd1;
            end
            
            // Count pipeline flushes (branch/jump taken)
            if (if_flush || id_flush || ex_flush) begin
                flush_counter <= flush_counter + 32'd1;
            end
        end
    end
    
    assign perf_cycle_count = cycle_counter;
    assign perf_insn_count  = insn_counter;
    assign perf_stall_count = stall_counter;
    assign perf_flush_count = flush_counter;
    
    //==========================================================================
    // REGISTER FILE SNAPSHOT (Debug Read)
    //==========================================================================
    // Combinational read of any register when CPU is halted
    
    always_comb begin
        if (dbg_rf_addr == 5'b0) begin
            dbg_rf_rdata = 32'h0;  // x0 always reads as zero
        end else begin
            dbg_rf_rdata = regfile[dbg_rf_addr];
        end
    end
    
    //==========================================================================
    // SOFTWARE RESET CONTROL
    //==========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            soft_reset_active <= 1'b0;
            reset_done_reg <= 1'b0;
        end else begin
            if (dbg_soft_reset && !soft_reset_active) begin
                // Trigger soft reset for one cycle
                soft_reset_active <= 1'b1;
                reset_done_reg <= 1'b0;
            end else if (soft_reset_active) begin
                // Deassert soft reset, set done flag
                soft_reset_active <= 1'b0;
                reset_done_reg <= 1'b1;
            end else if (!dbg_soft_reset) begin
                // Clear done flag when reset request is deasserted
                reset_done_reg <= 1'b0;
            end
        end
    end
    
    assign dbg_reset_done = reset_done_reg;
    
    //==========================================================================
    // MMIO - LED REGISTER
    //==========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led_reg <= 4'h0;
        end else if (ex_mem_reg.ctrl.mem_write && (mem_addr == 32'h0000_407C)) begin
            // LED register at byte address 0x407C
            led_reg <= ex_mem_reg.rs2_data[3:0];
        end
    end
    
    //==========================================================================
    // TRACE BUFFER OUTPUT
    //==========================================================================
    
    assign trace_valid   = wb_valid;
    assign trace_pc      = pc_wb;
    assign trace_insn    = insn_wb;
    assign trace_rd_addr = mem_wb_reg.rd_addr;
    assign trace_rd_data = wb_result;
    
    //==========================================================================
    // TRACE BUFFER INSTANTIATION
    //==========================================================================
    // 64-entry trace buffer with UVM and UART hardware access interfaces
    
    Rv32i_Trace_Buffer #(
        .DEPTH(64)
    ) u_trace_buffer (
        .clk           (clk),
        .rst_n         (rst_n && !soft_reset_active),  // Reset on hardware or software reset
        
        // CPU trace inputs (WB stage)
        .insn_valid    (trace_valid),
        .insn          (trace_insn),
        .pc            (trace_pc),
        .rd_addr       (trace_rd_addr),
        .rd_value      (trace_rd_data),
        
        // Hardware debug read interface (UART accessible via Register_Block)
        .dbg_read_addr (dbg_trace_addr),
        .dbg_read_data (dbg_trace_data),
        .dbg_write_ptr (dbg_trace_wptr),
        .dbg_entry_count(dbg_trace_count),
        
        // UVM direct access interface (simulation only)
        .trace_buffer  (),  // Not connected - UVM uses hierarchical access
        .write_ptr     (),  // Not connected
        .entry_count   ()   // Not connected
    );
    
    //==========================================================================
    // RAM INITIALIZATION
    //==========================================================================
    // RAM Initialization (Simulation Only)
    // For synthesis: initial blocks ignored, RAM has undefined values at power-on
    // For simulation: Testbench loads program via $readmemh
    // CRITICAL: No zero-fill loop here to avoid race with testbench $readmemh
    //==========================================================================

endmodule : rv32i_core
