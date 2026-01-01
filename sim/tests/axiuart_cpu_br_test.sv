`timescale 1ns / 1ps

// Test: CPU Branch (BR) Instruction
// Description: Tests all branch conditions and offset calculations
//
// Test Coverage:
// - BR.AL (always) - unconditional branch
// - BR.Z / BR.NZ - zero flag conditions
// - BR.C / BR.NC - carry flag conditions  
// - BR.N / BR.NN - negative flag conditions
// - Forward and backward branches
// - Loop constructs

class axiuart_cpu_br_test extends axiuart_cpu_test_base;
    `uvm_component_utils(axiuart_cpu_br_test)

    import td4cpu_isa_pkg::*;

    function new(string name = "axiuart_cpu_br_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Build BR instruction
    function bit [15:0] build_br(bit [2:0] cond, bit signed [8:0] offset);
        return {OP_BR, cond, offset[8:0]};
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), "=== Starting CPU Branch Instruction Test ===", UVM_LOW)
        
        // Initialize bridge (reset sequence)
        begin
            uart_reset_sequence reset_seq;
            reset_seq = uart_reset_sequence::type_id::create("reset_seq");
            reset_seq.reset_cycles = 100;
            reset_seq.start(env.uart_agt.sequencer);
            #10us;
        end
        
        test_br_always();
        test_br_zero_flag();
        test_br_carry_flag();
        test_br_negative_flag();
        test_br_loop();
        test_br_forward_backward();
        
        `uvm_info(get_type_name(), "=== CPU Branch Test Complete ===", UVM_LOW)
        
        phase.drop_objection(this);
    endtask

    // Helper: Poll until CPU halts
    task wait_for_halt(input time timeout = 1ms);
        automatic int poll_count = 0;
        automatic int max_polls = int'(timeout / 1us);
        automatic bit halted;
        
        do begin
            #1us;
            halted = axiuart_tb_top.dut.cpu_inst.halted;
            poll_count++;
            
            if (poll_count > max_polls) begin
                `uvm_fatal(get_type_name(), $sformatf("CPU halt timeout after %0t", timeout))
            end
        end while (!halted);
    endtask

    // Helper: Assert CPU register value
    task assert_cpu_reg_equal(input bit [2:0] reg_num, input bit [15:0] expected, input string msg);
        bit [15:0] actual;
        read_cpu_reg(reg_num, actual);
        assert_equal_16(actual, expected, msg);
    endtask

    // Implement pure virtual task from base class
    virtual task run_test_sequence();
        // Not used - test logic is in run_phase
    endtask

    // Helper: Load program and run CPU
    task load_and_run_program(bit [15:0] prog[], int size);
        halt_cpu();
        #500ns;
        
        // Load program
        for (int i = 0; i < size; i++) begin
            write_insn(i, prog[i]);
        end
        
        reset_cpu();
        set_cpu_pc(16'h0000);
        
        // Clear halt reason and run
        write_reg(CPU_DBG_CTRL, 32'h00000010); // CLR_HALT_REASON
        #200ns;
        run_cpu();
    endtask

    // Test 1: BR.AL (Always branch)
    task test_br_always();
        bit [15:0] pc_val;
        
        `uvm_info(get_type_name(), "--- Test 1: BR.AL (Unconditional Branch) ---", UVM_LOW)
        
        // Program (with delay slot):
        // 0x0000: LDI R0, #0x5
        // 0x0001: BR.AL +2       (branch to 0x0004)
        // 0x0002: LDI R7, #0x16  (DELAY SLOT - always executes!)
        // 0x0003: LDI R0, #0xA   (skipped)
        // 0x0004: LDI R1, #0xFF  (branch target)
        // 0x0005: BRK
        
        halt_cpu();
        #500ns;
        
        write_insn(16'h0000, {OP_LDI, 3'd0, 9'd5});           // LDI R0, #5
        write_insn(16'h0001, build_br(COND_AL, 9'd2));        // BR.AL +2
        write_insn(16'h0002, {OP_LDI, 3'd7, 9'h16});          // LDI R7, #0x16 (DELAY SLOT)
        write_insn(16'h0003, {OP_LDI, 3'd0, 9'd10});          // LDI R0, #0xA (skipped)
        write_insn(16'h0004, {OP_LDI, 3'd1, 9'd255});         // LDI R1, #0xFF
        write_insn(16'h0005, {OP_SYS, 9'h000, SYSOP_BRK});    // BRK
        
        reset_cpu();
        set_cpu_pc(16'h0000);
        
        // Clear halt reason and run
        write_reg(CPU_DBG_CTRL, 32'h00000010); // CLR_HALT_REASON
        #200ns;
        run_cpu();
        
        wait_for_halt(1ms);
        
        read_cpu_pc(pc_val);
        assert_equal_16(pc_val, 16'h0006, "PC after BR.AL");
        
        assert_cpu_reg_equal(3'd0, 16'h0005, "R0 = 5 (initial value)");
        assert_cpu_reg_equal(3'd7, 16'h0016, "R7 = 0x16 (delay slot executed!)");
        assert_cpu_reg_equal(3'd1, 16'h00FF, "R1 = 0xFF (branch target executed)");
        
        `uvm_info(get_type_name(), "Test 1 PASSED: BR.AL", UVM_LOW)
    endtask

    // Test 2: BR.Z and BR.NZ (Zero flag)
    task test_br_zero_flag();
        bit [15:0] pc_val;
        
        `uvm_info(get_type_name(), "--- Test 2: BR.Z / BR.NZ (Zero Flag) ---", UVM_LOW)
        
        // Test 2a: BR.Z taken (Z=1)
        `uvm_info(get_type_name(), "Test 2a: BR.Z taken when Z=1", UVM_MEDIUM)
        
        // Program (with delay slot):
        // 0x0000: LDI R0, #1
        // 0x0001: ADDI R0, #-1      (R0=0, Z=1)
        // 0x0002: BR.Z +2           (taken, branch to 0x0005)
        // 0x0003: LDI R7, #0x77     (DELAY SLOT - executes regardless!)
        // 0x0004: LDI R1, #0xAA     (skipped)
        // 0x0005: LDI R1, #0xCC     (branch target)
        // 0x0006: BRK
        
        write_insn(16'h0000, {OP_LDI, 3'd0, 9'd1});           // LDI R0, #1
        write_insn(16'h0001, {OP_ADDI, 3'd0, 9'h1FF});        // ADDI R0, #-1 (sets Z=1)
        write_insn(16'h0002, build_br(COND_Z, 9'd2));         // BR.Z +2
        write_insn(16'h0003, {OP_LDI, 3'd7, 9'h77});          // LDI R7, #0x77 (DELAY SLOT)
        write_insn(16'h0004, {OP_LDI, 3'd1, 9'hAA});          // LDI R1, #0xAA (skipped)
        write_insn(16'h0005, {OP_LDI, 3'd1, 9'hCC});          // LDI R1, #0xCC
        write_insn(16'h0006, {OP_SYS, 9'h000, SYSOP_BRK});    // BRK
        
        reset_cpu();
        set_cpu_pc(16'h0000);
        run_cpu();
        wait_for_halt(1ms);
        
        assert_cpu_reg_equal(3'd0, 16'h0000, "R0 = 0 (Z flag set)");
        assert_cpu_reg_equal(3'd7, 16'h0077, "R7 = 0x77 (delay slot executed even when branch taken)");
        assert_cpu_reg_equal(3'd1, 16'h00CC, "R1 = 0xCC (BR.Z taken)");
        
        // Test 2b: BR.NZ not taken (Z=1)
        `uvm_info(get_type_name(), "Test 2b: BR.NZ not taken when Z=1", UVM_MEDIUM)
        
        // Program (with delay slot):
        // 0x0000: LDI R0, #1
        // 0x0001: ADDI R0, #-1      (R0=0, Z=1)
        // 0x0002: BR.NZ +2          (not taken)
        // 0x0003: LDI R3, #0x55     (DELAY SLOT - still executes!)
        // 0x0004: LDI R2, #0xDD     (executed - sequential)
        // 0x0005: BRK
        
        write_insn(16'h0000, {OP_LDI, 3'd0, 9'd1});           // LDI R0, #1
        write_insn(16'h0001, {OP_ADDI, 3'd0, 9'h1FF});        // ADDI R0, #-1
        write_insn(16'h0002, build_br(COND_NZ, 9'd2));        // BR.NZ +2 (not taken)
        write_insn(16'h0003, {OP_LDI, 3'd3, 9'h55});          // LDI R3, #0x55 (DELAY SLOT)
        write_insn(16'h0004, {OP_LDI, 3'd2, 9'hDD});          // LDI R2, #0xDD
        write_insn(16'h0005, {OP_SYS, 9'h000, SYSOP_BRK});    // BRK
        
        reset_cpu();
        set_cpu_pc(16'h0000);
        run_cpu();
        wait_for_halt(1ms);
        
        assert_cpu_reg_equal(3'd3, 16'h0055, "R3 = 0x55 (delay slot executed even when branch NOT taken)");
        assert_cpu_reg_equal(3'd2, 16'h00DD, "R2 = 0xDD (BR.NZ not taken, sequential execution)");
        
        `uvm_info(get_type_name(), "Test 2 PASSED: BR.Z / BR.NZ", UVM_LOW)
    endtask

    // Test 3: BR.C and BR.NC (Carry flag)
    task test_br_carry_flag();
        `uvm_info(get_type_name(), "--- Test 3: BR.C / BR.NC (Carry Flag) ---", UVM_LOW)
        
        // Test 3a: BR.C taken (C=1 from overflow)
        `uvm_info(get_type_name(), "Test 3a: BR.C taken when C=1", UVM_MEDIUM)
        
        // Program (with delay slot):
        // 0x0000: LDI R0, #0xFF
        // 0x0001: ADDI R0, #1       (overflow, C=1)
        // 0x0002: BR.C +1           (taken, branch to 0x0004)
        // 0x0003: LDI R7, #0x88     (DELAY SLOT)
        // 0x0004: LDI R3, #0x22     (branch target)
        // 0x0005: BRK
        
        write_insn(16'h0000, {OP_LDI, 3'd0, 9'h0FF});         // LDI R0, #0xFF
        write_insn(16'h0001, {OP_ADDI, 3'd0, 9'd1});          // ADDI R0, #1 (sets C=1)
        write_insn(16'h0002, build_br(COND_C, 9'd1));         // BR.C +1
        write_insn(16'h0003, {OP_LDI, 3'd7, 9'h88});          // LDI R7, #0x88 (DELAY SLOT)
        write_insn(16'h0004, {OP_LDI, 3'd3, 9'h22});          // LDI R3, #0x22
        write_insn(16'h0005, {OP_SYS, 9'h000, SYSOP_BRK});    // BRK
        
        reset_cpu();
        set_cpu_pc(16'h0000);
        run_cpu();
        wait_for_halt(1ms);
        
        assert_cpu_reg_equal(3'd7, 16'h0088, "R7 = 0x88 (delay slot executed)");
        assert_cpu_reg_equal(3'd3, 16'h0022, "R3 = 0x22 (BR.C taken)");
        
        `uvm_info(get_type_name(), "Test 3 PASSED: BR.C / BR.NC", UVM_LOW)
    endtask

    // Test 4: BR.N and BR.NN (Negative flag)
    task test_br_negative_flag();
        `uvm_info(get_type_name(), "--- Test 4: BR.N / BR.NN (Negative Flag) ---", UVM_LOW)
        
        // Test 4a: BR.N taken (N=1, MSB set)
        `uvm_info(get_type_name(), "Test 4a: BR.N taken when N=1", UVM_MEDIUM)
        
        // Program (with delay slot):
        // 0x0000: LDI R0, #0
        // 0x0001: ADDI R0, #-1      (R0=0xFFFF, N=1)
        // 0x0002: BR.N +1           (taken, branch to 0x0004)
        // 0x0003: LDI R7, #0x99     (DELAY SLOT)
        // 0x0004: LDI R4, #0x44     (branch target)
        // 0x0005: BRK
        
        write_insn(16'h0000, {OP_LDI, 3'd0, 9'd0});           // LDI R0, #0
        write_insn(16'h0001, {OP_ADDI, 3'd0, 9'h1FF});        // ADDI R0, #-1 (sets N=1)
        write_insn(16'h0002, build_br(COND_N, 9'd1));         // BR.N +1
        write_insn(16'h0003, {OP_LDI, 3'd7, 9'h99});          // LDI R7, #0x99 (DELAY SLOT)
        write_insn(16'h0004, {OP_LDI, 3'd4, 9'h44});          // LDI R4, #0x44
        write_insn(16'h0005, {OP_SYS, 9'h000, SYSOP_BRK});    // BRK
        
        reset_cpu();
        set_cpu_pc(16'h0000);
        run_cpu();
        wait_for_halt(1ms);
        
        assert_cpu_reg_equal(3'd7, 16'h0099, "R7 = 0x99 (delay slot executed)");
        assert_cpu_reg_equal(3'd4, 16'h0044, "R4 = 0x44 (BR.N taken)");
        
        `uvm_info(get_type_name(), "Test 4 PASSED: BR.N / BR.NN", UVM_LOW)
    endtask

    // Test 5: Loop construct with BR
    task test_br_loop();
        `uvm_info(get_type_name(), "--- Test 5: Loop Construct (Backward Branch) ---", UVM_LOW)
        
        // Program: Count R0 from 0 to 3 (optimized with delay slot)
        // 0x0000: LDI R0, #0        ; Counter
        // 0x0001: LDI R1, #3        ; Loop limit
        // 0x0002: CMP R0, R1        ; Compare (sets flags)
        // 0x0003: BR.NZ -1          ; Loop if not equal (backward to 0x0003)
        // 0x0004: ADDI R0, #1       ; DELAY SLOT: R++ (executes every iteration!)
        // 0x0005: BRK
        
        write_insn(16'h0000, {OP_LDI, 3'd0, 9'd0});                    // LDI R0, #0
        write_insn(16'h0001, {OP_LDI, 3'd1, 9'd3});                    // LDI R1, #3
        write_insn(16'h0002, {OP_R_ALU, 3'd0, 3'd1, FUNCT_CMP});       // CMP R0, R1
        write_insn(16'h0003, build_br(COND_NZ, -9'sd1));               // BR.NZ -1 (to 0x0003)
        write_insn(16'h0004, {OP_ADDI, 3'd0, 9'd1});                   // ADDI R0, #1 (DELAY SLOT)
        write_insn(16'h0005, {OP_SYS, 9'h000, SYSOP_BRK});             // BRK
        
        reset_cpu();
        set_cpu_pc(16'h0000);
        run_cpu();
        wait_for_halt(2ms);  // Longer timeout for loop
        
        assert_cpu_reg_equal(3'd0, 16'h0003, "R0 = 3 (loop completed 3 iterations)");
        assert_cpu_reg_equal(3'd1, 16'h0003, "R1 = 3 (loop limit unchanged)");
        
        `uvm_info(get_type_name(), "Test 5 PASSED: Loop construct", UVM_LOW)
    endtask

    // Test 6: Forward and backward branches
    task test_br_forward_backward();
        `uvm_info(get_type_name(), "--- Test 6: Forward/Backward Branch Mix ---", UVM_LOW)
        
        // Program: Simple state machine (with delay slots)
        // 0x0000: LDI R5, #0x10
        // 0x0001: BR.AL +3          ; Forward to 0x0005
        // 0x0002: LDI R6, #0x01     ; DELAY SLOT (first branch marker)
        // 0x0003: LDI R5, #0x20     ; (skipped initially)
        // 0x0004: BR.AL +3          ; Forward to 0x0008
        // 0x0005: LDI R6, #0x02     ; DELAY SLOT (second branch marker)
        // 0x0006: LDI R5, #0x30     ; (never executed)
        // 0x0007: LDI R5, #0x40     ; First forward target
        // 0x0008: BR.AL -4          ; Backward to 0x0005
        // 0x0009: LDI R6, #0x03     ; DELAY SLOT (third branch marker)
        // 0x000A: BRK               ; Second forward target
        
        write_insn(16'h0000, {OP_LDI, 3'd5, 9'h10});          // LDI R5, #0x10
        write_insn(16'h0001, build_br(COND_AL, 9'd3));        // BR.AL +3
        write_insn(16'h0002, {OP_LDI, 3'd6, 9'h01});          // LDI R6, #0x01 (DELAY SLOT 1)
        write_insn(16'h0003, {OP_LDI, 3'd5, 9'h20});          // LDI R5, #0x20 (skipped)
        write_insn(16'h0004, build_br(COND_AL, 9'd3));        // BR.AL +3
        write_insn(16'h0005, {OP_LDI, 3'd6, 9'h02});          // LDI R6, #0x02 (DELAY SLOT 2)
        write_insn(16'h0006, {OP_LDI, 3'd5, 9'h30});          // LDI R5, #0x30 (never)
        write_insn(16'h0007, {OP_LDI, 3'd5, 9'h40});          // LDI R5, #0x40
        write_insn(16'h0008, build_br(COND_AL, -9'sd4));      // BR.AL -4 (to 0x0005)
        write_insn(16'h0009, {OP_LDI, 3'd6, 9'h03});          // LDI R6, #0x03 (DELAY SLOT 3)
        write_insn(16'h000A, {OP_SYS, 9'h000, SYSOP_BRK});    // BRK
        
        reset_cpu();
        set_cpu_pc(16'h0000);
        run_cpu();
        wait_for_halt(1ms);
        
        assert_cpu_reg_equal(3'd5, 16'h0040, "R5 = 0x40 (forward/backward path executed correctly)");
        assert_cpu_reg_equal(3'd6, 16'h0003, "R6 = 0x03 (all delay slots executed in order: 0x01->0x03->0x02)");
        
        `uvm_info(get_type_name(), "Test 6 PASSED: Forward/Backward branches", UVM_LOW)
    endtask

endclass
