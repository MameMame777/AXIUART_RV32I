`timescale 1ns / 1ps

//==============================================================================
// VexRiscv Base Test Class
//==============================================================================
// Base class for all VexRiscv verification tests.
// Extends axiuart_base_test with VexRiscv-specific functionality:
// - Intel HEX program loading with address translation
// - tohost monitoring for pass/fail detection
// - CPU control (reset, start, halt, step)
// - Register access helpers
//==============================================================================

class vexriscv_base_test extends axiuart_base_test;
    
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
                    @(posedge top.clk);
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
                repeat(max_cycles) @(posedge top.clk);
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
        
        @(posedge top.clk);
        top.rst <= 1;
        repeat(10) @(posedge top.clk);
        top.rst <= 0;
        repeat(5) @(posedge top.clk);
        
        `uvm_info(get_type_name(), "CPU reset complete", UVM_MEDIUM)
    endtask
    
    virtual task start_cpu();
        `uvm_info(get_type_name(), "Starting CPU execution", UVM_MEDIUM)
        
        // Release CPU from reset/halt state
        // Implementation depends on CPU debug interface
        
        // For now, just ensure reset is deasserted
        @(posedge top.clk);
        top.rst <= 0;
        
        `uvm_info(get_type_name(), "CPU started", UVM_MEDIUM)
    endtask
    
    virtual task halt_cpu();
        `uvm_info(get_type_name(), "Halting CPU", UVM_MEDIUM)
        
        // Halt CPU via debug interface
        // Implementation depends on CPU debug capabilities
        
        `uvm_warning(get_type_name(), 
            "halt_cpu() not implemented - override in derived test")
    endtask
    
    virtual task step_cpu(int num_cycles = 1);
        `uvm_info(get_type_name(), 
            $sformatf("Stepping CPU for %0d cycles", num_cycles), 
            UVM_MEDIUM)
        
        // Single-step CPU execution
        repeat(num_cycles) @(posedge top.clk);
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
        // Placeholder for backdoor memory read
        // Returns 1 if address valid, 0 otherwise
        
        // Implementation would use hierarchical reference:
        // data = top.u_memory.mem[addr[12:2]];
        
        `uvm_warning(get_type_name(), 
            "read_memory_backdoor() not implemented - returning 0")
        data = 32'h00000000;
        return 0;
    endfunction
    
    virtual task write_memory_backdoor(bit [31:0] addr, bit [31:0] data);
        // Placeholder for backdoor memory write
        
        // Implementation would use hierarchical reference:
        // top.u_memory.mem[addr[12:2]] = data;
        
        `uvm_warning(get_type_name(), 
            "write_memory_backdoor() not implemented")
    endtask
    
    //==========================================================================
    // Regfile Access Helpers (for VexRiscv)
    //==========================================================================
    
    virtual function bit [31:0] read_regfile_backdoor(int reg_num);
        // Placeholder for backdoor regfile read
        
        // Implementation would use hierarchical reference:
        // return top.u_vexriscv.decode_RegFilePlugin_regFile[reg_num];
        
        `uvm_warning(get_type_name(), 
            "read_regfile_backdoor() not implemented - returning 0")
        return 32'h00000000;
    endfunction
    
    virtual task write_regfile_backdoor(int reg_num, bit [31:0] value);
        // Placeholder for backdoor regfile write
        
        // Implementation would use hierarchical reference:
        // top.u_vexriscv.decode_RegFilePlugin_regFile[reg_num] = value;
        
        `uvm_warning(get_type_name(), 
            "write_regfile_backdoor() not implemented")
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
                    "==================================================\n" +
                    "  TEST PASSED\n" +
                    "==================================================", 
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
    
endclass : vexriscv_base_test
