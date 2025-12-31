// Simple test to debug ADDI instruction
// Tests: LDI R1, #10 then ADDI R1, #5 then BRK
// Expected: R1 = 15

`timescale 1ns / 1ps

class axiuart_cpu_simple_addi_test extends axiuart_cpu_test_base;
    `uvm_component_utils(axiuart_cpu_simple_addi_test)
    
    import td4cpu_isa_pkg::*;
    
    logic [15:0] r1_val;
    
    function new(string name = "axiuart_cpu_simple_addi_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    task do_reset();
        reset_dut();
        #1us; // Wait for reset to settle
    endtask
    
    virtual task run_test_sequence();
        // Required by base class but not used in free-running test
    endtask
    
    task write_insn(logic [15:0] addr, logic [15:0] data);
        write_ram_direct(addr, data);
    endtask
    
    task wait_for_halt(logic [7:0] expected_reason, int timeout_us);
        int elapsed_us = 0;
        `uvm_info("CPU_TEST", $sformatf("Waiting for halt (reason=0x%02x, timeout=%0dus)", expected_reason, timeout_us), UVM_MEDIUM)
        
        while (elapsed_us < timeout_us) begin
            if (axiuart_tb_top.dut.cpu_inst.halted && axiuart_tb_top.dut.cpu_inst.halt_reason == expected_reason) begin
                `uvm_info("CPU_TEST", $sformatf("✓ CPU halted with reason=0x%02x after %0d us", expected_reason, elapsed_us), UVM_LOW)
                return;
            end
            #1us;
            elapsed_us++;
        end
        
        `uvm_error("CPU_TEST", $sformatf("Timeout after %0dus. halted=%0b reason=0x%02x pc=0x%04x", 
            elapsed_us, 
            axiuart_tb_top.dut.cpu_inst.halted,
            axiuart_tb_top.dut.cpu_inst.halt_reason,
            axiuart_tb_top.dut.cpu_inst.pc))
    endtask
    
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        
        phase.raise_objection(this);
        
        do_reset();
        halt_cpu();
        write_cpu_reg(7, 16'h0); // Clear halt_reason manually
        
        // Write minimal program
        write_insn(16'h0000, {OP_LDI, 3'd1, 9'd10});       // LDI R1, #10
        write_insn(16'h0001, {OP_ADDI, 3'd1, 9'd5});       // ADDI R1, #5   → R1 should be 15
        write_insn(16'h0002, {OP_SYS, 9'd0, SYSOP_BRK});   // BRK
        
        set_cpu_pc(16'h0000);
        run_cpu();
        
        wait_for_halt(8'h05, 100); // 100μs timeout
        
        // Check result
        read_cpu_reg(1, r1_val);
        `uvm_info("CPU_TEST", $sformatf("R1 = 0x%04x (expected 0x000F)", r1_val), UVM_LOW)
        
        if (r1_val == 16'h000F) begin
            `uvm_info("CPU_TEST", "✓ ADDI TEST PASSED", UVM_LOW)
        end else begin
            `uvm_error("CPU_TEST", $sformatf("ADDI TEST FAILED: R1=0x%04x (expected 0x000F)", r1_val))
        end
        
        phase.drop_objection(this);
    endtask
    
endclass
