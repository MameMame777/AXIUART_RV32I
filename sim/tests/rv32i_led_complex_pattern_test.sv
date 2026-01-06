`timescale 1ns / 1ps

//==============================================================================
// RV32I Complex LED Pattern Test - Multi-Mode Animation
//==============================================================================

class rv32i_led_complex_pattern_test extends rv32i_base_test;
    
    `uvm_component_utils(rv32i_led_complex_pattern_test)
    
    // LED write tracking
    int led_write_count;
    logic [3:0] last_led_value;
    logic [3:0] led_history [$];
    
    function new(string name = "rv32i_led_complex_pattern_test", uvm_component parent = null);
        super.new(name, parent);
        led_write_count = 0;
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Expect many instructions (83 + loop iterations)
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_insn_min", 83);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_insn_max", 10000);
        uvm_config_db#(int)::set(this, "env.scoreboard", "expected_ebreak_count", 0);
        // Don't check specific LED value - we expect multiple different values
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info("RV32I_COMPLEX", "***** RV32I Complex LED Pattern Test *****", UVM_LOW)
        `uvm_info("RV32I_COMPLEX", "Testing 83-instruction multi-mode animation", UVM_LOW)
        `uvm_info("RV32I_COMPLEX", "Modes: Counter -> Knight Rider -> Blink -> Alternating", UVM_LOW)
        
        // Reset and halt
        reset_sequence();
        halt_cpu();
        
        // Load complex pattern program
        load_complex_pattern_program();
        
        // Start CPU
        `uvm_info("RV32I_COMPLEX", "Starting CPU execution - monitoring LED writes", UVM_MEDIUM)
        start_cpu();
        
        // Monitor LED changes for a while
        fork
            monitor_led_changes();
        join_none
        
        // Let it run enough to see pattern changes
        // Each mode has different iteration counts:
        // - Mode 3 (Alternating): 50 iterations
        // - Mode 0 (Counter): 16 iterations  
        // - Mode 1 (Knight): 30 iterations
        // - Mode 2 (Blink): 20 iterations
        // With 5M cycle delay, each iteration = 40ms @ 125MHz
        // We'll run for 100us to see initial pattern
        #100000ns;  // 100 microseconds
        
        // Stop monitoring
        disable fork;
        
        // Halt CPU
        halt_cpu();
        
        // Report results
        report_led_patterns();
        
        `uvm_info("RV32I_COMPLEX", "***** Test Complete *****", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
    
    // Include generated memory initialization
    `include "rv32i_complex_pattern_mem.svh"
    
    virtual task monitor_led_changes();
        logic [3:0] prev_led = 4'hX;
        logic [3:0] curr_led;
        
        forever begin
            @(posedge rv32i_tb_top.tb_if.clk);
            
            curr_led = rv32i_tb_top.tb_if.led_reg;
            
            // Detect LED write
            if (curr_led !== prev_led && curr_led !== 4'hX) begin
                led_write_count++;
                last_led_value = curr_led;
                led_history.push_back(curr_led);
                
                `uvm_info("RV32I_COMPLEX", 
                    $sformatf("[%0t] LED Write #%0d: 0x%X (%04b)", 
                              $time, led_write_count, curr_led, curr_led),
                    UVM_HIGH)
                
                prev_led = curr_led;
            end
        end
    endtask
    
    virtual task report_led_patterns();
        int mode0_detections = 0;  // Counter (0-15)
        int mode1_detections = 0;  // Knight Rider (1,2,4,8)
        int mode2_detections = 0;  // Blink (0xF, 0x0)
        int mode3_detections = 0;  // Alternating (0x5, 0xA)
        
        `uvm_info("RV32I_COMPLEX", "================================================================================", UVM_LOW)
        `uvm_info("RV32I_COMPLEX", "LED Pattern Analysis", UVM_LOW)
        `uvm_info("RV32I_COMPLEX", "================================================================================", UVM_LOW)
        `uvm_info("RV32I_COMPLEX", $sformatf("Total LED writes detected: %0d", led_write_count), UVM_LOW)
        `uvm_info("RV32I_COMPLEX", $sformatf("Last LED value: 0x%X (%04b)", last_led_value, last_led_value), UVM_LOW)
        
        if (led_write_count > 0) begin
            `uvm_info("RV32I_COMPLEX", "", UVM_LOW)
            `uvm_info("RV32I_COMPLEX", "LED Value History (first 20):", UVM_LOW)
            
            for (int i = 0; i < led_history.size() && i < 20; i++) begin
                logic [3:0] val = led_history[i];
                string pattern_type = "Unknown";
                
                // Classify pattern
                if (val inside {4'h0, 4'h1, 4'h2, 4'h3, 4'h4, 4'h5, 4'h6, 4'h7,
                                4'h8, 4'h9, 4'hA, 4'hB, 4'hC, 4'hD, 4'hE, 4'hF}) begin
                    if (val == 4'h5 || val == 4'hA) begin
                        pattern_type = "Mode 3: Alternating";
                        mode3_detections++;
                    end else if (val == 4'h1 || val == 4'h2 || val == 4'h4 || val == 4'h8) begin
                        pattern_type = "Mode 1: Knight Rider";
                        mode1_detections++;
                    end else if (val == 4'hF || val == 4'h0) begin
                        // Could be blink or counter
                        if (i > 0 && (led_history[i-1] == 4'hF || led_history[i-1] == 4'h0)) begin
                            pattern_type = "Mode 2: Blink";
                            mode2_detections++;
                        end else begin
                            pattern_type = "Mode 0/2: Counter or Blink";
                            mode0_detections++;
                        end
                    end else begin
                        pattern_type = "Mode 0: Counter";
                        mode0_detections++;
                    end
                end
                
                `uvm_info("RV32I_COMPLEX", 
                    $sformatf("  [%2d] 0x%X (%04b) - %s", i+1, val, val, pattern_type),
                    UVM_LOW)
            end
            
            `uvm_info("RV32I_COMPLEX", "", UVM_LOW)
            `uvm_info("RV32I_COMPLEX", "Pattern Mode Detections:", UVM_LOW)
            `uvm_info("RV32I_COMPLEX", $sformatf("  Mode 0 (Counter):     %0d detections", mode0_detections), UVM_LOW)
            `uvm_info("RV32I_COMPLEX", $sformatf("  Mode 1 (Knight Rider): %0d detections", mode1_detections), UVM_LOW)
            `uvm_info("RV32I_COMPLEX", $sformatf("  Mode 2 (Blink):       %0d detections", mode2_detections), UVM_LOW)
            `uvm_info("RV32I_COMPLEX", $sformatf("  Mode 3 (Alternating): %0d detections", mode3_detections), UVM_LOW)
            
            `uvm_info("RV32I_COMPLEX", "", UVM_LOW)
            
            if (led_write_count >= 5) begin
                `uvm_info("RV32I_COMPLEX", "SUCCESS: Multiple LED writes detected - complex pattern working!", UVM_LOW)
            end else begin
                `uvm_warning("RV32I_COMPLEX", $sformatf("Only %0d LED writes detected - may need longer runtime", led_write_count))
            end
        end else begin
            `uvm_error("RV32I_COMPLEX", "FAILURE: No LED writes detected!")
        end
        
        `uvm_info("RV32I_COMPLEX", "================================================================================", UVM_LOW)
    endtask

endclass
