//------------------------------------------------------------------------------
// AXIUART Base Test
// Purpose: Foundation test class with common infrastructure
// Features:
//   - Environment validation (hang prevention)
//   - Global timeout management (default: 30s)
//   - UVM error/warning tracking
//   - Configurable test parameters via command line
//   - Debug mode support
//   - Strict mode (fail on warnings)
// Usage:
//   +GLOBAL_TIMEOUT=60000  // Set 60s timeout (milliseconds)
//   +DEBUG_MODE=1          // Enable debug logging
//   +STRICT_MODE=1         // Fail on warnings
//   +TOPOLOGY_DEPTH=5      // Set topology print depth
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

class axiuart_base_test extends uvm_test;
    `uvm_component_utils(axiuart_base_test)
    
    // Environment
    axiuart_env env;
    uvm_table_printer printer;
    
    // Test control
    bit test_pass = 1;
    int initial_error_count = 0;
    int final_error_count = 0;
    int initial_warning_count = 0;
    int final_warning_count = 0;
    
    // Configurable parameters (can be overridden via config_db or command line)
    int global_timeout_ms = 30000;   // 30 seconds default
    bit enable_timeout = 1;           // Timeout protection enabled by default
    bit enable_debug_mode = 0;        // Debug mode (extra checks/logging)
    bit strict_mode = 0;              // Fail on any UVM_WARNING
    int topology_print_depth = 3;     // Topology print depth
    bit auto_validation = 1;          // Automatic environment validation
    
    function new(string name = "axiuart_base_test", uvm_component parent = null);
        super.new(name, parent);
        
        // Get configuration from command line
        void'($value$plusargs("GLOBAL_TIMEOUT=%d", global_timeout_ms));
        void'($value$plusargs("DEBUG_MODE=%d", enable_debug_mode));
        void'($value$plusargs("STRICT_MODE=%d", strict_mode));
        void'($value$plusargs("TOPOLOGY_DEPTH=%d", topology_print_depth));
        void'($value$plusargs("AUTO_VALIDATION=%d", auto_validation));
        
        if (enable_debug_mode) begin
            `uvm_info("BASE_TEST", 
                $sformatf("Configuration: timeout=%0dms, strict=%0d, depth=%0d", 
                    global_timeout_ms, strict_mode, topology_print_depth), UVM_LOW)
        end
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (enable_debug_mode) begin
            `uvm_info("BASE_TEST", "Starting build phase...", UVM_MEDIUM)
        end
        
        // Set recording detail
        uvm_config_db#(int)::set(this, "*", "recording_detail", UVM_FULL);
        
        // Create environment
        env = axiuart_env::type_id::create("env", this);
        if (env == null) begin
            `uvm_fatal("BASE_TEST", 
                {"Failed to create environment!\n",
                 "  Possible causes:\n",
                 "  - axiuart_env not registered with factory\n",
                 "  - Factory override error\n",
                 "  Check: `uvm_component_utils(axiuart_env)"})
        end
        
        // Configure printer
        printer = new();
        printer.knobs.depth = topology_print_depth;
        
        if (enable_debug_mode) begin
            `uvm_info("BASE_TEST", "Build phase completed successfully", UVM_MEDIUM)
        end
    endfunction
    
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        uvm_report_server server;
        server = uvm_report_server::get_server();
        
        // Print topology
        `uvm_info(get_type_name(),
            $sformatf("Printing test topology:\n%s", this.sprint(printer)), UVM_LOW)
        
        // Validate environment if enabled
        if (auto_validation) begin
            validate_environment();
        end
        
        // Store initial error/warning counts
        initial_error_count = server.get_severity_count(UVM_ERROR);
        initial_warning_count = server.get_severity_count(UVM_WARNING);
        
        if (enable_debug_mode) begin
            `uvm_info("BASE_TEST", 
                $sformatf("Elaboration complete - errors=%0d, warnings=%0d", 
                    initial_error_count, initial_warning_count), UVM_MEDIUM)
        end
    endfunction
    
    //--------------------------------------------------------------------------
    // Environment Validation - Prevents silent failures and hangs
    //--------------------------------------------------------------------------
    virtual function void validate_environment();
        bit validation_passed = 1;
        
        if (enable_debug_mode) begin
            `uvm_info("BASE_TEST", "Starting environment validation...", UVM_MEDIUM)
        end
        
        // Check environment
        if (env == null) begin
            `uvm_fatal("BASE_TEST", 
                {"Environment is NULL after build phase!\n",
                 "  This is a critical failure - test cannot proceed.\n",
                 "  Check: build_phase() in base test"})
            validation_passed = 0;
        end
        
        // Check agent
        if (env.uart_agt == null) begin
            `uvm_fatal("BASE_TEST", 
                {"UART agent is NULL!\n",
                 "  Likely cause: axiuart_env.build_phase() failed\n",
                 "  Check: Agent creation in environment"})
            validation_passed = 0;
        end
        
        // Validate sequencer (warning only - passive mode is valid)
        if (env.uart_agt.sequencer == null) begin
            `uvm_warning("BASE_TEST", 
                {"UART sequencer is NULL!\n",
                 "  Agent may be configured as UVM_PASSIVE.\n",
                 "  Sequence-based tests will not work.\n",
                 "  If this is intentional, ignore this warning.\n",
                 "  If not, check: agent is_active configuration"})
        end else if (enable_debug_mode) begin
            `uvm_info("BASE_TEST", "✓ Sequencer available", UVM_MEDIUM)
        end
        
        // Check driver (warning only)
        if (env.uart_agt.driver == null) begin
            `uvm_warning("BASE_TEST", 
                {"UART driver is NULL!\n",
                 "  Agent is configured as UVM_PASSIVE.\n",
                 "  Sequence items will not be driven."})
        end else if (enable_debug_mode) begin
            `uvm_info("BASE_TEST", "✓ Driver available", UVM_MEDIUM)
        end
        
        // Check monitor
        if (env.uart_agt.monitor == null) begin
            `uvm_warning("BASE_TEST", "UART monitor is NULL!")
        end else if (enable_debug_mode) begin
            `uvm_info("BASE_TEST", "✓ Monitor available", UVM_MEDIUM)
        end
        
        // Check scoreboard
        if (env.scoreboard == null) begin
            `uvm_warning("BASE_TEST", "Scoreboard is NULL!")
        end else if (enable_debug_mode) begin
            `uvm_info("BASE_TEST", "✓ Scoreboard available", UVM_MEDIUM)
        end
        
        if (validation_passed) begin
            `uvm_info("BASE_TEST", "✓ Environment validation passed", UVM_LOW)
        end
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        // Set drain time
        phase.phase_done.set_drain_time(this, 50);
        
        // Optional: Global timeout protection (simple time-based)
        if (enable_timeout) begin
            if (enable_debug_mode) begin
                `uvm_info("BASE_TEST", 
                    $sformatf("Global timeout watchdog active: %0dms", global_timeout_ms), 
                    UVM_MEDIUM)
            end
            
            fork
                begin
                    // Timeout watchdog - runs in background
                    #(global_timeout_ms * 1ms);
                    `uvm_fatal("BASE_TEST", 
                        $sformatf({"Global timeout (%0dms) exceeded!\n",
                                   "  Test appears to be hung.\n",
                                   "  Common causes:\n",
                                   "  - Infinite loop in test code\n",
                                   "  - Waiting for event that never occurs\n",
                                   "  - Sequence not completing\n",
                                   "  - Missing objection drop\n",
                                   "  Increase timeout with +GLOBAL_TIMEOUT=<ms> if needed"}, 
                            global_timeout_ms))
                end
            join_none
        end
    endtask
    
    virtual function void report_phase(uvm_phase phase);
        uvm_report_server server;
        int error_delta, warning_delta;
        bit local_pass;
        
        server = uvm_report_server::get_server();
        
        // Get final counts
        final_error_count = server.get_severity_count(UVM_ERROR);
        final_warning_count = server.get_severity_count(UVM_WARNING);
        
        // Calculate deltas
        error_delta = final_error_count - initial_error_count;
        warning_delta = final_warning_count - initial_warning_count;
        
        // Determine pass/fail
        local_pass = test_pass && (error_delta == 0);
        
        // Strict mode: fail on warnings too
        if (strict_mode && warning_delta > 0) begin
            local_pass = 0;
            `uvm_error(get_type_name(), 
                $sformatf("STRICT MODE VIOLATION: %0d warning(s) detected during test", 
                    warning_delta))
        end
        
        // Print detailed summary
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        `uvm_info(get_type_name(), "       TEST SUMMARY REPORT", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        `uvm_info(get_type_name(), 
            $sformatf("Test Name:     %s", get_type_name()), UVM_LOW)
        `uvm_info(get_type_name(), 
            $sformatf("Errors:        %0d (initial: %0d, delta: %0d)", 
                final_error_count, initial_error_count, error_delta), UVM_LOW)
        `uvm_info(get_type_name(), 
            $sformatf("Warnings:      %0d (initial: %0d, delta: %0d)", 
                final_warning_count, initial_warning_count, warning_delta), UVM_LOW)
        `uvm_info(get_type_name(), 
            $sformatf("Strict Mode:   %s", strict_mode ? "ENABLED" : "DISABLED"), UVM_LOW)
        `uvm_info(get_type_name(), 
            $sformatf("Timeout:       %0dms", global_timeout_ms), UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        // Final verdict
        if(local_pass) begin
            `uvm_info(get_type_name(), "** UVM TEST PASSED **", UVM_NONE)
        end else begin
            `uvm_error(get_type_name(), "** UVM TEST FAILED **")
        end
        
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
    endfunction
    
    //--------------------------------------------------------------------------
    // Utility Functions - For derived classes
    //--------------------------------------------------------------------------
    
    // Set test pass/fail status
    virtual function void set_test_pass(bit pass);
        test_pass = pass;
        if (enable_debug_mode) begin
            `uvm_info("BASE_TEST", 
                $sformatf("Test status set to: %s", pass ? "PASS" : "FAIL"), UVM_MEDIUM)
        end
    endfunction
    
    // Get test pass/fail status
    virtual function bit get_test_pass();
        return test_pass;
    endfunction
    
    // Get error count delta since test start
    virtual function int get_error_delta();
        uvm_report_server server;
        server = uvm_report_server::get_server();
        return server.get_severity_count(UVM_ERROR) - initial_error_count;
    endfunction
    
    // Get warning count delta since test start
    virtual function int get_warning_delta();
        uvm_report_server server;
        server = uvm_report_server::get_server();
        return server.get_severity_count(UVM_WARNING) - initial_warning_count;
    endfunction
    
endclass
