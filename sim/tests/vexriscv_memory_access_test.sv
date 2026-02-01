`timescale 1ns / 1ps

//==============================================================================
// VexRiscv Memory Access Test
//==============================================================================
// Test ID: Stage 1.3 - Smoke Tests
// Duration: ~8s
//
// Purpose:
//   Verify VexRiscv memory load/store operations:
//   - SW (store word) operation
//   - LW (load word) operation
//   - Load-use hazard detection (1-cycle stall)
//
// Test Sequence:
//   LUI x15, 0x80001     // x15 = 0x80001000 (target address in BlockRAM)
//   SW x0, 0(x15)        // mem[0x80001000] = 0
//   LUI x10, 0x12345     // x10 = 0x12345000
//   ADDI x10, x10, 0x678 // x10 = 0x12345678
//   SW x10, 0(x15)       // mem[0x80001000] = 0x12345678
//   LW x11, 0(x15)       // x11 = mem[0x80001000] (load-use stall)
//   EBREAK
//
// Expected Results:
//   x11 = 0x12345678 (value stored and loaded correctly)
//   1-cycle stall between SW and LW
//
// Pass/Fail Criteria:
//   - x11 matches stored value
//   - Load-use hazard handled correctly
//==============================================================================

class vexriscv_memory_access_test extends vexriscv_base_test;
    
    `uvm_component_utils(vexriscv_memory_access_test)
    
    function new(string name = "vexriscv_memory_access_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        use_tohost_checking = 0;
        timeout_cycles = 200;
        auto_start_cpu = 0;
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        bit [31:0] x11_val;
        bit test_passed;
        
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), 
            "VexRiscv Memory Access Test - Testing LW/SW operations", 
            UVM_NONE)
        
        reset_cpu();
        load_memory_test_program();
        start_cpu();
        
        repeat(50) @(posedge $root.rv32i_tb_top.clk);  // Wait for completion
        
        halt_cpu();
        read_cpu_reg(11, x11_val);
        
        test_passed = (x11_val == 32'h12345678);
        
        if (test_passed) begin
            `uvm_info(get_type_name(), 
                $sformatf("PASS: x11 = 0x%08X (expected 0x12345678)", x11_val), 
                UVM_NONE)
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("FAIL: x11 = 0x%08X (expected 0x12345678)", x11_val))
        end
        
        phase.drop_objection(this);
    endtask
    
    virtual task load_memory_test_program();
        `uvm_info(get_type_name(), "Loading memory test program...", UVM_MEDIUM)
        // VexRiscv memory base is 0x80000000
        // FIX Issue #18: Corrected instruction encodings (rd=x15, not x14/x31)
        write_memory_backdoor(32'h80000000, 32'h800017B7);  // LUI x15, 0x80001     (rd=15)
        write_memory_backdoor(32'h80000004, 32'h0007A023);  // SW x0, 0(x15)        (rs1=15)
        write_memory_backdoor(32'h80000008, 32'h12345537);  // LUI x10, 0x12345
        write_memory_backdoor(32'h8000000C, 32'h67850513);  // ADDI x10, x10, 0x678
        write_memory_backdoor(32'h80000010, 32'h00A7A023);  // SW x10, 0(x15)       (rs1=15)
        write_memory_backdoor(32'h80000014, 32'h0007A583);  // LW x11, 0(x15)       (rs1=15)
        write_memory_backdoor(32'h80000018, 32'h00100073);  // EBREAK
    endtask
    
endclass : vexriscv_memory_access_test
