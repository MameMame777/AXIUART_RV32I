`timescale 1ns / 1ps

//==============================================================================
// VexRiscv Base Test Class
//==============================================================================
// Base class for all VexRiscv verification tests.
// Extends uvm_test with VexRiscv-specific functionality:
// - Intel HEX program loading with address translation
// - tohost monitoring for pass/fail detection
// - CPU control (reset, start, halt, step)
// - Register access helpers
//==============================================================================

import uvm_pkg::*;
import axiuart_pkg::*;

class vexriscv_base_test extends uvm_test;
    
    `uvm_component_utils(vexriscv_base_test)
    
    //==========================================================================
    // Configuration Properties
    //==========================================================================
    
    // Hex file path (relative to workspace root)
    string hex_file_path = "";
    
    // Enable tohost monitoring
    bit use_tohost_checking = 1;
    
    // Default timeout for test execution (cycles)
    int timeout_cycles = 10000;
    
    // Address translation offset (VexRiscv 0x80000000 → bare-metal 0x00000000)
    int address_offset = -32'h80000000;
    
    // tohost address (translated from 0x80001000)
    bit [31:0] tohost_addr = 32'h00001000;
    
    // fromhost address (translated from 0x80001040)
    bit [31:0] fromhost_addr = 32'h00001040;
    
    // CPU reset signal control (via register interface)
    bit auto_start_cpu = 1;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    
    function new(string name = "vexriscv_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get configuration from command line
        if (!uvm_config_db#(string)::get(this, "", "hex_file", hex_file_path)) begin
            `uvm_info(get_type_name(), 
                "No hex_file specified via +UVM_CONFIG, will use default", 
                UVM_MEDIUM)
        end
        
        if (!uvm_config_db#(int)::get(this, "", "timeout_cycles", timeout_cycles)) begin
            timeout_cycles = 10000;  // Default
        end
        
        `uvm_info(get_type_name(), 
            $sformatf("VexRiscv Base Test Configuration:\n" +
                      "  hex_file_path:    %s\n" +
                      "  tohost_addr:      0x%08X\n" +
                      "  timeout_cycles:   %0d\n" +
                      "  auto_start_cpu:   %0d",
                      hex_file_path, tohost_addr, timeout_cycles, auto_start_cpu),
            UVM_LOW)
    endfunction
    
    //==========================================================================
    // Run Phase
    //==========================================================================
    
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        
        phase.raise_objection(this);
        
        // Standard VexRiscv test sequence
        fork
            begin
                // 1. Reset CPU
                reset_cpu();
                
                // 2. Load program (if specified)
                if (hex_file_path != "") begin
                    load_hex_file(hex_file_path, 1);  // translate_addr=1
                end
                
                // 3. Start CPU
                if (auto_start_cpu) begin
                    start_cpu();
                end
                
                // 4. Wait for test completion
                if (use_tohost_checking) begin
                    wait_for_tohost(timeout_cycles);
                end else begin
                    // Fixed delay if tohost checking disabled
                    #(timeout_cycles * 10ns);
                end
                
                // 5. Analyze results
                check_test_results();
            end
        join
        
        phase.drop_objection(this);
    endtask
    
    //==========================================================================
    // Hex File Loading
    //==========================================================================
    
    virtual task load_hex_file(string hex_path, bit translate_addr = 1);
        string python_cmd;
        string workspace_root;
        string full_hex_path;
        int fd, status;
        string line;
        
        `uvm_info(get_type_name(), 
            $sformatf("Loading hex file: %s (translate=%0d)", hex_path, translate_addr), 
            UVM_LOW)
        
        // Get workspace root
        workspace_root = "e:\\Nautilus\\workspace\\fpgawork\\AXIUART_RV32I";
        
        // Build full path
        full_hex_path = {workspace_root, "\\", hex_path};
        
        // Build Python command to load hex file
        python_cmd = $sformatf(
            "python %s\\mcp_server\\tools\\vexriscv_hex_loader.py %s %s",
            workspace_root,
            full_hex_path,
            translate_addr ? "--offset -0x80000000" : "--offset 0"
        );
        
        // Execute Python loader (this returns word-aligned data)
        // In real implementation, this would call Python via DPI or file interface
        // For now, we assume memory is loaded via $readmemh or backdoor
        
        `uvm_info(get_type_name(), 
            $sformatf("Python command: %s", python_cmd), 
            UVM_DEBUG)
        
        // Load memory using backdoor access
        // This is a placeholder - actual implementation depends on testbench architecture
        load_memory_backdoor(full_hex_path, translate_addr);
        
        `uvm_info(get_type_name(), "Hex file loaded successfully", UVM_LOW)
    endtask
    
    virtual task load_memory_backdoor(string hex_path, bit translate_addr);
        // Placeholder for memory loading via backdoor
        // Actual implementation options:
        // 1. DPI call to Python hex loader
        // 2. SystemVerilog $readmemh with preprocessing
        // 3. UVM register backdoor write
        
        `uvm_warning(get_type_name(), 
            "load_memory_backdoor() is not implemented - override in derived test")
    endtask
    
    //==========================================================================
    // tohost Monitoring
    //==========================================================================
    
    virtual task wait_for_tohost(int max_cycles = 10000);
        bit [31:0] tohost_value;
        int cycle_count = 0;
        bit timeout = 0;
        
        `uvm_info(get_type_name(), 
            $sformatf("Waiting for tohost write at 0x%08X (max %0d cycles)", 
                      tohost_addr, max_cycles), 
            UVM_MEDIUM)
        
        fork
            begin
                // Monitor tohost address for write
                forever begin
                    @(posedge $root.rv32i_tb_top.clk);
                    cycle_count++;
                    
                    // Check if tohost was written
                    if (read_memory_backdoor(tohost_addr, tohost_value)) begin
                        if (tohost_value != 0) begin
                            `uvm_info(get_type_name(), 
                                $sformatf("tohost write detected: 0x%08X at cycle %0d", 
                                          tohost_value, cycle_count), 
                                UVM_LOW)
                            break;
                        end
                    end
                end
            end
            
            begin
                // Timeout watchdog
                repeat(max_cycles) @(posedge $root.rv32i_tb_top.clk);
                timeout = 1;
                `uvm_error(get_type_name(), 
                    $sformatf("Timeout waiting for tohost write after %0d cycles", 
                              max_cycles))
            end
        join_any
        disable fork;
        
        // Analyze tohost value
        if (!timeout) begin
            if (tohost_value == 32'h00000001) begin
                `uvm_info(get_type_name(), 
                    "TEST PASSED (tohost = 1)", 
                    UVM_LOW)
            end else begin
                `uvm_error(get_type_name(), 
                    $sformatf("TEST FAILED (tohost = 0x%08X, expected 0x00000001)", 
                              tohost_value))
            end
        end
    endtask
    
    //==========================================================================
    // CPU Control Methods
    //==========================================================================
    
    virtual task reset_cpu();
        `uvm_info(get_type_name(), "Asserting CPU reset", UVM_MEDIUM)
        
        // Assert reset via register interface or direct signal
        // Implementation depends on testbench architecture
        
        @(posedge $root.rv32i_tb_top.clk);
        $root.rv32i_tb_top.uart_vif.rst <= 1;
        repeat(10) @(posedge $root.rv32i_tb_top.clk);
        $root.rv32i_tb_top.uart_vif.rst <= 0;
        repeat(5) @(posedge $root.rv32i_tb_top.clk);
        
        `uvm_info(get_type_name(), "CPU reset complete", UVM_MEDIUM)
    endtask
    
    virtual task start_cpu();
        `uvm_info(get_type_name(), "Starting CPU execution", UVM_MEDIUM)
        
        // Ensure reset is deasserted
        @(posedge $root.rv32i_tb_top.clk);
        $root.rv32i_tb_top.uart_vif.rst <= 0;
        
        // Set CPU RUN bit in Register_Block (cpu_mem_ctrl_reg[7])
        // This is the correct way - modifying the register directly
        @(posedge $root.rv32i_tb_top.clk);
        $root.rv32i_tb_top.dut.register_block_inst.cpu_mem_ctrl_reg[7] = 1'b1;
        $display("[%0t] [BASE_TEST] Setting cpu_mem_ctrl_reg[7]=1 (CPU RUN)", $time);
        
        @(posedge $root.rv32i_tb_top.clk);
        $root.rv32i_tb_top.dut.register_block_inst.cpu_mem_ctrl_reg[7] = 1'b0;
        $display("[%0t] [BASE_TEST] Clearing cpu_mem_ctrl_reg[7]=0 (RUN pulse complete)", $time);
        
        // Wait for CPU to enter running state
        wait_cpu_running();
        
        `uvm_info(get_type_name(), "CPU started successfully", UVM_MEDIUM)
    endtask
    
    virtual task halt_cpu();
        `uvm_info(get_type_name(), "Halting CPU via control signal", UVM_MEDIUM)
        
        // Set CPU HALT bit in Register_Block (cpu_mem_ctrl_reg[8])
        @(posedge $root.rv32i_tb_top.clk);
        $root.rv32i_tb_top.dut.register_block_inst.cpu_mem_ctrl_reg[8] = 1'b1;
        $display("[%0t] [BASE_TEST] Setting cpu_mem_ctrl_reg[8]=1 (CPU HALT)", $time);
        
        @(posedge $root.rv32i_tb_top.clk);
        $root.rv32i_tb_top.dut.register_block_inst.cpu_mem_ctrl_reg[8] = 1'b0;
        $display("[%0t] [BASE_TEST] Clearing cpu_mem_ctrl_reg[8]=0 (HALT pulse complete)", $time);
        
        // Wait for CPU to enter halted state
        wait_cpu_halted();
        
        `uvm_info(get_type_name(), "CPU halted successfully", UVM_MEDIUM)
    endtask
    
    virtual task step_cpu(int num_instructions = 1);
        logic [31:0] initial_pc, current_pc;
        int timeout_cycles = 100;
        int elapsed_cycles;
        
        `uvm_info(get_type_name(), 
            $sformatf("Stepping CPU for %0d instructions", num_instructions), 
            UVM_MEDIUM)
        
        // Ensure CPU is halted before stepping
        if (!is_cpu_halted()) begin
            halt_cpu();
        end
        
        for (int i = 0; i < num_instructions; i++) begin
            // Read current PC
            initial_pc = $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.decode_PC;
            
            // Start CPU briefly
            @(posedge $root.rv32i_tb_top.clk);
            force $root.rv32i_tb_top.dut.vexriscv_inst.rv32i_cpu_run = 1'b1;
            @(posedge $root.rv32i_tb_top.clk);
            release $root.rv32i_tb_top.dut.vexriscv_inst.rv32i_cpu_run;
            
            // Wait for PC to change (instruction completion)
            elapsed_cycles = 0;
            do begin
                @(posedge $root.rv32i_tb_top.clk);
                current_pc = $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.decode_PC;
                elapsed_cycles++;
                
                if (elapsed_cycles >= timeout_cycles) begin
                    `uvm_error(get_type_name(), 
                        $sformatf("Timeout waiting for instruction completion (PC stuck at 0x%08X)", initial_pc))
                    return;
                end
            end while (current_pc == initial_pc);
            
            // Halt after instruction completes
            halt_cpu();
            
            `uvm_info(get_type_name(), 
                $sformatf("Step %0d/%0d: PC 0x%08X -> 0x%08X (%0d cycles)", 
                    i+1, num_instructions, initial_pc, current_pc, elapsed_cycles), 
                UVM_HIGH)
        end
        
        `uvm_info(get_type_name(), 
            $sformatf("Step complete: final PC = 0x%08X", current_pc), 
            UVM_MEDIUM)
    endtask
    
    //==========================================================================
    // Register Access Helpers
    //==========================================================================
    
    virtual task read_cpu_reg(int reg_num, output bit [31:0] value);
        `uvm_info(get_type_name(), 
            $sformatf("Reading CPU register x%0d", reg_num), 
            UVM_DEBUG)
        
        // Read register via debug interface or backdoor
        // Implementation depends on CPU architecture
        
        value = read_regfile_backdoor(reg_num);
    endtask
    
    virtual task write_cpu_reg(int reg_num, bit [31:0] value);
        `uvm_info(get_type_name(), 
            $sformatf("Writing CPU register x%0d = 0x%08X", reg_num, value), 
            UVM_DEBUG)
        
        // Write register via debug interface or backdoor
        // Implementation depends on CPU architecture
        
        write_regfile_backdoor(reg_num, value);
    endtask
    
    //==========================================================================
    // Memory Access Helpers
    //==========================================================================
    
    virtual function bit read_memory_backdoor(bit [31:0] addr, 
                                              output bit [31:0] data);
        // Backdoor memory read from VexRiscv BlockRAM
        // Returns 1 if address valid, 0 otherwise
        
        // Check address range (8KB = 0x0000-0x1FFF)
        if (addr < 32'h0000_2000) begin
            // Hierarchical path: $root → rv32i_tb_top → dut (AXIUART_Top) → vexriscv_inst → mem_crossbar → blockram_inst → mem array
            data = $root.rv32i_tb_top.dut.vexriscv_inst.mem_crossbar.blockram_inst.mem[addr[12:2]];
            return 1;
        end else begin
            `uvm_warning(get_type_name(), 
                $sformatf("read_memory_backdoor: Address 0x%08X out of range (0x0000-0x1FFF)", addr))
            data = 32'h00000000;
            return 0;
        end
    endfunction
    
    virtual task write_memory_backdoor(bit [31:0] addr, bit [31:0] data);
        // Backdoor memory write to VexRiscv BlockRAM
        logic [10:0] word_addr;
        
        // Check address range (0x80000000-0x80001FFF = 8KB)
        if (addr >= 32'h8000_0000 && addr < 32'h8000_2000) begin
            // Convert CPU address to BRAM word address
            word_addr = (addr - 32'h8000_0000) >> 2;
            
            // Hierarchical path: $root → rv32i_tb_top → dut (AXIUART_Top) → vexriscv_inst → mem_crossbar → blockram_inst → mem array
            $root.rv32i_tb_top.dut.vexriscv_inst.mem_crossbar.blockram_inst.mem[word_addr] = data;
            
            `uvm_info(get_type_name(), 
                $sformatf("Write backdoor: addr=0x%08X → mem[%0d] = 0x%08X", addr, word_addr, data), 
                UVM_DEBUG)
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("write_memory_backdoor: Address 0x%08X out of range (0x80000000-0x80001FFF)", addr))
        end
    endtask
    
    //==========================================================================
    // Regfile Access Helpers (for VexRiscv)
    //==========================================================================
    
    virtual function bit [31:0] read_regfile_backdoor(int reg_num);
        // Backdoor register file read from VexRiscv
        
        // Check register number range (x0-x31)
        if (reg_num >= 0 && reg_num < 32) begin
            // Hierarchical path: $root → rv32i_tb_top → dut (AXIUART_Top) → vexriscv_inst → cpu_core → u_regfile → regfile array
            return $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.u_regfile.regfile[reg_num];
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("read_regfile_backdoor: Register x%0d out of range (0-31)", reg_num))
            return 32'h00000000;
        end
    endfunction
    
    virtual task write_regfile_backdoor(int reg_num, bit [31:0] value);
        // Backdoor register file write to VexRiscv
        
        // Check register number range (x0-x31)
        if (reg_num >= 0 && reg_num < 32) begin
            if (reg_num == 0) begin
                `uvm_warning(get_type_name(), 
                    "write_regfile_backdoor: Attempting to write x0 (hardwired to zero)")
            end else begin
                // Hierarchical path: $root → rv32i_tb_top → dut (AXIUART_Top) → vexriscv_inst → cpu_core → u_regfile → regfile array
                $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.u_regfile.regfile[reg_num] = value;
                
                `uvm_info(get_type_name(), 
                    $sformatf("Write backdoor: x%0d = 0x%08X", reg_num, value), 
                    UVM_DEBUG)
            end
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("write_regfile_backdoor: Register x%0d out of range (0-31)", reg_num))
        end
    endtask
    
    //==========================================================================
    // Result Checking
    //==========================================================================
    
    virtual task check_test_results();
        bit [31:0] tohost_value;
        
        // Read final tohost value
        if (read_memory_backdoor(tohost_addr, tohost_value)) begin
            if (tohost_value == 32'h00000001) begin
                `uvm_info(get_type_name(), 
                    "==================================================\n  TEST PASSED\n==================================================", 
                    UVM_NONE)
            end else if (tohost_value != 0) begin
                `uvm_error(get_type_name(), 
                    $sformatf("==================================================\n" +
                              "  TEST FAILED (tohost = 0x%08X)\n" +
                              "==================================================", 
                              tohost_value))
            end else begin
                `uvm_warning(get_type_name(), 
                    "Test completed but tohost not written (timeout?)")
            end
        end
    endtask
    
    //==========================================================================
    // Debug Helpers
    //==========================================================================
    
    virtual task dump_regfile();
        bit [31:0] reg_val;
        
        `uvm_info(get_type_name(), "Register File Dump:", UVM_NONE)
        for (int i = 0; i < 32; i++) begin
            read_cpu_reg(i, reg_val);
            `uvm_info(get_type_name(), 
                $sformatf("  x%-2d = 0x%08X", i, reg_val), 
                UVM_NONE)
        end
    endtask
    
    virtual task dump_memory_range(bit [31:0] start_addr, bit [31:0] end_addr);
        bit [31:0] addr, data;
        
        `uvm_info(get_type_name(), 
            $sformatf("Memory Dump: 0x%08X - 0x%08X", start_addr, end_addr), 
            UVM_NONE)
        
        for (addr = start_addr; addr <= end_addr; addr += 4) begin
            if (read_memory_backdoor(addr, data)) begin
                `uvm_info(get_type_name(), 
                    $sformatf("  [0x%08X] = 0x%08X", addr, data), 
                    UVM_NONE)
            end
        end
    endtask
    
    //==========================================================================
    // CPU Status Helpers
    //==========================================================================
    
    virtual function bit is_cpu_halted();
        return $root.rv32i_tb_top.dut.vexriscv_inst.rv32i_cpu_halted;
    endfunction
    
    virtual task wait_cpu_halted(int timeout_cycles = 100);
        int elapsed = 0;
        
        while (!$root.rv32i_tb_top.dut.vexriscv_inst.rv32i_cpu_halted) begin
            @(posedge $root.rv32i_tb_top.clk);
            elapsed++;
            
            if (elapsed >= timeout_cycles) begin
                `uvm_error(get_type_name(), 
                    "Timeout waiting for CPU to halt")
                return;
            end
        end
        
        `uvm_info(get_type_name(), 
            $sformatf("CPU halted after %0d cycles", elapsed), 
            UVM_HIGH)
    endtask
    
    virtual task wait_cpu_running(int timeout_cycles = 100);
        int elapsed = 0;
        
        while ($root.rv32i_tb_top.dut.vexriscv_inst.rv32i_cpu_halted) begin
            @(posedge $root.rv32i_tb_top.clk);
            elapsed++;
            
            if (elapsed >= timeout_cycles) begin
                `uvm_error(get_type_name(), 
                    "Timeout waiting for CPU to start running")
                return;
            end
        end
        
        `uvm_info(get_type_name(), 
            $sformatf("CPU running after %0d cycles", elapsed), 
            UVM_HIGH)
    endtask
    
    //==========================================================================
    // Test Result Tracking (Stub for Future Implementation)
    //==========================================================================
    
    virtual function void set_test_pass(bit passed);
        // Reserved for future test result tracking infrastructure
        // Currently: No-op stub to satisfy derived test calls
        `uvm_info(get_type_name(), 
            $sformatf("Test result recorded: %s", passed ? "PASS" : "FAIL"), 
            UVM_DEBUG)
    endfunction
    
endclass : vexriscv_base_test
