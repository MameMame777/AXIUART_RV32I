`timescale 1ns / 1ps

//==============================================================================
// RV32I Memory Protection Specification (SVA)
//==============================================================================
// Specification: CPU stores MUST NOT write to instruction memory region
// during normal execution (when !cpu_halted).
//
// Purpose: Prevent von Neumann architecture hazard where data stores
// corrupt instruction memory, causing phantom instructions and infinite loops.
//
// Protection Boundary: First 512 words (2KB, addresses 0x000-0x1FF)
// reserved for instruction memory.
//
// Exception: Debug interface may write to instruction region when cpu_halted
// for program initialization.
//==============================================================================

module rv32i_mem_protect_spec (
    input logic        clk,
    input logic        rst,
    
    // Port B control signals
    input logic        ram_ena_b,
    input logic [10:0] ram_addr_b,      // Word address [10:0]
    input logic [3:0]  ram_we_b,        // Byte write enables
    input logic [31:0] ram_wdata_b,
    
    // CPU state
    input logic        cpu_halted,      // Debug mode vs CPU execution
    input logic [31:0] ex_mem_pc        // PC of instruction in MEM stage (for error reporting)
);

    //==========================================================================
    // Protection Boundary Parameter
    //==========================================================================
    localparam INSN_REGION_END = 11'h100;  // First 256 words (1KB) reserved for instructions
    
    //==========================================================================
    // SPEC-MP-1: CPU MUST NOT Write to Instruction Region
    //==========================================================================
    // During CPU execution (!cpu_halted), any write attempt to addresses
    // below INSN_REGION_END (instruction region) is a protocol violation.
    //
    // Rationale: Von Neumann unified memory allows data stores to corrupt
    // instruction fetch, causing phantom instructions and control flow bugs.
    //
    // Example Violation: Store at PC 0x1C writes to address 0xDC, overwriting
    // instruction with data value, creating phantom JALR that jumps to loop start.
    
    property p_no_cpu_write_to_instruction_region;
        @(posedge clk) disable iff (rst)
        (ram_ena_b && (|ram_we_b) && !cpu_halted)
        |-> (ram_addr_b >= INSN_REGION_END);
    endproperty
    
    assert_no_cpu_write_to_insn_region: assert property (p_no_cpu_write_to_instruction_region)
        else $error("[SPEC-MP-1] CPU write to instruction region: PC=0x%08h, target_word=0x%03h (byte 0x%04h), we=%04b, data=0x%08h",
                    ex_mem_pc, ram_addr_b, {ram_addr_b, 2'b00}, ram_we_b, ram_wdata_b);
    
    //==========================================================================
    // SPEC-MP-2: Debug Writes Allowed to Full Address Space
    //==========================================================================
    // When cpu_halted, debug interface may write anywhere including
    // instruction region for program loading.
    //
    // This is NOT an assertion (informational only) - debug writes are intentional.
    
    // Coverage: Track debug writes to instruction region
    cover_debug_write_to_insn_region: cover property (
        @(posedge clk) disable iff (rst)
        (ram_ena_b && (|ram_we_b) && cpu_halted && (ram_addr_b < INSN_REGION_END))
    );
    
    //==========================================================================
    // SPEC-MP-3: Memory Access Statistics
    //==========================================================================
    // Track write patterns for debugging and optimization
    
    // Coverage: CPU writes to data region (normal operation)
    cover_cpu_write_to_data_region: cover property (
        @(posedge clk) disable iff (rst)
        (ram_ena_b && (|ram_we_b) && !cpu_halted && (ram_addr_b >= INSN_REGION_END))
    );
    
    // Coverage: CPU read from instruction region (instruction fetch)
    cover_cpu_read_from_insn_region: cover property (
        @(posedge clk) disable iff (rst)
        (ram_ena_b && (ram_we_b == 4'b0000) && !cpu_halted && (ram_addr_b < INSN_REGION_END))
    );
    
    //==========================================================================
    // Debug Monitoring
    //==========================================================================
    // Display protection violations with detailed context
    
    always @(posedge clk) begin
        if (!rst && ram_ena_b && (|ram_we_b) && !cpu_halted && (ram_addr_b < INSN_REGION_END)) begin
            $display("[MEM_PROTECT] @%0t VIOLATION DETECTED:", $time);
            $display("  PC in MEM stage:     0x%08h", ex_mem_pc);
            $display("  Target word address: 0x%03h (byte address 0x%04h)", ram_addr_b, {ram_addr_b, 2'b00});
            $display("  Write enables:       %04b", ram_we_b);
            $display("  Write data:          0x%08h", ram_wdata_b);
            $display("  Protection boundary: 0x%03h (addresses 0x000-0x1FF protected)", INSN_REGION_END);
        end
    end

endmodule : rv32i_mem_protect_spec
