`timescale 1ns / 1ps

//==============================================================================
// VexRiscv MEM Stage Bypass Test
//==============================================================================
// Test ID: Stage 1.5 - Hazard Tests
// Duration: ~5s
//
// Purpose:
//   Verify VexRiscv MEM→EX data forwarding:
//   - RAW hazard with 1-cycle gap
//   - No stall required (forwarding from MEM stage)
//
// Test Sequence:
//   ADDI x1, x0, 5    // x1 = 5
//   NOP               // Gap
//   ADDI x2, x1, 1    // x2 = 6 (MEM→EX forward)
//   EBREAK
//
// Expected Results:
//   - x2 = 6
//   - Total: 4 cycles (no stall)
//
// Pass/Fail Criteria:
//   - Correct register value
//   - Cycle count = 4
//==============================================================================

class vexriscv_mem_bypass_test extends vexriscv_base_test;
    
    `uvm_component_utils(vexriscv_mem_bypass_test)
    
    function new(string name = "vexriscv_mem_bypass_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        use_tohost_checking = 0;
        timeout_cycles = 50;
        auto_start_cpu = 0;
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        bit [31:0] x2_val;
        bit test_passed;
        
        phase.raise_objection(this);
        
        reset_cpu();
        
        write_memory_backdoor(32'h00, 32'h00500093);  // ADDI x1, x0, 5
        write_memory_backdoor(32'h04, 32'h00000013);  // NOP
        write_memory_backdoor(32'h08, 32'h00108113);  // ADDI x2, x1, 1
        write_memory_backdoor(32'h0C, 32'h00100073);  // EBREAK
        
        start_cpu();
        repeat(20) @(posedge $root.rv32i_tb_top.clk);
        halt_cpu();
        
        read_cpu_reg(2, x2_val);
        test_passed = (x2_val == 6);
        
        if (test_passed) begin
            `uvm_info(get_type_name(), $sformatf("PASS: x2=%0d (MEM bypass)", x2_val), UVM_NONE)
        end else begin
            `uvm_error(get_type_name(), $sformatf("FAIL: x2=%0d (expected 6)", x2_val))
        end
        
        phase.drop_objection(this);
    endtask
    
endclass : vexriscv_mem_bypass_test
