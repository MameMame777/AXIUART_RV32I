`timescale 1ns / 1ps

//==============================================================================
// RV32I Exception Handler Test
//==============================================================================
// Comprehensive test for exception handling with trap handler and MRET:
// 1. EBREAK triggers exception trap
// 2. CPU jumps to trap handler (mtvec address)
// 3. Handler reads CSRs (mepc, mcause, mtval)
// 4. Handler executes MRET to return
// 5. CPU resumes at interrupted PC
//
// Test Program:
//   Main code (0x0000):
//     0x0000: ADDI x1, x0, 1     - Initialize x1=1
//     0x0004: EBREAK             - Trigger exception (trap to 0x0100)
//     0x0008: ADDI x2, x0, 99    - Should NOT execute immediately
//     0x000C: ADDI x3, x0, 3     - Resumes here after handler
//
//   Trap handler (0x0100):
//     0x0100: CSRR x10, mepc     (0x34102573) - Read exception PC
//     0x0104: CSRR x11, mcause   (0x342025F3) - Read exception cause
//     0x0108: CSRR x12, mtval    (0x34302673) - Read trap value
//     0x010C: ADDI x13, x0, 42   (0x02A00693) - Handler work (x13=42)
//     0x0110: MRET               (0x30200073) - Return to mepc
//
// Expected Results:
//   - mepc = 0x0004 (EBREAK PC)
//   - mcause = 0x00000003 (CAUSE_BREAKPOINT)
//   - mtval = 0x00000000
//   - x10 = 0x0004 (CSR read from handler)
//   - x11 = 0x0003
//   - x12 = 0x0000
//   - x13 = 42 (handler side effect)
//   - PC returns to 0x0004 after MRET
//   - Trace shows handler execution (0x0100-0x0110)
//
// Author: GitHub Copilot
// Date: 2026-01-04
//==============================================================================

class rv32i_exception_handler_test extends rv32i_base_test;
    
    `uvm_component_utils(rv32i_exception_handler_test)
    
    // CSR addresses (RISC-V Privileged Spec)
    localparam bit [11:0] CSR_MTVEC  = 12'h305;
    localparam bit [11:0] CSR_MEPC   = 12'h341;
    localparam bit [11:0] CSR_MCAUSE = 12'h342;
    localparam bit [11:0] CSR_MTVAL  = 12'h343;
    
    // Exception cause codes
    localparam bit [31:0] CAUSE_BREAKPOINT = 32'h00000003;
    
    function new(string name = "rv32i_exception_handler_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Configure for exception handler test
        // Expect main code + handler instructions
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_insn_min", 6);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_insn_max", 10);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_ebreak_count", 1);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info("EXCEPTION_HANDLER", "***** Starting RV32I Exception Handler Test *****", UVM_LOW)
        
        // Reset and initialize
        reset_sequence();
        halt_cpu();
        
        // Setup trap handler address
        setup_trap_handler();
        
        // Load test program
        load_exception_handler_program();
        
        // Start CPU and let it run
        `uvm_info("EXCEPTION_HANDLER", "Starting CPU - will trap to handler on EBREAK", UVM_MEDIUM)
        start_cpu();
        
        // Wait for trap handler to execute and MRET to return
        wait_for_handler_completion(2000);
        
        // Halt CPU to read final state
        halt_cpu();
        #100ns;
        
        // Verify exception CSR values
        verify_csr_state();
        
        // Verify register state (handler side effects)
        verify_register_state();
        
        // Verify trace buffer (handler execution)
        verify_trace_buffer();
        
        #1000ns;
        
        `uvm_info("EXCEPTION_HANDLER", "***** RV32I Exception Handler Test Complete *****", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
    
    //--------------------------------------------------------------------------
    // Setup Trap Handler Address
    //--------------------------------------------------------------------------
    
    virtual task setup_trap_handler();
        bit [31:0] mtvec_value;
        
        `uvm_info("EXCEPTION_HANDLER", "Setting up trap handler", UVM_MEDIUM)
        
        // Set mtvec CSR to 0x0100 (trap handler base address)
        mtvec_value = 32'h0000_0100;
        
        // Write mtvec via CSR write sequence (using CSRRW instruction)
        // We'll use debug memory write to set up initial CSR value
        // Note: In real hardware, firmware would initialize this
        
        `uvm_info("EXCEPTION_HANDLER", $sformatf("mtvec = 0x%08X (trap handler address)", mtvec_value), UVM_MEDIUM)
        
        // For this test, we assume mtvec defaults to 0x0000 or needs explicit setup
        // We'll use a bootstrap sequence to write mtvec before main code
        
        // Bootstrap: Write mtvec CSR then jump to main
        // 0x0000: LUI x15, 0x00001   (0x00001FB7) - x15 = 0x1000
        // 0x0004: CSRRW x0, mtvec, x15 (0x305FBF73) - mtvec = 0x0100, discard old value
        // 0x0008: JAL x0, 0x10       (0x010000EF) - Jump to main code at 0x0018
        
        // Bootstrap: Set mtvec to 0x0100 (trap handler base address)
        // NOTE: CPU starts at PC=0x0004 (not 0x0000), so first instruction is at RAM[1]
        // 0x0000: (unused, PC never reaches here)
        // 0x0004: ADDI x31, x0, 1    -> x31 = 1
        // 0x0008: SLLI x31, x31, 8   -> x31 = 0x100
        // 0x000C-0x0014: NOPs (allow SLLI to reach WB before CSRW reads x31)
        // 0x0018: CSRW mtvec, x31    -> mtvec = 0x100
        // 0x001C: JAL x0, +0         -> PC = 0x001C (infinite loop to halt)
        
        write_debug_mem(11'h001, 32'h00100F93); // RAM[1] @ PC=0x0004: ADDI x31, x0, 1
        write_debug_mem(11'h002, 32'h008F9F93); // RAM[2] @ PC=0x0008: SLLI x31, x31, 8
        write_debug_mem(11'h003, 32'h00000013); // RAM[3] @ PC=0x000C: NOP (avoid read-after-write hazard)
        write_debug_mem(11'h004, 32'h00000013); // RAM[4] @ PC=0x0010: NOP
        write_debug_mem(11'h005, 32'h00000013); // RAM[5] @ PC=0x0014: NOP
        write_debug_mem(11'h006, 32'h305F9073); // RAM[6] @ PC=0x0018: CSRW mtvec, x31
        write_debug_mem(11'h007, 32'h0000006F); // RAM[7] @ PC=0x001C: JAL x0, +0 (infinite loop)
        
        `uvm_info("EXCEPTION_HANDLER", "Bootstrap code loaded (sets mtvec to 0x0100)", UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Load Exception Handler Test Program
    //--------------------------------------------------------------------------
    
    virtual task load_exception_handler_program();
        `uvm_info("EXCEPTION_HANDLER", "Loading exception handler program", UVM_MEDIUM)
        
        // Layout:
        // 0x0004-0x001C: Bootstrap (sets mtvec) + NOPs
        // 0x0020-0x002C: Main code
        // 0x0100-0x0110: Trap handler
        
        // === Main Code (0x0020 = word address 0x008) ===
        write_debug_mem(11'h008, 32'h00100093); // RAM[8] @ PC=0x0020: ADDI x1, x0, 1 (x1=1)
        write_debug_mem(11'h009, 32'h00100073); // RAM[9] @ PC=0x0024: EBREAK (trap to 0x0100)
        write_debug_mem(11'h00A, 32'h06300113); // RAM[10] @ PC=0x0028: ADDI x2, x0, 99 (should not execute)
        write_debug_mem(11'h00B, 32'h00300193); // RAM[11] @ PC=0x002C: ADDI x3, x0, 3 (will execute after handler return)
        
        // === Trap Handler (0x0100 = word address 0x040) ===
        write_debug_mem(11'h040, 32'h34102573); // RAM[64] @ PC=0x0100: CSRR x10, mepc (read exception PC)
        write_debug_mem(11'h041, 32'h342025F3); // RAM[65] @ PC=0x0104: CSRR x11, mcause (read exception cause)
        write_debug_mem(11'h042, 32'h34302673); // RAM[66] @ PC=0x0108: CSRR x12, mtval (read trap value)
        write_debug_mem(11'h043, 32'h02A00693); // RAM[67] @ PC=0x010C: ADDI x13, x0, 42 (x13=42, handler work)
        write_debug_mem(11'h044, 32'h30200073); // RAM[68] @ PC=0x0110: MRET (return to mepc)
        
        `uvm_info("EXCEPTION_HANDLER", "Program loaded:", UVM_MEDIUM)
        `uvm_info("EXCEPTION_HANDLER", "  Bootstrap: RAM[1-7] @ PC=0x0004-0x001C", UVM_MEDIUM)
        `uvm_info("EXCEPTION_HANDLER", "  Main: RAM[8-11] @ PC=0x0020-0x002C", UVM_MEDIUM)
        `uvm_info("EXCEPTION_HANDLER", "  Handler: RAM[64-68] @ PC=0x0100-0x0110", UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Wait for Handler Completion
    //--------------------------------------------------------------------------
    
    virtual task wait_for_handler_completion(int timeout_cycles);
        int cycle_count = 0;
        bit handler_started = 0;
        bit handler_completed = 0;
        bit [31:0] current_pc;
        
        `uvm_info("EXCEPTION_HANDLER", "Waiting for trap handler to execute", UVM_MEDIUM)
        
        while (cycle_count < timeout_cycles) begin
            @(posedge vif.clk);
            current_pc = vif.pc_if;
            
            // Detect handler entry (PC in range 0x0100-0x0114)
            if (!handler_started && current_pc >= 32'h0100 && current_pc <= 32'h0114) begin
                handler_started = 1;
                `uvm_info("EXCEPTION_HANDLER", $sformatf("Trap handler entered at PC=0x%08X", current_pc), UVM_LOW)
            end
            
            // Detect handler exit (PC returns to main code after MRET)
            if (handler_started && current_pc < 32'h0100) begin
                handler_completed = 1;
                `uvm_info("EXCEPTION_HANDLER", $sformatf("MRET completed, returned to PC=0x%08X", current_pc), UVM_LOW)
                // Give a few more cycles for instructions to complete
                repeat(10) @(posedge vif.clk);
                return;
            end
            
            cycle_count++;
        end
        
        if (!handler_started) begin
            `uvm_error("EXCEPTION_HANDLER", "Trap handler never entered")
        end else if (!handler_completed) begin
            `uvm_error("EXCEPTION_HANDLER", "MRET never completed")
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Verify CSR State
    //--------------------------------------------------------------------------
    
    virtual task verify_csr_state();
        bit [31:0] mepc_value, mcause_value, mtval_value;
        
        `uvm_info("EXCEPTION_HANDLER", "=== CSR State Verification ===", UVM_LOW)
        
        // Note: Direct CSR reads from testbench not implemented in current design
        // Instead, verify through register values (handler read CSRs into x10-x12)
        
        // Read x10 (should contain mepc value)
        read_register(5'd10, mepc_value);
        `uvm_info("EXCEPTION_HANDLER", $sformatf("x10 (mepc) = 0x%08X (expected 0x00000024)", mepc_value), UVM_MEDIUM)
        
        // Read x11 (should contain mcause value)
        read_register(5'd11, mcause_value);
        `uvm_info("EXCEPTION_HANDLER", $sformatf("x11 (mcause) = 0x%08X (expected 0x00000003)", mcause_value), UVM_MEDIUM)
        
        // Read x12 (should contain mtval value)
        read_register(5'd12, mtval_value);
        `uvm_info("EXCEPTION_HANDLER", $sformatf("x12 (mtval) = 0x%08X (expected 0x00000000)", mtval_value), UVM_MEDIUM)
        
        // Verify values
        if (mepc_value != 32'h0000_0024) begin
            `uvm_error("EXCEPTION_HANDLER", $sformatf("mepc mismatch: expected 0x00000024, got 0x%08X", mepc_value))
        end else begin
            `uvm_info("EXCEPTION_HANDLER", "PASS: mepc correct (EBREAK PC)", UVM_LOW)
        end
        
        if (mcause_value != CAUSE_BREAKPOINT) begin
            `uvm_error("EXCEPTION_HANDLER", $sformatf("mcause mismatch: expected 0x%08X, got 0x%08X", CAUSE_BREAKPOINT, mcause_value))
        end else begin
            `uvm_info("EXCEPTION_HANDLER", "PASS: mcause correct (BREAKPOINT=3)", UVM_LOW)
        end
        
        if (mtval_value != 32'h0000_0000) begin
            `uvm_error("EXCEPTION_HANDLER", $sformatf("mtval mismatch: expected 0x00000000, got 0x%08X", mtval_value))
        end else begin
            `uvm_info("EXCEPTION_HANDLER", "PASS: mtval correct (0)", UVM_LOW)
        end
        
        `uvm_info("EXCEPTION_HANDLER", "==============================", UVM_LOW)
    endtask
    
    //--------------------------------------------------------------------------
    // Verify Register State
    //--------------------------------------------------------------------------
    
    virtual task verify_register_state();
        bit [31:0] x1_value, x13_value;
        
        `uvm_info("EXCEPTION_HANDLER", "=== Register State Verification ===", UVM_LOW)
        
        // Read x1 (set by main code before EBREAK)
        read_register(5'd1, x1_value);
        `uvm_info("EXCEPTION_HANDLER", $sformatf("x1 = %0d (expected 1)", x1_value), UVM_MEDIUM)
        
        // Read x13 (set by trap handler)
        read_register(5'd13, x13_value);
        `uvm_info("EXCEPTION_HANDLER", $sformatf("x13 = %0d (expected 42)", x13_value), UVM_MEDIUM)
        
        if (x1_value != 32'd1) begin
            `uvm_error("EXCEPTION_HANDLER", $sformatf("x1 mismatch: expected 1, got %0d", x1_value))
        end else begin
            `uvm_info("EXCEPTION_HANDLER", "PASS: x1 correct (main code executed)", UVM_LOW)
        end
        
        if (x13_value != 32'd42) begin
            `uvm_error("EXCEPTION_HANDLER", $sformatf("x13 mismatch: expected 42, got %0d", x13_value))
        end else begin
            `uvm_info("EXCEPTION_HANDLER", "PASS: x13 correct (handler executed)", UVM_LOW)
        end
        
        `uvm_info("EXCEPTION_HANDLER", "===================================", UVM_LOW)
    endtask
    
    //--------------------------------------------------------------------------
    // Verify Trace Buffer
    //--------------------------------------------------------------------------
    
    virtual task verify_trace_buffer();
        logic [31:0] pc, insn;
        logic [31:0] rd_value;
        logic [4:0] rd_addr;
        logic [6:0] entry_count;
        bit handler_found = 0;
        
        @(posedge vif.clk);
        entry_count = vif.dbg_trace_count;
        
        `uvm_info("EXCEPTION_HANDLER", "=== Trace Buffer Verification ===", UVM_LOW)
        `uvm_info("EXCEPTION_HANDLER", $sformatf("Total entries: %0d", entry_count), UVM_LOW)
        
        // Scan for handler execution (PC in 0x0100-0x0114 range)
        for (int i = 0; i < entry_count && i < 64; i++) begin
            logic [5:0] idx;
            idx = i;
            read_trace_entry(idx, pc, insn, rd_value, rd_addr);
            
            if (pc >= 32'h0100 && pc <= 32'h0114) begin
                handler_found = 1;
                `uvm_info("EXCEPTION_HANDLER", 
                          $sformatf("Handler trace[%0d]: PC=0x%08X, INSN=0x%08X", i, pc, insn), UVM_MEDIUM)
            end
        end
        
        if (!handler_found) begin
            `uvm_error("EXCEPTION_HANDLER", "Trap handler not found in trace buffer")
        end else begin
            `uvm_info("EXCEPTION_HANDLER", "PASS: Trap handler execution confirmed", UVM_LOW)
        end
        
        `uvm_info("EXCEPTION_HANDLER", "=================================", UVM_LOW)
    endtask
    
endclass
