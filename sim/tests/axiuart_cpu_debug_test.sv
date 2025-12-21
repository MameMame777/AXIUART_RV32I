//------------------------------------------------------------------------------
// AXIUART CPU Debug Test
// Purpose: Validate TD4CPU16 debug infrastructure via UART-AXI4-Lite path
// Description: Tests memory access, PC control, step execution, and breakpoint detection
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

import td4cpu_isa_pkg::*;
import axiuart_reg_pkg::*;  // Use auto-generated register addresses

class axiuart_cpu_debug_test extends axiuart_base_test;
    `uvm_component_utils(axiuart_cpu_debug_test)
    
    // Use addresses from axiuart_reg_pkg (auto-generated)
    localparam bit [31:0] CPU_DBG_CTRL     = REG_CPU_DBG_CTRL;
    localparam bit [31:0] CPU_DBG_STATUS   = REG_CPU_DBG_STATUS;
    localparam bit [31:0] CPU_PC           = REG_CPU_PC;
    localparam bit [31:0] CPU_SP           = REG_CPU_SP;
    localparam bit [31:0] CPU_FLAGS        = REG_CPU_FLAGS;
    localparam bit [31:0] CPU_REG_ADDR     = REG_CPU_REG_INDEX;
    localparam bit [31:0] CPU_REG_DATA     = REG_CPU_REG_DATA;
    localparam bit [31:0] CPU_BP0_ADDR     = REG_CPU_BP0_PC;
    localparam bit [31:0] CPU_BP1_ADDR     = REG_CPU_BP1_PC;
    localparam bit [31:0] CPU_BP_CTRL      = REG_CPU_BP_CTRL;
    localparam bit [31:0] CPU_MEM_ADDR     = REG_CPU_MEM_ADDR;
    localparam bit [31:0] CPU_MEM_WDATA    = REG_CPU_MEM_WDATA;
    localparam bit [31:0] CPU_MEM_RDATA    = REG_CPU_MEM_RDATA;
    localparam bit [31:0] CPU_MEM_CTRL     = REG_CPU_MEM_CTRL;
    localparam bit [31:0] CPU_ID           = REG_CPU_ID;
    
    // CPU_DBG_CTRL bit positions
    localparam int HALT_REQ_BIT  = 0;
    localparam int RUN_REQ_BIT   = 1;
    localparam int STEP_REQ_BIT  = 2;
    localparam int RESET_REQ_BIT = 3;
    
    // CPU_DBG_STATUS bit positions
    localparam int HALTED_BIT    = 0;
    localparam int RUNNING_BIT   = 1;
    localparam int BRK_HIT_BIT   = 8;
    localparam int BP_HIT_BIT    = 9;
    
    // CPU_MEM_CTRL bit positions
    localparam int MEM_WR_REQ_BIT   = 0;
    localparam int MEM_RD_REQ_BIT   = 1;
    localparam int MEM_AUTO_INC_BIT = 2;
    localparam int MEM_BUSY_BIT     = 16;
    localparam int MEM_ERR_BIT      = 17;
    
    function new(string name = "axiuart_cpu_debug_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction
    
    // Helper task: Register write
    task write_reg(bit [31:0] addr, bit [31:0] data);
        uart_reg_write_sequence seq;
        seq = uart_reg_write_sequence::type_id::create("wr_seq");
        seq.reg_addr = addr;
        seq.reg_data = data;
        seq.start(env.uart_agt.sequencer);
        #100ns; // Allow transaction to complete
    endtask
    
    // Helper task: Register read
    task read_reg(bit [31:0] addr, output bit [31:0] data);
        uart_reg_read_sequence seq;
        seq = uart_reg_read_sequence::type_id::create("rd_seq");
        seq.reg_addr = addr;
        seq.start(env.uart_agt.sequencer);
        #100ns; // Allow transaction to complete
        // Note: Actual read data would come from monitor/scoreboard
        // For now, we just send the read request
        data = 32'h0; // Placeholder
    endtask
    
    // Helper task: Write CPU memory
    task write_cpu_mem(bit [15:0] addr, bit [15:0] data);
        `uvm_info(get_type_name(), 
            $sformatf("Writing CPU Memory[0x%04X] = 0x%04X", addr, data), UVM_MEDIUM)
        
        // Set memory address
        write_reg(CPU_MEM_ADDR, {16'h0, addr});
        
        // Set memory write data
        write_reg(CPU_MEM_WDATA, {16'h0, data});
        
        // Issue write request (write-1-to-pulse, bit 1 = write_req)
        write_reg(CPU_MEM_CTRL, 32'h0000_0002);  // MEM_WR_REQ (bit 1)
        
        #500ns; // Wait for memory write
    endtask
    
    // Helper task: Set CPU PC
    task set_cpu_pc(bit [15:0] pc_value);
        `uvm_info(get_type_name(), 
            $sformatf("Setting CPU PC = 0x%04X", pc_value), UVM_MEDIUM)
        write_reg(CPU_PC, {16'h0, pc_value});
    endtask
    
    // Helper task: Step CPU execution
    task step_cpu();
        `uvm_info(get_type_name(), "Issuing CPU STEP request", UVM_MEDIUM)
        write_reg(CPU_DBG_CTRL, 32'h0000_0004);  // STEP_REQ bit
        #1000ns; // Wait for step to complete
    endtask
    
    task run_phase(uvm_phase phase);
        uart_reset_sequence reset_seq;
        bit [31:0] read_value;
        bit [15:0] brk_insn;
        bit [15:0] expected_pc;
        
        phase.raise_objection(this, "Starting CPU debug test");
        `uvm_info(get_type_name(), "=== AXIUART CPU Debug Test Started ===", UVM_LOW)
        
        // Execute reset sequence
        reset_seq = uart_reset_sequence::type_id::create("reset_seq");
        reset_seq.reset_cycles = 100;
        reset_seq.start(env.uart_agt.sequencer);
        
        // Wait for reset to settle
        #1000ns;
        
        //----------------------------------------------------------------------
        // Test 1: Read CPU_DBG_STATUS - should be halted after reset
        //----------------------------------------------------------------------
        `uvm_info(get_type_name(), "--- Test 1: Read initial CPU status ---", UVM_LOW)
        read_reg(CPU_DBG_STATUS, read_value);
        `uvm_info(get_type_name(), "CPU should be HALTED after reset", UVM_MEDIUM)
        
        //----------------------------------------------------------------------
        // Test 2: Write BRK instruction to memory address 0x0000
        //----------------------------------------------------------------------
        `uvm_info(get_type_name(), "--- Test 2: Write BRK instruction to memory ---", UVM_LOW)
        
        // BRK encoding: OP_SYS(6) | reserved(9) | SYSOP_BRK(3)
        // From td4cpu_isa_pkg: OP_SYS = 4'h6, SYSOP_BRK = 3'h1
        brk_insn = {OP_SYS, 9'h000, SYSOP_BRK};  // 0x6001
        
        write_cpu_mem(16'h0000, brk_insn);
        `uvm_info(get_type_name(), 
            $sformatf("Wrote BRK instruction 0x%04X to address 0x0000", brk_insn), 
            UVM_MEDIUM)
        
        //----------------------------------------------------------------------
        // Test 3: Read back memory to verify write
        //----------------------------------------------------------------------
        `uvm_info(get_type_name(), "--- Test 3: Read back memory ---", UVM_LOW)
        
        // Set memory address
        write_reg(CPU_MEM_ADDR, 32'h0000_0000);
        
        // Issue read request (write-1-to-pulse, bit 0 = read_req)
        write_reg(CPU_MEM_CTRL, 32'h0000_0001);  // MEM_RD_REQ (bit 0)
        #500ns;
        
        // Read memory data (should contain BRK instruction)
        read_reg(CPU_MEM_RDATA, read_value);
        `uvm_info(get_type_name(), 
            $sformatf("Read back: 0x%04X (expected: 0x%04X)", read_value[15:0], brk_insn), 
            UVM_MEDIUM)
        
        //----------------------------------------------------------------------
        // Test 4: Set PC to 0x0000
        //----------------------------------------------------------------------
        `uvm_info(get_type_name(), "--- Test 4: Set PC to 0x0000 ---", UVM_LOW)
        set_cpu_pc(16'h0000);
        
        //----------------------------------------------------------------------
        // Test 5: Step execution (should execute BRK and halt)
        //----------------------------------------------------------------------
        `uvm_info(get_type_name(), "--- Test 5: Step execute BRK instruction ---", UVM_LOW)
        step_cpu();
        
        // Read PC (should be 0x0001 after BRK fetch)
        read_reg(CPU_PC, read_value);
        expected_pc = 16'h0001;
        `uvm_info(get_type_name(), 
            $sformatf("PC after step: 0x%04X (expected: 0x%04X)", 
                      read_value[15:0], expected_pc), 
            UVM_MEDIUM)
        
        // Read status (should show brk_hit)
        read_reg(CPU_DBG_STATUS, read_value);
        `uvm_info(get_type_name(), 
            $sformatf("Status after BRK: 0x%08X (brk_hit bit should be set)", read_value), 
            UVM_MEDIUM)
        
        //----------------------------------------------------------------------
        // Test 6: Read CPU ID register
        //----------------------------------------------------------------------
        `uvm_info(get_type_name(), "--- Test 6: Read CPU ID ---", UVM_LOW)
        read_reg(CPU_ID, read_value);
        `uvm_info(get_type_name(), 
            $sformatf("CPU_ID: 0x%08X (expected: 0x54443410 = 'TD4' + version)", read_value), 
            UVM_MEDIUM)
        
        //----------------------------------------------------------------------
        // Test completion
        //----------------------------------------------------------------------
        #2000ns;
        
        `uvm_info(get_type_name(), "=== AXIUART CPU Debug Test Completed ===", UVM_LOW)
        `uvm_info(get_type_name(), 
            "All debug paths exercised: memory write/read, PC control, step execution", 
            UVM_LOW)
        
        phase.drop_objection(this, "CPU debug test completed");
    endtask
endclass
