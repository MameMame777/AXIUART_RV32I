//------------------------------------------------------------------------------
// CPU Test Base Class - Common functionality for all CPU tests
// Purpose: Eliminate code duplication and standardize test patterns
// Usage: Extend this class and implement run_test_sequence()
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

import uvm_pkg::*;
import td4cpu_isa_pkg::*;
import axiuart_reg_pkg::*;

virtual class axiuart_cpu_test_base extends axiuart_base_test;
    
    // Register addresses (from package)
    localparam bit [31:0] CPU_DBG_CTRL     = REG_CPU_DBG_CTRL;
    localparam bit [31:0] CPU_DBG_STATUS   = REG_CPU_DBG_STATUS;
    localparam bit [31:0] CPU_PC           = REG_CPU_PC;
    localparam bit [31:0] CPU_REG_INDEX    = REG_CPU_REG_INDEX;
    localparam bit [31:0] CPU_REG_DATA     = REG_CPU_REG_DATA;
    localparam bit [31:0] CPU_MEM_ADDR     = REG_CPU_MEM_ADDR;
    localparam bit [31:0] CPU_MEM_WDATA    = REG_CPU_MEM_WDATA;
    localparam bit [31:0] CPU_MEM_RDATA    = REG_CPU_MEM_RDATA;
    localparam bit [31:0] CPU_MEM_CTRL     = REG_CPU_MEM_CTRL;
    localparam bit [31:0] CPU_TRACE_BUF_ADDR = 32'h0034;
    localparam bit [31:0] CPU_TRACE_BUF_DATA = 32'h0038;
    
    // Test configuration
    int reset_cycles = 200;
    int step_timeout_cycles = 50;
    bit enable_debug_logging = 0;
    
    // Test statistics
    int tests_passed = 0;
    int tests_failed = 0;
    
    function new(string name, uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    // Pure virtual - must be implemented by derived tests
    pure virtual task run_test_sequence();
    
    //--------------------------------------------------------------------------
    // Environment Validation - Prevents silent hangs
    //--------------------------------------------------------------------------
    protected function void validate_test_environment();
        // Check environment exists
        if (env == null) begin
            `uvm_fatal(get_type_name(), 
                {"Environment is NULL!\n",
                 "  Likely cause: axiuart_base_test.build_phase() failed\n",
                 "  Check: UVM factory registration and config_db settings"})
        end
        
        // Check agent exists
        if (env.uart_agt == null) begin
            `uvm_fatal(get_type_name(),
                {"UART agent is NULL!\n",
                 "  Likely cause: axiuart_env.build_phase() failed\n",
                 "  Check: Agent creation in environment"})
        end
        
        // Check sequencer exists (critical for sequence execution)
        if (env.uart_agt.sequencer == null) begin
            `uvm_fatal(get_type_name(),
                {"Sequencer is NULL!\n",
                 "  Likely cause: Agent is_active != UVM_ACTIVE\n",
                 "  Check: uvm_config_db settings for 'is_active'\n",
                 "  Solution: Ensure agent is created with UVM_ACTIVE mode"})
        end
        
        // Check driver exists (needed for sequence item execution)
        if (env.uart_agt.driver == null) begin
            `uvm_fatal(get_type_name(),
                {"Driver is NULL!\n",
                 "  Likely cause: Agent is_active != UVM_ACTIVE\n",
                 "  Check: Agent configuration in build_phase"})
        end
        
        `uvm_info(get_type_name(), "✓ Environment validation passed", UVM_MEDIUM)
    endfunction
    
    //--------------------------------------------------------------------------
    // Standardized run_phase - same for all tests
    //--------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        // Defensive validation - detect environment issues early
        validate_test_environment();
        
        phase.raise_objection(this, {"Starting ", get_type_name()});
        
        print_test_header();
        
        // Standard initialization sequence
        wait_for_clock_stable();
        execute_reset_sequence();
        initialize_cpu_debug();
        verify_communication();
        
        // Execute test-specific code
        run_test_sequence();
        
        // Standard cleanup
        report_results();
        
        #500ns;
        phase.drop_objection(this, {get_type_name(), " completed"});
    endtask
    
    //--------------------------------------------------------------------------
    // Protected: Standard initialization with timeout protection
    //--------------------------------------------------------------------------
    protected task wait_for_clock_stable();
        `uvm_info(get_type_name(), "Waiting for clock stabilization...", UVM_LOW)
        
        fork
            begin
                repeat(10) @(posedge axiuart_tb_top.clk);
                #1us;
            end
            begin
                #100us;
                `uvm_fatal(get_type_name(), 
                    "Clock stabilization timeout - clock not running or stuck?")
            end
        join_any
        disable fork;
        
        `uvm_info(get_type_name(), "Clock stable", UVM_MEDIUM)
    endtask
    
    protected task execute_reset_sequence();
        uart_reset_sequence reset_seq;
        
        `uvm_info(get_type_name(), "Executing reset sequence...", UVM_LOW)
        reset_seq = uart_reset_sequence::type_id::create("reset_seq");
        reset_seq.reset_cycles = this.reset_cycles;
        
        fork
            begin
                reset_seq.start(env.uart_agt.sequencer);
                `uvm_info(get_type_name(), "Reset sequence completed", UVM_LOW)
            end
            begin
                #10ms;
                `uvm_fatal(get_type_name(), "Reset sequence timeout!")
            end
        join_any
        disable fork;
        
        #100ns; // Additional settling time
    endtask
    
    protected task initialize_cpu_debug();
        `uvm_info(get_type_name(), "Initializing CPU debug interface...", UVM_LOW)
        
        fork
            begin
                write_reg(CPU_DBG_CTRL, 32'h00000001); // Halt
                #50ns;
                write_reg(CPU_DBG_STATUS, 32'hFFFFFFFF); // Clear status
                #50ns;
            end
            begin
                #50ms;
                `uvm_fatal(get_type_name(), 
                    "CPU debug initialization timeout - check UART communication")
            end
        join_any
        disable fork;
    endtask
    
    protected task verify_communication();
        bit [31:0] version_reg;
        
        fork
            begin
                read_reg(REG_VERSION, version_reg);
                `uvm_info(get_type_name(), $sformatf("Version: 0x%08x", version_reg), UVM_LOW)
            end
            begin
                #50ms;
                `uvm_fatal(get_type_name(), 
                    "Communication verification timeout - check UART/AXI bridge")
            end
        join_any
        disable fork;
    endtask
    
    //--------------------------------------------------------------------------
    // Protected: Safe helper tasks with automatic timeout/error checking
    //--------------------------------------------------------------------------
    protected task write_reg(bit [31:0] addr, bit [31:0] data);
        uart_reg_write_sequence wr_seq;
        wr_seq = uart_reg_write_sequence::type_id::create("wr_seq");
        wr_seq.reg_addr = addr;
        wr_seq.reg_data = data;
        
        fork
            begin
                wr_seq.start(env.uart_agt.sequencer);
            end
            begin
                #5ms;
                `uvm_error(get_type_name(), $sformatf("write_reg(0x%08x) timeout", addr))
            end
        join_any
        disable fork;
    endtask
    
    protected task read_reg(bit [31:0] addr, output bit [31:0] data);
        uart_reg_read_sequence rd_seq;
        rd_seq = uart_reg_read_sequence::type_id::create("rd_seq");
        rd_seq.reg_addr = addr;
        
        fork
            begin
                rd_seq.start(env.uart_agt.sequencer);
                data = rd_seq.read_data;
            end
            begin
                #5ms;
                `uvm_error(get_type_name(), $sformatf("read_reg(0x%08x) timeout", addr))
                data = 32'h0;
            end
        join_any
        disable fork;
    endtask
    
    protected task step_cpu();
        bit [31:0] status;
        bit cpu_halted;
        bit [7:0] halt_reason;
        int timeout_count;
        bit [15:0] cpu_pc;
        bit [15:0] insn_at_pc;
        
        // Verify halted
        cpu_halted = axiuart_tb_top.dut.cpu_inst.halted;
        if (!cpu_halted) begin
            `uvm_warning(get_type_name(), "CPU not halted - halting first")
            write_reg(CPU_DBG_CTRL, 32'h00000001);
            #100ns;
        end
        
        // Clear and step
        write_reg(CPU_DBG_CTRL, 32'h00000010); // CLR_HALT_REASON
        #50ns;
        write_reg(CPU_DBG_CTRL, 32'h00000004); // Step
        #50ns;
        
        // Poll with timeout
        timeout_count = 0;
        do begin
            #200ns;
            read_reg(CPU_DBG_STATUS, status);
            halt_reason = status[15:8];
            timeout_count++;
            
            // FAIL FAST: If halt_reason is unexpected (not STEP_DONE=0x03), diagnose and abort
            if (halt_reason != 8'h00 && halt_reason != 8'h03) begin
                bit [31:0] pc_val;
                read_reg(CPU_PC, pc_val);
                cpu_pc = pc_val[15:0];
                
                // Try to read instruction at PC (may fail if PC is out-of-bounds)
                read_ram_direct(cpu_pc, insn_at_pc);
                
                `uvm_fatal(get_type_name(), 
                    $sformatf("step_cpu() FAIL FAST: unexpected halt_reason=0x%02x (0x03=STEP_DONE, 0x06=PC_OOB). PC=0x%04x, insn=0x%04x, poll_count=%0d", 
                        halt_reason, cpu_pc, insn_at_pc, timeout_count))
            end
            
            if (timeout_count > step_timeout_cycles) begin
                `uvm_fatal(get_type_name(), 
                    $sformatf("step_cpu() timeout - halt_reason=0x%02x", halt_reason))
            end
        end while ((halt_reason != 8'h03) && (timeout_count <= step_timeout_cycles));
        
        if (enable_debug_logging) begin
            `uvm_info(get_type_name(), 
                $sformatf("Step done: halt_reason=0x%02x", halt_reason), UVM_HIGH)
        end
        
        #50ns;
    endtask
    
    protected task reset_cpu();
        write_reg(CPU_DBG_CTRL, 32'h00000001); // Halt
        #50ns;
        write_reg(CPU_PC, 32'h00000000); // Reset PC to 0x0000
        #50ns;
    endtask
    
    protected task write_insn(bit [15:0] addr, bit [15:0] insn);
        write_reg(CPU_MEM_ADDR, {16'h0000, addr});
        #2us;
        write_reg(CPU_MEM_WDATA, {16'h0000, insn});
        #2us;
        write_reg(CPU_MEM_CTRL, 32'h00000002); // Write request
        #4us;
    endtask
    
    protected task write_cpu_reg(bit [2:0] reg_idx, bit [15:0] value);
        write_reg(CPU_REG_INDEX, {29'h0, reg_idx});
        #2us;
        write_reg(CPU_REG_DATA, {16'h0000, value});
        #4us;
    endtask
    
    protected task read_cpu_reg(bit [2:0] reg_idx, output bit [15:0] value);
        bit [31:0] rdata;
        write_reg(CPU_REG_INDEX, {29'h0, reg_idx});
        #10ns;
        read_reg(CPU_REG_DATA, rdata);
        value = rdata[15:0];
        #10ns;
    endtask
    
    protected task read_cpu_pc(output bit [15:0] value);
        bit [31:0] rdata;
        read_reg(CPU_PC, rdata);
        value = rdata[15:0];
        #10ns;
    endtask
    
    protected task write_ram_direct(bit [15:0] addr, bit [15:0] data);
        write_reg(CPU_MEM_ADDR, {16'h0000, addr});
        #2us;
        write_reg(CPU_MEM_WDATA, {16'h0000, data});
        #2us;
        write_reg(CPU_MEM_CTRL, 32'h00000002); // Write request
        #4us;
    endtask
    
    protected task read_ram_direct(bit [15:0] addr, output bit [15:0] data);
        bit [31:0] rdata;
        write_reg(CPU_MEM_ADDR, {16'h0000, addr});
        #2us;
        write_reg(CPU_MEM_CTRL, 32'h00000001); // Read request
        #4us;
        read_reg(CPU_MEM_RDATA, rdata);
        data = rdata[15:0];
        #10ns;
    endtask
    
    protected task set_cpu_pc(bit [15:0] pc_value);
        write_reg(CPU_PC, {16'h0000, pc_value});
        #200ns;
    endtask
    
    protected task halt_cpu();
        write_reg(CPU_DBG_CTRL, 32'h00000001); // Halt
        #100ns;
    endtask
    
    protected task run_cpu();
        write_reg(CPU_DBG_CTRL, 32'h00000008); // Run
        #100ns;
    endtask
    
    protected task read_cpu_flags(output bit [3:0] flags);
        bit [31:0] status;
        read_reg(CPU_DBG_STATUS, status);
        flags = status[19:16]; // [N, Z, C, V]
    endtask
    
    protected task read_trace_buffer(bit [15:0] index, output bit [7:0] data);
        bit [31:0] rdata;
        write_reg(CPU_TRACE_BUF_ADDR, {16'h0000, index});
        #10ns;
        read_reg(CPU_TRACE_BUF_DATA, rdata);
        data = rdata[7:0];
        #10ns;
    endtask
    
    //--------------------------------------------------------------------------
    // Protected: Test assertion helpers
    //--------------------------------------------------------------------------
    protected function void assert_equal_8(bit [7:0] actual, bit [7:0] expected, string msg);
        if (actual == expected) begin
            `uvm_info(get_type_name(), {"✓ ", msg}, UVM_LOW)
            tests_passed++;
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("✗ %s: expected 0x%02x, got 0x%02x", msg, expected, actual))
            tests_failed++;
        end
    endfunction
    
    protected function void assert_equal_16(bit [15:0] actual, bit [15:0] expected, string msg);
        if (actual == expected) begin
            `uvm_info(get_type_name(), {"✓ ", msg}, UVM_LOW)
            tests_passed++;
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("✗ %s: expected 0x%04x, got 0x%04x", msg, expected, actual))
            tests_failed++;
        end
    endfunction
    
    protected function void assert_equal_4(bit [3:0] actual, bit [3:0] expected, string msg);
        if (actual == expected) begin
            `uvm_info(get_type_name(), {"✓ ", msg}, UVM_LOW)
            tests_passed++;
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("✗ %s: expected 0x%01x, got 0x%01x", msg, expected, actual))
            tests_failed++;
        end
    endfunction
    
    //--------------------------------------------------------------------------
    // Protected: Standard reporting
    //--------------------------------------------------------------------------
    protected virtual task print_test_header();
        string test_name = get_type_name();
        int name_len = test_name.len();
        int padding = (43 - name_len) / 2;
        string pad_str = "";
        
        // Build padding string
        for (int i = 0; i < padding; i++) pad_str = {pad_str, " "};
        
        `uvm_info(test_name, "╔═══════════════════════════════════════════╗", UVM_LOW)
        `uvm_info(test_name, $sformatf("║%s%s%s║", pad_str, test_name, pad_str), UVM_LOW)
        `uvm_info(test_name, "╚═══════════════════════════════════════════╝", UVM_LOW)
    endtask
    
    protected task report_results();
        `uvm_info(get_type_name(), "╔═══════════════════════════════════════╗", UVM_LOW)
        `uvm_info(get_type_name(), 
            $sformatf("║  PASSED: %2d  FAILED: %2d            ║", tests_passed, tests_failed), 
            UVM_LOW)
        `uvm_info(get_type_name(), "╚═══════════════════════════════════════╝", UVM_LOW)
        
        if (tests_failed == 0) begin
            `uvm_info(get_type_name(), "✓ ALL TESTS PASSED", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("✗ %0d TEST(S) FAILED", tests_failed))
        end
    endtask
    
endclass
