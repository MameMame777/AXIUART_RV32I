// ============================================================================
// TD4 CPU Basic Instruction Test
// Tests: LDI, ADDI, ST/LD to RAM (no MMIO)
// ============================================================================

class axiuart_cpu_inst_test extends axiuart_base_test;
    `uvm_component_utils(axiuart_cpu_inst_test)
    
    function new(string name = "axiuart_cpu_inst_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this, "Starting CPU instruction test");
        
        `uvm_info("CPU_INST", "╔═══════════════════════════════════════════════╗", UVM_LOW)
        `uvm_info("CPU_INST", "║   CPU BASIC INSTRUCTION TEST                  ║", UVM_LOW)
        `uvm_info("CPU_INST", "╚═══════════════════════════════════════════════╝", UVM_LOW)
        
        // Initialize CPU debug interface
        init_cpu_debug();
        
        // Test 1: LDI instruction
        test_ldi();
        
        // Test 2: ADDI instruction (unsigned)
        test_addi();
        
        // Test 3: ST/LD to RAM
        test_ram_store_load();
        
        // Test 4: Address calculation with ADDI
        test_address_build();
        
        // Summary
        `uvm_info("CPU_INST", "╔═══════════════════════════════════════════════╗", UVM_LOW)
        if (tests_failed == 0) begin
            `uvm_info("CPU_INST", $sformatf("║   ALL TESTS PASSED (%0d/%0d)                   ║", tests_passed, tests_passed), UVM_LOW)
        end else begin
            `uvm_info("CPU_INST", $sformatf("║   TESTS: %0d PASSED, %0d FAILED                ║", tests_passed, tests_failed), UVM_LOW)
        end
        `uvm_info("CPU_INST", "╚═══════════════════════════════════════════════╝", UVM_LOW)
        
        if (tests_failed > 0) begin
            `uvm_error("CPU_INST", $sformatf("CPU instruction test completed with %0d failures", tests_failed))
        end else begin
            `uvm_info("CPU_INST", "CPU instruction test completed successfully", UVM_LOW)
        end
        
        phase.drop_objection(this, "CPU instruction test completed");
    endtask
    
    // Test 1: LDI instruction
    task test_ldi();
        bit [15:0] reg_val;
        
        `uvm_info("CPU_INST", "=== Test 1: LDI Instruction ===", UVM_LOW)
        
        // Program:
        // 0x0000: LDI R1, #0x123
        // 0x0001: LDI R2, #0x1FF
        // 0x0002: LDI R3, #0x000
        // 0x0003: SYS BRK
        
        write_insn(16'h0000, {OP_LDI, 3'd1, 9'h123});
        write_insn(16'h0001, {OP_LDI, 3'd2, 9'h1FF});
        write_insn(16'h0002, {OP_LDI, 3'd3, 9'h000});
        write_insn(16'h0003, {OP_SYS, 9'd0, 4'd0});
        
        set_cpu_pc(16'h0000);
        
        // Execute LDI R1, #0x123
        step_cpu();
        read_cpu_reg(1, reg_val);
        if (reg_val == 16'h0123) begin
            `uvm_info("CPU_INST", $sformatf("✓ LDI R1, #0x123: R1=0x%04x", reg_val), UVM_LOW)
            tests_passed++;
        end else begin
            `uvm_error("CPU_INST", $sformatf("✗ LDI R1, #0x123 FAILED: got 0x%04x, expected 0x0123", reg_val))
            tests_failed++;
        end
        
        // Execute LDI R2, #0x1FF
        step_cpu();
        read_cpu_reg(2, reg_val);
        if (reg_val == 16'h01FF) begin
            `uvm_info("CPU_INST", $sformatf("✓ LDI R2, #0x1FF: R2=0x%04x", reg_val), UVM_LOW)
            tests_passed++;
        end else begin
            `uvm_error("CPU_INST", $sformatf("✗ LDI R2, #0x1FF FAILED: got 0x%04x, expected 0x01FF", reg_val))
            tests_failed++;
        end
        
        // Execute LDI R3, #0x000
        step_cpu();
        read_cpu_reg(3, reg_val);
        if (reg_val == 16'h0000) begin
            `uvm_info("CPU_INST", $sformatf("✓ LDI R3, #0x000: R3=0x%04x", reg_val), UVM_LOW)
            tests_passed++;
        end else begin
            `uvm_error("CPU_INST", $sformatf("✗ LDI R3, #0x000 FAILED: got 0x%04x, expected 0x0000", reg_val))
            tests_failed++;
        end
    endtask
    
    // Test 2: ADDI instruction (unsigned addition)
    task test_addi();
        bit [15:0] reg_val;
        
        `uvm_info("CPU_INST", "=== Test 2: ADDI Instruction (Unsigned) ===", UVM_LOW)
        
        // Program:
        // 0x0000: LDI R1, #0x100
        // 0x0001: ADDI R1, #0x050
        // 0x0002: ADDI R1, #0x00A
        // 0x0003: SYS BRK
        // Expected: R1 = 0x100 + 0x50 + 0xA = 0x15A
        
        write_insn(16'h0000, {OP_LDI, 3'd1, 9'h100});
        write_insn(16'h0001, {OP_ADDI, 3'd1, 9'h050});
        write_insn(16'h0002, {OP_ADDI, 3'd1, 9'h00A});
        write_insn(16'h0003, {OP_SYS, 9'd0, 4'd0});
        
        set_cpu_pc(16'h0000);
        
        step_cpu(); // LDI R1, #0x100
        step_cpu(); // ADDI R1, #0x050
        step_cpu(); // ADDI R1, #0x00A
        
        read_cpu_reg(1, reg_val);
        if (reg_val == 16'h015A) begin
            `uvm_info("CPU_INST", $sformatf("✓ ADDI chain: R1=0x%04x (expected 0x015A)", reg_val), UVM_LOW)
            tests_passed++;
        end else begin
            `uvm_error("CPU_INST", $sformatf("✗ ADDI chain FAILED: got 0x%04x, expected 0x015A", reg_val))
            tests_failed++;
        end
    endtask
    
    // Test 3: ST/LD to RAM
    task test_ram_store_load();
        bit [15:0] reg_val, mem_val;
        
        `uvm_info("CPU_INST", "=== Test 3: ST/LD to RAM ===", UVM_LOW)
        
        // Program:
        // 0x0000: LDI R0, #0xABCD & 0x1FF = 0x0CD
        // 0x0001: LDI R1, #0x100  (address)
        // 0x0002: ST R0, [R1+0]   (write to RAM[0x100])
        // 0x0003: LDI R2, #0x000  (clear R2)
        // 0x0004: LD R2, [R1+0]   (read from RAM[0x100])
        // 0x0005: SYS BRK
        
        write_insn(16'h0000, {OP_LDI, 3'd0, 9'h0CD});
        write_insn(16'h0001, {OP_LDI, 3'd1, 9'h100});
        write_insn(16'h0002, {OP_ST, 3'd0, 3'd1, 6'h00});
        write_insn(16'h0003, {OP_LDI, 3'd2, 9'h000});
        write_insn(16'h0004, {OP_LD, 3'd2, 3'd1, 6'h00});
        write_insn(16'h0005, {OP_SYS, 9'd0, 4'd0});
        
        set_cpu_pc(16'h0000);
        
        step_cpu(); // LDI R0, #0x0CD
        read_cpu_reg(0, reg_val);
        `uvm_info("CPU_INST", $sformatf("R0 (data) = 0x%04x", reg_val), UVM_MEDIUM)
        
        step_cpu(); // LDI R1, #0x100
        read_cpu_reg(1, reg_val);
        `uvm_info("CPU_INST", $sformatf("R1 (addr) = 0x%04x", reg_val), UVM_MEDIUM)
        
        step_cpu(); // ST R0, [R1+0]
        #100ns;
        
        // Read RAM directly to verify write
        read_cpu_mem(16'h0100, mem_val);
        `uvm_info("CPU_INST", $sformatf("RAM[0x0100] after ST = 0x%04x", mem_val), UVM_MEDIUM)
        
        step_cpu(); // LDI R2, #0x000
        step_cpu(); // LD R2, [R1+0]
        
        read_cpu_reg(2, reg_val);
        if (reg_val == 16'h00CD) begin
            `uvm_info("CPU_INST", $sformatf("✓ ST/LD RAM: R2=0x%04x (expected 0x00CD)", reg_val), UVM_LOW)
            tests_passed++;
        end else begin
            `uvm_error("CPU_INST", $sformatf("✗ ST/LD RAM FAILED: got 0x%04x, expected 0x00CD", reg_val))
            tests_failed++;
        end
    endtask
    
    // Test 4: Address building with multiple ADDI
    task test_address_build();
        bit [15:0] reg_val;
        
        `uvm_info("CPU_INST", "=== Test 4: Address Build (128 + 4×128 = 0x280) ===", UVM_LOW)
        
        // Program: Build address 0x280 = 128 + 4×128
        // 0x0000: LDI R1, #0x80   (128)
        // 0x0001: ADDI R1, #0x80  (256)
        // 0x0002: ADDI R1, #0x80  (384)
        // 0x0003: ADDI R1, #0x80  (512)
        // 0x0004: ADDI R1, #0x80  (640 = 0x280)
        // 0x0005: SYS BRK
        
        write_insn(16'h0000, {OP_LDI, 3'd1, 9'h080});
        write_insn(16'h0001, {OP_ADDI, 3'd1, 9'h080});
        write_insn(16'h0002, {OP_ADDI, 3'd1, 9'h080});
        write_insn(16'h0003, {OP_ADDI, 3'd1, 9'h080});
        write_insn(16'h0004, {OP_ADDI, 3'd1, 9'h080});
        write_insn(16'h0005, {OP_SYS, 9'd0, 4'd0});
        
        set_cpu_pc(16'h0000);
        
        step_cpu(); // LDI R1, #0x80
        for (int i = 0; i < 4; i++) begin
            step_cpu(); // ADDI R1, #0x80
        end
        
        read_cpu_reg(1, reg_val);
        if (reg_val == 16'h0280) begin
            `uvm_info("CPU_INST", $sformatf("✓ Address build: R1=0x%04x (expected 0x0280)", reg_val), UVM_LOW)
            tests_passed++;
        end else begin
            `uvm_error("CPU_INST", $sformatf("✗ Address build FAILED: got 0x%04x, expected 0x0280", reg_val))
            tests_failed++;
        end
    endtask
    
endclass
