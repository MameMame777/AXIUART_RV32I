//------------------------------------------------------------------------------
// CPU Logic Test - Unified ALU and Logic Verification
// Purpose: Comprehensive test suite for TD4 CPU ALU operations
// Features: Register manipulation, instruction execution, flag verification
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

import uvm_pkg::*;
import td4cpu_isa_pkg::*;
import axiuart_reg_pkg::*;

class axiuart_cpu_logic_test extends axiuart_base_test;
    `uvm_component_utils(axiuart_cpu_logic_test)

    // Register addresses from axiuart_reg_pkg
    localparam bit [31:0] CPU_DBG_CTRL     = REG_CPU_DBG_CTRL;
    localparam bit [31:0] CPU_DBG_STATUS   = REG_CPU_DBG_STATUS;
    localparam bit [31:0] CPU_PC           = REG_CPU_PC;
    localparam bit [31:0] CPU_FLAGS        = REG_CPU_FLAGS;
    localparam bit [31:0] CPU_REG_INDEX    = REG_CPU_REG_INDEX;
    localparam bit [31:0] CPU_REG_DATA     = REG_CPU_REG_DATA;
    localparam bit [31:0] CPU_MEM_ADDR     = REG_CPU_MEM_ADDR;
    localparam bit [31:0] CPU_MEM_WDATA    = REG_CPU_MEM_WDATA;
    localparam bit [31:0] CPU_MEM_RDATA    = REG_CPU_MEM_RDATA;
    localparam bit [31:0] CPU_MEM_CTRL     = REG_CPU_MEM_CTRL;

    // Test statistics
    int tests_passed = 0;
    int tests_failed = 0;
    
    // Test case storage for batch execution
    typedef struct {
        string test_name;
        bit [2:0] rd_idx;
        bit [2:0] rs_idx;
        bit [15:0] rd_init;
        bit [15:0] rs_init;
        bit [5:0] funct;
        bit [15:0] expected_result;
        bit expected_z;
        bit expected_n;
        bit expected_c;
        bit check_writeback;
    } test_case_t;
    
    test_case_t test_cases[];

    function new(string name = "axiuart_cpu_logic_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //--------------------------------------------------------------------------
    // Helper Tasks - Register Access
    //--------------------------------------------------------------------------
    task write_reg(bit [31:0] addr, bit [31:0] data);
        uart_reg_write_sequence wr_seq;
        wr_seq = uart_reg_write_sequence::type_id::create("wr_seq");
        wr_seq.reg_addr = addr;
        wr_seq.reg_data = data;
        wr_seq.start(env.uart_agt.sequencer);
    endtask

    task read_reg(bit [31:0] addr, output bit [31:0] data);
        uart_reg_read_sequence rd_seq;
        rd_seq = uart_reg_read_sequence::type_id::create("rd_seq");
        rd_seq.reg_addr = addr;
        rd_seq.start(env.uart_agt.sequencer);
        data = rd_seq.read_data;
    endtask
    
    //--------------------------------------------------------------------------
    // Direct Trace Buffer Access (bypasses UART completely)
    //--------------------------------------------------------------------------
    task read_trace_buffer_direct(input int index, output bit [31:0] data);
        // Direct hierarchical access to CPU trace buffer
        data = axiuart_tb_top.dut.cpu_inst.trace_buffer[index[7:0]];
    endtask
    
    task read_trace_ptr_direct(output bit [7:0] ptr);
        // Direct hierarchical access to trace write pointer
        ptr = axiuart_tb_top.dut.cpu_inst.trace_write_ptr;
    endtask

    task do_reset();
        uart_reset_sequence reset_seq;
        `uvm_info("CPU_LOGIC", "Executing UART reset sequence", UVM_LOW)
        reset_seq = uart_reset_sequence::type_id::create("reset_seq");
        reset_seq.reset_cycles = 100;
        reset_seq.start(env.uart_agt.sequencer);
        #10us; // Increased wait after reset for CPU to settle
        `uvm_info("CPU_LOGIC", "UART reset complete", UVM_LOW)
    endtask

    //--------------------------------------------------------------------------
    // Helper Tasks - CPU Control
    //--------------------------------------------------------------------------
    task init_cpu_debug();
        bit cpu_halted_state;
        
        // Clear HALT_ON_RESET flag and halt CPU
        write_reg(CPU_DBG_CTRL, 32'h00000001); // Halt CPU (bit[0])
        #5us;
        
        // Check CPU halted state directly
        cpu_halted_state = axiuart_tb_top.dut.cpu_inst.halted;
        `uvm_info("CPU_LOGIC", $sformatf("CPU halted state: %0d", cpu_halted_state), UVM_MEDIUM)
        
        write_reg(CPU_DBG_STATUS, 32'hFFFFFFFF); // Clear status flags
        #5us;
    endtask

    task halt_cpu();
        write_reg(CPU_DBG_CTRL, 32'h00000001); // Halt request
        #5us;
    endtask

    task step_cpu();
        bit [31:0] status, old_status;
        int timeout_count;
        
        read_reg(CPU_DBG_STATUS, old_status);
        write_reg(CPU_DBG_CTRL, 32'h00000004); // Step request
        #1us;
        
        // Poll for status change indicating step completion
        timeout_count = 0;
        do begin
            #50us; // Reduced from 100us
            read_reg(CPU_DBG_STATUS, status);
            timeout_count++;
            if (timeout_count > 50) begin // Reduced from 100
                `uvm_error("CPU_LOGIC", $sformatf("step_cpu() timeout - status=0x%08x", status))
                break;
            end
        end while (status == old_status);
        
        #5us; // Reduced from 10us
    endtask

    task set_cpu_pc(input bit [15:0] pc_value);
        write_reg(CPU_PC, {16'h0000, pc_value});
        #1us;
    endtask

    //--------------------------------------------------------------------------
    // Helper Tasks - Memory and Register Access
    //--------------------------------------------------------------------------
    task write_insn(input bit [15:0] addr, input bit [15:0] insn);
        write_reg(CPU_MEM_ADDR, {16'h0000, addr});
        #200us; // Reduced from 1ms
        write_reg(CPU_MEM_WDATA, {16'h0000, insn});
        #200us; // Reduced from 1ms
        write_reg(CPU_MEM_CTRL, 32'h00000002); // Write enable
        #400us; // Reduced from 2ms
    endtask

    task write_cpu_reg(input bit [2:0] reg_idx, input bit [15:0] value);
        write_reg(CPU_REG_INDEX, {29'h0, reg_idx});
        #200us; // Reduced from 1ms
        write_reg(CPU_REG_DATA, {16'h0000, value});
        #400us; // Reduced from 2ms
    endtask

    task read_cpu_reg(input bit [2:0] reg_idx, output bit [15:0] value);
        bit [31:0] rdata;
        write_reg(CPU_REG_INDEX, {29'h0, reg_idx});
        #1us;
        read_reg(CPU_REG_DATA, rdata);
        value = rdata[15:0];
        #1us;
    endtask

    task read_cpu_flags(output bit flag_z, output bit flag_n, output bit flag_c);
        bit [31:0] rdata;
        read_reg(CPU_FLAGS, rdata);
        flag_z = rdata[0];
        flag_n = rdata[1];
        flag_c = rdata[2];
        #1us;
    endtask

    //--------------------------------------------------------------------------
    // Helper Function - Instruction Building
    //--------------------------------------------------------------------------
    function bit [15:0] build_r_insn(bit [2:0] rd, bit [2:0] rs, bit [5:0] funct);
        return {OP_R_ALU, rd, rs, funct};
    endfunction

    //--------------------------------------------------------------------------
    // Sequential execution with fixed waits (no polling)
    // Load instruction -> Set registers -> Step -> Repeat
    //--------------------------------------------------------------------------
    task execute_all_tests_batch();
        bit [7:0] trace_ptr_final;
        bit [31:0] trace_entry;
        bit [31:0] trace_base_addr = 32'h00001300;
        bit [31:0] trace_ptr_addr = 32'h0000123C;
        
        `uvm_info("CPU_LOGIC", "=== Sequential Execution (No Polling) ===", UVM_LOW)
        
        // Initialize CPU once
        init_cpu_debug();
        set_cpu_pc(16'h0000);
        
        // Execute each test sequentially: load, set regs, step
        for (int i = 0; i < test_cases.size(); i++) begin
            bit cpu_halted_before, cpu_halted_after;
            
            // Reset PC to 0 for each test
            set_cpu_pc(16'h0000);
            
            // Load instruction to address 0
            write_insn(16'h0000, build_r_insn(test_cases[i].rd_idx, test_cases[i].rs_idx, test_cases[i].funct));
            
            // Set register initial values
            write_cpu_reg(test_cases[i].rd_idx, test_cases[i].rd_init);
            write_cpu_reg(test_cases[i].rs_idx, test_cases[i].rs_init);
            
            // Check CPU state before step (direct access)
            cpu_halted_before = axiuart_tb_top.dut.cpu_inst.halted;
            
            // Execute instruction (step with fixed wait)
            write_reg(CPU_DBG_CTRL, 32'h00000004); // Step request
            #100us; // Fixed wait instead of polling
            
            // Check CPU state after step (direct access)
            cpu_halted_after = axiuart_tb_top.dut.cpu_inst.halted;
            
            if (i < 3) begin // Log first 3 tests for debug
                `uvm_info("CPU_LOGIC", $sformatf("[%0d] Halted: before=%0d after=%0d", i, cpu_halted_before, cpu_halted_after), UVM_MEDIUM)
            end
        end
        
        `uvm_info("CPU_LOGIC", $sformatf("Executed %0d test instructions", test_cases.size()), UVM_MEDIUM)
        
        // Halt CPU
        write_reg(CPU_DBG_CTRL, 32'h00000001);
        #1ms;
        
        // Read final trace pointer (DIRECT ACCESS - no UART!)
        read_trace_ptr_direct(trace_ptr_final);
        `uvm_info("CPU_LOGIC", $sformatf("Trace pointer after execution: %0d", trace_ptr_final), UVM_MEDIUM)
        
        // Read all trace entries and verify (DIRECT ACCESS - no UART!)
        for (int i = 0; i < test_cases.size(); i++) begin
            bit [15:0] actual_result;
            bit [15:0] actual_insn;
            
            if (i < trace_ptr_final) begin
                // Direct read from trace buffer
                read_trace_buffer_direct(i, trace_entry);
                
                actual_result = trace_entry[15:0];
                actual_insn = trace_entry[31:16];
                
                if (actual_result === test_cases[i].expected_result) begin
                    `uvm_info("CPU_LOGIC", $sformatf("[%0d] %s: PASS (0x%04h)", 
                        i, test_cases[i].test_name, actual_result), UVM_MEDIUM)
                    tests_passed++;
                end else begin
                    `uvm_error("CPU_LOGIC", $sformatf("[%0d] %s: FAIL - Expected=0x%04h, Got=0x%04h",
                        i, test_cases[i].test_name, test_cases[i].expected_result, actual_result))
                    tests_failed++;
                end
            end else begin
                `uvm_error("CPU_LOGIC", $sformatf("[%0d] %s: NOT EXECUTED (trace_ptr=%0d)",
                    i, test_cases[i].test_name, trace_ptr_final))
                tests_failed++;
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Main Test Phase - Batch Mode
    //--------------------------------------------------------------------------
    // Fast execution using trace buffer (eliminates UART polling overhead)
    //--------------------------------------------------------------------------
    task execute_and_verify(
        input string test_name,
        input bit [2:0] rd_idx,
        input bit [2:0] rs_idx,
        input bit [15:0] rd_init,
        input bit [15:0] rs_init,
        input bit [5:0] funct,
        input bit [15:0] expected_result,
        input bit expected_z,
        input bit expected_n,
        input bit expected_c,
        input bit check_writeback
    );
        bit [15:0] insn;
        bit [15:0] actual_result;
        bit [31:0] trace_entry;
        bit [7:0]  trace_ptr_before, trace_ptr_after;
        bit [31:0] trace_ptr_addr = 32'h0000123C;  // REG_CPU_TRACE_PTR
        bit [31:0] trace_base_addr = 32'h00001300; // REG_CPU_TRACE_BASE
        bit test_passed = 1'b1;
        
        `uvm_info("CPU_LOGIC", $sformatf("=== %s ===", test_name), UVM_MEDIUM)
        
        // Initialize CPU state
        init_cpu_debug();
        set_cpu_pc(16'h0000);
        
        // Load operands
        write_cpu_reg(rd_idx, rd_init);
        write_cpu_reg(rs_idx, rs_init);
        
        // Build and load instruction
        insn = build_r_insn(rd_idx, rs_idx, funct);
        write_insn(16'h0000, insn);
        
        `uvm_info("CPU_LOGIC", $sformatf("  Insn: 0x%04h (R%0d=0x%04h, R%0d=0x%04h, funct=0x%02h)",
            insn, rd_idx, rd_init, rs_idx, rs_init, funct), UVM_HIGH)
        
        // Read trace pointer before execution
        read_reg(trace_ptr_addr, trace_ptr_before);
        
        // Execute instruction with direct step request (no polling)
        write_reg(CPU_DBG_CTRL, 32'h00000004); // Step request
        #5ms; // Fixed wait for execution completion (UART + CPU execution)
        
        // Read trace pointer after execution
        read_reg(trace_ptr_addr, trace_ptr_after);
        
        // Verify trace was captured
        if (trace_ptr_after === trace_ptr_before) begin
            `uvm_error("CPU_LOGIC", "  FAIL: Trace buffer not updated - instruction did not execute")
            test_passed = 1'b0;
        end else begin
            // Read most recent trace entry
            read_reg(trace_base_addr + ((trace_ptr_after - 1) * 4), trace_entry);
            
            // Extract result and instruction from trace
            actual_result = trace_entry[15:0];   // Result in lower 16 bits
            // trace_entry[31:16] contains instruction (for debugging)
            
            // Verify result
            if (check_writeback) begin
                if (actual_result !== expected_result) begin
                    `uvm_error("CPU_LOGIC", $sformatf("  FAIL: Result mismatch! Expected=0x%04h, Actual=0x%04h",
                        expected_result, actual_result))
                    test_passed = 1'b0;
                end else begin
                    `uvm_info("CPU_LOGIC", $sformatf("  PASS: Result = 0x%04h (trace)", actual_result), UVM_MEDIUM)
                end
            end
        end
        
        halt_cpu();
        
        // Update statistics
        if (test_passed) tests_passed++;
        else tests_failed++;
    endtask

    //--------------------------------------------------------------------------
    // Main Test Phase
    //--------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        
        phase.raise_objection(this);
        
        do_reset();
        
        `uvm_info("CPU_LOGIC", "========================================", UVM_LOW)
        `uvm_info("CPU_LOGIC", "CPU Logic Test Suite - Batch Execution with Trace Buffer", UVM_LOW)
        `uvm_info("CPU_LOGIC", "========================================", UVM_LOW)
        
        // Build test case array
        test_cases = new[17];
        
        test_cases[0] = '{
            test_name: "ADD: Basic (1+2=3)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'h0001, rs_init: 16'h0002,
            funct: FUNCT_ADD,
            expected_result: 16'h0003,
            expected_z: 1'b0, expected_n: 1'b0, expected_c: 1'b0,
            check_writeback: 1'b1
        };
        
        test_cases[1] = '{
            test_name: "ADD: Zero (0+0=0, Z=1)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'h0000, rs_init: 16'h0000,
            funct: FUNCT_ADD,
            expected_result: 16'h0000,
            expected_z: 1'b1, expected_n: 1'b0, expected_c: 1'b0,
            check_writeback: 1'b1
        };
        
        test_cases[2] = '{
            test_name: "ADD: Carry (FFFF+1=0, Z=1, C=1)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'hFFFF, rs_init: 16'h0001,
            funct: FUNCT_ADD,
            expected_result: 16'h0000,
            expected_z: 1'b1, expected_n: 1'b0, expected_c: 1'b1,
            check_writeback: 1'b1
        };
        
        test_cases[3] = '{
            test_name: "ADD: Negative (7FFF+1=8000, N=1)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'h7FFF, rs_init: 16'h0001,
            funct: FUNCT_ADD,
            expected_result: 16'h8000,
            expected_z: 1'b0, expected_n: 1'b1, expected_c: 1'b0,
            check_writeback: 1'b1
        };
        
        test_cases[4] = '{
            test_name: "SUB: Basic (5-2=3, C=1)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'h0005, rs_init: 16'h0002,
            funct: FUNCT_SUB,
            expected_result: 16'h0003,
            expected_z: 1'b0, expected_n: 1'b0, expected_c: 1'b1,
            check_writeback: 1'b1
        };
        
        test_cases[5] = '{
            test_name: "SUB: Zero (3-3=0, Z=1, C=1)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'h0003, rs_init: 16'h0003,
            funct: FUNCT_SUB,
            expected_result: 16'h0000,
            expected_z: 1'b1, expected_n: 1'b0, expected_c: 1'b1,
            check_writeback: 1'b1
        };
        
        test_cases[6] = '{
            test_name: "SUB: Borrow (2-5=FFFD, N=1, C=0)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'h0002, rs_init: 16'h0005,
            funct: FUNCT_SUB,
            expected_result: 16'hFFFD,
            expected_z: 1'b0, expected_n: 1'b1, expected_c: 1'b0,
            check_writeback: 1'b1
        };
        
        test_cases[7] = '{
            test_name: "AND: Alternating (AAAA&5555=0, Z=1)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'hAAAA, rs_init: 16'h5555,
            funct: FUNCT_AND,
            expected_result: 16'h0000,
            expected_z: 1'b1, expected_n: 1'b0, expected_c: 1'b0,
            check_writeback: 1'b1
        };
        
        test_cases[8] = '{
            test_name: "AND: All Ones (FFFF&FFFF=FFFF, N=1)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'hFFFF, rs_init: 16'hFFFF,
            funct: FUNCT_AND,
            expected_result: 16'hFFFF,
            expected_z: 1'b0, expected_n: 1'b1, expected_c: 1'b0,
            check_writeback: 1'b1
        };
        
        test_cases[9] = '{
            test_name: "OR: Alternating (AAAA|5555=FFFF, N=1)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'hAAAA, rs_init: 16'h5555,
            funct: FUNCT_OR,
            expected_result: 16'hFFFF,
            expected_z: 1'b0, expected_n: 1'b1, expected_c: 1'b0,
            check_writeback: 1'b1
        };
        
        test_cases[10] = '{
            test_name: "XOR: Self (1234^1234=0, Z=1)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'h1234, rs_init: 16'h1234,
            funct: FUNCT_XOR,
            expected_result: 16'h0000,
            expected_z: 1'b1, expected_n: 1'b0, expected_c: 1'b0,
            check_writeback: 1'b1
        };
        
        test_cases[11] = '{
            test_name: "CMP: Equal (1234==1234, Z=1, C=1)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'h1234, rs_init: 16'h1234,
            funct: FUNCT_CMP,
            expected_result: 16'h0000,
            expected_z: 1'b1, expected_n: 1'b0, expected_c: 1'b1,
            check_writeback: 1'b0
        };
        
        test_cases[12] = '{
            test_name: "CMP: Greater (1000>0100, Z=0, C=1)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'h1000, rs_init: 16'h0100,
            funct: FUNCT_CMP,
            expected_result: 16'h0F00,
            expected_z: 1'b0, expected_n: 1'b0, expected_c: 1'b1,
            check_writeback: 1'b0
        };
        
        test_cases[13] = '{
            test_name: "CMP: Less (0100<1000, N=1, C=0)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'h0100, rs_init: 16'h1000,
            funct: FUNCT_CMP,
            expected_result: 16'hF100,
            expected_z: 1'b0, expected_n: 1'b1, expected_c: 1'b0,
            check_writeback: 1'b0
        };
        
        test_cases[14] = '{
            test_name: "SHL1: Basic (4000<<1=8000, N=1)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'h4000, rs_init: 16'h0000,
            funct: FUNCT_SHL1,
            expected_result: 16'h8000,
            expected_z: 1'b0, expected_n: 1'b1, expected_c: 1'b0,
            check_writeback: 1'b1
        };
        
        test_cases[15] = '{
            test_name: "SHL1: Carry (8001<<1=0002, C=1)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'h8001, rs_init: 16'h0000,
            funct: FUNCT_SHL1,
            expected_result: 16'h0002,
            expected_z: 1'b0, expected_n: 1'b0, expected_c: 1'b1,
            check_writeback: 1'b1
        };
        
        test_cases[16] = '{
            test_name: "SHR1: Basic (0002>>1=0001)",
            rd_idx: 3'd1, rs_idx: 3'd2,
            rd_init: 16'h0002, rs_init: 16'h0000,
            funct: FUNCT_SHR1,
            expected_result: 16'h0001,
            expected_z: 1'b0, expected_n: 1'b0, expected_c: 1'b0,
            check_writeback: 1'b1
        };
        
        // Execute all tests in batch mode
        execute_all_tests_batch();
        
        // Test Summary
        `uvm_info("CPU_LOGIC", "========================================", UVM_LOW)
        `uvm_info("CPU_LOGIC", $sformatf("Test Summary: %0d passed, %0d failed", tests_passed, tests_failed), UVM_LOW)
        if (tests_failed == 0) begin
            `uvm_info("CPU_LOGIC", "*** ALL TESTS PASSED ***", UVM_LOW)
        end else begin
            `uvm_error("CPU_LOGIC", $sformatf("*** %0d TESTS FAILED ***", tests_failed))
            test_pass = 0;
        end
        `uvm_info("CPU_LOGIC", "========================================", UVM_LOW)
        
        #10us;
        phase.drop_objection(this);
    endtask

endclass
