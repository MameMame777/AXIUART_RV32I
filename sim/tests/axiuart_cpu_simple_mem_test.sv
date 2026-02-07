//------------------------------------------------------------------------------
// AXIUART CPU Simple Memory Test (RV32I)
// Purpose: Verify UART→Register_Block→Port B→BRAM read/write path
// Description: Tests CPU_MEM_* registers for 32-bit BRAM access via UART
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

import axiuart_reg_pkg::*;

class axiuart_cpu_simple_mem_test extends axiuart_base_test;
    `uvm_component_utils(axiuart_cpu_simple_mem_test)
    
    // Use addresses from axiuart_reg_pkg (imported by axiuart_pkg)
    localparam bit [31:0] CPU_MEM_ADDR     = axiuart_reg_pkg::REG_CPU_MEM_ADDR;
    localparam bit [31:0] CPU_MEM_WDATA    = axiuart_reg_pkg::REG_CPU_MEM_WDATA;
    localparam bit [31:0] CPU_MEM_RDATA    = axiuart_reg_pkg::REG_CPU_MEM_RDATA;
    localparam bit [31:0] CPU_MEM_CTRL     = axiuart_reg_pkg::REG_CPU_MEM_CTRL;
    
    // CPU_MEM_CTRL bits (check actual bitfield from REG_CPU_MEM_CTRL definition)
    localparam bit [31:0] MEM_RD_REQ    = 32'h0000_0010;  // Bit 4: read request
    localparam bit [31:0] MEM_WR_REQ    = 32'h0000_0020;  // Bit 5: write request
    localparam bit [31:0] MEM_BE_FULL   = 32'h0000_000F;  // Bits[3:0]: full word byte enables
    localparam bit [31:0] MEM_HALT      = 32'h0000_0100;  // Bit 8: halt CPU (must stay SET during debug access)
    localparam int        CTRL_BUSY_BIT   = 6;            // Bit 6: busy flag
    localparam int        CTRL_HALTED_BIT = 9;            // Bit 9: CPU is halted (read-only)
    
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
    
    // Write to CPU memory (32-bit word address and data for RV32I)
    task write_mem_debug(input bit [10:0] word_addr, input bit [31:0] data);
        bit [31:0] ctrl_val;
        int timeout;
        
        `uvm_info(get_type_name(), 
            $sformatf(">>> WRITE: word_addr=0x%03X data=0x%08X", word_addr, data), UVM_LOW)
        
        // Set address (convert word address to byte address by shifting left 2)
        // Register expects byte address, extracts word address via [12:2]
        write_reg(CPU_MEM_ADDR, {20'h0, word_addr, 2'b00});
        `uvm_info(get_type_name(), "  - Address set", UVM_MEDIUM)
        #1us;
        
        // Set write data (full 32-bit word)
        write_reg(CPU_MEM_WDATA, data);
        `uvm_info(get_type_name(), "  - Write data set", UVM_MEDIUM)
        #1us;
        
        // Trigger write with byte enables AND keep halt bit set
        write_reg(CPU_MEM_CTRL, MEM_WR_REQ | MEM_BE_FULL | MEM_HALT);
        `uvm_info(get_type_name(), "  - Write triggered (WR_REQ + BE + HALT)", UVM_LOW)
        
        // Wait for completion (poll BUSY bit)
        timeout = 0;
        forever begin
            #50ns;
            read_reg(CPU_MEM_CTRL, ctrl_val);
            if (ctrl_val[CTRL_BUSY_BIT] === 1'b0) break;
            timeout++;
            if (timeout > 200) begin
                `uvm_error(get_type_name(),
                    $sformatf("Timeout writing to memory word_addr 0x%03X", word_addr))
                break;
            end
        end
        
        `uvm_info(get_type_name(), "  - Write complete", UVM_LOW)
    endtask
    
    // Read from CPU memory - Scoreboard will verify response
    task read_mem_debug(input bit [10:0] word_addr);
        bit [31:0] ctrl_val;
        bit [31:0] dummy_data;
        int timeout;
        
        `uvm_info(get_type_name(), 
            $sformatf("<<< READ: word_addr=0x%03X", word_addr), UVM_LOW)
        
        // Set address (convert word address to byte address by shifting left 2)
        // Register expects byte address, extracts word address via [12:2]
        write_reg(CPU_MEM_ADDR, {20'h0, word_addr, 2'b00});
        `uvm_info(get_type_name(), "  - Address set", UVM_MEDIUM)
        #1us;
        
        // Trigger read (keep halt bit set)
        write_reg(CPU_MEM_CTRL, MEM_RD_REQ | MEM_HALT);
        `uvm_info(get_type_name(), "  - Read triggered (RD_REQ + HALT)", UVM_LOW)
        
        // Wait for completion (poll BUSY bit)
        timeout = 0;
        forever begin
            #50ns;
            read_reg(CPU_MEM_CTRL, ctrl_val);
            if (ctrl_val[CTRL_BUSY_BIT] === 1'b0) break;
            timeout++;
            if (timeout > 200) begin
                `uvm_error(get_type_name(),
                    $sformatf("Timeout reading from memory word_addr 0x%03X", word_addr))
                break;
            end
        end
        
        // Read result (Scoreboard will verify automatically)
        read_reg(CPU_MEM_RDATA, dummy_data);
        #1us;
        
        `uvm_info(get_type_name(), "  - Read complete (Scoreboard verifying)", UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        
        super.run_phase(phase);
        
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        `uvm_info(get_type_name(), "  RV32I BRAM Access Test (UART→Port B)", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        // Reset DUT
        do_reset();
        #50us;
        
        // Verify CPU is halted after reset
        begin
            bit [31:0] ctrl_rd;
            read_reg(CPU_MEM_CTRL, ctrl_rd);
            if (ctrl_rd[CTRL_HALTED_BIT] !== 1'b1) begin
                `uvm_info(get_type_name(), "CPU not halted after reset, sending halt command", UVM_LOW)
                write_reg(CPU_MEM_CTRL, MEM_HALT);
                #10us;
                read_reg(CPU_MEM_CTRL, ctrl_rd);
                if (ctrl_rd[CTRL_HALTED_BIT] !== 1'b1)
                    `uvm_error(get_type_name(), $sformatf("CPU still not halted! CTRL=0x%08X", ctrl_rd))
            end
            `uvm_info(get_type_name(), $sformatf("CPU_MEM_CTRL=0x%08X (halted=%0b)", ctrl_rd, ctrl_rd[CTRL_HALTED_BIT]), UVM_LOW)
        end
        
        `uvm_info(get_type_name(), "\n--- Note: RV32I CPU debug interface allows memory access anytime ---", UVM_LOW)
        
        `uvm_info(get_type_name(), "\n========================================", UVM_LOW)
        `uvm_info(get_type_name(), "Test 1: Write RV32I instruction to addr 0x000", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        write_mem_debug(11'h000, 32'h00A00093);  // ADDI x1, x0, 10
        #10us;
        read_mem_debug(11'h000);
        
        `uvm_info(get_type_name(), "\n========================================", UVM_LOW)
        `uvm_info(get_type_name(), "Test 2: Overwrite same address", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        write_mem_debug(11'h000, 32'h000048B7);  // LUI x17, 0x4
        #10us;
        read_mem_debug(11'h000);
        
        `uvm_info(get_type_name(), "\n========================================", UVM_LOW)
        `uvm_info(get_type_name(), "Test 3: Write to multiple addresses", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        write_mem_debug(11'h001, 32'h00500113);  // ADDI x2, x0, 5
        write_mem_debug(11'h002, 32'h002081B3);  // ADD x3, x1, x2
        write_mem_debug(11'h003, 32'h00100073);  // EBREAK
        #10us;
        
        read_mem_debug(11'h001);
        read_mem_debug(11'h002);
        read_mem_debug(11'h003);
        read_mem_debug(11'h000);  // Verify addr 0x000 unchanged
        
        `uvm_info(get_type_name(), "\n========================================", UVM_LOW)
        `uvm_info(get_type_name(), "Test 4: Pattern test (0x00000000, 0xFFFFFFFF)", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        write_mem_debug(11'h010, 32'h00000000);
        write_mem_debug(11'h011, 32'hFFFFFFFF);
        #10us;
        
        read_mem_debug(11'h010);
        read_mem_debug(11'h011);
        
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
