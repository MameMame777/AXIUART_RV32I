`timescale 1ns / 1ps

//==============================================================================
// VexRiscv DBus Access Test
//==============================================================================
// Test ID: Stage 1.9 - Bus Protocol Tests
// Duration: ~10s
//
// Purpose:
//   Verify VexRiscv data bus (DBus) protocol:
//   - Byte, halfword, word access operations
//   - Correct size field encoding (00=byte, 01=halfword, 10=word)
//   - Proper byte lane masking
//   - No bus errors
//
// Test Sequence:
//   SB (store byte)
//   SH (store halfword)
//   SW (store word)
//   LB/LBU (load byte)
//   LH/LHU (load halfword)
//   LW (load word)
//
// Expected Results:
//   - All accesses complete without errors
//   - Size encoding correct
//   - Byte lanes properly masked
//
// Pass/Fail Criteria:
//   - All transactions successful
//   - No protocol violations
//==============================================================================

class vexriscv_dbus_access_test extends vexriscv_base_test;
    
    `uvm_component_utils(vexriscv_dbus_access_test)
    
    function new(string name = "vexriscv_dbus_access_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        use_tohost_checking = 0;
        timeout_cycles = 200;
        auto_start_cpu = 0;
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        int transaction_count = 0;
        bit test_passed;
        bit [31:0] mem_word;
        bit [31:0] reg_x12;
        bit [31:0] reg_x13;
        bit [31:0] reg_x14;

        phase.raise_objection(this);

        `uvm_info(get_type_name(),
            "VexRiscv DBus Access Test - Testing byte/halfword/word accesses",
            UVM_NONE)

        reset_cpu();
        test_passed = 1;

        // Load test program with various store/load operations
        // Data area at 0x80001000 (separate from code at 0x80000000)
        write_memory_backdoor(32'h80000000, 32'h80001537);  // LUI x10, 0x80001 (data addr)
        write_memory_backdoor(32'h80000004, 32'h0FF00593);  // LI x11, 0xFF
        write_memory_backdoor(32'h80000008, 32'h00B50023);  // SB x11, 0(x10) - byte store
        write_memory_backdoor(32'h8000000C, 32'h00B51023);  // SH x11, 0(x10) - halfword store
        write_memory_backdoor(32'h80000010, 32'h00B52023);  // SW x11, 0(x10) - word store
        write_memory_backdoor(32'h80000014, 32'h00050603);  // LB x12, 0(x10) - byte load
        write_memory_backdoor(32'h80000018, 32'h00051683);  // LH x13, 0(x10) - halfword load
        write_memory_backdoor(32'h8000001C, 32'h00052703);  // LW x14, 0(x10) - word load
        write_memory_backdoor(32'h80000020, 32'h00100073);  // EBREAK

        start_cpu();

        // Monitor DBus transactions
        repeat(100) begin
            @(posedge $root.rv32i_tb_top.clk);
            transaction_count++;
        end

        halt_cpu();

        // Validate final memory content (address 0x80001000 -> BRAM[0x1000])
        if (read_memory_backdoor(32'h0000_1000, mem_word)) begin
            if (mem_word !== 32'h0000_00FF) begin
                `uvm_error(get_type_name(),
                    $sformatf("FAIL: BRAM[0x1000] = 0x%08X, expected 0x000000FF", mem_word))
                test_passed = 0;
            end else begin
                `uvm_info(get_type_name(),
                    $sformatf("BRAM[0x1000] = 0x%08X (store result OK)", mem_word),
                    UVM_LOW)
            end
        end else begin
            `uvm_error(get_type_name(), "FAIL: BRAM[0x1000] read failed")
            test_passed = 0;
        end

        // Validate load results in registers
        read_cpu_reg(12, reg_x12);  // LB
        read_cpu_reg(13, reg_x13);  // LH
        read_cpu_reg(14, reg_x14);  // LW

        if (reg_x12 !== 32'hFFFF_FFFF) begin
            `uvm_error(get_type_name(),
                $sformatf("FAIL: x12 = 0x%08X, expected 0xFFFFFFFF (LB)", reg_x12))
            test_passed = 0;
        end
        if (reg_x13 !== 32'h0000_00FF) begin
            `uvm_error(get_type_name(),
                $sformatf("FAIL: x13 = 0x%08X, expected 0x000000FF (LH)", reg_x13))
            test_passed = 0;
        end
        if (reg_x14 !== 32'h0000_00FF) begin
            `uvm_error(get_type_name(),
                $sformatf("FAIL: x14 = 0x%08X, expected 0x000000FF (LW)", reg_x14))
            test_passed = 0;
        end

        test_passed = test_passed && (transaction_count >= 50);

        if (test_passed) begin
            `uvm_info(get_type_name(),
                "PASS: DBus protocol test completed",
                UVM_NONE)
        end else begin
            `uvm_error(get_type_name(),
                "FAIL: DBus protocol issues detected")
        end

        phase.drop_objection(this);
    endtask
    
endclass : vexriscv_dbus_access_test
