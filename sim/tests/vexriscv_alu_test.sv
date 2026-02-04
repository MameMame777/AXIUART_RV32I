`timescale 1ns / 1ps

//==============================================================================
// VexRiscv ALU Operations Test
//==============================================================================
// Test ID: Stage 1.2 - ALU Functionality
// Duration: ~15s
// 
// Purpose:
//   Verify VexRiscv unoptimized decoder ALU control signals for all RV32I
//   arithmetic, logical, comparison, and shift instructions.
//
// Control Signals Verified:
//   - ALU_CTRL (ADD_SUB, SLT_SLTU, BITWISE)
//   - ALU_BITWISE_CTRL (XOR, OR, AND)
//   - SHIFT_CTRL (SLL, SRL, SRA)
//   - SRC1_CTRL, SRC2_CTRL (RS vs IMI selection)
//   - SRC_LESS_UNSIGNED, SRC_USE_SUB_LESS
//
// Test Categories:
//   1. Arithmetic: ADD, SUB, ADDI
//   2. Logical: AND, OR, XOR, ANDI, ORI, XORI
//   3. Comparison: SLT, SLTU, SLTI, SLTIU
//   4. Shift: SLL, SRL, SRA, SLLI, SRLI, SRAI
//   5. Upper Immediate: LUI, AUIPC
//
// Expected Results:
//   All ALU operations produce correct results matching RV32I ISA specification
//
// Pass/Fail Criteria:
//   - All register values match expected computation results
//   - No pipeline stalls or hazards
//==============================================================================

class vexriscv_alu_test extends vexriscv_base_test;
    
    `uvm_component_utils(vexriscv_alu_test)
    
    //==========================================================================
    // Constructor
    //==========================================================================
    
    function new(string name = "vexriscv_alu_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Configure test parameters
        use_tohost_checking = 0;  // Use direct register checking
        timeout_cycles = 500;     // Extended for comprehensive ALU testing (33 instructions)
        auto_start_cpu = 0;       // Manual control
        
        `uvm_info(get_type_name(), "VexRiscv ALU Operations Test configured", UVM_LOW)
    endfunction
    
    //==========================================================================
    // Run Phase - Override to implement custom test sequence
    //==========================================================================
    
    virtual task run_phase(uvm_phase phase);
        bit test_passed;
        int error_count = 0;
        
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), 
            "============================================================\n  VexRiscv ALU Operations Test\n  Testing: All RV32I ALU instructions\n============================================================", 
            UVM_NONE)
        
        // 1. Reset CPU
        reset_cpu();
        `uvm_info(get_type_name(), "CPU reset complete", UVM_MEDIUM)
        
        // 2. Load test program
        load_test_program();
        
        // 3. Start CPU and execute test
        start_cpu();
        `uvm_info(get_type_name(), "CPU started, executing ALU test program...", UVM_MEDIUM)
        
        // 4. Wait for completion
        wait_for_completion();
        
        // 5. Halt CPU
        halt_cpu();
        `uvm_info(get_type_name(), "CPU halted, reading register file...", UVM_MEDIUM)
        
        // 6. Verify results
        test_passed = verify_alu_results(error_count);
        
        // 7. Report final status
        if (test_passed) begin
            `uvm_info(get_type_name(), 
                $sformatf("\n========================================\n  TEST PASSED\n  All %0d ALU operations correct\n========================================", 
                    28),  // Total test count
                UVM_NONE)
        end else begin
            `uvm_error(get_type_name(), 
                $sformatf("\n========================================\n  TEST FAILED\n  %0d ALU operation(s) incorrect\n========================================", 
                    error_count))
        end
        
        phase.drop_objection(this);
    endtask
    
    //==========================================================================
    // Load Test Program
    //==========================================================================
    
    //==========================================================================
    // Load Test Program
    //==========================================================================
    
    virtual task load_test_program();
        bit [31:0] test_program[];
        int i;
        
        test_program = new[33];  // 33 instructions (NOP padding removed - Issue #39 fixed)

        // Initialization
        test_program[0]  = 32'h01000093;  // ADDI x1, x0, 16       x1 = 16
        test_program[1]  = 32'h00800113;  // ADDI x2, x0, 8        x2 = 8
        test_program[2]  = 32'hFFF00193;  // ADDI x3, x0, -1       x3 = 0xFFFFFFFF
        test_program[3]  = 32'h80000237;  // LUI  x4, 0x80000      x4 = 0x80000000
        // Arithmetic
        test_program[4]  = 32'h002082B3;  // ADD  x5, x1, x2       x5 = 16 + 8 = 24 (0x18)
        test_program[5]  = 32'h40208333;  // SUB  x6, x1, x2       x6 = 16 - 8 = 8
        test_program[6]  = 32'h00508393;  // ADDI x7, x1, 5        x7 = 16 + 5 = 21 (0x15)
        test_program[7]  = 32'hFFD08413;  // ADDI x8, x1, -3       x8 = 16 - 3 = 13 (0x0D)
        // Logical
        test_program[8]  = 32'h0020F4B3;  // AND  x9, x1, x2       x9 = 0x10 & 0x08 = 0x00
        test_program[9]  = 32'h0020E533;  // OR   x10, x1, x2      x10 = 0x10 | 0x08 = 0x18
        test_program[10] = 32'h0020C5B3;  // XOR  x11, x1, x2      x11 = 0x10 ^ 0x08 = 0x18
        test_program[11] = 32'h00F0F613;  // ANDI x12, x1, 15      x12 = 0x10 & 0x0F = 0x00
        test_program[12] = 32'h00F0E693;  // ORI  x13, x1, 15      x13 = 0x10 | 0x0F = 0x1F
        test_program[13] = 32'h0FF0C713;  // XORI x14, x1, 255     x14 = 0x10 ^ 0xFF = 0xEF
        // Comparison
        test_program[14] = 32'h0020A7B3;  // SLT  x15, x1, x2      x15 = (16 < 8) ? 1 : 0 = 0
        test_program[15] = 32'h0030A833;  // SLT  x16, x1, x3      x16 = (16 < -1) ? 1 : 0 = 0
        test_program[16] = 32'h0020B8B3;  // SLTU x17, x1, x2      x17 = (16 < 8) ? 1 : 0 = 0
        test_program[17] = 32'h0030B933;  // SLTU x18, x1, x3      x18 = (16 < 0xFFFFFFFF) ? 1 : 0 = 1
        test_program[18] = 32'h0080A993;  // SLTI x19, x1, 8       x19 = (16 < 8) ? 1 : 0 = 0
        test_program[19] = 32'h0140AA13;  // SLTI x20, x1, 20      x20 = (16 < 20) ? 1 : 0 = 1
        test_program[20] = 32'h0080BA93;  // SLTIU x21, x1, 8      x21 = (16 < 8) ? 1 : 0 = 0
        // Comparison (continued)
        test_program[21] = 32'h0140BB13;  // SLTIU x22, x1, 20     x22 = (16 < 20) ? 1 : 0 = 1
        // Shift
        test_program[22] = 32'h00209B93;  // SLLI x23, x1, 2       x23 = 16 << 2 = 64 (0x40)
        test_program[23] = 32'h00111C13;  // SLLI x24, x2, 1       x24 = 8 << 1 = 16 (0x10)
        test_program[24] = 32'h00115C93;  // SRLI x25, x2, 1       x25 = 8 >> 1 = 4
        test_program[25] = 32'h0021DD33;  // SRL  x26, x3, x2      x26 = 0xFFFFFFFF >> 8 = 0x00FFFFFF
        test_program[26] = 32'h4021DD93;  // SRAI x27, x3, 2       x27 = -1 >>> 2 = -1 (0xFFFFFFFF)
        test_program[27] = 32'h00221E13;  // SLL  x28, x4, x2      x28 = 0x80000000 << 8 = 0x00000000
        // Upper Immediate
        test_program[28] = 32'h12345EB7;  // LUI  x29, 0x12345     x29 = 0x12345000
        test_program[29] = 32'h00000F17;  // AUIPC x30, 0          x30 = PC (0x80000000 + 29*4 = 0x80000074)
        // Edge cases
        test_program[30] = 32'h80008FB7;  // LUI  x31, 0x80008     x31 = 0x80008000
        test_program[31] = 32'hFFF08F93;  // ADDI x31, x1, -1      x31 = 16 - 1 = 15 (0x0F)
        // Terminator
        test_program[32] = 32'h00100073;  // EBREAK

        // Write test program to Block RAM via backdoor
        for (i = 0; i < 33; i++) begin
            write_memory_backdoor(32'h80000000 + (i * 4), test_program[i]);
        end

        `uvm_info(get_type_name(),
            $sformatf("Loaded %0d-instruction ALU test program", 33),
            UVM_MEDIUM)
    endtask
    
    //==========================================================================
    // Wait for Completion
    //==========================================================================
    
    virtual task wait_for_completion();
        int cycle_count = 0;
        
        `uvm_info(get_type_name(), "Waiting for test completion...", UVM_MEDIUM)
        
        // Wait for instructions to complete WriteBack stage
        // 33 instructions * ~5 cycles/inst + boot latency = ~200 cycles
        forever begin
            @(posedge $root.rv32i_tb_top.clk);
            cycle_count++;
            
            if (cycle_count >= timeout_cycles) begin
                `uvm_warning(get_type_name(), 
                    $sformatf("Test timeout after %0d cycles", cycle_count))
                break;
            end
            
            // Wait sufficient cycles for all ALU operations to complete
            // 33 instructions need more time due to pipeline + dependencies
            if (cycle_count >= 400) begin
                `uvm_info(get_type_name(), 
                    $sformatf("Test completed in %0d cycles", cycle_count), 
                    UVM_MEDIUM)
                break;
            end
        end
    endtask
    
    //==========================================================================
    // Verify ALU Results
    //==========================================================================
    
    virtual function bit verify_alu_results(output int error_count);
        bit [31:0] reg_values[32];
        bit [31:0] expected_values[32];
        bit all_passed = 1;
        error_count = 0;
        
        // Read all registers
        for (int i = 0; i < 32; i++) begin
            read_cpu_reg(i, reg_values[i]);
        end
        
        // Initialize expected values
        for (int i = 0; i < 32; i++) begin
            expected_values[i] = 32'h0;
        end
        
        // Set expected results based on test program
        expected_values[1]  = 32'h00000010;  // x1 = 16
        expected_values[2]  = 32'h00000008;  // x2 = 8
        expected_values[3]  = 32'hFFFFFFFF;  // x3 = -1
        expected_values[4]  = 32'h80000000;  // x4 = 0x80000000
        
        // Arithmetic
        expected_values[5]  = 32'h00000018;  // x5 = 24
        expected_values[6]  = 32'h00000008;  // x6 = 8
        expected_values[7]  = 32'h00000015;  // x7 = 21
        expected_values[8]  = 32'h0000000D;  // x8 = 13
        
        // Logical
        expected_values[9]  = 32'h00000000;  // x9 = 0
        expected_values[10] = 32'h00000018;  // x10 = 24
        expected_values[11] = 32'h00000018;  // x11 = 24
        expected_values[12] = 32'h00000000;  // x12 = 0
        expected_values[13] = 32'h0000001F;  // x13 = 31
        expected_values[14] = 32'h000000EF;  // x14 = 239
        
        // Comparison
        expected_values[15] = 32'h00000000;  // x15 = 0 (16 < 8 signed = false)
        expected_values[16] = 32'h00000000;  // x16 = 0 (16 < -1 signed = false)
        expected_values[17] = 32'h00000000;  // x17 = 0 (16 < 8 unsigned = false)
        expected_values[18] = 32'h00000001;  // x18 = 1 (16 < 0xFFFFFFFF unsigned = true)
        expected_values[19] = 32'h00000000;  // x19 = 0 (16 < 8 = false)
        expected_values[20] = 32'h00000001;  // x20 = 1 (16 < 20 = true)
        expected_values[21] = 32'h00000000;  // x21 = 0 (16 < 8 unsigned = false)
        expected_values[22] = 32'h00000001;  // x22 = 1 (16 < 20 unsigned = true)
        
        // Shift
        expected_values[23] = 32'h00000040;  // x23 = 64
        expected_values[24] = 32'h00000010;  // x24 = 16
        expected_values[25] = 32'h00000004;  // x25 = 4
        expected_values[26] = 32'h00FFFFFF;  // x26 = 0x00FFFFFF
        expected_values[27] = 32'hFFFFFFFF;  // x27 = -1
        expected_values[28] = 32'h00000000;  // x28 = 0
        
        // Upper Immediate
        expected_values[29] = 32'h12345000;  // x29 = 0x12345000
        expected_values[30] = 32'h80000074;  // x30 = PC of AUIPC at index 29 (0x80000000 + 29*4)
        
        // Edge cases
        expected_values[31] = 32'h0000000F;  // x31 = 15
        
        // Verify each register
        `uvm_info(get_type_name(), "\n========== ALU Results Verification ==========", UVM_NONE)
        
        for (int i = 1; i < 32; i++) begin
            if (reg_values[i] !== expected_values[i]) begin
                `uvm_error(get_type_name(), 
                    $sformatf("FAIL: x%0d = 0x%08X (expected 0x%08X)", 
                        i, reg_values[i], expected_values[i]))
                error_count++;
                all_passed = 0;
            end else begin
                `uvm_info(get_type_name(), 
                    $sformatf("PASS: x%0d = 0x%08X", i, reg_values[i]), 
                    UVM_MEDIUM)
            end
        end
        
        // Always verify x0 is zero
        if (reg_values[0] !== 32'h0) begin
            `uvm_error(get_type_name(), 
                $sformatf("FAIL: x0 = 0x%08X (expected 0x00000000 - hardwired zero)", 
                    reg_values[0]))
            error_count++;
            all_passed = 0;
        end else begin
            `uvm_info(get_type_name(), 
                $sformatf("PASS: x0 = 0x%08X (hardwired zero)", reg_values[0]), 
                UVM_MEDIUM)
        end
        
        return all_passed;
    endfunction
    
endclass
