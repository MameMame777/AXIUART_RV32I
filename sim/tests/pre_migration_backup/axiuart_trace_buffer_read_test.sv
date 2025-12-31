//------------------------------------------------------------------------------
// Trace Buffer Read Test - MIGRATED to axiuart_cpu_test_base pattern
// Purpose: Validate trace buffer register read via UART interface
// Reduced from 194 lines to 96 lines (50% reduction)
// Eliminated: 6 duplicate helper methods
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

import uvm_pkg::*;
import td4cpu_isa_pkg::*;
import axiuart_reg_pkg::*;

class axiuart_trace_buffer_read_test extends axiuart_cpu_test_base;
    
    `uvm_component_utils(axiuart_trace_buffer_read_test)
    
    // Trace buffer register addresses (specific to this test)
    localparam bit [31:0] REG_CPU_TRACE_ADDR  = 32'h00001238;
    localparam bit [31:0] REG_CPU_TRACE_RDATA = 32'h0000123C;
    localparam bit [31:0] REG_CPU_TRACE_PTR   = 32'h00001244;
    localparam bit [31:0] REG_CPU_TRACE_CTRL  = 32'h00001240;
    
    function new(string name = "axiuart_trace_buffer_read_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual task run_test_sequence();
        bit [31:0] read_data;
        bit [31:0] trace_ptr_before, trace_ptr_after;
        bit [15:0] insn;
        
        `uvm_info(get_type_name(), "=== Starting Trace Buffer Read Test ===", UVM_LOW)
        
        // Step 1: Load ADD instruction at address 0
        // ADD R0, R1 (opcode=0x0040)
        insn = 16'h0040;
        write_insn(16'h0000, insn);
        
        // Load operands: R0 = 1, R1 = 2
        write_cpu_reg(0, 16'h0001);
        write_cpu_reg(1, 16'h0002);
        
        // Reset PC to 0
        set_cpu_pc(16'h0000);
        
        // Step 2: Check trace pointer before execution
        trace_ptr_before = axiuart_tb_top.dut.cpu_inst.trace_write_ptr;
        `uvm_info(get_type_name(), 
            $sformatf("Trace pointer before = %0d", trace_ptr_before), UVM_MEDIUM)
        
        // Step 3: Execute ONE instruction
        step_cpu();
        #100ns;
        
        // Step 4: Verify trace was captured
        trace_ptr_after = axiuart_tb_top.dut.cpu_inst.trace_write_ptr;
        `uvm_info(get_type_name(), 
            $sformatf("Trace pointer after = %0d", trace_ptr_after), UVM_MEDIUM)
        
        if (trace_ptr_after <= trace_ptr_before) begin
            `uvm_error(get_type_name(), "Trace buffer not populated - CPU did not execute")
            tests_failed++;
        end else begin
            `uvm_info(get_type_name(), "✓ Trace buffer populated", UVM_LOW)
            tests_passed++;
        end
        
        // Step 5: Read trace buffer entry via UART register interface
        `uvm_info(get_type_name(), 
            "Reading trace buffer entry #0 via UART registers", UVM_LOW)
        
        // Set trace buffer address (entry 0)
        write_reg(REG_CPU_TRACE_ADDR, 32'h00000000);
        #1us;
        
        // Read trace data
        read_reg(REG_CPU_TRACE_RDATA, read_data);
        
        `uvm_info(get_type_name(), 
            $sformatf("Trace data: 0x%08h (insn=0x%04h, result=0x%04h)", 
                read_data, read_data[31:16], read_data[15:0]), UVM_LOW)
        
        // Step 6: Verify instruction field
        if (read_data[31:16] !== 16'h0040) begin
            `uvm_error(get_type_name(), 
                $sformatf("✗ Instruction mismatch: expected 0x0040, got 0x%04h", 
                    read_data[31:16]))
            tests_failed++;
        end else begin
            `uvm_info(get_type_name(), "✓ Instruction matched (0x0040)", UVM_LOW)
            tests_passed++;
        end
        
        // Step 7: Verify result field (should be 3 = 1 + 2)
        if (read_data[15:0] !== 16'h0003) begin
            `uvm_error(get_type_name(), 
                $sformatf("✗ Result mismatch: expected 0x0003, got 0x%04h", 
                    read_data[15:0]))
            tests_failed++;
        end else begin
            `uvm_info(get_type_name(), "✓ Result matched (0x0003 = 1 + 2)", UVM_LOW)
            tests_passed++;
        end
        
        // Step 8: Test reading second entry (if exists)
        if (trace_ptr_after > 1) begin
            `uvm_info(get_type_name(), "Reading trace buffer entry #1", UVM_MEDIUM)
            write_reg(REG_CPU_TRACE_ADDR, 32'h00000001);
            #1us;
            read_reg(REG_CPU_TRACE_RDATA, read_data);
            `uvm_info(get_type_name(), 
                $sformatf("Entry #1 data: 0x%08h", read_data), UVM_MEDIUM)
        end
        
        `uvm_info(get_type_name(), "=== Trace Buffer Read Test Complete ===", UVM_LOW)
    endtask
    
endclass
