//------------------------------------------------------------------------------
// Test Template - Copy this file when creating new CPU tests
// Purpose: Provides foolproof skeleton with all required components
// Usage: 
//   1. Copy this file to your_test_name.sv
//   2. Replace "MyTestName" with your actual test name (search/replace)
//   3. Implement test logic in run_test_sequence()
//   4. Add include to axiuart_test_pkg.sv
//   5. Run: python mcp_server/mcp_client.py --tool run_uvm_simulation --test-name your_test_name
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

import uvm_pkg::*;
import td4cpu_isa_pkg::*;
import axiuart_reg_pkg::*;

//------------------------------------------------------------------------------
// Test Class Definition
//------------------------------------------------------------------------------
class MyTestName extends axiuart_cpu_test_base;
    
    // REQUIRED: Register test with UVM factory
    `uvm_component_utils(MyTestName)
    
    // Constructor
    function new(string name = "MyTestName", uvm_component parent = null);
        super.new(name, parent);
        
        // OPTIONAL: Override test configuration
        // this.reset_cycles = 200;              // Default: 200 cycles
        // this.step_timeout_cycles = 50;        // Default: 50 cycles
        // this.enable_debug_logging = 1;        // Default: 0 (disabled)
    endfunction
    
    //--------------------------------------------------------------------------
    // REQUIRED: Implement test-specific sequence
    // NOTE: DO NOT override run_phase() - use this method instead
    //--------------------------------------------------------------------------
    virtual task run_test_sequence();
        `uvm_info(get_type_name(), "=== Starting Test Sequence ===", UVM_LOW)
        
        // =====================================================================
        // TODO: Implement your test logic here
        // =====================================================================
        
        // Example 1: Test single instruction
        // -------------------------------------
        // write_insn(16'h0000, 16'h3005);     // PC=0x0000: LDI R0, 0x05
        // write_insn(16'h0001, 16'hF000);     // PC=0x0001: SYS BRK
        // reset_cpu();                         // Reset CPU (leaves halted)
        // step_cpu();                          // Execute one instruction
        // read_trace_buffer(16'h0000, data);  // Read trace entry
        // assert_equal_8(data, 8'h05, "R0 = 0x05");
        
        // Example 2: Test instruction sequence
        // -------------------------------------
        // write_insn(16'h0000, 16'h3103);     // LDI R1, 0x03
        // write_insn(16'h0001, 16'h4102);     // ADDI R1, 0x02
        // write_insn(16'h0002, 16'hF000);     // SYS BRK
        // reset_cpu();
        // step_cpu();                          // Execute LDI
        // step_cpu();                          // Execute ADDI
        // read_trace_buffer(16'h0001, data);
        // assert_equal_8(data, 8'h05, "R1 = 0x05 after ADDI");
        
        // Example 3: Test memory operations
        // ----------------------------------
        // write_cpu_reg(3, 16'h0100);         // Set R3 = base address
        // write_insn(16'h0000, 16'h32AB);     // LDI R2, 0xAB
        // write_insn(16'h0001, 16'h6200);     // ST R2, [R3+0]
        // reset_cpu();
        // step_cpu();                          // Execute LDI
        // step_cpu();                          // Execute ST (2-cycle)
        // read_ram_direct(16'h0100, data16);
        // assert_equal_16(data16, 16'h00AB, "RAM[0x100] = 0xAB");
        
        // Example 4: Test CPU flags
        // -------------------------
        // write_insn(16'h0000, 16'h3000);     // LDI R0, 0x00
        // reset_cpu();
        // step_cpu();
        // read_cpu_flags(flags);
        // assert_equal_4(flags, 4'b0010, "Zero flag set");
        
        // =====================================================================
        // Available Helper Methods (from axiuart_cpu_test_base)
        // =====================================================================
        //
        // Instruction Management:
        //   write_insn(addr, insn)                - Write instruction to CPU RAM
        //   
        // CPU Control:
        //   reset_cpu()                            - Reset CPU (leaves halted)
        //   halt_cpu()                             - Halt running CPU
        //   run_cpu()                              - Start CPU from halt
        //   step_cpu()                             - Execute one instruction (step mode)
        //   set_cpu_pc(pc_value)                   - Set program counter
        //
        // Register Access:
        //   write_cpu_reg(reg_idx, data)           - Write CPU register (R0-R7)
        //   read_cpu_reg(reg_idx, output data)     - Read CPU register
        //   read_cpu_flags(output flags)           - Read CPU flags [N, Z, C, V]
        //
        // Memory Access:
        //   write_ram_direct(addr, data)           - Write to CPU RAM (debug path)
        //   read_ram_direct(addr, output data)     - Read from CPU RAM (debug path)
        //
        // Trace Buffer:
        //   read_trace_buffer(pc, output data)     - Read trace entry for PC
        //
        // Low-level Register I/O (if needed):
        //   write_reg(addr, data)                  - Direct register write
        //   read_reg(addr, output data)            - Direct register read
        //
        // Assertions (auto-increments pass/fail counters):
        //   assert_equal_8(actual, expected, msg)  - Compare 8-bit values
        //   assert_equal_16(actual, expected, msg) - Compare 16-bit values
        //   assert_equal_4(actual, expected, msg)  - Compare 4-bit values (flags)
        //
        // =====================================================================
        
        `uvm_info(get_type_name(), "=== Test Sequence Complete ===", UVM_LOW)
    endtask
    
    //--------------------------------------------------------------------------
    // OPTIONAL: Add helper tasks specific to this test
    //--------------------------------------------------------------------------
    
    // Example: Custom verification task
    // task verify_register_value(int reg_idx, bit [15:0] expected);
    //     bit [15:0] actual;
    //     read_cpu_reg(reg_idx, actual);
    //     assert_equal_16(actual, expected, 
    //         $sformatf("R%0d value check", reg_idx));
    // endtask
    
endclass

//------------------------------------------------------------------------------
// CHECKLIST FOR NEW TEST:
// ☐ Renamed class from "MyTestName" to your test name
// ☐ Updated `uvm_component_utils() macro with your class name
// ☐ Updated function new() name parameter
// ☐ Implemented run_test_sequence() with test logic
// ☐ Added test assertions using assert_equal_* methods
// ☐ Added `include "your_test_name.sv" to axiuart_test_pkg.sv
// ☐ Compiled test: --mode compile
// ☐ Ran test: --mode run --waves
// ☐ Verified waveforms in sim/exec/wave/
//------------------------------------------------------------------------------
