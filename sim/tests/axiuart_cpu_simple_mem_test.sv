//------------------------------------------------------------------------------
// AXIUART CPU Simple Memory Test
// Purpose: Debug basic CPU memory read/write via debug interface
// Description: Minimal test to verify single address write and read
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

import td4cpu_isa_pkg::*;
import axiuart_reg_pkg::*;

class axiuart_cpu_simple_mem_test extends axiuart_base_test;
    `uvm_component_utils(axiuart_cpu_simple_mem_test)
    
    // Use addresses from axiuart_reg_pkg
    localparam bit [31:0] CPU_DBG_CTRL     = REG_CPU_DBG_CTRL;
    localparam bit [31:0] CPU_DBG_STATUS   = REG_CPU_DBG_STATUS;
    localparam bit [31:0] CPU_MEM_ADDR     = REG_CPU_MEM_ADDR;
    localparam bit [31:0] CPU_MEM_WDATA    = REG_CPU_MEM_WDATA;
    localparam bit [31:0] CPU_MEM_RDATA    = REG_CPU_MEM_RDATA;
    localparam bit [31:0] CPU_MEM_CTRL     = REG_CPU_MEM_CTRL;
    
    // CPU_MEM_CTRL bits
    localparam bit [31:0] MEM_RD_REQ = 32'h0000_0001;  // Bit 0: read request
    localparam bit [31:0] MEM_WR_REQ = 32'h0000_0002;  // Bit 1: write request
    
    function new(string name = "axiuart_cpu_simple_mem_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction
    
    //--------------------------------------------------------------------------
    // Helper tasks
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
    
    task do_reset();
        uart_reset_sequence reset_seq;
        `uvm_info(get_type_name(), "Executing UART reset sequence", UVM_LOW)
        reset_seq = uart_reset_sequence::type_id::create("reset_seq");
        reset_seq.reset_cycles = 100;
        reset_seq.start(env.uart_agt.sequencer);
        #1000ns;
        `uvm_info(get_type_name(), "UART reset complete", UVM_LOW)
    endtask
    
    // Write to CPU memory and report details
    task write_mem_debug(input bit [15:0] addr, input bit [15:0] data);
        `uvm_info(get_type_name(), 
            $sformatf(">>> WRITE: addr=0x%04X data=0x%04X", addr, data), UVM_LOW)
        
        // Set address
        write_reg(CPU_MEM_ADDR, {16'h0000, addr});
        `uvm_info(get_type_name(), "  - Address set", UVM_MEDIUM)
        #1us;
        
        // Set write data
        write_reg(CPU_MEM_WDATA, {16'h0000, data});
        `uvm_info(get_type_name(), "  - Write data set", UVM_MEDIUM)
        #1us;
        
        // Trigger write
        write_reg(CPU_MEM_CTRL, MEM_WR_REQ);
        `uvm_info(get_type_name(), "  - Write triggered (bit 1)", UVM_LOW)
        #20us;  // Extra time for completion
        
        `uvm_info(get_type_name(), "  - Write complete", UVM_LOW)
    endtask
    
    // Read from CPU memory - Scoreboard will verify response
    task read_mem_debug(input bit [15:0] addr);
        bit [31:0] dummy_data;
        
        `uvm_info(get_type_name(), 
            $sformatf("<<< READ: addr=0x%04X", addr), UVM_LOW)
        
        // Set address
        write_reg(CPU_MEM_ADDR, {16'h0000, addr});
        `uvm_info(get_type_name(), "  - Address set", UVM_MEDIUM)
        #1us;
        
        // Trigger read
        write_reg(CPU_MEM_CTRL, MEM_RD_REQ);
        `uvm_info(get_type_name(), "  - Read triggered (bit 0)", UVM_LOW)
        #20us;  // Extra time for completion
        
        // Read result (Scoreboard will verify automatically)
        read_reg(CPU_MEM_RDATA, dummy_data);
        #1us;
        
        `uvm_info(get_type_name(), "  - Read complete (Scoreboard verifying)", UVM_MEDIUM)
    endtask
    
    // Note: Verification now done by Scoreboard automatically
    
    //--------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bit [31:0] status;
        
        super.run_phase(phase);
        
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        `uvm_info(get_type_name(), "  Simple CPU Memory Debug Test", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        // Reset and halt CPU
        do_reset();
        #50us;
        
        `uvm_info(get_type_name(), "\n--- Halting CPU ---", UVM_LOW)
        write_reg(CPU_DBG_CTRL, 32'h0000_0001);  // Assert HALT_REQ
        #20us;
        
        read_reg(CPU_DBG_STATUS, status);
        `uvm_info(get_type_name(), 
            $sformatf("CPU Status: 0x%08X (bit 0=%b = halted)", 
                status, status[0]), UVM_LOW)
        
        if (status[0] != 1'b1) begin
            `uvm_error(get_type_name(), "CPU failed to halt!")
        end
        
        `uvm_info(get_type_name(), "\n========================================", UVM_LOW)
        `uvm_info(get_type_name(), "Test 1: Write 0x1234 to address 0x0000", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        write_mem_debug(16'h0000, 16'h1234);
        #10us;
        read_mem_debug(16'h0000);
        
        `uvm_info(get_type_name(), "\n========================================", UVM_LOW)
        `uvm_info(get_type_name(), "Test 2: Write 0x5678 to same address", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        write_mem_debug(16'h0000, 16'h5678);
        #10us;
        read_mem_debug(16'h0000);
        
        `uvm_info(get_type_name(), "\n========================================", UVM_LOW)
        `uvm_info(get_type_name(), "Test 3: Write to different addresses", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        write_mem_debug(16'h0001, 16'hAAAA);
        write_mem_debug(16'h0002, 16'hBBBB);
        write_mem_debug(16'h0003, 16'hCCCC);
        #10us;
        
        read_mem_debug(16'h0001);
        read_mem_debug(16'h0002);
        read_mem_debug(16'h0003);
        read_mem_debug(16'h0000);  // Verify 0x0000 unchanged
        
        `uvm_info(get_type_name(), "\n========================================", UVM_LOW)
        `uvm_info(get_type_name(), "Test 4: Pattern test (0x0000, 0xFFFF)", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        write_mem_debug(16'h0010, 16'h0000);
        write_mem_debug(16'h0011, 16'hFFFF);
        #10us;
        
        read_mem_debug(16'h0010);
        read_mem_debug(16'h0011);
        
        // Final summary - check Scoreboard results
        `uvm_info(get_type_name(), "\n========================================", UVM_LOW)
        `uvm_info(get_type_name(), "  FINAL RESULTS (Scoreboard Verification)", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        if (env.scoreboard.cpu_memory_mismatch_count > 0) begin
            `uvm_error(get_type_name(), 
                $sformatf("CPU MEMORY TEST FAILED: %0d mismatches detected", 
                    env.scoreboard.cpu_memory_mismatch_count))
        end else if (env.scoreboard.cpu_memory_match_count == 0) begin
            `uvm_warning(get_type_name(), 
                "No CPU memory reads were verified")
        end else begin
            `uvm_info(get_type_name(), 
                $sformatf("*** CPU MEMORY TEST PASSED: %0d operations verified ***", 
                    env.scoreboard.cpu_memory_match_count), UVM_LOW)
        end
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        #10us;
        phase.drop_objection(this);
    endtask
    
endclass
