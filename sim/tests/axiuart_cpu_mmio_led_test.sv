//------------------------------------------------------------------------------
// CPU MMIO LED Test - LD/ST Instruction Verification for LED Control
// Purpose: Verify CPU can access LED register at 0x101F using LD/ST instructions
// Features: LDI, LD, ST to MMIO space, LED output observation
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

import uvm_pkg::*;
import td4cpu_isa_pkg::*;
import axiuart_reg_pkg::*;

class axiuart_cpu_mmio_led_test extends axiuart_base_test;
    `uvm_component_utils(axiuart_cpu_mmio_led_test)

    // Register addresses from axiuart_reg_pkg
    localparam bit [31:0] CPU_DBG_CTRL     = REG_CPU_DBG_CTRL;
    localparam bit [31:0] CPU_DBG_STATUS   = REG_CPU_DBG_STATUS;
    localparam bit [31:0] CPU_PC           = REG_CPU_PC;
    localparam bit [31:0] CPU_FLAGS        = REG_CPU_FLAGS;
    localparam bit [31:0] CPU_REG_INDEX    = REG_CPU_REG_INDEX;
    localparam bit [31:0] CPU_REG_DATA     = REG_CPU_REG_DATA;
    localparam bit [31:0] CPU_MEM_ADDR     = REG_CPU_MEM_ADDR;
    localparam bit [31:0] CPU_MEM_WDATA    = REG_CPU_MEM_WDATA;
    localparam bit [31:0] CPU_MEM_RDATA    = REG_CPU_MEM_RDATA;
    localparam bit [31:0] CPU_MEM_CTRL     = REG_CPU_MEM_CTRL;

    // MMIO LED address (maximum reachable with ST instruction's 6-bit signed offset)
    localparam bit [15:0] LED_MMIO_ADDR = 16'h101F;
    
    // Test statistics
    int tests_passed = 0;
    int tests_failed = 0;

    function new(string name = "axiuart_cpu_mmio_led_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //--------------------------------------------------------------------------
    // Helper Tasks - Register Access
    //--------------------------------------------------------------------------
    task write_reg(bit [31:0] addr, bit [31:0] data);
        uart_reg_write_sequence wr_seq;
        wr_seq = uart_reg_write_sequence::type_id::create("wr_seq");
        wr_seq.reg_addr = addr;
        wr_seq.reg_data = data;
        wr_seq.start(env.uart_agt.sequencer);
    endtask

    task read_reg(bit [31:0] addr, output bit [31:0] data);
        uart_reg_read_sequence rd_seq;
        rd_seq = uart_reg_read_sequence::type_id::create("rd_seq");
        rd_seq.reg_addr = addr;
        rd_seq.start(env.uart_agt.sequencer);
        data = rd_seq.read_data;
    endtask

    //--------------------------------------------------------------------------
    // Helper Tasks - CPU Control
    //--------------------------------------------------------------------------
    task init_cpu_debug();
        bit cpu_halted_state;
        
        // Halt CPU and clear halt-on-reset flag
        write_reg(CPU_DBG_CTRL, 32'h00000001); // Halt CPU (bit[0])
        #50ns;
        
        // Verify CPU halted state directly
        cpu_halted_state = axiuart_tb_top.dut.cpu_inst.halted;
        `uvm_info("CPU_MMIO", $sformatf("CPU halted state: %0d", cpu_halted_state), UVM_MEDIUM)
        
        write_reg(CPU_DBG_STATUS, 32'hFFFFFFFF); // Clear status flags
        #50ns;
    endtask

    task halt_cpu();
        write_reg(CPU_DBG_CTRL, 32'h00000001); // Halt request
        #50ns;
    endtask

    task step_cpu();
        bit [31:0] status;
        bit cpu_halted;
        bit [7:0] halt_reason;
        int timeout_count;
        
        // Verify CPU is halted before stepping
        cpu_halted = axiuart_tb_top.dut.cpu_inst.halted;
        if (!cpu_halted) begin
            `uvm_warning("CPU_MMIO", "step_cpu() called but CPU not halted - halting first")
            write_reg(CPU_DBG_CTRL, 32'h00000001);
            #100ns;
        end
        
        // Clear halt reason before stepping
        write_reg(CPU_DBG_CTRL, 32'h00000010); // CLR_HALT_REASON
        #50ns;
        
        // Issue step command
        write_reg(CPU_DBG_CTRL, 32'h00000004); // Step request
        #50ns;
        
        // Poll for STEP_DONE halt reason (bits[15:8] = 0x03)
        timeout_count = 0;
        do begin
            #200ns;
            read_reg(CPU_DBG_STATUS, status);
            halt_reason = status[15:8];
            timeout_count++;
            if (timeout_count > 50) begin
                `uvm_error("CPU_MMIO", $sformatf("step_cpu() timeout after %0d polls - halt_reason=0x%02x (expected 0x03)", timeout_count, halt_reason))
                return; // Exit task on timeout
            end
        end while ((halt_reason != 8'h03) && (timeout_count <= 50));
        
        if (halt_reason == 8'h03) begin
            `uvm_info("CPU_MMIO", $sformatf("CPU step completed: halt_reason=0x%02x (STEP_DONE)", halt_reason), UVM_HIGH)
        end
        
        #50ns;
    endtask

    task set_cpu_pc(input bit [15:0] pc_value);
        write_reg(CPU_PC, {16'h0000, pc_value});
        #10ns;
    endtask

    //--------------------------------------------------------------------------
    // Helper Tasks - Memory and Register Access
    //--------------------------------------------------------------------------
    task write_insn(input bit [15:0] addr, input bit [15:0] insn);
        write_reg(CPU_MEM_ADDR, {16'h0000, addr});
        #2us;
        write_reg(CPU_MEM_WDATA, {16'h0000, insn});
        #2us;
        write_reg(CPU_MEM_CTRL, 32'h00000002); // Write request
        #4us; // Match working test timing
    endtask

    task write_cpu_reg(input bit [2:0] reg_idx, input bit [15:0] value);
        write_reg(CPU_REG_INDEX, {29'h0, reg_idx});
        #2us;
        write_reg(CPU_REG_DATA, {16'h0000, value});
        #4us; // Match working test timing
    endtask

    task read_cpu_reg(input bit [2:0] reg_idx, output bit [15:0] value);
        bit [31:0] rdata;
        write_reg(CPU_REG_INDEX, {29'h0, reg_idx});
        #10ns;
        read_reg(CPU_REG_DATA, rdata);
        value = rdata[15:0];
        #10ns;
    endtask

    task read_cpu_flags(output bit z, n, c, v);
        bit [31:0] flags_reg;
        read_reg(CPU_FLAGS, flags_reg);
        z = flags_reg[0];
        n = flags_reg[1];
        c = flags_reg[2];
        v = flags_reg[3];
    endtask

    //--------------------------------------------------------------------------
    // Helper Tasks - LED Observation
    //--------------------------------------------------------------------------
    task read_led_output(output bit [3:0] led_value);
        // Direct hierarchical access to LED output
        led_value = axiuart_tb_top.dut.led;
        `uvm_info("CPU_MMIO", $sformatf("LED output: 0x%01x (binary: %04b)", led_value, led_value), UVM_MEDIUM)
    endtask

    //--------------------------------------------------------------------------
    // Test Sequence Tasks
    //--------------------------------------------------------------------------
    
    // Test 1: Basic ST instruction to LED MMIO
    task test_st_to_led();
        bit [3:0] led_before, led_after;
        bit [15:0] r0_val, r1_val;
        
        `uvm_info("CPU_MMIO", "=== Test 1: ST instruction to LED MMIO ===", UVM_LOW)
        
        // Read LED state before
        read_led_output(led_before);
        `uvm_info("CPU_MMIO", $sformatf("LED before: 0x%01x", led_before), UVM_LOW)
        
        // Program: Build LED address 0x101F using ADDI instructions
        // 0x101F = 4127 = 256×16 + 31 = 0x1000 + 0x1F
        // Strategy: LDI 256, ADDI×16 to get 4096, then ADDI to reach 4127
        // 0x0000: LDI R0, #0xA        ; LED pattern = 10
        // 0x0001: LDI R1, #0x100      ; R1 = 256
        // 0x0002: ADDI R1, #0x100     ; R1 = 512
        // 0x0003: ADDI R1, #0x100     ; R1 = 768
        // 0x0004: ADDI R1, #0x100     ; R1 = 1024 (0x400)
        // 0x0005: ADDI R1, #0x100     ; R1 = 1280 (0x500)
        // 0x0006: ADDI R1, #0x100     ; R1 = 1536 (0x600)
        // 0x0007: ADDI R1, #0x100     ; R1 = 1792 (0x700)
        // 0x0008: ADDI R1, #0x100     ; R1 = 2048 (0x800)
        // 0x0009: ADDI R1, #0x100     ; R1 = 2304 (0x900)
        // 0x000A: ADDI R1, #0x100     ; R1 = 2560 (0xA00)
        // 0x000B: ADDI R1, #0x100     ; R1 = 2816 (0xB00)
        // 0x000C: ADDI R1, #0x100     ; R1 = 3072 (0xC00)
        // 0x000D: ADDI R1, #0x100     ; R1 = 3328 (0xD00)
        // 0x000E: ADDI R1, #0x100     ; R1 = 3584 (0xE00)
        // 0x000F: ADDI R1, #0x100     ; R1 = 3840 (0xF00)
        // 0x0010: ADDI R1, #0x100     ; R1 = 4096 (0x1000)
        // 0x0011: ADDI R1, #0x1F      ; R1 = 4127 (0x101F) ← LED address!
        // 0x0012: ST R0, [R1+0]       ; Write to LED
        // 0x0013: SYS #BRK            ; Halt
        
        write_insn(16'h0000, {OP_LDI, 3'd0, 9'h00A});    // LDI R0, #0xA
        $display("[DEBUG] Instruction at 0x0001: {OP_LDI=%0d, rd=1, imm=0x080} = 0x%04x", OP_LDI, {OP_LDI, 3'd1, 9'h080});
        write_insn(16'h0001, {OP_LDI, 3'd1, 9'h080});    // LDI R1, #0x80 (128) - Start with positive value
        write_insn(16'h0002, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0003, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0004, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0005, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0006, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0007, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0008, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0009, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h000A, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h000B, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h000C, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h000D, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h000E, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h000F, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0010, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0011, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0012, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0013, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0014, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0015, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0016, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0017, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0018, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0019, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h001A, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h001B, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h001C, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h001D, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h001E, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h001F, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80
        write_insn(16'h0020, {OP_ADDI, 3'd1, 9'h080});   // ADDI R1, #0x80 (31st ADDI)
        write_insn(16'h0021, {OP_ADDI, 3'd1, 9'h01F});   // ADDI R1, #0x1F → R1=0x101F (128 + 31×128 + 31 = 4127)
        write_insn(16'h0022, {OP_ST, 3'd0, 3'd1, 6'h00}); // ST R0, [R1+0]
        write_insn(16'h0023, {OP_SYS, 9'd0, 4'd0});      // SYS BRK
        
        // Reset PC and execute
        set_cpu_pc(16'h0000);
        `uvm_info("CPU_MMIO", "Executing: LDI R0, #0x0A", UVM_MEDIUM)
        step_cpu();
        read_cpu_reg(0, r0_val);
        `uvm_info("CPU_MMIO", $sformatf("R0 = 0x%04x (LED pattern)", r0_val), UVM_MEDIUM)
        
        `uvm_info("CPU_MMIO", "Building address 0x101F with LDI+ADDI...", UVM_MEDIUM)
        step_cpu(); // LDI R1, #0x80
        for (int i = 0; i < 32; i++) begin
            step_cpu(); // ADDI R1, #0x80 or #0x1F
        end
        read_cpu_reg(1, r1_val);
        `uvm_info("CPU_MMIO", $sformatf("R1 = 0x%04x (expected: 0x101F)", r1_val), UVM_MEDIUM)
        if (r1_val != 16'h101F) begin
            `uvm_error("CPU_MMIO", $sformatf("Address build failed: R1=0x%04x (expected 0x101F); aborting ST test", r1_val))
            tests_failed++;
            return;
        end
        
        `uvm_info("CPU_MMIO", "Executing: ST R0, [R1+0] (write to LED)", UVM_MEDIUM)
        step_cpu();
        #500ns; // Wait for LED output to settle
        
        read_led_output(led_after);
        `uvm_info("CPU_MMIO", $sformatf("LED after ST: 0x%01x (expected: 0x0A)", led_after), UVM_LOW)
        
        if (led_after == 4'hA) begin
            `uvm_info("CPU_MMIO", "✓ ST to LED MMIO PASSED", UVM_LOW)
            tests_passed++;
        end else begin
            `uvm_error("CPU_MMIO", $sformatf("✗ ST to LED MMIO FAILED: got 0x%01x, expected 0x0A", led_after))
            tests_failed++;
        end
    endtask

    // Test 2: LD instruction from LED MMIO (readback)
    task test_ld_from_led();
        bit [15:0] r2_val;
        bit [3:0] led_current;
        
        `uvm_info("CPU_MMIO", "=== Test 2: LD instruction from LED MMIO ===", UVM_LOW)
        
        // Continue from previous test state (LED should be 0xA)
        // Program continues at 0x0004:
        // 0x0004: LD R2, [R1+0x00]  ; Load from [0x101F] into R2
        // 0x0005: SYS #BRK          ; Halt
        
        write_insn(16'h0004, {OP_LD, 3'd2, 3'd1, 6'h00}); // LD R2, [R1+0]
        write_insn(16'h0005, {OP_SYS, 9'd0, 4'd0}); // SYS BRK
        
        set_cpu_pc(16'h0004);
        `uvm_info("CPU_MMIO", "Executing: LD R2, [R1+0] (read from 0x101F)", UVM_MEDIUM)
        step_cpu();
        #50ns;
        
        read_cpu_reg(2, r2_val);
        read_led_output(led_current);
        `uvm_info("CPU_MMIO", $sformatf("R2 after LD: 0x%04x, LED value: 0x%01x", r2_val, led_current), UVM_LOW)
        
        if (r2_val[3:0] == led_current) begin
            `uvm_info("CPU_MMIO", "✓ LD from LED MMIO PASSED", UVM_LOW)
            tests_passed++;
        end else begin
            `uvm_error("CPU_MMIO", $sformatf("✗ LD from LED MMIO FAILED: R2=0x%04x, LED=0x%01x", r2_val, led_current))
            tests_failed++;
        end
    endtask

    // Test 3: LED pattern sequence (simplified - 4 patterns only)
    task test_led_counter_pattern();
        bit [3:0] led_val;
        bit [15:0] r3_val;
        bit [15:0] r1_val;
        int pattern_errors = 0;
        
        `uvm_info("CPU_MMIO", "=== Test 3: LED Binary Counter Pattern (4 patterns) ===", UVM_LOW)
        
        // Simplified test: Only test 4 patterns instead of 16
        // Build LED address 0x101F = 4096 + 31 using ADDI sequence (same as Test 1)
        // 0x0010: LDI R3, #0x00     ; Counter = 0
        // 0x0011: LDI R1, #0x80     ; R1 = 128
        // 0x0012-0x0030: ADDI R1, #0x80 (31 times) ; R1 = 4096
        // 0x0031: ADDI R1, #0x1F    ; R1 = 4127 (0x101F)
        // 0x0032: ST R3, [R1+0]     ; Write to LED
        // 0x0033: ADDI R3, #3       ; Increment counter by 3
        // ... (repeat for 4 patterns)
        
        write_insn(16'h0010, {OP_LDI, 3'd3, 9'h000}); // LDI R3, #0
        write_insn(16'h0011, {OP_LDI, 3'd1, 9'h080}); // LDI R1, #0x80
        // ADDI sequence to build 0x1000
        for (int i = 0; i < 31; i++) begin
            write_insn(16'h0012 + i, {OP_ADDI, 3'd1, 9'h080}); // ADDI R1, #0x80
        end
        write_insn(16'h0031, {OP_ADDI, 3'd1, 9'h01F}); // ADDI R1, #0x1F → R1=0x101F
        
        set_cpu_pc(16'h0010);
        step_cpu(); // LDI R3
        step_cpu(); // LDI R1
        for (int i = 0; i < 32; i++) begin
            step_cpu(); // ADDI R1 (build address)
        end
        read_cpu_reg(1, r1_val);
        `uvm_info("CPU_MMIO", $sformatf("R1 = 0x%04x (expected: 0x101F)", r1_val), UVM_MEDIUM)
        if (r1_val != 16'h101F) begin
            `uvm_error("CPU_MMIO", $sformatf("Address build failed: R1=0x%04x (expected 0x101F); aborting pattern test", r1_val))
            tests_failed++;
            return;
        end
        
        // Test 4 patterns: 0x0, 0x3, 0x6, 0x9
        for (int i = 0; i < 4; i++) begin
            int expected_value = i * 3;
            
            // Write program: ST R3, [R1+0] and ADDI R3, #3
            // Start at 0x0032 (after address construction)
            write_insn(16'h0032 + (i*2), {OP_ST, 3'd3, 3'd1, 6'h00});
            write_insn(16'h0033 + (i*2), {OP_ADDI, 3'd3, 9'h003}); // ADDI R3, #3
            
            set_cpu_pc(16'h0032 + (i*2));
            step_cpu(); // ST
            #100ns;
            
            read_led_output(led_val);
            `uvm_info("CPU_MMIO", $sformatf("Counter[%0d]: LED=0x%01x (expected: 0x%01x)", i, led_val, expected_value[3:0]), UVM_MEDIUM)
            
            if (led_val != expected_value[3:0]) begin
                `uvm_error("CPU_MMIO", $sformatf("Pattern mismatch at step %0d", i))
                pattern_errors++;
            end
            
            if (i < 3) begin
                step_cpu(); // ADDI (increment for next iteration)
                read_cpu_reg(3, r3_val);
                `uvm_info("CPU_MMIO", $sformatf("R3 incremented to: 0x%04x", r3_val), UVM_HIGH)
            end
        end
        
        if (pattern_errors == 0) begin
            `uvm_info("CPU_MMIO", "✓ LED Counter Pattern PASSED (4 patterns)", UVM_LOW)
            tests_passed++;
        end else begin
            `uvm_error("CPU_MMIO", $sformatf("✗ LED Counter Pattern FAILED: %0d errors", pattern_errors))
            tests_failed++;
        end
    endtask

    // Test 4: Negative offset addressing
    task test_negative_offset();
        bit [3:0] led_val;
        bit [15:0] r4_val, r5_val;
        
        `uvm_info("CPU_MMIO", "=== Test 4: Negative Offset Addressing ===", UVM_LOW)
        
        // Program:
        // Build LED address 0x101F using negative offset from 0x1023
        // 0x0100: LDI R4, #0x05     ; LED pattern
        // 0x0101: LDI R5, #0x80     ; R5 = 128
        // 0x0102-0x0120: ADDI R5, #0x80 (31 times) ; R5 = 4096
        // 0x0121: ADDI R5, #0x23    ; R5 = 4131 (0x1023)
        // 0x0122: ST R4, [R5-0x04]  ; Store to [0x1023 - 4] = 0x101F
        
        write_insn(16'h0100, {OP_LDI, 3'd4, 9'h005}); // LDI R4, #0x05
        write_insn(16'h0101, {OP_LDI, 3'd5, 9'h080}); // LDI R5, #0x80
        // ADDI sequence to build 0x1000
        for (int i = 0; i < 31; i++) begin
            write_insn(16'h0102 + i, {OP_ADDI, 3'd5, 9'h080}); // ADDI R5, #0x80
        end
        write_insn(16'h0121, {OP_ADDI, 3'd5, 9'h023}); // ADDI R5, #0x23 → R5=0x1023
        write_insn(16'h0122, {OP_ST, 3'd4, 3'd5, 6'h3C}); // ST R4, [R5-4] (offset=-4 = 0x3C in 6-bit signed)
        
        set_cpu_pc(16'h0100);
        step_cpu(); // LDI R4
        read_cpu_reg(4, r4_val);
        `uvm_info("CPU_MMIO", $sformatf("R4 = 0x%04x", r4_val), UVM_MEDIUM)
        
        step_cpu(); // LDI R5
        for (int i = 0; i < 32; i++) begin
            step_cpu(); // ADDI R5 (build address)
        end
        read_cpu_reg(5, r5_val);
        `uvm_info("CPU_MMIO", $sformatf("R5 = 0x%04x (expected: 0x1023)", r5_val), UVM_MEDIUM)
        if (r5_val != 16'h1023) begin
            `uvm_error("CPU_MMIO", $sformatf("Address build failed: R5=0x%04x (expected 0x1023); aborting negative-offset test", r5_val))
            tests_failed++;
            return;
        end
        
        step_cpu(); // ST with negative offset
        #100ns;
        
        read_led_output(led_val);
        `uvm_info("CPU_MMIO", $sformatf("LED after negative offset ST: 0x%01x (expected: 0x05)", led_val), UVM_LOW)
        
        if (led_val == 4'h5) begin
            `uvm_info("CPU_MMIO", "✓ Negative Offset Addressing PASSED", UVM_LOW)
            tests_passed++;
        end else begin
            `uvm_error("CPU_MMIO", $sformatf("✗ Negative Offset Addressing FAILED: got 0x%01x, expected 0x05", led_val))
            tests_failed++;
        end
    endtask

    // Test 5: RAM vs MMIO addressing boundary
    task test_ram_mmio_boundary();
        bit [15:0] r6_val, r7_val;
        bit [3:0] led_val;
        
        `uvm_info("CPU_MMIO", "=== Test 5: RAM/MMIO Boundary Test ===", UVM_LOW)
        
        // Program:
        // 0x0200: LDI R6, #0x0F     ; Data for RAM
        // 0x0201: LDI R7, #0xFF     ; Address 0x0FFF (last RAM word)
        // 0x0202: ST R6, [R7+0x00]  ; Store to RAM
        // 0x0203: LDI R6, #0x03     ; Data for LED
        // 0x0204: LDI R7, #0x100    ; R7 = 256
        // 0x0205-0x0213: ADDI R7, #0x100 (15 times) ; R7 = 4096
        // 0x0214: ADDI R7, #0x1F    ; R7 = 4127 (0x101F)
        // 0x0215: ST R6, [R7+0x00]  ; Store to LED MMIO
        
        write_insn(16'h0200, {OP_LDI, 3'd6, 9'h00F}); // LDI R6, #0x0F
        write_insn(16'h0201, {OP_LDI, 3'd7, 9'h0FF}); // LDI R7, #0xFF
        write_insn(16'h0202, {OP_ST, 3'd6, 3'd7, 6'h00}); // ST R6, [R7+0] (to RAM)
        write_insn(16'h0203, {OP_LDI, 3'd6, 9'h003}); // LDI R6, #0x03
        write_insn(16'h0204, {OP_LDI, 3'd7, 9'h080}); // LDI R7, #0x80
        // ADDI sequence to build 0x1000
        for (int i = 0; i < 31; i++) begin
            write_insn(16'h0205 + i, {OP_ADDI, 3'd7, 9'h080}); // ADDI R7, #0x80
        end
        write_insn(16'h0224, {OP_ADDI, 3'd7, 9'h01F}); // ADDI R7, #0x1F → R7=0x101F
        write_insn(16'h0225, {OP_ST, 3'd6, 3'd7, 6'h00}); // ST R6, [R7+0] (to MMIO)
        
        set_cpu_pc(16'h0200);
        
        `uvm_info("CPU_MMIO", "Storing 0x0F to RAM[0x0FFF]", UVM_MEDIUM)
        step_cpu(); // LDI R6, #0x0F
        step_cpu(); // LDI R7, #0xFF
        step_cpu(); // ST to RAM
        #50ns;
        
        `uvm_info("CPU_MMIO", "Storing 0x03 to LED MMIO[0x101F]", UVM_MEDIUM)
        step_cpu(); // LDI R6, #0x03
        step_cpu(); // LDI R7, #0x80
        for (int i = 0; i < 32; i++) begin
            step_cpu(); // ADDI R7 (build address)
        end
        read_cpu_reg(7, r7_val);
        `uvm_info("CPU_MMIO", $sformatf("R7 = 0x%04x (expected: 0x101F)", r7_val), UVM_MEDIUM)
        if (r7_val != 16'h101F) begin
            `uvm_error("CPU_MMIO", $sformatf("Address build failed: R7=0x%04x (expected 0x101F); aborting boundary test", r7_val))
            tests_failed++;
            return;
        end
        step_cpu(); // ST to MMIO
        #100ns;
        
        read_led_output(led_val);
        `uvm_info("CPU_MMIO", $sformatf("LED after boundary test: 0x%01x (expected: 0x03)", led_val), UVM_LOW)
        
        if (led_val == 4'h3) begin
            `uvm_info("CPU_MMIO", "✓ RAM/MMIO Boundary Test PASSED", UVM_LOW)
            tests_passed++;
        end else begin
            `uvm_error("CPU_MMIO", $sformatf("✗ RAM/MMIO Boundary Test FAILED: got 0x%01x, expected 0x03", led_val))
            tests_failed++;
        end
    endtask

    //--------------------------------------------------------------------------
    // Main Test Sequence
    //--------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        uart_reset_sequence reset_seq;
        bit [31:0] version_reg;
        
        phase.raise_objection(this, "Starting CPU MMIO LED test");
        
        `uvm_info("CPU_MMIO", "╔═══════════════════════════════════════════════════════╗", UVM_LOW)
        `uvm_info("CPU_MMIO", "║   CPU MMIO LED TEST - LD/ST Instruction Validation   ║", UVM_LOW)
        `uvm_info("CPU_MMIO", "╚═══════════════════════════════════════════════════════╝", UVM_LOW)
        
        // Execute reset first to initialize DUT properly
        reset_seq = uart_reset_sequence::type_id::create("reset_seq");
        reset_seq.reset_cycles = 200;
        reset_seq.start(env.uart_agt.sequencer);
        
        #100ns;
        
        // Initialize CPU debug interface
        `uvm_info("CPU_MMIO", "Initializing CPU debug interface...", UVM_LOW)
        init_cpu_debug();
        
        // Read version register to confirm UART communication
        read_reg(REG_VERSION, version_reg);
        `uvm_info("CPU_MMIO", $sformatf("Version register: 0x%08x", version_reg), UVM_LOW)
        
        // Run test sequences
        test_st_to_led();
        #200ns;
        
        test_ld_from_led();
        #200ns;
        
        test_led_counter_pattern();
        #200ns;
        
        test_negative_offset();
        #200ns;
        
        test_ram_mmio_boundary();
        #200ns;
        
        // Final report
        `uvm_info("CPU_MMIO", "╔═══════════════════════════════════════════════════════╗", UVM_LOW)
        `uvm_info("CPU_MMIO", $sformatf("║   TEST SUMMARY: %0d PASSED, %0d FAILED%-19s║", 
                  tests_passed, tests_failed, ""), UVM_LOW)
        `uvm_info("CPU_MMIO", "╚═══════════════════════════════════════════════════════╝", UVM_LOW)
        
        if (tests_failed > 0) begin
            `uvm_error("CPU_MMIO", $sformatf("CPU MMIO LED test completed with %0d failures", tests_failed))
        end else begin
            `uvm_info("CPU_MMIO", "CPU MMIO LED test completed successfully!", UVM_LOW)
        end
        
        #500ns;
        phase.drop_objection(this, "CPU MMIO LED test completed");
    endtask

endclass
