//------------------------------------------------------------------------------
// CPU Basic Instruction Test - Individual Instruction Verification
// Purpose: Validate LDI, ADDI, ST, LD instructions using trace buffer
// Focus: Fast instruction-level testing without MMIO complexity
// Strategy: Execute 1-2 instructions, verify results via trace buffer
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

import uvm_pkg::*;
import td4cpu_isa_pkg::*;
import axiuart_reg_pkg::*;

class axiuart_cpu_basic_inst_test extends axiuart_cpu_test_base;
    
    `uvm_component_utils(axiuart_cpu_basic_inst_test)
    
    function new(string name = "axiuart_cpu_basic_inst_test", uvm_component parent = null);
        super.new(name, parent);
        // Optional: configure test parameters
        // this.reset_cycles = 200;
        // this.step_timeout_cycles = 50;
    endfunction
    
    //--------------------------------------------------------------------------
    // Implement test-specific sequence
    //--------------------------------------------------------------------------
    virtual task run_test_sequence();
        `uvm_info(get_type_name(), "=== Starting Basic Instruction Tests ===", UVM_LOW)
        
        test_ldi_instruction();
        #100ns;
        
        test_addi_instruction();
        #100ns;
        
        test_st_instruction();
        #100ns;
        
        test_ld_instruction();
        #100ns;
        
        `uvm_info(get_type_name(), "=== Basic Instruction Tests Complete ===", UVM_LOW)
    endtask
    
    //--------------------------------------------------------------------------
    // Test 1: LDI - Load Immediate
    //--------------------------------------------------------------------------
    task test_ldi_instruction();
        bit [7:0] trace_data;
        
        `uvm_info(get_type_name(), "--- Test 1: LDI Instruction ---", UVM_MEDIUM)
        
        // Program: LDI R0, 0x05
        write_insn(16'h0000, 16'h3005);  // PC=0x0000: LDI R0, 0x05
        write_insn(16'h0001, 16'hF000);  // PC=0x0001: SYS BRK
        
        // Reset CPU (leaves it halted for step mode)
        reset_cpu();
        
        // Execute LDI instruction (step mode)
        step_cpu();
        
        // Read trace buffer - should show R0 = 0x05
        read_trace_buffer(16'h0000, trace_data);
        
        assert_equal_8(trace_data, 8'h05, "LDI R0, 0x05 → R0");
    endtask
    
    //--------------------------------------------------------------------------
    // Test 2: ADDI - Add Immediate
    //--------------------------------------------------------------------------
    task test_addi_instruction();
        bit [7:0] trace_data;
        
        `uvm_info(get_type_name(), "--- Test 2: ADDI Instruction ---", UVM_MEDIUM)
        
        // Program:
        // LDI R1, 0x03
        // ADDI R1, 0x02  → R1 should be 0x05
        write_insn(16'h0000, 16'h3103);  // PC=0x0000: LDI R1, 0x03
        write_insn(16'h0001, 16'h4102);  // PC=0x0001: ADDI R1, 0x02
        write_insn(16'h0002, 16'hF000);  // PC=0x0002: SYS BRK
        
        reset_cpu();
        
        // Execute LDI R1, 0x03
        step_cpu();
        read_trace_buffer(16'h0000, trace_data);
        assert_equal_8(trace_data, 8'h03, "LDI R1, 0x03 → R1");
        
        // Execute ADDI R1, 0x02
        step_cpu();
        read_trace_buffer(16'h0001, trace_data);
        assert_equal_8(trace_data, 8'h05, "ADDI R1, 0x02 → R1 (0x03 + 0x02)");
    endtask
    
    //--------------------------------------------------------------------------
    // Test 3: ST - Store to RAM
    //--------------------------------------------------------------------------
    task test_st_instruction();
        bit [7:0] trace_data;
        bit [15:0] ram_data;
        
        `uvm_info(get_type_name(), "--- Test 3: ST Instruction (Store to RAM) ---", UVM_MEDIUM)
        
        // Program:
        // LDI R2, 0xAB
        // ST R2, [R3+0x00]  → RAM[0x0100] = 0xAB (R3 preset to 0x0100)
        write_insn(16'h0000, 16'h32AB);  // PC=0x0000: LDI R2, 0xAB
        write_insn(16'h0001, 16'h6200);  // PC=0x0001: ST R2, [R3+0]
        write_insn(16'h0002, 16'hF000);  // PC=0x0002: SYS BRK
        
        reset_cpu();
        
        // Set R3 as base address pointer = 0x0100
        write_cpu_reg(3, 16'h0100);
        
        // Execute LDI R2, 0xAB
        step_cpu();
        read_trace_buffer(16'h0000, trace_data);
        assert_equal_8(trace_data, 8'hAB, "LDI R2, 0xAB → R2");
        
        // Execute ST R2, [R3+0x00] → RAM[0x0100] = 0xAB
        `uvm_info(get_type_name(), "Executing ST R2, [R3+0x00] - 2-cycle operation", UVM_MEDIUM)
        step_cpu();
        #100ns; // Wait for write to complete
        
        // Read back from RAM via CPU register read
        read_ram_direct(16'h0100, ram_data);
        assert_equal_8(ram_data[7:0], 8'hAB, "ST R2, [R3+0x00] → RAM[0x0100]");
    endtask
    
    //--------------------------------------------------------------------------
    // Test 4: LD - Load from RAM
    //--------------------------------------------------------------------------
    task test_ld_instruction();
        bit [7:0] trace_data;
        
        `uvm_info(get_type_name(), "--- Test 4: LD Instruction (Load from RAM) ---", UVM_MEDIUM)
        
        // Pre-populate RAM[0x0200] = 0x42
        write_ram_direct(16'h0200, 16'h0042);
        
        // Program:
        // LD R4, [R3+0x00]  → R4 = RAM[0x0200] = 0x42
        write_insn(16'h0000, 16'h5400);  // PC=0x0000: LD R4, [R3+0x00]
        write_insn(16'h0001, 16'hF000);  // PC=0x0001: SYS BRK
        
        reset_cpu();
        
        // Set R3 as base address pointer = 0x0200
        write_cpu_reg(3, 16'h0200);
        
        // Execute LD R4, [R3+0x00] - 2-cycle operation
        `uvm_info(get_type_name(), "Executing LD R4, [R3+0x00] - 2-cycle operation", UVM_MEDIUM)
        step_cpu();
        #100ns; // Wait for load to complete
        read_trace_buffer(16'h0000, trace_data);
        
        assert_equal_8(trace_data, 8'h42, "LD R4, [R3+0x00] → R4 from RAM[0x0200]");
    endtask
    
endclass
