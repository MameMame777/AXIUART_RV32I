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
    input  logic        cpu_step,       // Single-step execution
    output logic        cpu_halted,     // CPU halted status
    output logic        cpu_break,      // Breakpoint hit (EBREAK)
    
    // Debug memory interface (Port B - external access when CPU halted)
    input  logic [10:0] dbg_mem_addr,   // Word address for debug access
    input  logic [31:0] dbg_mem_wdata,  // Write data
    output logic [31:0] dbg_mem_rdata,  // Read data
    input  logic [3:0]  dbg_mem_we,     // Byte write enables (active when cpu_halted)
    input  logic        dbg_mem_re,     // Read enable
    
    // MMIO interface (LED register)
    output logic [3:0]  led_out,
    
    // Trace buffer interface
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
    
    // Internal RAM (2048 x 32-bit = 8KB) - True Dual-Port
    // Port A: CPU instruction fetch (IF) + data access (MEM)
    // Port B: Debug/external access via dbg_mem_* (when CPU halted)
    (* ram_style = "block" *)
    (* rw_addr_collision = "no" *)  // Avoid collision warnings (Port B has priority)
    logic [31:0] ram [0:2047];
    
    // Port A - CPU access
    logic [10:0] ram_addr_if;   // Word address for instruction fetch
    logic [10:0] ram_addr_mem;  // Word address for data access
    logic        ram_we_mem;
    logic [31:0] ram_wdata_mem;
    logic [31:0] ram_rdata_if;
    logic [31:0] ram_rdata_mem;
    logic [3:0]  ram_we_byte;   // Byte write enable for SB/SH/SW
    
    // Port B - Debug access (registered read, priority write)
    logic [31:0] dbg_mem_rdata_reg;
    
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
        logic [31:0] result;        // ALU result or memory data
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
    logic        ex_branch_taken;
    logic [31:0] ex_branch_target;
    
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
    // INSTRUCTION MEMORY (Dual-Port Block RAM)
    //==========================================================================
    // Port A: CPU instruction fetch + data access
    // Port B: Debug/external access (priority over Port A writes)
    //==========================================================================
    
    // Word address calculation (byte address [31:2] = word address)
    assign ram_addr_if = pc_if[12:2];  // IF stage fetch
    
    // Port A - Instruction Fetch (registered read, 1-cycle latency)
    always_ff @(posedge clk) begin
        if (!if_stall) begin
            ram_rdata_if <= ram[ram_addr_if];
        end
    end
    
    assign insn_if = ram_rdata_if;
    
    //==========================================================================
    // PROGRAM COUNTER MANAGEMENT
    //==========================================================================
    
    // PC next-value logic
    always_comb begin
        if (pc_sel_branch) begin
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
        end else if (running && !cpu_halt) begin
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
    // ID/EX PIPELINE REGISTER
    //==========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_reg <= '0;
        end else if (id_flush) begin
            // Flush - insert bubble
            id_ex_reg.valid <= 1'b0;
        end else if (!id_stall) begin
            // Normal progression
            id_ex_reg.pc       <= pc_id;
            id_ex_reg.insn     <= insn_id;
            id_ex_reg.rs1_data <= rf_rdata1;
            id_ex_reg.rs2_data <= rf_rdata2;
            id_ex_reg.ctrl     <= id_ctrl;
            id_ex_reg.valid    <= id_valid;
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
    
    // Forwarding multiplexers for rs1 and rs2
    always_comb begin
        case (forward_rs1)
            2'b00:   ex_rs1_forwarded = id_ex_reg.rs1_data;
            2'b01:   ex_rs1_forwarded = ex_mem_reg.alu_result;
            2'b10:   ex_rs1_forwarded = mem_wb_reg.result;
            default: ex_rs1_forwarded = id_ex_reg.rs1_data;
        endcase
        
        case (forward_rs2)
            2'b00:   ex_rs2_forwarded = id_ex_reg.rs2_data;
            2'b01:   ex_rs2_forwarded = ex_mem_reg.alu_result;
            2'b10:   ex_rs2_forwarded = mem_wb_reg.result;
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
    
    // Adder/Subtractor
    logic [32:0] add_sub_temp;  // Extra bit for carry
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
    
    // Branch taken signal
    assign ex_branch_taken = id_ex_reg.ctrl.is_branch && branch_condition_met && ex_valid;
    
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
    
    // Branch/jump target selection
    always_comb begin
        if (is_jump) begin
            // Jump instruction (JAL or JALR)
            if (id_ex_reg.ctrl.is_jalr)
                ex_branch_target = jump_target_jalr;
            else
                ex_branch_target = jump_target_jal;
        end else if (ex_branch_taken) begin
            // Branch instruction (taken)
            ex_branch_target = pc_ex + id_ex_reg.ctrl.immediate;
        end else begin
            // Sequential execution
            ex_branch_target = 32'h0;
        end
    end
    
    // Control hazard: flush pipeline on branch/jump
    assign pc_sel_branch = ex_branch_taken || is_jump;
    assign pc_branch_target = ex_branch_target;
    
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
            ex_mem_reg.pc         <= pc_ex;
            ex_mem_reg.insn       <= insn_ex;
            ex_mem_reg.alu_result <= ex_alu_result;
            ex_mem_reg.rs2_data   <= ex_alu_op2;  // Forwarded rs2 for stores
            ex_mem_reg.ctrl       <= id_ex_reg.ctrl;
            ex_mem_reg.valid      <= ex_valid;
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
    
    // Data memory read (registered)
    always_ff @(posedge clk) begin
        if (ex_mem_reg.ctrl.mem_read) begin
            mem_raw_data <= ram[ram_addr_mem];
        end
    end
    
    assign ram_rdata_mem = mem_raw_data;  // Keep for debug
    
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
    
    // Port A - Data Memory Write (CPU MEM stage) with byte enables
    // Port B has priority: if both write same address, Port B wins
    always_ff @(posedge clk) begin
        // Port B write (debug access - only when CPU halted, but logic allows override)
        if (|dbg_mem_we) begin
            // Port B write with byte enables (priority over Port A)
            if (dbg_mem_we[0]) ram[dbg_mem_addr][7:0]   <= dbg_mem_wdata[7:0];
            if (dbg_mem_we[1]) ram[dbg_mem_addr][15:8]  <= dbg_mem_wdata[15:8];
            if (dbg_mem_we[2]) ram[dbg_mem_addr][23:16] <= dbg_mem_wdata[23:16];
            if (dbg_mem_we[3]) ram[dbg_mem_addr][31:24] <= dbg_mem_wdata[31:24];
        end
        // Port A write (CPU data access) - only if Port B not writing same address
        else if (ex_mem_reg.ctrl.mem_write && mem_is_ram) begin
            // Write only enabled byte lanes
            if (mem_byte_enable[0]) ram[ram_addr_mem][7:0]   <= mem_store_data[7:0];
            if (mem_byte_enable[1]) ram[ram_addr_mem][15:8]  <= mem_store_data[15:8];
            if (mem_byte_enable[2]) ram[ram_addr_mem][23:16] <= mem_store_data[23:16];
            if (mem_byte_enable[3]) ram[ram_addr_mem][31:24] <= mem_store_data[31:24];
        end
    end
    
    // Port B - Debug Memory Read (registered, 1-cycle latency)
    always_ff @(posedge clk) begin
        if (dbg_mem_re) begin
            dbg_mem_rdata_reg <= ram[dbg_mem_addr];
        end
    end
    
    assign dbg_mem_rdata = dbg_mem_rdata_reg;
    
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
                default: mem_wb_reg.result <= ex_mem_reg.alu_result;
            endcase
            
            mem_wb_reg.rd_addr <= ex_mem_reg.ctrl.rd_addr;
            mem_wb_reg.rf_wen  <= ex_mem_reg.ctrl.rf_wen;
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
    // HAZARD DETECTION & FORWARDING
    //==========================================================================
    
    // RAW (Read-After-Write) hazard detection:
    // - Occurs when an instruction reads a register that a previous instruction writes
    // - Forwarding paths: EX→EX, MEM→EX, WB→EX (priority: EX > MEM > WB)
    // - Load-use hazard: Special case requiring 1-cycle stall (load result not ready)
    
    logic ex_writes_rd;   // EX stage writes to rd
    logic mem_writes_rd;  // MEM stage writes to rd
    logic wb_writes_rd;   // WB stage writes to rd
    logic ex_is_load;     // EX stage is a load instruction
    
    // Detect if pipeline stages write to registers
    assign ex_writes_rd  = id_ex_reg.ctrl.rf_wen && (id_ex_reg.ctrl.rd_addr != 5'b0) && id_ex_reg.valid;
    assign mem_writes_rd = ex_mem_reg.ctrl.rf_wen && (ex_mem_reg.ctrl.rd_addr != 5'b0) && ex_mem_reg.valid;
    assign wb_writes_rd  = mem_wb_reg.rf_wen && (mem_wb_reg.rd_addr != 5'b0) && mem_wb_reg.valid;
    
    // Detect if EX stage is a load (result not ready until MEM stage)
    assign ex_is_load = id_ex_reg.ctrl.mem_read && id_ex_reg.valid;
    
    //--------------------------------------------------------------------------
    // FORWARDING LOGIC FOR RS1
    //--------------------------------------------------------------------------
    // Priority: EX stage > MEM stage > WB stage > Register File
    
    always_comb begin
        forward_rs1 = 2'b00;  // Default: use register file
        
        // Check if EX stage reads rs1 (rs1_addr != 0)
        if (id_ex_reg.ctrl.rs1_addr != 5'b0) begin
            // Check WB stage (lowest priority)
            if (wb_writes_rd && (mem_wb_reg.rd_addr == id_ex_reg.ctrl.rs1_addr)) begin
                forward_rs1 = 2'b10;  // Forward from WB (mem_wb_reg.result)
            end
            
            // Check MEM stage (medium priority) - result ready in MEM
            if (mem_writes_rd && (ex_mem_reg.ctrl.rd_addr == id_ex_reg.ctrl.rs1_addr)) begin
                forward_rs1 = 2'b01;  // Forward from MEM (ex_mem_reg.alu_result)
            end
            
            // Check EX stage (highest priority) - result ready in MEM next cycle
            if (ex_writes_rd && (id_ex_reg.ctrl.rd_addr == id_ex_reg.ctrl.rs1_addr)) begin
                forward_rs1 = 2'b01;  // Forward from MEM (ex_mem_reg in next cycle)
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // FORWARDING LOGIC FOR RS2
    //--------------------------------------------------------------------------
    // Same priority as rs1: EX > MEM > WB > RF
    
    always_comb begin
        forward_rs2 = 2'b00;  // Default: use register file
        
        // Check if EX stage reads rs2 (rs2_addr != 0)
        if (id_ex_reg.ctrl.rs2_addr != 5'b0) begin
            // Check WB stage (lowest priority)
            if (wb_writes_rd && (mem_wb_reg.rd_addr == id_ex_reg.ctrl.rs2_addr)) begin
                forward_rs2 = 2'b10;  // Forward from WB (mem_wb_reg.result)
            end
            
            // Check MEM stage (medium priority) - result ready in MEM
            if (mem_writes_rd && (ex_mem_reg.ctrl.rd_addr == id_ex_reg.ctrl.rs2_addr)) begin
                forward_rs2 = 2'b01;  // Forward from MEM (ex_mem_reg.alu_result)
            end
            
            // Check EX stage (highest priority) - result ready in MEM next cycle
            if (ex_writes_rd && (id_ex_reg.ctrl.rd_addr == id_ex_reg.ctrl.rs2_addr)) begin
                forward_rs2 = 2'b01;  // Forward from MEM (ex_mem_reg in next cycle)
            end
        end
    end
    
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
    // PIPELINE CONTROL - PLACEHOLDER
    //==========================================================================
    
    assign if_valid = running && !cpu_halt;
    assign if_stall = hazard_load_use;
    assign id_stall = hazard_load_use;
    assign if_flush = pc_sel_branch;  // Flush on branch/jump
    assign id_flush = pc_sel_branch;
    assign ex_flush = 1'b0;
    
    //==========================================================================
    // DEBUG CONTROL
    //==========================================================================
    
    // EBREAK detection: Check if MEM stage is executing EBREAK instruction
    logic ebreak_detected;
    logic ecall_detected;
    
    assign ebreak_detected = ex_mem_reg.valid && ex_mem_reg.ctrl.is_ebreak;
    assign ecall_detected  = ex_mem_reg.valid && ex_mem_reg.ctrl.is_ecall;
    
    // Debug state machine
    logic cpu_break_reg;  // Latched breakpoint signal
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running <= 1'b0;
            cpu_halted <= 1'b1;
            cpu_break_reg <= 1'b0;
        end else begin
            if (cpu_run) begin
                // Start/resume execution - clear break
                running <= 1'b1;
                cpu_halted <= 1'b0;
                cpu_break_reg <= 1'b0;
            end else if (cpu_halt || ebreak_detected) begin
                // Halt on external request or EBREAK instruction
                running <= 1'b0;
                cpu_halted <= 1'b1;
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
    
    // Breakpoint signal: Persists until cleared by cpu_run
    assign cpu_break = cpu_break_reg;
    
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
    // RAM INITIALIZATION
    //==========================================================================
    // RAM Initialization (Simulation Only)
    // For synthesis: initial blocks ignored, RAM has undefined values at power-on
    // For simulation: Testbench loads program via $readmemh
    // CRITICAL: No zero-fill loop here to avoid race with testbench $readmemh
    //==========================================================================

endmodule : rv32i_core
