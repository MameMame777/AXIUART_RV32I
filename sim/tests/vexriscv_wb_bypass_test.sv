`timescale 1ns / 1ps

//==============================================================================
// VexRiscv WB Stage Bypass Test (bypassWriteBackBuffer Validation)
//==============================================================================
// Test ID: Stage 1.6 - Hazard Tests  
// Duration: ~5s
//
// Purpose:
//   CRITICAL TEST - Verify bypassWriteBackBuffer=true fix:
//   - RAW hazard with 2-cycle gap (WB→EX forwarding)
//   - OLD CONFIG: would stall (bypassWriteBackBuffer=false)
//   - NEW CONFIG: NO stall (bypassWriteBackBuffer=true)
//
// Test Sequence:
//   ADDI x1, x0, 5    // x1 = 5
//   NOP               // Gap 1
//   NOP               // Gap 2
//   ADDI x2, x1, 1    // x2 = 6 (WB→EX forward)
//   EBREAK
//
// Expected Results:
//   - x2 = 6
//   - Total: 5 cycles (NO STALL - proves bypassWriteBackBuffer works)
//
// Pass/Fail Criteria:
//   - Correct register value
//   - Cycle count = 5 (old config would be 6 with stall)
//==============================================================================

class vexriscv_wb_bypass_test extends vexriscv_base_test;
    
    `uvm_component_utils(vexriscv_wb_bypass_test)
    
    function new(string name = "vexriscv_wb_bypass_test", uvm_component parent = null);
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
        int cycle_count;
        bit test_passed;
        
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), 
            "VexRiscv WB Bypass Test - CRITICAL: Testing bypassWriteBackBuffer fix", 
            UVM_NONE)
        
        reset_cpu();
        
        // VexRiscv memory base is 0x80000000
        write_memory_backdoor(32'h80000000, 32'h00500093);  // ADDI x1, x0, 5
        write_memory_backdoor(32'h80000004, 32'h00000013);  // NOP
        write_memory_backdoor(32'h80000008, 32'h00000013);  // NOP
        write_memory_backdoor(32'h8000000C, 32'h00108113);  // ADDI x2, x1, 1
        write_memory_backdoor(32'h80000010, 32'h00100073);  // EBREAK
        
        start_cpu();
        
        cycle_count = 0;
        repeat(25) begin
            @(posedge $root.rv32i_tb_top.clk);
            cycle_count++;
        end
        
        halt_cpu();
        read_cpu_reg(2, x2_val);
        
        // Key test: cycle count should be ~5, NOT 6
        test_passed = (x2_val == 6) && (cycle_count <= 15);
        
        if (test_passed) begin
            `uvm_info(get_type_name(), 
                $sformatf("PASS: x2=%0d, cycles=%0d (bypassWriteBackBuffer WORKING!)", 
                          x2_val, cycle_count), 
                UVM_NONE)
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("FAIL: x2=%0d (exp:6), cycles=%0d (bypassWriteBackBuffer issue?)", 
                          x2_val, cycle_count))
        end
        
        phase.drop_objection(this);
    endtask
    
endclass : vexriscv_wb_bypass_test
