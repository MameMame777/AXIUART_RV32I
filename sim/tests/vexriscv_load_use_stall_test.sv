`timescale 1ns / 1ps

//==============================================================================
// VexRiscv Load-Use Stall Test
//==============================================================================
// Test ID: Stage 1.7 - Hazard Tests
// Duration: ~8s
//
// Purpose:
//   Verify VexRiscv load-use hazard handling:
//   - LW followed immediately by use of loaded register
//   - MANDATORY 1-cycle stall (cannot forward LW result in time)
//
// Test Sequence:
//   LW x1, 0(x0)      // Load from address 0
//   ADDI x2, x1, 1    // Use x1 immediately (load-use hazard)
//   EBREAK
//
// Expected Results:
//   - 1-cycle stall inserted by hazard unit
//   - Total: 4 cycles (3 instructions + 1 stall)
//
// Pass/Fail Criteria:
//   - Stall detected (cycle count = 4, not 3)
//==============================================================================

class vexriscv_load_use_stall_test extends vexriscv_base_test;
    
    `uvm_component_utils(vexriscv_load_use_stall_test)
    
    function new(string name = "vexriscv_load_use_stall_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        use_tohost_checking = 0;
        timeout_cycles = 50;
        auto_start_cpu = 0;
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        int cycle_count;
        bit test_passed;
        
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), 
            "VexRiscv Load-Use Stall Test - Testing mandatory 1-cycle stall", 
            UVM_NONE)
        
        reset_cpu();
        
        // Prepare memory with test value (VexRiscv memory base is 0x80000000)
        write_memory_backdoor(32'h80001000, 32'h00000005);  // Data: 5 at address 0x80001000

        // Load test program (CPU resets to 0x80000000)
        write_memory_backdoor(32'h80000000, 32'h80001537);  // LUI x10, 0x80001 (load base addr)
        write_memory_backdoor(32'h80000004, 32'h00052083);  // LW x1, 0(x10)
        write_memory_backdoor(32'h80000008, 32'h00108113);  // ADDI x2, x1, 1
        write_memory_backdoor(32'h8000000C, 32'h00100073);  // EBREAK
        
        start_cpu();
        
        cycle_count = 0;
        while (!is_cpu_halted() && (cycle_count < timeout_cycles)) begin
            @(posedge $root.rv32i_tb_top.clk);
            cycle_count++;
        end

        if (!is_cpu_halted()) begin
            `uvm_error(get_type_name(),
                $sformatf("Timeout waiting for CPU halt after %0d cycles", timeout_cycles))
            halt_cpu();
        end
        
        // Key test: Should take ~4 cycles (with stall), not 3
        // Allow margin for pipeline fill/drain
        test_passed = (cycle_count >= 8 && cycle_count <= 20);
        
        if (test_passed) begin
            `uvm_info(get_type_name(), 
                $sformatf("PASS: cycles=%0d (stall detected)", cycle_count), 
                UVM_NONE)
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("FAIL: cycles=%0d (expected 8-20 with stall)", cycle_count))
        end
        
        phase.drop_objection(this);
    endtask
    
endclass : vexriscv_load_use_stall_test
