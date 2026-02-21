`timescale 1ns / 1ps

//==============================================================================
// VexRiscv Computation Programs Test
//==============================================================================
// Purpose:
//   Reproduce and verify the real hardware computation programs used by
//   software/exec/computation_test.py at simulation level.
//
// Programs:
//   1) sum100     : a0 = 5050
//   2) fibonacci  : a0 = 55
//   3) bitcount   : a0 = 16
//
// Pass criteria per program:
//   - rv32i_cpu_break is asserted within timeout
//   - break_pc points to the final EBREAK instruction
//   - instruction at break_pc is 0x00100073
//   - a0 (x10) equals expected value
//==============================================================================

class vexriscv_compute_programs_test extends vexriscv_base_test;

    `uvm_component_utils(vexriscv_compute_programs_test)

    localparam bit [31:0] PROG_BASE     = 32'h8000_0000;
    localparam bit [31:0] EBREAK_OPCODE = 32'h0010_0073;

    function new(string name = "vexriscv_compute_programs_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        use_tohost_checking = 0;
        auto_start_cpu      = 0;
        timeout_cycles      = 120000;
    endfunction

    virtual task run_phase(uvm_phase phase);
        bit test_passed;
        bit case_passed;

        phase.raise_objection(this);

        `uvm_info(get_type_name(),
            "============================================================\n  VexRiscv Computation Programs Test\n  Source parity: software/exec/computation_test.py\n============================================================",
            UVM_NONE)

        reset_cpu();

        test_passed = 1'b1;
        run_sum100(case_passed);
        test_passed &= case_passed;
        run_fibonacci(case_passed);
        test_passed &= case_passed;
        run_bitcount(case_passed);
        test_passed &= case_passed;

        if (test_passed) begin
            `uvm_info(get_type_name(),
                "============================================================\n  TEST PASSED\n  All computation programs matched expected a0 and EBREAK PC\n============================================================",
                UVM_NONE)
        end else begin
            `uvm_error(get_type_name(),
                "============================================================\n  TEST FAILED\n  One or more computation programs mismatched\n============================================================")
        end

        phase.drop_objection(this);
    endtask

    virtual task load_sum100();
        write_memory_backdoor(PROG_BASE + 32'd0,  32'h00000513);
        write_memory_backdoor(PROG_BASE + 32'd4,  32'h00100593);
        write_memory_backdoor(PROG_BASE + 32'd8,  32'h06500613);
        write_memory_backdoor(PROG_BASE + 32'd12, 32'h00B50533);
        write_memory_backdoor(PROG_BASE + 32'd16, 32'h00158593);
        write_memory_backdoor(PROG_BASE + 32'd20, 32'hFEC59CE3);
        write_memory_backdoor(PROG_BASE + 32'd24, 32'h00100073);
    endtask

    virtual task load_fibonacci();
        write_memory_backdoor(PROG_BASE + 32'd0,  32'h00000513);
        write_memory_backdoor(PROG_BASE + 32'd4,  32'h00100593);
        write_memory_backdoor(PROG_BASE + 32'd8,  32'h00A00613);
        write_memory_backdoor(PROG_BASE + 32'd12, 32'h00B506B3);
        write_memory_backdoor(PROG_BASE + 32'd16, 32'h00058513);
        write_memory_backdoor(PROG_BASE + 32'd20, 32'h00068593);
        write_memory_backdoor(PROG_BASE + 32'd24, 32'hFFF60613);
        write_memory_backdoor(PROG_BASE + 32'd28, 32'hFE0618E3);
        write_memory_backdoor(PROG_BASE + 32'd32, 32'h00100073);
    endtask

    virtual task load_bitcount();
        write_memory_backdoor(PROG_BASE + 32'd0,  32'hA5A5A5B7);
        write_memory_backdoor(PROG_BASE + 32'd4,  32'h5A558593);
        write_memory_backdoor(PROG_BASE + 32'd8,  32'h00000513);
        write_memory_backdoor(PROG_BASE + 32'd12, 32'h02000613);
        write_memory_backdoor(PROG_BASE + 32'd16, 32'h00100693);
        write_memory_backdoor(PROG_BASE + 32'd20, 32'h00D5F733);
        write_memory_backdoor(PROG_BASE + 32'd24, 32'h00E50533);
        write_memory_backdoor(PROG_BASE + 32'd28, 32'h0015D593);
        write_memory_backdoor(PROG_BASE + 32'd32, 32'hFFF60613);
        write_memory_backdoor(PROG_BASE + 32'd36, 32'hFE0618E3);
        write_memory_backdoor(PROG_BASE + 32'd40, 32'h00100073);
    endtask

    virtual task execute_and_check(string name,
                                   int unsigned prog_size,
                                   bit [31:0] expected_a0,
                                   output bit ok);
        bit [31:0] a0_val;
        bit [31:0] a1_val;
        bit [31:0] a2_val;
        bit [31:0] a0_pre_halt;
        bit [31:0] break_pc;
        bit [31:0] break_inst;
        bit [31:0] expected_break_pc;
        int cycles;
        int branch_total;
        int branch_taken;
        bit [31:0] branch_src1_last;
        bit [31:0] branch_src2_last;
        bit        branch_do_last;
        int env_ebreak_seen;
        int decode_branch_seen;

        ok = 1'b1;

        `uvm_info(get_type_name(),
            $sformatf("------------------------------------------------------------\n[CASE] %s\n  expected a0 = %0d (0x%08X)\n  program size = %0d instructions",
                      name, expected_a0, expected_a0, prog_size),
            UVM_LOW)

        expected_break_pc = PROG_BASE + ((prog_size - 1) * 4);
        branch_total = 0;
        branch_taken = 0;
        branch_src1_last = 32'h0;
        branch_src2_last = 32'h0;
        branch_do_last = 1'b0;
        env_ebreak_seen = 0;
        decode_branch_seen = 0;

        start_cpu();

        cycles = 0;
        while (!$root.rv32i_tb_top.dut.vexriscv_inst.rv32i_cpu_break && (cycles < timeout_cycles)) begin
            @(posedge $root.rv32i_tb_top.clk);
            cycles++;

            if ($root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.execute_arbitration_isFiring &&
                ($root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.execute_BRANCH_CTRL == 2'd1)) begin
                branch_total++;
                branch_do_last = $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.execute_BRANCH_DO;
                branch_src1_last = $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.execute_BranchPlugin_branch_src1;
                branch_src2_last = $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.execute_BranchPlugin_branch_src2;
                if (branch_do_last) branch_taken++;

                if (branch_total <= 6) begin
                    `uvm_info(get_type_name(),
                        $sformatf("[%s] BRANCH[%0d]: pc=0x%08X taken=%0d cmp_src1=0x%08X cmp_src2=0x%08X eq=%0d target=0x%08X calc_src1=0x%08X calc_src2=0x%08X",
                                  name,
                                  branch_total,
                                  $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.execute_PC,
                                  branch_do_last,
                                  $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.execute_SRC1,
                                  $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.execute_SRC2,
                                  $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.execute_BranchPlugin_eq,
                                  $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.execute_BRANCH_CALC,
                                  branch_src1_last,
                                  branch_src2_last),
                        UVM_LOW)
                end
            end

            if ($root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.decode_arbitration_isValid &&
                ($root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.decode_INSTRUCTION[6:0] == 7'h63)) begin
                decode_branch_seen++;
                if (decode_branch_seen <= 6) begin
                    `uvm_info(get_type_name(),
                        $sformatf("[%s] DECODE_BRANCH[%0d]: pc=0x%08X inst=0x%08X rs1_use=%0d rs2_use=%0d src0Haz=%0d src1Haz=%0d",
                                  name,
                                  decode_branch_seen,
                                  $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.decode_PC,
                                  $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.decode_INSTRUCTION,
                                  $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.decode_RS1_USE,
                                  $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.decode_RS2_USE,
                                  $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.HazardSimplePlugin_src0Hazard,
                                  $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.HazardSimplePlugin_src1Hazard),
                        UVM_LOW)
                end
            end

            if ($root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.execute_arbitration_isValid &&
                ($root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.execute_ENV_CTRL == 2'd3)) begin
                env_ebreak_seen++;
                if (env_ebreak_seen <= 2) begin
                    `uvm_info(get_type_name(),
                        $sformatf("[%s] EXEC_ENV_EBREAK[%0d]: pc=0x%08X instr=0x%08X",
                                  name,
                                  env_ebreak_seen,
                                  $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.execute_PC,
                                  $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.execute_INSTRUCTION),
                        UVM_LOW)
                end
            end
        end

        if (!$root.rv32i_tb_top.dut.vexriscv_inst.rv32i_cpu_break) begin
            `uvm_error(get_type_name(),
                $sformatf("[%s] Timeout waiting for rv32i_cpu_break after %0d cycles", name, timeout_cycles))
            ok = 1'b0;
            return;
        end

        // Sample x10 immediately at break detect to check overwrite timing.
        read_cpu_reg(10, a0_pre_halt);

        halt_cpu();

        read_cpu_reg(10, a0_val);
        read_cpu_reg(11, a1_val);
        read_cpu_reg(12, a2_val);
        break_pc = $root.rv32i_tb_top.dut.vexriscv_inst.break_pc;

        if (!read_memory_backdoor(break_pc - 32'h8000_0000, break_inst)) begin
            `uvm_error(get_type_name(),
                $sformatf("[%s] Failed to read instruction at break_pc=0x%08X", name, break_pc))
            ok = 1'b0;
        end

        if (a0_val !== expected_a0) begin
            `uvm_error(get_type_name(),
                $sformatf("[%s] a0 mismatch: pre_halt=0x%08X post_halt=0x%08X expected=0x%08X x11=0x%08X x12=0x%08X cycles=%0d branch_total=%0d branch_taken=%0d env_ebreak_seen=%0d last_branch_do=%0d last_src1=0x%08X last_src2=0x%08X",
                          name, a0_pre_halt, a0_val, expected_a0, a1_val, a2_val, cycles,
                          branch_total, branch_taken, env_ebreak_seen, branch_do_last, branch_src1_last, branch_src2_last))
            ok = 1'b0;
        end

        if (break_pc !== expected_break_pc) begin
            `uvm_error(get_type_name(),
                $sformatf("[%s] break_pc mismatch: actual=0x%08X expected=0x%08X", name, break_pc, expected_break_pc))
            ok = 1'b0;
        end

        if (break_inst !== EBREAK_OPCODE) begin
            `uvm_error(get_type_name(),
                $sformatf("[%s] break instruction mismatch at 0x%08X: actual=0x%08X expected=0x%08X",
                          name, break_pc, break_inst, EBREAK_OPCODE))
            ok = 1'b0;
        end

        if (ok) begin
            `uvm_info(get_type_name(),
                $sformatf("[%s] PASS: a0=0x%08X break_pc=0x%08X cycles=%0d", name, a0_val, break_pc, cycles),
                UVM_LOW)
        end else begin
            `uvm_info(get_type_name(),
                $sformatf("[%s] DEBUG: break_pc=0x%08X break_inst=0x%08X pre_halt_a0=0x%08X post_halt_a0=0x%08X x11=0x%08X x12=0x%08X cycles=%0d branch_total=%0d branch_taken=%0d env_ebreak_seen=%0d",
                          name, break_pc, break_inst, a0_pre_halt, a0_val, a1_val, a2_val, cycles,
                      branch_total, branch_taken, env_ebreak_seen),
                UVM_LOW)
        end
    endtask

    virtual task run_sum100(output bit ok);
        halt_cpu();
        load_sum100();
        execute_and_check("sum100", 7, 32'd5050, ok);
    endtask

    virtual task run_fibonacci(output bit ok);
        halt_cpu();
        load_fibonacci();
        execute_and_check("fibonacci", 9, 32'd55, ok);
    endtask

    virtual task run_bitcount(output bit ok);
        halt_cpu();
        load_bitcount();
        execute_and_check("bitcount", 11, 32'd16, ok);
    endtask

endclass : vexriscv_compute_programs_test
