`timescale 1ns / 1ps

//==============================================================================
// RV32I Instruction Fetch (IF) Stage Module
//==============================================================================
// Combinational logic for PC management, breakpoint detection, and instruction
// fetch control. All sequential logic (PC register, IF/ID register) resides
// in rv32i_top.sv.
//
// See: rtl/cpu/rv32i_if_spec.md for detailed specification
//==============================================================================

module rv32i_if
    import rv32i_isa_pkg::*;
(
    // Current PC (input from IF/ID pipeline register in top)
    input  logic [31:0] pc_current,
    input  logic        if_valid,
    
    // Stall and flush control
    input  logic        if_stall,
    input  logic        if_flush,
    
    // Branch/Jump control (from EX stage)
    input  logic        branch_taken,
    input  logic [31:0] branch_target,
    
    // Exception/MRET control (from MEM/CSR)
    input  logic        exception_trap,
    input  logic [31:0] trap_vector,
    input  logic        mret_req,
    input  logic [31:0] mret_pc,
    
    // Instruction RAM interface (Port A)
    output logic [10:0] insn_ram_addr,    // Word address [10:0] for 8KB (2048 words)
    input  logic [31:0] insn_ram_rdata,
    
    // Hardware breakpoint interface
    input  logic [3:0]  dbg_bp_enable,
    input  logic [31:0] dbg_bp_addr[4],
    output logic [3:0]  dbg_bp_hit,
    output logic        cpu_break,
    
    // CPU control
    input  logic        running,          // CPU is running (not halted)
    input  logic        cpu_run,          // Start/resume signal
    input  logic        cpu_halted,       // CPU halted status
    
    // Skip breakpoint once (for resume from breakpoint)
    input  logic        bp_skip_once,
    output logic        bp_match,
    
    // PC output for next stage
    output logic [31:0] pc_next,
    output logic [31:0] pc_out,
    output logic [31:0] insn_out,
    output logic        valid_out
);

    //==========================================================================
    // Breakpoint Detection Logic
    //==========================================================================
    // Detect if current PC matches any enabled breakpoint
    // bp_match is used to halt CPU when breakpoint is hit
    
    always_comb begin
        bp_match = 1'b0;
        for (int i = 0; i < 4; i++) begin
            if (dbg_bp_enable[i] && (pc_current == dbg_bp_addr[i]) && running) begin
                bp_match = 1'b1;
            end
        end
    end
    
    // Individual breakpoint hit flags (latched in top module)
    always_comb begin
        for (int i = 0; i < 4; i++) begin
            dbg_bp_hit[i] = dbg_bp_enable[i] && (pc_current == dbg_bp_addr[i]) && running;
        end
    end
    
    // CPU break signal (for external monitoring)
    assign cpu_break = bp_match && !bp_skip_once;
    
    //==========================================================================
    // PC Next-Value Logic
    //==========================================================================
    // Priority (highest to lowest):
    // 1. Exception trap → trap_vector (from mtvec CSR)
    // 2. MRET → mret_pc (from mepc CSR)
    // 3. Branch/Jump taken → branch_target
    // 4. Sequential → PC + 4
    // 5. Stall → hold current PC
    
    always_comb begin
        if (exception_trap) begin
            // Exception trap: Redirect to trap handler (highest priority)
            pc_next = trap_vector;
        end else if (mret_req) begin
            // MRET: Return from trap handler (second priority)
            pc_next = mret_pc;
        end else if (branch_taken) begin
            // Branch or jump taken - use target address
            pc_next = branch_target;
        end else if (!if_stall) begin
            // Sequential execution - increment by 4 (byte addressing)
            pc_next = pc_current + 32'd4;
        end else begin
            // Stall - hold current PC
            pc_next = pc_current;
        end
    end
    
    //==========================================================================
    // Instruction RAM Address Generation
    //==========================================================================
    // Convert byte address to word address for Block RAM
    // PC is byte-addressed, RAM is word-addressed (32-bit words)
    // Address range: 0x0000 - 0x1FFF (8KB) → word address [10:0]
    
    assign insn_ram_addr = pc_current[12:2];  // [12:2] = divide by 4 for word address
    
    //==========================================================================
    // IF Stage Outputs
    //==========================================================================
    // Pass PC and instruction to IF/ID pipeline register (registered in top)
    
    assign pc_out   = pc_current;
    assign insn_out = insn_ram_rdata;
    assign valid_out = if_valid && !if_flush && running && (!bp_match || bp_skip_once);
    
endmodule : rv32i_if
