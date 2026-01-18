`timescale 1ns / 1ps

//==============================================================================
// VexRiscv tohost Monitor
//==============================================================================
// UVM monitor for VexRiscv test completion detection.
// Watches memory writes to tohost address (0x00001000) for pass/fail status.
//
// Pass/Fail Protocol:
// - tohost = 1: Test PASSED
// - tohost = other non-zero: Test FAILED (error code)
// - tohost = 0: Test still running
//
// Usage:
//   vexriscv_tohost_monitor monitor;
//   monitor.tohost_addr = 32'h00001000;
//   @(monitor.tohost_event);  // Wait for tohost write
//   if (monitor.test_passed) $display("PASS");
//==============================================================================

class vexriscv_tohost_monitor extends uvm_monitor;
    
    `uvm_component_utils(vexriscv_tohost_monitor)
    
    //==========================================================================
    // Configuration
    //==========================================================================
    
    // tohost address to monitor (default: 0x00001000)
    bit [31:0] tohost_addr = 32'h00001000;
    
    // fromhost address (optional bidirectional communication)
    bit [31:0] fromhost_addr = 32'h00001040;
    
    // Enable verbose logging
    bit verbose = 0;
    
    //==========================================================================
    // Status Flags
    //==========================================================================
    
    // Test completion detected
    bit test_completed = 0;
    
    // Test result
    bit test_passed = 0;
    
    // tohost value written by test
    bit [31:0] tohost_value = 0;
    
    // Cycle count when tohost was written
    int completion_cycle = 0;
    
    //==========================================================================
    // Events
    //==========================================================================
    
    // Triggered when tohost is written
    event tohost_event;
    
    // Triggered when test passes
    event test_pass_event;
    
    // Triggered when test fails
    event test_fail_event;
    
    //==========================================================================
    // Analysis Port (for scoreboard connection)
    //==========================================================================
    
    uvm_analysis_port #(bit [31:0]) tohost_ap;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    
    function new(string name = "vexriscv_tohost_monitor", uvm_component parent = null);
        super.new(name, parent);
        tohost_ap = new("tohost_ap", this);
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get configuration from UVM config DB
        if (!uvm_config_db#(bit [31:0])::get(this, "", "tohost_addr", tohost_addr)) begin
            tohost_addr = 32'h00001000;  // Default
        end
        
        if (!uvm_config_db#(bit [31:0])::get(this, "", "fromhost_addr", fromhost_addr)) begin
            fromhost_addr = 32'h00001040;  // Default
        end
        
        if (!uvm_config_db#(bit)::get(this, "", "verbose", verbose)) begin
            verbose = 0;
        end
        
        `uvm_info(get_type_name(), 
            $sformatf("tohost Monitor Configuration:\n" +
                      "  tohost_addr:   0x%08X\n" +
                      "  fromhost_addr: 0x%08X\n" +
                      "  verbose:       %0d",
                      tohost_addr, fromhost_addr, verbose),
            UVM_MEDIUM)
    endfunction
    
    //==========================================================================
    // Run Phase
    //==========================================================================
    
    virtual task run_phase(uvm_phase phase);
        fork
            monitor_tohost();
        join_none
    endtask
    
    //==========================================================================
    // Monitor tohost Address
    //==========================================================================
    
    virtual task monitor_tohost();
        bit [31:0] current_value = 0;
        bit [31:0] prev_value = 0;
        int cycle = 0;
        
        `uvm_info(get_type_name(), 
            $sformatf("Started monitoring tohost at 0x%08X", tohost_addr), 
            UVM_LOW)
        
        forever begin
            @(posedge top.clk);
            cycle++;
            
            // Read tohost address via backdoor
            if (read_tohost_backdoor(current_value)) begin
                
                // Detect write (transition from 0 to non-zero)
                if (current_value != 0 && prev_value == 0) begin
                    
                    // Test completion detected
                    test_completed = 1;
                    tohost_value = current_value;
                    completion_cycle = cycle;
                    
                    // Determine pass/fail
                    test_passed = (current_value == 32'h00000001);
                    
                    // Log result
                    if (test_passed) begin
                        `uvm_info(get_type_name(), 
                            $sformatf("TEST PASSED at cycle %0d (tohost = 0x%08X)", 
                                      cycle, current_value), 
                            UVM_LOW)
                        -> test_pass_event;
                    end else begin
                        `uvm_error(get_type_name(), 
                            $sformatf("TEST FAILED at cycle %0d (tohost = 0x%08X)", 
                                      cycle, current_value))
                        -> test_fail_event;
                    end
                    
                    // Trigger tohost event
                    -> tohost_event;
                    
                    // Send to analysis port
                    tohost_ap.write(current_value);
                    
                    // Stop monitoring after first write
                    break;
                    
                end else if (verbose && current_value != prev_value) begin
                    `uvm_info(get_type_name(), 
                        $sformatf("tohost changed: 0x%08X -> 0x%08X at cycle %0d", 
                                  prev_value, current_value, cycle), 
                        UVM_DEBUG)
                end
                
                prev_value = current_value;
            end
        end
        
        `uvm_info(get_type_name(), "Monitoring stopped (test completed)", UVM_MEDIUM)
    endtask
    
    //==========================================================================
    // Backdoor Memory Read
    //==========================================================================
    
    virtual function bit read_tohost_backdoor(output bit [31:0] data);
        // Placeholder for backdoor memory read
        // Returns 1 if read successful, 0 otherwise
        
        // Implementation depends on testbench memory architecture
        // Examples:
        // 1. Hierarchical reference to BlockRAM:
        //    data = top.u_blockram.mem[tohost_addr[12:2]];
        // 2. Hierarchical reference to system memory:
        //    data = top.u_memory.read_word(tohost_addr);
        // 3. AXI backdoor monitor:
        //    data = axi_monitor.read_address(tohost_addr);
        
        // For now, return failure (must be overridden or configured)
        `uvm_warning(get_type_name(), 
            "read_tohost_backdoor() not implemented - override in derived class")
        data = 32'h00000000;
        return 0;
    endfunction
    
    //==========================================================================
    // Helper Methods
    //==========================================================================
    
    // Wait for tohost write with timeout
    virtual task wait_for_tohost(int timeout_cycles = 10000);
        int start_cycle;
        bit timeout = 0;
        
        if (test_completed) begin
            `uvm_info(get_type_name(), 
                "Test already completed (tohost already written)", 
                UVM_MEDIUM)
            return;
        end
        
        `uvm_info(get_type_name(), 
            $sformatf("Waiting for tohost write (timeout = %0d cycles)", timeout_cycles), 
            UVM_MEDIUM)
        
        fork
            begin
                // Wait for tohost event
                @(tohost_event);
            end
            
            begin
                // Timeout watchdog
                repeat(timeout_cycles) @(posedge top.clk);
                timeout = 1;
            end
        join_any
        disable fork;
        
        if (timeout) begin
            `uvm_error(get_type_name(), 
                $sformatf("Timeout waiting for tohost write after %0d cycles", 
                          timeout_cycles))
        end
    endtask
    
    // Check if test passed
    virtual function bit is_test_passed();
        return test_completed && test_passed;
    endfunction
    
    // Check if test failed
    virtual function bit is_test_failed();
        return test_completed && !test_passed;
    endfunction
    
    // Get test result as string
    virtual function string get_result_string();
        if (!test_completed) begin
            return "RUNNING";
        end else if (test_passed) begin
            return "PASSED";
        end else begin
            return $sformatf("FAILED (error code: 0x%08X)", tohost_value);
        end
    endfunction
    
    // Reset monitor state
    virtual function void reset_monitor();
        test_completed = 0;
        test_passed = 0;
        tohost_value = 0;
        completion_cycle = 0;
        
        `uvm_info(get_type_name(), "Monitor state reset", UVM_MEDIUM)
    endfunction
    
    //==========================================================================
    // Report Phase
    //==========================================================================
    
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        if (test_completed) begin
            `uvm_info(get_type_name(), 
                $sformatf("==================================================\n" +
                          "  tohost Monitor Summary\n" +
                          "==================================================\n" +
                          "  Result:          %s\n" +
                          "  tohost value:    0x%08X\n" +
                          "  Completion cycle: %0d\n" +
                          "==================================================",
                          get_result_string(), tohost_value, completion_cycle),
                UVM_NONE)
        end else begin
            `uvm_warning(get_type_name(), 
                "Test completed but tohost was never written")
        end
    endfunction
    
endclass : vexriscv_tohost_monitor


//==============================================================================
// VexRiscv tohost Monitor with BlockRAM Backdoor
//==============================================================================
// Concrete implementation for systems using BlockRAM.
// Directly reads from BlockRAM via hierarchical reference.
//==============================================================================

class vexriscv_tohost_monitor_blockram extends vexriscv_tohost_monitor;
    
    `uvm_component_utils(vexriscv_tohost_monitor_blockram)
    
    // Hierarchical path to BlockRAM
    string blockram_path = "top.u_blockram.mem";
    
    function new(string name = "vexriscv_tohost_monitor_blockram", 
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(string)::get(this, "", "blockram_path", blockram_path)) begin
            blockram_path = "top.u_blockram.mem";
        end
        
        `uvm_info(get_type_name(), 
            $sformatf("BlockRAM path: %s", blockram_path), 
            UVM_MEDIUM)
    endfunction
    
    virtual function bit read_tohost_backdoor(output bit [31:0] data);
        // Read from BlockRAM via hierarchical reference
        // Word address = byte address / 4
        int word_addr = tohost_addr >> 2;
        
        // Hierarchical reference (must be adapted to actual testbench)
        // data = top.u_blockram.mem[word_addr];
        
        // For now, placeholder
        `uvm_warning(get_type_name(), 
            "read_tohost_backdoor() using BlockRAM not yet connected - " +
            "update hierarchical path")
        data = 32'h00000000;
        return 0;
    endfunction
    
endclass : vexriscv_tohost_monitor_blockram
