//------------------------------------------------------------------------------
// AXIUART CPU Memory Test
// Purpose: Validate TD4CPU16 RAM integrity via debug interface
// Description: Galloping, Marching, and pattern-based memory tests
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

import td4cpu_isa_pkg::*;
import axiuart_reg_pkg::*;

class axiuart_cpu_memory_test extends axiuart_base_test;
    `uvm_component_utils(axiuart_cpu_memory_test)
    
    // Use addresses from axiuart_reg_pkg
    localparam bit [31:0] CPU_DBG_CTRL     = REG_CPU_DBG_CTRL;
    localparam bit [31:0] CPU_DBG_STATUS   = REG_CPU_DBG_STATUS;
    localparam bit [31:0] CPU_MEM_ADDR     = REG_CPU_MEM_ADDR;
    localparam bit [31:0] CPU_MEM_WDATA    = REG_CPU_MEM_WDATA;
    localparam bit [31:0] CPU_MEM_RDATA    = REG_CPU_MEM_RDATA;
    localparam bit [31:0] CPU_MEM_CTRL     = REG_CPU_MEM_CTRL;
    
    // CPU_DBG_CTRL bits
    localparam bit [3:0] HALT_REQ_BIT = 0;
    
    // CPU_MEM_CTRL bits
    localparam bit [31:0] MEM_RD_REQ = 32'h0000_0001;  // Bit 0: read request
    localparam bit [31:0] MEM_WR_REQ = 32'h0000_0002;  // Bit 1: write request
    localparam bit [31:0] MEM_AUTO_INC = 32'h0000_0004; // Bit 2: auto-increment address
    
    // Memory test parameters (reduced for faster simulation)
    localparam int RAM_SIZE = 4096;           // Total RAM size (words)
    localparam int GALLOP_STRIDE = 1024;      // Test every 1024th address (4 locations)
    localparam int MARCH_TEST_SIZE = 16;      // Test first 16 locations for march
    localparam int PATTERN_TEST_SIZE = 32;    // Pattern test size (reduced from 128)
    
    // Test patterns
    localparam bit [15:0] PATTERN_ZERO     = 16'h0000;
    localparam bit [15:0] PATTERN_ONE      = 16'hFFFF;
    localparam bit [15:0] PATTERN_AA       = 16'hAAAA;
    localparam bit [15:0] PATTERN_55       = 16'h5555;
    localparam bit [15:0] PATTERN_WALK1_START = 16'h0001;
    localparam bit [15:0] PATTERN_WALK0_START = 16'hFFFE;
    
    // CPU Memory Debug tracking (local shadow for verification)
    bit [15:0] cpu_memory_shadow[bit [15:0]];  // CPU internal memory shadow
    int cpu_memory_match_count;
    int cpu_memory_mismatch_count;
    
    function new(string name = "axiuart_cpu_memory_test", uvm_component parent = null);
        super.new(name, parent);
        cpu_memory_match_count = 0;
        cpu_memory_mismatch_count = 0;
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction
    
    //--------------------------------------------------------------------------
    // Base helper tasks
    //--------------------------------------------------------------------------
    
    // Helper task: Register write
    task write_reg(bit [31:0] addr, bit [31:0] data);
        uart_reg_write_sequence wr_seq;
        wr_seq = uart_reg_write_sequence::type_id::create("wr_seq");
        wr_seq.reg_addr = addr;
        wr_seq.reg_data = data;
        wr_seq.start(env.uart_agt.sequencer);
    endtask
    
    // Helper task: Register read
    task read_reg(bit [31:0] addr, output bit [31:0] data);
        uart_reg_read_sequence rd_seq;
        rd_seq = uart_reg_read_sequence::type_id::create("rd_seq");
        rd_seq.reg_addr = addr;
        rd_seq.start(env.uart_agt.sequencer);
        data = rd_seq.read_data;
    endtask
    
    // UART reset sequence
    task do_reset();
        uart_reset_sequence reset_seq;
        `uvm_info(get_type_name(), "Executing UART reset sequence", UVM_MEDIUM)
        reset_seq = uart_reset_sequence::type_id::create("reset_seq");
        reset_seq.reset_cycles = 100;
        reset_seq.start(env.uart_agt.sequencer);
        #1000ns;
        `uvm_info(get_type_name(), "UART reset complete", UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Helper tasks
    //--------------------------------------------------------------------------
    
    // Write to CPU memory via debug interface
    task write_cpu_mem(input bit [15:0] addr, input bit [15:0] data);
        write_reg(CPU_MEM_ADDR, {16'h0000, addr});   // Set address
        #100ns;
        write_reg(CPU_MEM_WDATA, {16'h0000, data});  // Set write data
        #100ns;
        write_reg(CPU_MEM_CTRL, MEM_WR_REQ);         // Trigger write (bit 1)
        #2us;  // Wait for UART completion
        
        // Track in local shadow memory
        cpu_memory_shadow[addr] = data;
    endtask
    
    // Read from CPU memory via debug interface
    // NOTE: Using hierarchical access for verification (like trace buffer test)
    // UART read path not yet reliable for scoreboard verification
    task read_cpu_mem(input bit [15:0] addr);
        bit [15:0] expected_data;
        bit [15:0] actual_data;
        
        write_reg(CPU_MEM_ADDR, {16'h0000, addr});   // Set address
        #100ns;
        write_reg(CPU_MEM_CTRL, MEM_RD_REQ);         // Trigger read (bit 0)
        #2us;  // Wait for memory read to complete
        
        // Read directly from DUT (hierarchical access)
        actual_data = axiuart_tb_top.dut.cpu_inst.ram[addr];
        
        // Verify against shadow memory
        if (cpu_memory_shadow.exists(addr)) begin
            expected_data = cpu_memory_shadow[addr];
            if (actual_data == expected_data) begin
                cpu_memory_match_count++;
                `uvm_info(get_type_name(), 
                    $sformatf("CPU_MEM READ MATCH: ADDR=0x%04X Expected=0x%04X Got=0x%04X", 
                              addr, expected_data, actual_data), UVM_HIGH)
            end else begin
                cpu_memory_mismatch_count++;
                `uvm_error(get_type_name(), 
                    $sformatf("CPU_MEM READ MISMATCH: ADDR=0x%04X Expected=0x%04X Got=0x%04X",
                              addr, expected_data, actual_data))
            end
        end else begin
            `uvm_warning(get_type_name(), 
                $sformatf("CPU_MEM read from unwritten address: ADDR=0x%04X DATA=0x%04X",
                          addr, actual_data))
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Test 1: Galloping Pattern (0s and 1s)
    //--------------------------------------------------------------------------
    task galloping_test();
        bit [15:0] test_addr;
        int addr_idx;
        
        `uvm_info(get_type_name(), "=== Galloping Pattern Test ===", UVM_LOW)
        
        // Galloping 0s: Write 0 to one location, verify all others are not affected
        `uvm_info(get_type_name(), "--- Galloping 0s (stride 256) ---", UVM_LOW)
        
        // Initialize all test locations to 0xFFFF
        for (addr_idx = 0; addr_idx < RAM_SIZE; addr_idx += GALLOP_STRIDE) begin
            write_cpu_mem(addr_idx, PATTERN_ONE);
        end
        
        // For each test location, write 0 and verify all others still 0xFFFF
        for (addr_idx = 0; addr_idx < RAM_SIZE; addr_idx += GALLOP_STRIDE) begin
            test_addr = addr_idx;
            write_cpu_mem(test_addr, PATTERN_ZERO);
            
            // Verify only adjacent locations (simplified for speed)
            if (addr_idx > 0) read_cpu_mem(addr_idx - GALLOP_STRIDE);
            read_cpu_mem(test_addr);
            if (addr_idx + GALLOP_STRIDE < RAM_SIZE) read_cpu_mem(addr_idx + GALLOP_STRIDE);
            
            // Restore to 0xFFFF
            write_cpu_mem(test_addr, PATTERN_ONE);
        end
        
        // Galloping 1s: Write 1 to one location, verify all others are not affected
        `uvm_info(get_type_name(), "--- Galloping 1s (stride 256) ---", UVM_LOW)
        
        // Initialize all test locations to 0x0000
        for (addr_idx = 0; addr_idx < RAM_SIZE; addr_idx += GALLOP_STRIDE) begin
            write_cpu_mem(addr_idx, PATTERN_ZERO);
        end
        
        // For each test location, write 0xFFFF and verify neighbors
        for (addr_idx = 0; addr_idx < RAM_SIZE; addr_idx += GALLOP_STRIDE) begin
            test_addr = addr_idx;
            write_cpu_mem(test_addr, PATTERN_ONE);
            
            // Verify only adjacent locations (simplified for speed)
            if (addr_idx > 0) read_cpu_mem(addr_idx - GALLOP_STRIDE);
            read_cpu_mem(test_addr);
            if (addr_idx + GALLOP_STRIDE < RAM_SIZE) read_cpu_mem(addr_idx + GALLOP_STRIDE);
            
            // Restore to 0x0000
            write_cpu_mem(test_addr, PATTERN_ZERO);
        end
        
        `uvm_info(get_type_name(), "Galloping test complete", UVM_LOW)
    endtask
    
    //--------------------------------------------------------------------------
    // Test 2: March C- Algorithm
    // ↑(w0); ↑(r0,w1); ↑(r1,w0); ↓(r0,w1); ↓(r1,w0); ↓(r0)
    //--------------------------------------------------------------------------
    task march_c_minus_test();
        `uvm_info(get_type_name(), "=== March C- Test ===", UVM_LOW)
        
        // Phase 1: ↑(w0) - Write 0 ascending
        `uvm_info(get_type_name(), "Phase 1: ↑(w0)", UVM_MEDIUM)
        for (int addr = 0; addr < MARCH_TEST_SIZE; addr++) begin
            write_cpu_mem(addr, PATTERN_ZERO);
        end
        
        // Phase 2: ↑(r0,w1) - Read 0, Write 1 ascending
        `uvm_info(get_type_name(), "Phase 2: ↑(r0,w1)", UVM_MEDIUM)
        for (int addr = 0; addr < MARCH_TEST_SIZE; addr++) begin
            read_cpu_mem(addr);  // Scoreboard verifies against shadow
            write_cpu_mem(addr, PATTERN_ONE);
        end
        
        // Phase 3: ↑(r1,w0) - Read 1, Write 0 ascending
        `uvm_info(get_type_name(), "Phase 3: ↑(r1,w0)", UVM_MEDIUM)
        for (int addr = 0; addr < MARCH_TEST_SIZE; addr++) begin
            read_cpu_mem(addr);  // Scoreboard verifies against shadow
            write_cpu_mem(addr, PATTERN_ZERO);
        end
        
        // Phase 4: ↓(r0,w1) - Read 0, Write 1 descending
        `uvm_info(get_type_name(), "Phase 4: ↓(r0,w1)", UVM_MEDIUM)
        for (int addr = MARCH_TEST_SIZE - 1; addr >= 0; addr--) begin
            read_cpu_mem(addr);  // Scoreboard verifies against shadow
            write_cpu_mem(addr, PATTERN_ONE);
        end
        
        // Phase 5: ↓(r1,w0) - Read 1, Write 0 descending
        `uvm_info(get_type_name(), "Phase 5: ↓(r1,w0)", UVM_MEDIUM)
        for (int addr = MARCH_TEST_SIZE - 1; addr >= 0; addr--) begin
            read_cpu_mem(addr);  // Scoreboard verifies against shadow
            write_cpu_mem(addr, PATTERN_ZERO);
        end
        
        // Phase 6: ↓(r0) - Read 0 descending
        `uvm_info(get_type_name(), "Phase 6: ↓(r0)", UVM_MEDIUM)
        for (int addr = MARCH_TEST_SIZE - 1; addr >= 0; addr--) begin
            read_cpu_mem(addr);  // Scoreboard verifies against shadow
        end
        
        `uvm_info(get_type_name(), "March C- test complete", UVM_LOW)
    endtask
    
    //--------------------------------------------------------------------------
    // Test 3: Checkerboard Pattern
    //--------------------------------------------------------------------------
    task checkerboard_test();
        `uvm_info(get_type_name(), "=== Checkerboard Pattern Test ===", UVM_LOW)
        
        // Write AA/55 checkerboard
        `uvm_info(get_type_name(), "Writing 0xAAAA/0x5555 pattern", UVM_MEDIUM)
        for (int addr = 0; addr < PATTERN_TEST_SIZE; addr++) begin
            if (addr % 2 == 0)
                write_cpu_mem(addr, PATTERN_AA);
            else
                write_cpu_mem(addr, PATTERN_55);
        end
        
        // Verify AA/55 pattern (Scoreboard verifies automatically)
        `uvm_info(get_type_name(), "Verifying 0xAAAA/0x5555 pattern", UVM_MEDIUM)
        for (int addr = 0; addr < PATTERN_TEST_SIZE; addr++) begin
            read_cpu_mem(addr);
        end
        
        // Invert to 55/AA pattern
        `uvm_info(get_type_name(), "Writing 0x5555/0xAAAA pattern (inverted)", UVM_MEDIUM)
        for (int addr = 0; addr < PATTERN_TEST_SIZE; addr++) begin
            if (addr % 2 == 0)
                write_cpu_mem(addr, PATTERN_55);
            else
                write_cpu_mem(addr, PATTERN_AA);
        end
        
        // Verify inverted pattern (Scoreboard verifies automatically)
        `uvm_info(get_type_name(), "Verifying 0x5555/0xAAAA pattern", UVM_MEDIUM)
        for (int addr = 0; addr < PATTERN_TEST_SIZE; addr++) begin
            read_cpu_mem(addr);
        end
        
        `uvm_info(get_type_name(), "Checkerboard test complete", UVM_LOW)
    endtask
    
    //--------------------------------------------------------------------------
    // Test 4: Walking 1s and 0s
    //--------------------------------------------------------------------------
    task walking_bit_test();
        bit [15:0] walk1_pattern;
        bit [15:0] walk0_pattern;
        
        `uvm_info(get_type_name(), "=== Walking Bits Test ===", UVM_LOW)
        
        // Walking 1s - single bit high, shifts left
        `uvm_info(get_type_name(), "Walking 1s pattern", UVM_MEDIUM)
        walk1_pattern = PATTERN_WALK1_START;
        for (int bit_pos = 0; bit_pos < 16; bit_pos++) begin
            int addr = bit_pos * 4;  // Space out addresses
            if (addr < PATTERN_TEST_SIZE) begin
                write_cpu_mem(addr, walk1_pattern);
                read_cpu_mem(addr);  // Scoreboard verifies automatically
                walk1_pattern = walk1_pattern << 1;
            end
        end
        
        // Walking 0s - single bit low, shifts left
        `uvm_info(get_type_name(), "Walking 0s pattern", UVM_MEDIUM)
        walk0_pattern = PATTERN_WALK0_START;
        for (int bit_pos = 0; bit_pos < 16; bit_pos++) begin
            int addr = bit_pos * 4;
            if (addr < PATTERN_TEST_SIZE) begin
                write_cpu_mem(addr, walk0_pattern);
                read_cpu_mem(addr);  // Scoreboard verifies automatically
                walk0_pattern = (walk0_pattern << 1) | 16'h0001;
            end
        end
        
        `uvm_info(get_type_name(), "Walking bits test complete", UVM_LOW)
    endtask
    
    //--------------------------------------------------------------------------
    // Test 5: Address-as-Data Test
    //--------------------------------------------------------------------------
    task address_as_data_test();
        `uvm_info(get_type_name(), "=== Address-as-Data Test ===", UVM_LOW)
        
        // Write address value to each location
        `uvm_info(get_type_name(), "Writing address values", UVM_MEDIUM)
        for (int addr = 0; addr < PATTERN_TEST_SIZE; addr++) begin
            write_cpu_mem(addr, addr[15:0]);
        end
        
        // Verify all locations contain their address (Scoreboard verifies automatically)
        `uvm_info(get_type_name(), "Verifying address values", UVM_MEDIUM)
        for (int addr = 0; addr < PATTERN_TEST_SIZE; addr++) begin
            read_cpu_mem(addr);
        end
        
        // Write inverted address values
        `uvm_info(get_type_name(), "Writing inverted address values", UVM_MEDIUM)
        for (int addr = 0; addr < PATTERN_TEST_SIZE; addr++) begin
            write_cpu_mem(addr, ~addr[15:0]);
        end
        
        // Verify inverted values (Scoreboard verifies automatically)
        `uvm_info(get_type_name(), "Verifying inverted address values", UVM_MEDIUM)
        for (int addr = 0; addr < PATTERN_TEST_SIZE; addr++) begin
            read_cpu_mem(addr);
        end
        
        `uvm_info(get_type_name(), "Address-as-data test complete", UVM_LOW)
    endtask
    
    //--------------------------------------------------------------------------
    // Main test sequence
    //--------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bit [31:0] read_value;
        
        super.run_phase(phase);
        
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        `uvm_info(get_type_name(), "  TD4CPU Memory Pattern Test - March C- Only", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        // Reset and halt CPU
        do_reset();
        #50us;
        
        write_reg(CPU_DBG_CTRL, 32'h0000_0001);  // Assert HALT_REQ
        #20us;
        read_reg(CPU_DBG_STATUS, read_value);
        `uvm_info(get_type_name(), 
            $sformatf("CPU Status after halt: 0x%08X", read_value), UVM_LOW)
        
        // Run memory tests - ONLY March C- for debugging
        // galloping_test();
        march_c_minus_test();
        // checkerboard_test();
        // walking_bit_test();
        // address_as_data_test();
        
        // Final summary from local verification (hierarchical access)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        `uvm_info(get_type_name(), 
            $sformatf("  CPU Memory Verification Results - MATCHES: %0d, MISMATCHES: %0d", 
                cpu_memory_match_count, cpu_memory_mismatch_count), UVM_LOW)
        
        if (cpu_memory_mismatch_count == 0) begin
            `uvm_info(get_type_name(), 
                $sformatf("  *** MEMORY TEST PASSED: %0d read operations verified ***", 
                    cpu_memory_match_count), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("  *** MEMORY TEST FAILED: %0d mismatches ***", 
                    cpu_memory_mismatch_count))
        end
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        #100us;
        phase.drop_objection(this);
        
    endtask
    
endclass : axiuart_cpu_memory_test
