`timescale 1ns / 1ps

//==============================================================================
// RV32I LED MMIO Test - Exact same program as Python script
//==============================================================================

class rv32i_led_mmio_simple_test extends rv32i_base_test;
    
    `uvm_component_utils(rv32i_led_mmio_simple_test)
    
    function new(string name = "rv32i_led_mmio_simple_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Expect 4 instructions before loop
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_insn_min", 4);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_insn_max", 100);  // Allow loop iterations
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_ebreak_count", 0); // No EBREAK
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_led_value", 32'h0000000F); // LED = 0xF
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info("RV32I_LED_MMIO", "***** RV32I LED MMIO Simple Test *****", UVM_LOW)
        `uvm_info("RV32I_LED_MMIO", "Testing exact same program as Python script", UVM_LOW)
        
        // Reset and halt
        reset_sequence();
        halt_cpu();
        
        // Load program - EXACT SAME AS PYTHON
        load_led_program();
        
        // Start CPU
        `uvm_info("RV32I_LED_MMIO", "Starting CPU execution", UVM_MEDIUM)
        start_cpu();
        
        // Let it run for a while
        #1000ns;
        
        // Check LED value
        check_led_value();
        
        // Halt CPU to stop infinite loop
        halt_cpu();
        
        `uvm_info("RV32I_LED_MMIO", "***** Test Complete *****", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
    
    virtual task load_led_program();
        `uvm_info("RV32I_LED_MMIO", "Loading LED control program", UVM_MEDIUM)
        
        // Python program:
        // enc.lui(15, 0x4)           # x15 = 0x4000
        // enc.addi(16, 15, 0x7C)     # x16 = 0x407C
        // enc.addi(17, 0, 0xF)       # x17 = 15
        // enc.sw(17, 16, 0)          # MEM[0x407C] = 0xF
        // enc.jal(0, -4)             # Loop
        
        write_debug_mem(11'h000, 32'h000047B7); // LUI x15, 0x4
        write_debug_mem(11'h001, 32'h07C78813); // ADDI x16, x15, 0x7C
        write_debug_mem(11'h002, 32'h00F00893); // ADDI x17, x0, 0xF
        write_debug_mem(11'h003, 32'h01182023); // SW x17, 0(x16)
        write_debug_mem(11'h004, 32'hFFDFF06F); // JAL x0, -4
        
        `uvm_info("RV32I_LED_MMIO", "Program loaded", UVM_MEDIUM)
        
        // Display program
        `uvm_info("RV32I_LED_MMIO", "Program:", UVM_LOW)
        `uvm_info("RV32I_LED_MMIO", "  0x0000: LUI x15, 0x4", UVM_LOW)
        `uvm_info("RV32I_LED_MMIO", "  0x0004: ADDI x16, x15, 0x7C", UVM_LOW)
        `uvm_info("RV32I_LED_MMIO", "  0x0008: ADDI x17, x0, 0xF", UVM_LOW)
        `uvm_info("RV32I_LED_MMIO", "  0x000C: SW x17, 0(x16) -> MEM[0x407C] = 0xF", UVM_LOW)
        `uvm_info("RV32I_LED_MMIO", "  0x0010: JAL x0, -4 (loop to SW)", UVM_LOW)
    endtask
    
    virtual task check_led_value();
        logic [3:0] led_value;
        
        // Read LED from testbench interface
        led_value = rv32i_tb_top.tb_if.led_reg;
        
        `uvm_info("RV32I_LED_MMIO", $sformatf("LED Value = 0x%X (expected 0xF)", led_value), UVM_LOW)
        
        if (led_value == 4'hF) begin
            `uvm_info("RV32I_LED_MMIO", "✓ LED value correct!", UVM_LOW)
        end else begin
            `uvm_error("RV32I_LED_MMIO", $sformatf("✗ LED value mismatch: got 0x%X, expected 0xF", led_value))
        end
    endtask

endclass

