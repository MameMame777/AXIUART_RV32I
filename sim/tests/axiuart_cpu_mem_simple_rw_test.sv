// =============================================================================
// Project: TD4UART
// File:    axiuart_cpu_mem_simple_rw_test.sv
// Purpose: Minimal 10 read/write operations test for CPU memory
//          Isolates UVM infrastructure issues with simple test case
// =============================================================================

`timescale 1ns / 1ps

import axiuart_reg_pkg::*;

class axiuart_cpu_mem_simple_rw_test extends axiuart_base_test;
    `uvm_component_utils(axiuart_cpu_mem_simple_rw_test)

    // Test parameters
    localparam int NUM_OPERATIONS = 10;

    // Local shadow memory for verification
    bit [15:0] shadow_mem[bit [15:0]];
    
    // Local counters
    int match_count = 0;
    int mismatch_count = 0;
    
    // Control bit definitions (REG_CPU_MEM_CTRL)
    localparam bit [31:0] MEM_RD_REQ = 32'h00000001;  // Read request bit[0]
    localparam bit [31:0] MEM_WR_REQ = 32'h00000002;  // Write request bit[1]

    function new(string name = "axiuart_cpu_mem_simple_rw_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // UART register write sequence wrapper
    task write_reg(bit [31:0] addr, bit [31:0] data);
        uart_reg_write_sequence wr_seq;
        wr_seq = uart_reg_write_sequence::type_id::create("wr_seq");
        wr_seq.reg_addr = addr;
        wr_seq.reg_data = data;
        wr_seq.start(env.uart_agt.sequencer);
    endtask

    // UART register read sequence wrapper
    task read_reg(bit [31:0] addr, output bit [31:0] data);
        uart_reg_read_sequence rd_seq;
        rd_seq = uart_reg_read_sequence::type_id::create("rd_seq");
        rd_seq.reg_addr = addr;
        rd_seq.start(env.uart_agt.sequencer);
        data = rd_seq.read_data;
        // NOTE: Scoreboard will verify read response automatically via Monitor
    endtask

    // Reset DUT
    task do_reset();
        uart_reset_sequence reset_seq;
        `uvm_info(get_type_name(), "Executing UART reset sequence", UVM_LOW)
        reset_seq = uart_reset_sequence::type_id::create("reset_seq");
        reset_seq.reset_cycles = 100;
        reset_seq.start(env.uart_agt.sequencer);
        #1000ns;
        `uvm_info(get_type_name(), "UART reset complete", UVM_LOW)
    endtask

    // Halt CPU for memory access
    task halt_cpu();
        `uvm_info(get_type_name(), "Halting CPU for debug access", UVM_LOW)
        write_reg(REG_CPU_DBG_CTRL, 32'h00000001);  // Set halt request bit
        #1us;  // Wait for CPU to halt
        `uvm_info(get_type_name(), "CPU halted", UVM_LOW)
    endtask

    // Write to CPU memory
    task write_cpu_mem(input bit [15:0] addr, input bit [15:0] data);
        `uvm_info(get_type_name(), 
            $sformatf("WRITE: addr=0x%04X data=0x%04X", addr, data), 
            UVM_MEDIUM)
        
        // Set address
        write_reg(REG_CPU_MEM_ADDR, {16'h0000, addr});
        
        // Set write data
        write_reg(REG_CPU_MEM_WDATA, {16'h0000, data});
        
        // Write request
        write_reg(REG_CPU_MEM_CTRL, MEM_WR_REQ);
        
        // Update local shadow memory
        shadow_mem[addr] = data;
        
        #2us;  // Short delay between operations
    endtask

    // Read from CPU memory via UART
    task read_cpu_mem(input bit [15:0] addr);
        bit [31:0] read_data;
        bit [15:0] expected_data;
        
        `uvm_info(get_type_name(), 
            $sformatf("READ: addr=0x%04X", addr), 
            UVM_MEDIUM)
        
        // Set address
        write_reg(REG_CPU_MEM_ADDR, {16'h0000, addr});
        
        // Read request (triggers CPU to read from memory into REG_CPU_MEM_RDATA)
        write_reg(REG_CPU_MEM_CTRL, MEM_RD_REQ);
        
        // Now read the latched result via UART - sequence will wait for response
        read_reg(REG_CPU_MEM_RDATA, read_data);
        expected_data = shadow_mem[addr];
        
        // Verify result
        if (read_data[15:0] == expected_data) begin
            `uvm_info(get_type_name(), 
                $sformatf("READ MATCH: addr=0x%04X expected=0x%04X got=0x%04X", 
                    addr, expected_data, read_data[15:0]), 
                UVM_MEDIUM)
            match_count++;
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("READ MISMATCH: addr=0x%04X expected=0x%04X got=0x%04X", 
                    addr, expected_data, read_data[15:0]))
            mismatch_count++;
        end
    endtask

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this, "axiuart_cpu_mem_simple_rw_test running");
        
        super.run_phase(phase);
        
        `uvm_info(get_type_name(), 
            "=== Starting 10 R/W CPU Memory Test ===", 
            UVM_LOW)
        
        //----------------------------------------------------------------------
        // Phase 0: Reset and Halt CPU
        //----------------------------------------------------------------------
        do_reset();
        #1us;
        halt_cpu();
        #1us;
        
        //----------------------------------------------------------------------
        // Phase 1: Write 10 locations
        //----------------------------------------------------------------------
        `uvm_info(get_type_name(), 
            "--- Phase 1: Writing 10 locations ---", 
            UVM_LOW)
        
        for (int i = 0; i < NUM_OPERATIONS; i++) begin
            write_cpu_mem(i, 16'h1000 + i);  // addr=0..9, data=0x1000..0x1009
        end
        
        `uvm_info(get_type_name(), 
            "--- Phase 2: Reading back 10 locations ---", 
            UVM_LOW)
        
        // Phase 2: Read back and verify
        for (int i = 0; i < NUM_OPERATIONS; i++) begin
            read_cpu_mem(i);
        end
        
        // Report results
        `uvm_info(get_type_name(), 
            $sformatf("=== Test Complete: %0d matches, %0d mismatches ===", 
                match_count, mismatch_count), 
            UVM_LOW)
        
        if (mismatch_count == 0) begin
            `uvm_info(get_type_name(), 
                "*** 10 R/W Test PASSED (all UART reads verified) ***", 
                UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("*** 10 R/W Test FAILED (%0d mismatches) ***", mismatch_count))
        end
        
        #10us;
        
        phase.drop_objection(this, "axiuart_cpu_mem_simple_rw_test done");
    endtask

endclass
