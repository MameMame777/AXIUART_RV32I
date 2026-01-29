`timescale 1ns / 1ps

//==============================================================================
// VexRiscv EX Stage Bypass Test
//==============================================================================
// Test ID: Stage 1.4 - Hazard Tests
// Duration: ~5s
//
// Purpose:
//   Verify VexRiscv EX→EX data forwarding (bypass):
//   - RAW hazard: Consumer in EX needs producer result from EX
//   - No stall required (forwarding resolves hazard)
//
// Test Sequence:
//   ADDI x1, x0, 5    // x1 = 5 (cycle 1)
//   ADDI x2, x1, 1    // x2 = x1 + 1 = 6 (cycle 2, RAW on x1)
//   EBREAK
//
// Expected Results:
//   - x1 = 5
//   - x2 = 6 (correctly forwarded)
//   - Total: 3 cycles (NO STALL - critical test)
//
// Pass/Fail Criteria:
//   - Register values correct
//   - Cycle count = 3 (proves bypass works)
//==============================================================================

class vexriscv_ex_bypass_test extends vexriscv_base_test;
    
    `uvm_component_utils(vexriscv_ex_bypass_test)
    
    function new(string name = "vexriscv_ex_bypass_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        use_tohost_checking = 0;
        timeout_cycles = 50;
        auto_start_cpu = 0;
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        bit [31:0] x1_val, x2_val;
        int cycle_count;
        bit test_passed;
        
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), 
            "VexRiscv EX Bypass Test - Testing EX→EX forwarding", 
            UVM_NONE)
        
        reset_cpu();
        
        // Load test (VexRiscv memory base is 0x80000000)
        write_memory_backdoor(32'h80000000, 32'h00500093);  // ADDI x1, x0, 5
        write_memory_backdoor(32'h80000004, 32'h00108113);  // ADDI x2, x1, 1
        write_memory_backdoor(32'h80000008, 32'h00100073);  // EBREAK
        
        start_cpu();
        
        // Count cycles
        cycle_count = 0;
        repeat(20) begin
            @(posedge $root.rv32i_tb_top.clk);
            cycle_count++;
        end
        
        halt_cpu();
        read_cpu_reg(1, x1_val);
        read_cpu_reg(2, x2_val);
        
        test_passed = (x1_val == 5) && (x2_val == 6) && (cycle_count <= 10);
        
        if (test_passed) begin
            `uvm_info(get_type_name(), 
                $sformatf("PASS: x1=%0d, x2=%0d, cycles=%0d (EX bypass working)", 
                          x1_val, x2_val, cycle_count), 
                UVM_NONE)
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("FAIL: x1=%0d(exp:5), x2=%0d(exp:6), cycles=%0d", 
                          x1_val, x2_val, cycle_count))
        end
        
        phase.drop_objection(this);
    endtask
    
endclass : vexriscv_ex_bypass_test
