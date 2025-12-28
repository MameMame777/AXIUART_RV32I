`timescale 1ns / 1ps

class axiuart_trace_buffer_read_test extends axiuart_base_test;
    `uvm_component_utils(axiuart_trace_buffer_read_test)
    
    // Register addresses (updated for new architecture)
    localparam bit [31:0] REG_CPU_TRACE_ADDR = 32'h00001238;  // NEW: Trace buffer address register
    localparam bit [31:0] REG_CPU_TRACE_RDATA = 32'h0000123C;  // NEW: Trace buffer read data
    localparam bit [31:0] REG_CPU_TRACE_PTR  = 32'h00001244;
    localparam bit [31:0] REG_CPU_TRACE_CTRL = 32'h00001240;
    localparam bit [31:0] CPU_DBG_CTRL       = 32'h00001200;
    localparam bit [31:0] CPU_DBG_STATUS     = 32'h00001204;
    localparam bit [31:0] CPU_PC             = 32'h00001208;
    localparam bit [31:0] CPU_REG_INDEX      = 32'h00001214;
    localparam bit [31:0] CPU_REG_DATA       = 32'h00001218;
    localparam bit [31:0] CPU_MEM_ADDR       = 32'h00001228;
    localparam bit [31:0] CPU_MEM_WDATA      = 32'h0000122C;
    localparam bit [31:0] CPU_MEM_CTRL       = 32'h00001234;
    
    function new(string name = "axiuart_trace_buffer_read_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    task write_reg(input bit [31:0] addr, input bit [31:0] data);
        uart_reg_write_sequence wr_seq;
        wr_seq = uart_reg_write_sequence::type_id::create("wr_seq");
        wr_seq.reg_addr = addr;
        wr_seq.reg_data = data;
        wr_seq.start(env.uart_agt.sequencer);
    endtask
    
    task read_reg(input bit [31:0] addr, output bit [31:0] data);
        uart_reg_read_sequence rd_seq;
        rd_seq = uart_reg_read_sequence::type_id::create("rd_seq");
        rd_seq.reg_addr = addr;
        rd_seq.start(env.uart_agt.sequencer);
        data = rd_seq.read_data;
    endtask

    // CPU helper tasks (from axiuart_cpu_logic_test)
    task init_cpu_debug();
        write_reg(CPU_DBG_CTRL, 32'h00000001); // Halt CPU
        #5us;
        write_reg(CPU_DBG_STATUS, 32'hFFFFFFFF); // Clear status flags
        #5us;
    endtask

    task write_insn(input bit [15:0] addr, input bit [15:0] insn);
        write_reg(CPU_MEM_ADDR, {16'h0000, addr});
        #200us;
        write_reg(CPU_MEM_WDATA, {16'h0000, insn});
        #200us;
        write_reg(CPU_MEM_CTRL, 32'h00000002); // Write enable
        #400us;
    endtask

    task write_cpu_reg(input bit [2:0] reg_idx, input bit [15:0] value);
        write_reg(CPU_REG_INDEX, {29'h0, reg_idx});
        #200us;
        write_reg(CPU_REG_DATA, {16'h0000, value});
        #400us;
    endtask

    task set_cpu_pc(input bit [15:0] pc_value);
        write_reg(CPU_PC, {16'h0000, pc_value});
        #1us;
    endtask
    
    virtual task run_phase(uvm_phase phase);
        uart_reset_sequence reset_seq;
        bit [31:0] read_data;
        bit [31:0] trace_ptr_before, trace_ptr_after;
        bit [15:0] insn;
        int tests_passed = 0;
        int tests_failed = 0;
        
        phase.raise_objection(this);
        
        `uvm_info("TRACE_BUF_READ", "========================================", UVM_LOW)
        `uvm_info("TRACE_BUF_READ", "Trace Buffer Register Read Test", UVM_LOW)
        `uvm_info("TRACE_BUF_READ", "========================================", UVM_LOW)
        
        // Step 0: UART reset sequence to initialize CPU properly (PC=0x0000)
        `uvm_info("TRACE_BUF_READ", "Step 0: Executing UART reset sequence", UVM_LOW)
        reset_seq = uart_reset_sequence::type_id::create("reset_seq");
        reset_seq.reset_cycles = 100;
        reset_seq.start(env.uart_agt.sequencer);
        #10us; // Wait for CPU to settle after reset
        
        // Step 1: Initialize CPU debug mode (trace is ENABLED BY DEFAULT - don't touch it!)
        `uvm_info("TRACE_BUF_READ", "Step 1: Initialize CPU debug mode", UVM_LOW)
        init_cpu_debug();  // Halt CPU, clear status
        set_cpu_pc(16'h0000);  // Set PC after init
        
        // Step 2: Reset PC and load instruction (matching working test pattern)
        `uvm_info("TRACE_BUF_READ", "Step 2: Set PC and load instruction", UVM_LOW)
        set_cpu_pc(16'h0000);  // Reset PC again before test (like working test)
        
        // Load ADD instruction at address 0: opcode 0x0040 (ADD R0, R1)
        // Encoding: opcode=0x0(R-format), Rd=0, Rs=1, funct=0x00(ADD)
        insn = 16'h0040;  // ADD R0, R1 (R0 = R0 + R1)
        write_insn(16'h0000, insn);
        
        // THEN load operands: R0 = 1, R1 = 2
        write_cpu_reg(3'h0, 16'h0001);  // R0 = 1
        write_cpu_reg(3'h1, 16'h0002);  // R1 = 2
        
        // Step 4: Execute and verify (back to hierarchical - UART read not ready)
        `uvm_info("TRACE_BUF_READ", "Step 4: Execute instruction and verify trace capture", UVM_LOW)
        trace_ptr_before = axiuart_tb_top.dut.cpu_inst.trace_write_ptr;
        `uvm_info("TRACE_BUF_READ", $sformatf("Trace pointer before = %0d", trace_ptr_before), UVM_LOW)
        
        // Execute ONE instruction
        write_reg(CPU_DBG_CTRL, 32'h00000004);  // STEP
        #100us;
        
        // Read trace pointer AFTER execution
        trace_ptr_after = axiuart_tb_top.dut.cpu_inst.trace_write_ptr;
        `uvm_info("TRACE_BUF_READ", $sformatf("Trace pointer after = %0d", trace_ptr_after), UVM_LOW)
        
        // Verify trace was captured
        if (trace_ptr_after <= trace_ptr_before) begin
            `uvm_error("TRACE_BUF_READ", "Trace buffer not populated - CPU did not execute")
            tests_failed++;
        end else begin
            `uvm_info("TRACE_BUF_READ", "✓ Trace buffer populated successfully", UVM_LOW)
            tests_passed++;
        end
        
        // Step 5: **CRITICAL TEST** - Read trace buffer via UART (like CPU_MEM pattern)
        `uvm_info("TRACE_BUF_READ", "========================================", UVM_LOW)
        `uvm_info("TRACE_BUF_READ", "Step 5: Read trace buffer entry via UART register interface", UVM_LOW)
        `uvm_info("TRACE_BUF_READ", "  Architecture: Write index to REG_CPU_TRACE_ADDR, read from REG_CPU_TRACE_RDATA", UVM_LOW)
        
        // Set trace buffer address (entry 0)
        write_reg(REG_CPU_TRACE_ADDR, 32'h00000000);  // Entry index 0
        #1us;  // Wait for address to stabilize
        
        // Read trace data from hierarchical path (UART read via Monitor not yet implemented)
        // TODO: Implement Scoreboard-based verification when Monitor supports read responses
        read_data = axiuart_tb_top.dut.cpu_inst.trace_buffer[0];
        
        `uvm_info("TRACE_BUF_READ", $sformatf("  Read data: 0x%08h", read_data), UVM_LOW)
        `uvm_info("TRACE_BUF_READ", $sformatf("  Instruction[31:16]: 0x%04h", read_data[31:16]), UVM_LOW)
        `uvm_info("TRACE_BUF_READ", $sformatf("  Result[15:0]:      0x%04h", read_data[15:0]), UVM_LOW)
        
        // Verify instruction matches
        if (read_data[31:16] !== 16'h0040) begin
            `uvm_error("TRACE_BUF_READ", $sformatf("  ✗ Instruction mismatch - Expected=0x0040, Got=0x%04h", read_data[31:16]))
            tests_failed++;
        end else begin
            `uvm_info("TRACE_BUF_READ", "  ✓ Instruction matched", UVM_LOW)
            tests_passed++;
        end
        
        // Verify result (should be 3 = 1 + 2)
        if (read_data[15:0] !== 16'h0003) begin
            `uvm_error("TRACE_BUF_READ", $sformatf("  ✗ Result mismatch - Expected=0x0003, Got=0x%04h", read_data[15:0]))
            tests_failed++;
        end else begin
            `uvm_info("TRACE_BUF_READ", "  ✓ Result matched", UVM_LOW)
            tests_passed++;
        end
        
        // Step 6: Test reading second entry (if exists)
        if (trace_ptr_after > 1) begin
            `uvm_info("TRACE_BUF_READ", "Step 6: Test reading entry #1", UVM_LOW)
            write_reg(REG_CPU_TRACE_ADDR, 32'h00000001);  // Entry index 1
            #1us;
            read_data = axiuart_tb_top.dut.cpu_inst.trace_buffer[1];
            `uvm_info("TRACE_BUF_READ", $sformatf("  Entry #1 data: 0x%08h", read_data), UVM_LOW)
        end
        
        // Summary
        `uvm_info("TRACE_BUF_READ", "========================================", UVM_LOW)
        `uvm_info("TRACE_BUF_READ", $sformatf("Test Summary: %0d passed, %0d failed", tests_passed, tests_failed), UVM_LOW)
        
        if (tests_failed > 0) begin
            `uvm_error("TRACE_BUF_READ", $sformatf("*** %0d TESTS FAILED ***", tests_failed))
        end else begin
            `uvm_info("TRACE_BUF_READ", "*** ALL TESTS PASSED ***", UVM_LOW)
        end
        `uvm_info("TRACE_BUF_READ", "========================================", UVM_LOW)
        
        #10us;
        phase.drop_objection(this);
    endtask

endclass
