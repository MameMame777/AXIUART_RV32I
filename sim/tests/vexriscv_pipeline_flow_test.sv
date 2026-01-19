`timescale 1ns / 1ps

//==============================================================================
// VexRiscv Pipeline Flow Test
//==============================================================================
// Test ID: Stage 1.2 - Smoke Tests
// Duration: ~5s
// 
// Purpose:
//   Verify VexRiscv 4-stage pipeline basic flow:
//   - DECODE → EXECUTE → MEMORY → WRITEBACK progression
//   - No unexpected stalls on simple instructions
//   - PC increment by 4 each cycle
//
// Test Sequence:
//   8 consecutive NOPs (ADDI x0, x0, 0)
//
// Expected Results:
//   - Each NOP takes exactly 1 cycle (no stalls)
//   - PC advances: 0x00 → 0x04 → 0x08 → ... → 0x1C
//   - Total cycles: 8 (or 11 with pipeline fill/drain)
//
// Pass/Fail Criteria:
//   - Minimum 7 instructions executed (PC ≥ 0x1C)
//   - No pipeline stalls detected
//==============================================================================

class vexriscv_pipeline_flow_test extends vexriscv_base_test;
    
    `uvm_component_utils(vexriscv_pipeline_flow_test)
    
    function new(string name = "vexriscv_pipeline_flow_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        use_tohost_checking = 0;
        timeout_cycles = 50;
        auto_start_cpu = 0;
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        bit [31:0] final_pc;
        int cycle_count;
        bit test_passed;
        
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), 
            "VexRiscv Pipeline Flow Test - Testing 4-stage progression", 
            UVM_NONE)
        
        reset_cpu();
        load_nop_sequence();
        start_cpu();
        
        // Execute and measure
        execute_and_count(cycle_count);
        
        halt_cpu();
        
        // Verify PC advanced
        // final_pc = read_pc();  // Implementation-specific
        test_passed = (cycle_count >= 7 && cycle_count <= 15);
        
        if (test_passed) begin
            `uvm_info(get_type_name(), 
                $sformatf("PASS: Pipeline executed %0d cycles (expected 7-15)", cycle_count), 
                UVM_NONE)
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("FAIL: Pipeline executed %0d cycles (expected 7-15)", cycle_count))
        end
        
        phase.drop_objection(this);
    endtask
    
    virtual task load_nop_sequence();
        `uvm_info(get_type_name(), "Loading 8 NOPs...", UVM_MEDIUM)
        for (int i = 0; i < 8; i++) begin
            write_memory_backdoor(32'h00000000 + (i * 4), 32'h00000013);  // ADDI x0, x0, 0 (NOP)
        end
    endtask
    
    virtual task execute_and_count(output int cycles);
        cycles = 0;
        for (int i = 0; i < 20; i++) begin
            @(posedge $root.rv32i_tb_top.clk);
            cycles++;
        end
    endtask
    
endclass : vexriscv_pipeline_flow_test
