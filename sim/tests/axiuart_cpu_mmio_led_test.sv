// Redesigned LED MMIO Test - Run CPU freely, not step-by-step
// 
// Test Philosophy:
// 1. Write program to CPU RAM (while CPU halted)
// 2. Start CPU running
// 3. CPU executes program freely and writes to LED via MMIO
// 4. CPU halts itself with BRK instruction
// 5. Verify LED register contains expected value
//
// This is more realistic than stepping through every instruction!

class axiuart_cpu_mmio_led_test extends axiuart_cpu_test_base;
    
    `uvm_component_utils(axiuart_cpu_mmio_led_test)
    
    function new(string name = "axiuart_cpu_mmio_led_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    task do_reset();
        uart_reset_sequence reset_seq;
        `uvm_info("CPU_MMIO", "Executing UART reset sequence", UVM_LOW)
        reset_seq = uart_reset_sequence::type_id::create("reset_seq");
        reset_seq.reset_cycles = 100;
        reset_seq.start(env.uart_agt.sequencer);
        #10us; // Wait after reset for CPU to settle
        `uvm_info("CPU_MMIO", "UART reset complete", UVM_LOW)
    endtask
    
    // Implement pure virtual task from base class (not used - we override run_phase)
    virtual task run_test_sequence();
        // Not used - test logic is in run_phase
    endtask
    
    // Helper: Write instruction to CPU RAM (CPU must be halted)
    task write_insn(input bit [15:0] addr, input bit [15:0] insn);
        write_ram_direct(addr, insn);
    endtask
    
    // Helper: Clear halt reason register
    task clear_halt_reason();
        write_reg(CPU_DBG_CTRL, 32'h00000010); // CLR_HALT_REASON
        #50ns;
    endtask
    
    // Helper: Poll until CPU halts with expected reason (DIRECT VERSION - bypasses UART)
    task wait_for_halt(input bit [7:0] expected_reason, input int timeout_us = 100);
        automatic int poll_count = 0;
        automatic int max_polls = timeout_us;
        automatic bit halted;
        automatic bit [7:0] halt_reason;
        
        `uvm_info("CPU_MMIO", $sformatf("Waiting for CPU halt (expected reason=0x%02x)...", expected_reason), UVM_MEDIUM)
        
        do begin
            #1us;
            halted = axiuart_tb_top.dut.cpu_inst.halted;
            halt_reason = axiuart_tb_top.dut.cpu_inst.halt_reason;
            poll_count++;
            
            if (poll_count % 100 == 0) begin
                `uvm_info("CPU_MMIO", $sformatf("Still waiting... halted=%0d reason=0x%02x pc=0x%04x [%0d/%0d us]", 
                          halted, halt_reason, axiuart_tb_top.dut.cpu_inst.pc, poll_count, max_polls), UVM_MEDIUM)
            end
            
            if (poll_count > max_polls) begin
                `uvm_fatal("CPU_MMIO", $sformatf("ABORT: wait_for_halt() timeout after %0d us. halted=%0d reason=0x%02x pc=0x%04x", 
                           poll_count, halted, halt_reason, axiuart_tb_top.dut.cpu_inst.pc))
            end
        end while (!halted || halt_reason != expected_reason);
        
        `uvm_info("CPU_MMIO", $sformatf("CPU halted: reason=0x%02x after %0d us", halt_reason, poll_count), UVM_LOW)
    endtask
    
    // Helper: Start CPU running
    task run_cpu();
        `uvm_info("CPU_MMIO", "Starting CPU execution (RUN)", UVM_MEDIUM)
        write_reg(CPU_DBG_CTRL, 32'h00000002); // RUN command
        #200ns; // Allow state change
    endtask
    
    virtual task run_phase(uvm_phase phase);
        bit [15:0] r0_val, r1_val, pc_val;
        bit [3:0] led_val;
        bit [31:0] status;
        
        phase.raise_objection(this);
        
        do_reset();
        
        `uvm_info("CPU_MMIO", "========================================", UVM_LOW)
        `uvm_info("CPU_MMIO", "Test 1: Simple LED Write Pattern", UVM_LOW)
        `uvm_info("CPU_MMIO", "========================================", UVM_LOW)
        
        // Ensure CPU is halted
        halt_cpu();
        clear_halt_reason();
        
        // Program (total: 4 instructions):
        // 0x0000: LDI R0, #0x0A       ; R0 = 0x0A (LED pattern)
        // 0x0001: LDI R1, #0x1F       ; R1 = 0x1F (low byte of LED address)
        // 0x0002: ST R0, [R1+0x100]   ; Write R0 to [R1+256] = [0x11F] = 0x101F (LED MMIO)
        // 0x0003: SYS #BRK            ; Halt with BRK
        
        write_insn(16'h0000, {OP_LDI, 3'd0, 9'd10});          // LDI R0, #10
        write_insn(16'h0001, {OP_LDI, 3'd1, 9'd31});          // LDI R1, #31
        write_insn(16'h0002, {OP_ST, 3'd0, 3'd1, 6'sd16});    // ST R0, [R1+16] → [31+256] = 287 = 0x11F ≠ LED!
        // CORRECTION: offset is 6-bit signed, max positive = +31
        // LED address = 0x101F = 4127
        // We need: base + offset = 4127
        // Max offset = +31, so base must be 4127 - 31 = 4096 = 0x1000
        
        `uvm_info("CPU_MMIO", "CORRECTED: Building address 0x101F = 0x1000 (base) + 0x1F (offset)", UVM_MEDIUM)
        
        write_insn(16'h0000, {OP_LDI, 3'd0, 9'd10});          // LDI R0, #10 (LED pattern)
        // Build R1 = 0x1000 using LDI + ADDIs
        write_insn(16'h0001, {OP_LDI, 3'd1, 9'd128});         // LDI R1, #128
        write_insn(16'h0002, {OP_ADDI, 3'd1, 9'd128});        // R1 = 256
        write_insn(16'h0003, {OP_ADDI, 3'd1, 9'd128});        // R1 = 384
        write_insn(16'h0004, {OP_ADDI, 3'd1, 9'd128});        // R1 = 512
        write_insn(16'h0005, {OP_ADDI, 3'd1, 9'd128});        // R1 = 640
        write_insn(16'h0006, {OP_ADDI, 3'd1, 9'd128});        // R1 = 768
        write_insn(16'h0007, {OP_ADDI, 3'd1, 9'd128});        // R1 = 896
        write_insn(16'h0008, {OP_ADDI, 3'd1, 9'd128});        // R1 = 1024
        write_insn(16'h0009, {OP_ADDI, 3'd1, 9'd128});        // R1 = 1152
        write_insn(16'h000A, {OP_ADDI, 3'd1, 9'd128});        // R1 = 1280
        write_insn(16'h000B, {OP_ADDI, 3'd1, 9'd128});        // R1 = 1408
        write_insn(16'h000C, {OP_ADDI, 3'd1, 9'd128});        // R1 = 1536
        write_insn(16'h000D, {OP_ADDI, 3'd1, 9'd128});        // R1 = 1664
        write_insn(16'h000E, {OP_ADDI, 3'd1, 9'd128});        // R1 = 1792
        write_insn(16'h000F, {OP_ADDI, 3'd1, 9'd128});        // R1 = 1920
        write_insn(16'h0010, {OP_ADDI, 3'd1, 9'd128});        // R1 = 2048
        write_insn(16'h0011, {OP_ADDI, 3'd1, 9'd128});        // R1 = 2176
        write_insn(16'h0012, {OP_ADDI, 3'd1, 9'd128});        // R1 = 2304
        write_insn(16'h0013, {OP_ADDI, 3'd1, 9'd128});        // R1 = 2432
        write_insn(16'h0014, {OP_ADDI, 3'd1, 9'd128});        // R1 = 2560
        write_insn(16'h0015, {OP_ADDI, 3'd1, 9'd128});        // R1 = 2688
        write_insn(16'h0016, {OP_ADDI, 3'd1, 9'd128});        // R1 = 2816
        write_insn(16'h0017, {OP_ADDI, 3'd1, 9'd128});        // R1 = 2944
        write_insn(16'h0018, {OP_ADDI, 3'd1, 9'd128});        // R1 = 3072
        write_insn(16'h0019, {OP_ADDI, 3'd1, 9'd128});        // R1 = 3200
        write_insn(16'h001A, {OP_ADDI, 3'd1, 9'd128});        // R1 = 3328
        write_insn(16'h001B, {OP_ADDI, 3'd1, 9'd128});        // R1 = 3456
        write_insn(16'h001C, {OP_ADDI, 3'd1, 9'd128});        // R1 = 3584
        write_insn(16'h001D, {OP_ADDI, 3'd1, 9'd128});        // R1 = 3712
        write_insn(16'h001E, {OP_ADDI, 3'd1, 9'd128});        // R1 = 3840
        write_insn(16'h001F, {OP_ADDI, 3'd1, 9'd128});        // R1 = 3968
        write_insn(16'h0020, {OP_ADDI, 3'd1, 9'd128});        // R1 = 4096 = 0x1000 ✓
        write_insn(16'h0021, {OP_ST, 3'd0, 3'd1, 6'sd31});    // ST R0, [R1+31] → [0x1000+0x1F] = 0x101F ✓
        write_insn(16'h0022, {OP_SYS, 9'd0, SYSOP_BRK});      // SYS BRK (0x6001)
        
        // CRITICAL: Wait for all UART writes to complete before running CPU
        `uvm_info("CPU_MMIO", "Waiting for all instruction writes to settle...", UVM_MEDIUM)
        #200us; // Allow time for 35+ UART transactions to complete
        
        // Set PC to start
        set_cpu_pc(16'h0000);
        
        // ===============================================
        // KEY CHANGE: Run CPU freely, don't step!
        // ===============================================
        run_cpu();
        
        // DEBUG: Check CPU state immediately after run_cpu()
        #100ns;
        `uvm_info("CPU_DEBUG", $sformatf("After run_cpu(): trace_valid=%0d trace_pc=0x%04x", 
                  axiuart_tb_top.cpu_trace_valid,
                  axiuart_tb_top.cpu_trace_pc), UVM_LOW)
        `uvm_info("CPU_DEBUG", "Starting wait_for_halt with direct CPU probing...", UVM_LOW)
        
        // Wait for BRK (halt_reason = 0x05)
        wait_for_halt(8'h05, 1000); // 1ms timeout (plenty for 35 instructions)
        
        // Verify results
        read_cpu_reg(0, r0_val);
        read_cpu_reg(1, r1_val);
        led_val = axiuart_tb_top.led; // Read LED directly from testbench signal
        
        // Also read other useful debug info
        read_cpu_pc(pc_val);
        
        `uvm_info("CPU_MMIO", $sformatf("CPU halted. R0=0x%04x R1=0x%04x PC=0x%04x LED=0x%01x", r0_val, r1_val, pc_val, led_val), UVM_LOW)
        
        if (r1_val != 16'h1000) begin
            `uvm_error("CPU_MMIO", $sformatf("Address build failed: R1=0x%04x (expected 0x1000)", r1_val))
        end
        
        if (led_val[3:0] != 4'hA) begin
            `uvm_error("CPU_MMIO", $sformatf("LED write failed: LED=0x%01x (expected 0xA)", led_val[3:0]))
        end else begin
            `uvm_info("CPU_MMIO", "✓ Test 1 PASSED: LED pattern = 0xA", UVM_LOW)
        end
        
        phase.drop_objection(this);
    endtask
    
endclass
