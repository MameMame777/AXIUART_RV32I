`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// RV32I Scoreboard Class
//------------------------------------------------------------------------------
// Validates executed instructions against expected behavior
// Checks:
//   - Instruction count (20-25 expected)
//   - Final LED value (0x5 expected)
//   - EBREAK detection (must occur once)
//
// Author: GitHub Copilot
// Date: 2026-01-02
//------------------------------------------------------------------------------

class rv32i_scoreboard extends uvm_scoreboard;
    
    `uvm_component_utils(rv32i_scoreboard)
    
    // Analysis export
    uvm_analysis_imp #(rv32i_transaction, rv32i_scoreboard) analysis_export;
    
    // Virtual interface (for LED checking)
    virtual rv32i_tb_if vif;
    
    // Expected values (defaults for rv32i_basic_test)
    // Can be overridden via uvm_config_db for custom tests
    int EXPECTED_INSN_COUNT_MIN = 23;  // Actual instructions (ram[0-22])
    int EXPECTED_INSN_COUNT_MAX = 26;  // +3 for pipeline drain (ID/EX/MEM stages after EBREAK)
    int EXPECTED_LED_VALUE = 4'h5;
    int EXPECTED_EBREAK_COUNT = 1;
    
    // Collected data
    rv32i_transaction transactions[$];
    int instruction_count;
    int ebreak_count;
    bit [3:0] final_led_value;
    bit ebreak_detected;
    
    // LED write tracking
    int led_write_count;
    bit [3:0] led_write_values[$];
    
    function new(string name = "rv32i_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        analysis_export = new("analysis_export", this);
        instruction_count = 0;
        ebreak_count = 0;
        led_write_count = 0;
        ebreak_detected = 0;
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get virtual interface
        if (!uvm_config_db#(virtual rv32i_tb_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("RV32I_SCOREBOARD", "Failed to get virtual interface from config DB")
        end
        
        // Get expected values from config DB (if set by test)
        void'(uvm_config_db#(int)::get(this, "", "expected_insn_min", EXPECTED_INSN_COUNT_MIN));
        void'(uvm_config_db#(int)::get(this, "", "expected_insn_max", EXPECTED_INSN_COUNT_MAX));
        void'(uvm_config_db#(int)::get(this, "", "expected_led_value", EXPECTED_LED_VALUE));
        void'(uvm_config_db#(int)::get(this, "", "expected_ebreak_count", EXPECTED_EBREAK_COUNT));
        
        `uvm_info("RV32I_SCOREBOARD", 
            $sformatf("Configuration: insn=[%0d-%0d], led=0x%h, ebreak=%0d",
                      EXPECTED_INSN_COUNT_MIN, EXPECTED_INSN_COUNT_MAX,
                      EXPECTED_LED_VALUE, EXPECTED_EBREAK_COUNT),
            UVM_MEDIUM)
    endfunction
    
    //--------------------------------------------------------------------------
    // Write Function - Called by Monitor
    //--------------------------------------------------------------------------
    
    virtual function void write(rv32i_transaction trans);
        rv32i_transaction trans_copy;
        
        // Store transaction
        $cast(trans_copy, trans.clone());
        transactions.push_back(trans_copy);
        instruction_count++;
        
        // Check for EBREAK
        if (trans.is_ebreak()) begin
            ebreak_count++;
            ebreak_detected = 1;
            `uvm_info("RV32I_SCOREBOARD", 
                $sformatf("EBREAK detected at PC=0x%08h (instruction #%0d)", 
                          trans.pc, instruction_count),
                UVM_MEDIUM)
        end
        
        // Check for LED writes (STORE to MMIO address 0x2000)
        if (trans.is_store()) begin
            // Extract store address from instruction (S-type immediate)
            bit [11:0] imm_s;
            bit [31:0] store_addr;
            imm_s = {trans.insn[31:25], trans.insn[11:7]};
            // Note: Full address calculation requires rs1 value, 
            // but for LED MMIO we can check the immediate field
            
            // LED MMIO address is 0x2000, check if this could be a LED write
            // For simplicity, track all stores and check LED register at end
            `uvm_info("RV32I_SCOREBOARD", 
                $sformatf("Store instruction detected at PC=0x%08h", trans.pc),
                UVM_HIGH)
        end
        
        `uvm_info("RV32I_SCOREBOARD", 
            $sformatf("Collected instruction #%0d: %s", 
                      instruction_count, trans.convert2string()),
            UVM_HIGH)
    endfunction
    
    //--------------------------------------------------------------------------
    // Check Phase - Validate Results
    //--------------------------------------------------------------------------
    
    virtual function void check_phase(uvm_phase phase);
        bit test_passed;
        
        super.check_phase(phase);
        
        test_passed = 1;
        
        // Sample final LED value
        final_led_value = vif.led_reg;
        
        `uvm_info("RV32I_SCOREBOARD", "===== RV32I Scoreboard Check Phase =====", UVM_LOW)
        
        // Check 1: Instruction count
        `uvm_info("RV32I_SCOREBOARD", 
            $sformatf("Check 1: Instruction Count = %0d (expected %0d-%0d)", 
                      instruction_count, EXPECTED_INSN_COUNT_MIN, EXPECTED_INSN_COUNT_MAX),
            UVM_LOW)
        
        if (instruction_count < EXPECTED_INSN_COUNT_MIN || 
            instruction_count > EXPECTED_INSN_COUNT_MAX) begin
            `uvm_error("RV32I_SCOREBOARD", 
                $sformatf("Instruction count mismatch: got %0d, expected %0d-%0d",
                          instruction_count, EXPECTED_INSN_COUNT_MIN, EXPECTED_INSN_COUNT_MAX))
            test_passed = 0;
        end else begin
            `uvm_info("RV32I_SCOREBOARD", "Instruction count PASS", UVM_LOW)
        end
        
        // Check 2: Final LED value
        `uvm_info("RV32I_SCOREBOARD", 
            $sformatf("Check 2: Final LED Value = 0x%h (expected 0x%h)", 
                      final_led_value, EXPECTED_LED_VALUE),
            UVM_LOW)
        
        if (final_led_value != EXPECTED_LED_VALUE) begin
            `uvm_error("RV32I_SCOREBOARD", 
                $sformatf("LED value mismatch: got 0x%h, expected 0x%h",
                          final_led_value, EXPECTED_LED_VALUE))
            test_passed = 0;
        end else begin
            `uvm_info("RV32I_SCOREBOARD", "LED value PASS", UVM_LOW)
        end
        
        // Check 3: EBREAK detection
        `uvm_info("RV32I_SCOREBOARD", 
            $sformatf("Check 3: EBREAK Count = %0d (expected %0d)", 
                      ebreak_count, EXPECTED_EBREAK_COUNT),
            UVM_LOW)
        
        if (ebreak_count != EXPECTED_EBREAK_COUNT) begin
            `uvm_error("RV32I_SCOREBOARD", 
                $sformatf("EBREAK count mismatch: got %0d, expected %0d",
                          ebreak_count, EXPECTED_EBREAK_COUNT))
            test_passed = 0;
        end else begin
            `uvm_info("RV32I_SCOREBOARD", "EBREAK detection PASS", UVM_LOW)
        end
        
        // Check 4: CPU break signal
        `uvm_info("RV32I_SCOREBOARD", 
            $sformatf("Check 4: CPU Break Signal = %0b (expected 1)", vif.cpu_break),
            UVM_LOW)
        
        if (!vif.cpu_break) begin
            `uvm_warning("RV32I_SCOREBOARD", "CPU break signal not asserted")
        end else begin
            `uvm_info("RV32I_SCOREBOARD", "CPU break signal PASS", UVM_LOW)
        end
        
        // Final result
        `uvm_info("RV32I_SCOREBOARD", "========================================", UVM_LOW)
        if (test_passed) begin
            `uvm_info("RV32I_SCOREBOARD", "***** ALL CHECKS PASSED *****", UVM_LOW)
        end else begin
            `uvm_error("RV32I_SCOREBOARD", "***** TEST FAILED *****")
        end
        
    endfunction
    
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        `uvm_info("RV32I_SCOREBOARD", "===== RV32I Scoreboard Summary =====", UVM_LOW)
        `uvm_info("RV32I_SCOREBOARD", 
            $sformatf("Total Instructions: %0d", instruction_count), UVM_LOW)
        `uvm_info("RV32I_SCOREBOARD", 
            $sformatf("EBREAK Count: %0d", ebreak_count), UVM_LOW)
        `uvm_info("RV32I_SCOREBOARD", 
            $sformatf("Final LED Value: 0x%h", final_led_value), UVM_LOW)
        `uvm_info("RV32I_SCOREBOARD", "====================================", UVM_LOW)
    endfunction
    
endclass
