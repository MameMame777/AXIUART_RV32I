`timescale 1ns / 1ps
//==============================================================================
// RV32I Memory Access Safety Assertions
// 
// This module contains SystemVerilog Assertions (SVA) to verify correct
// behavior of the dual-port RAM debug interface for RV32I CPU memory access.
//
// Specification Requirements:
// 1. Debug writes (Port B) only allowed when CPU is halted
// 2. No write collisions between Port A (CPU) and Port B (debug)
// 3. Memory busy signal properly tracks operation state
// 4. Read data captured correctly after busy completes
//
// Author: GitHub Copilot
// Date: 2026-01-03
//==============================================================================

module rv32i_mem_access_spec (
    input logic        clk,
    input logic        rst_n,
    
    // CPU state
    input logic        cpu_halted,
    input logic        cpu_running,
    
    // Port A (CPU internal access)
    input logic [10:0] ram_addr_if,      // IF stage address
    input logic [10:0] ram_addr_mem,     // MEM stage address
    input logic        ram_we_mem,       // CPU write enable
    input logic [31:0] ram_wdata_mem,    // CPU write data
    
    // Port B (Debug/external access)
    input logic [11:0] dbg_mem_addr,
    input logic [31:0] dbg_mem_wdata,
    input logic [31:0] dbg_mem_rdata,
    input logic [3:0]  dbg_mem_we,
    input logic        dbg_mem_re,
    
    // Register Block memory interface
    input logic [11:0] rv32i_mem_addr,
    input logic [31:0] rv32i_mem_wdata,
    input logic [31:0] rv32i_mem_rdata,
    input logic [3:0]  rv32i_mem_we,
    input logic        rv32i_mem_re,
    input logic        rv32i_mem_busy
);

    //==========================================================================
    // Safety Assertions
    //==========================================================================
    
    // ASSERTION 1: Debug writes only when CPU halted
    // Requirement: External memory writes via Port B must only occur when
    // CPU is in halted state to prevent corruption of running program.
    property p_dbg_write_only_when_halted;
        @(posedge clk) disable iff (!rst_n)
        (|dbg_mem_we) |-> cpu_halted;
    endproperty
    
    assert_dbg_write_only_when_halted: assert property (p_dbg_write_only_when_halted)
        else $error("[RV32I_MEM_SPEC] Debug write attempted while CPU not halted: dbg_mem_we=%b, cpu_halted=%b, cpu_running=%b",
                    dbg_mem_we, cpu_halted, cpu_running);
    
    // ASSERTION 2: CPU halted state stable during debug memory operation
    // Requirement: CPU halt state must remain stable during entire memory
    // access to prevent race conditions.
    property p_halted_stable_during_busy;
        @(posedge clk) disable iff (!rst_n)
        ($rose(rv32i_mem_busy) && cpu_halted) |-> 
        (cpu_halted throughout (rv32i_mem_busy [->1]));
    endproperty
    
    assert_halted_stable_during_busy: assert property (p_halted_stable_during_busy)
        else $error("[RV32I_MEM_SPEC] CPU halted state changed during memory operation");
    
    // ASSERTION 3: No simultaneous writes to same address
    // Requirement: Port A (CPU) and Port B (debug) must not write to the
    // same address simultaneously. Port B has priority, so CPU writes should
    // be blocked when CPU is halted.
    property p_no_write_collision;
        @(posedge clk) disable iff (!rst_n)
        (|dbg_mem_we && ram_we_mem) |-> (dbg_mem_addr != ram_addr_mem);
    endproperty
    
    assert_no_write_collision: assert property (p_no_write_collision)
        else $error("[RV32I_MEM_SPEC] Write collision detected: dbg_addr=0x%h, cpu_addr=0x%h",
                    dbg_mem_addr, ram_addr_mem);
    
    // ASSERTION 4: Memory busy tracks operation correctly
    // Requirement: Busy signal must be asserted when operation starts and
    // cleared exactly one cycle later (registered RAM, 1-cycle latency).
    property p_busy_1cycle_operation;
        @(posedge clk) disable iff (!rst_n)
        ($rose(rv32i_mem_busy)) |-> ##1 (!rv32i_mem_busy);
    endproperty
    
    assert_busy_1cycle_operation: assert property (p_busy_1cycle_operation)
        else $error("[RV32I_MEM_SPEC] Memory busy did not clear after 1 cycle");
    
    // ASSERTION 5: Read enable and write enable mutually exclusive
    // Requirement: Memory interface must not assert read and write enables
    // simultaneously (Register_Block should enforce this).
    property p_we_re_mutually_exclusive;
        @(posedge clk) disable iff (!rst_n)
        not (rv32i_mem_re && (|rv32i_mem_we));
    endproperty
    
    assert_we_re_mutually_exclusive: assert property (p_we_re_mutually_exclusive)
        else $error("[RV32I_MEM_SPEC] Read and write enables both active: we=%b, re=%b",
                    rv32i_mem_we, rv32i_mem_re);
    
    // ASSERTION 6: Debug read enable only when CPU halted
    // Requirement: External memory reads via Port B must only occur when
    // CPU is in halted state for consistent data visibility.
    property p_dbg_read_only_when_halted;
        @(posedge clk) disable iff (!rst_n)
        dbg_mem_re |-> cpu_halted;
    endproperty
    
    assert_dbg_read_only_when_halted: assert property (p_dbg_read_only_when_halted)
        else $error("[RV32I_MEM_SPEC] Debug read attempted while CPU not halted");
    
    //==========================================================================
    // Functional Coverage
    //==========================================================================
    
    covergroup cg_mem_access_states @(posedge clk);
        option.per_instance = 1;
        
        // CPU state coverage
        cp_cpu_state: coverpoint {cpu_halted, cpu_running} {
            bins halted     = {2'b10};
            bins running    = {2'b01};
            bins both_zero  = {2'b00};  // Should not happen
            bins both_one   = {2'b11};  // Should not happen
        }
        
        // Debug write enable patterns
        cp_dbg_we: coverpoint dbg_mem_we {
            bins no_write       = {4'b0000};
            bins byte0          = {4'b0001};
            bins byte1          = {4'b0010};
            bins byte2          = {4'b0100};
            bins byte3          = {4'b1000};
            bins word_lower     = {4'b0011};
            bins word_upper     = {4'b1100};
            bins full_word      = {4'b1111};
            bins other          = default;
        }
        
        // Debug operation types
        cp_dbg_op: coverpoint {dbg_mem_re, |dbg_mem_we} {
            bins idle       = {2'b00};
            bins read       = {2'b10};
            bins write      = {2'b01};
            bins invalid    = {2'b11};  // Should not happen
        }
        
        // Cross coverage: CPU state vs debug operations
        cx_state_op: cross cp_cpu_state, cp_dbg_op {
            // Only halted+read and halted+write are legal
            illegal_bins running_ops = binsof(cp_cpu_state.running) && 
                                       (binsof(cp_dbg_op.read) || binsof(cp_dbg_op.write));
        }
        
        // Memory busy state coverage
        cp_busy_state: coverpoint rv32i_mem_busy {
            bins idle   = {1'b0};
            bins busy   = {1'b1};
        }
        
        // Busy transitions
        cp_busy_trans: coverpoint rv32i_mem_busy {
            bins idle_to_busy   = (0 => 1);
            bins busy_to_idle   = (1 => 0);
            bins stay_idle      = (0 => 0);
            bins stay_busy      = (1 => 1);  // Should not happen (1-cycle ops)
        }
    endgroup
    
    cg_mem_access_states cg_inst = new();
    
    //==========================================================================
    // Performance Monitoring
    //==========================================================================
    
    // Count debug read operations
    int unsigned debug_read_count = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            debug_read_count <= 0;
        end else if (dbg_mem_re && cpu_halted) begin
            debug_read_count <= debug_read_count + 1;
        end
    end
    
    // Count debug write operations
    int unsigned debug_write_count = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            debug_write_count <= 0;
        end else if (|dbg_mem_we && cpu_halted) begin
            debug_write_count <= debug_write_count + 1;
        end
    end
    
    // Final statistics report
    final begin
        $display("[RV32I_MEM_SPEC] === Memory Access Statistics ===");
        $display("[RV32I_MEM_SPEC] Debug Reads:  %0d", debug_read_count);
        $display("[RV32I_MEM_SPEC] Debug Writes: %0d", debug_write_count);
        $display("[RV32I_MEM_SPEC] ===================================");
    end

endmodule : rv32i_mem_access_spec
