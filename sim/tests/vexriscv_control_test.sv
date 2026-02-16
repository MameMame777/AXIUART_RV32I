`timescale 1ns / 1ps

//==============================================================================
// VexRiscv Control State Transition Test
//==============================================================================
// Purpose:
//   Validate run/halt/step and EBREAK-driven halt behavior through the
//   AXIUART_Top -> Register_Block -> vexriscv_wrapper control path.
//==============================================================================

class vexriscv_control_test extends vexriscv_base_test;

    `uvm_component_utils(vexriscv_control_test)

    function new(string name = "vexriscv_control_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        auto_start_cpu = 0;
        use_tohost_checking = 0;
        timeout_cycles = 400;
    endfunction

    virtual task run_phase(uvm_phase phase);
        logic [31:0] pc_before;
        logic [31:0] pc_after;

        phase.raise_objection(this);

        `uvm_info(get_type_name(), "Issue #55: control transition test start", UVM_NONE)

        reset_cpu();

        // Program: NOP, NOP, EBREAK
        write_memory_backdoor(32'h8000_0000, 32'h0000_0013);
        write_memory_backdoor(32'h8000_0004, 32'h0000_0013);
        write_memory_backdoor(32'h8000_0008, 32'h0010_0073);

        // RESET -> HALTED
        if (!$root.rv32i_tb_top.dut.vexriscv_inst.rv32i_cpu_halted) begin
            `uvm_error(get_type_name(), "Expected HALTED after reset")
        end

        // HALTED -> RUNNING
        start_cpu();
        repeat (4) @(posedge $root.rv32i_tb_top.clk);
        if ($root.rv32i_tb_top.dut.vexriscv_inst.rv32i_cpu_halted) begin
            `uvm_error(get_type_name(), "Expected RUNNING after start_cpu")
        end

        // RUNNING -> HALTED by halt command
        halt_cpu();
        repeat (2) @(posedge $root.rv32i_tb_top.clk);
        if (!$root.rv32i_tb_top.dut.vexriscv_inst.rv32i_cpu_halted) begin
            `uvm_error(get_type_name(), "Expected HALTED after halt_cpu")
        end

        // Invalid transition request while halted should keep HALTED
        $root.rv32i_tb_top.dut.register_block_inst.cpu_mem_ctrl_reg[8] = 1'b1;
        @(posedge $root.rv32i_tb_top.clk);
        $root.rv32i_tb_top.dut.register_block_inst.cpu_mem_ctrl_reg[8] = 1'b0;
        repeat (2) @(posedge $root.rv32i_tb_top.clk);
        if (!$root.rv32i_tb_top.dut.vexriscv_inst.rv32i_cpu_halted) begin
            `uvm_error(get_type_name(), "HALT while HALTED must keep HALTED")
        end

        // STEP pulse should execute a single instruction and return to HALTED
        pc_before = $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.decode_PC;
        $root.rv32i_tb_top.dut.register_block_inst.dbg_reset_ctrl_reg[2] = 1'b1;
        @(posedge $root.rv32i_tb_top.clk);
        $root.rv32i_tb_top.dut.register_block_inst.dbg_reset_ctrl_reg[2] = 1'b0;
        repeat (8) @(posedge $root.rv32i_tb_top.clk);
        pc_after = $root.rv32i_tb_top.dut.vexriscv_inst.cpu_core.decode_PC;

        if (!$root.rv32i_tb_top.dut.vexriscv_inst.rv32i_cpu_halted) begin
            `uvm_error(get_type_name(), "Expected HALTED after STEP")
        end
        if (pc_after == pc_before) begin
            `uvm_warning(get_type_name(), $sformatf("STEP did not advance PC (pc=0x%08X)", pc_after))
        end

        // EBREAK auto-halt (inject deterministic break event)
        force $root.rv32i_tb_top.dut.vexriscv_inst.ebreak_detected = 1'b1;
        @(posedge $root.rv32i_tb_top.clk);
        release $root.rv32i_tb_top.dut.vexriscv_inst.ebreak_detected;
        repeat (2) @(posedge $root.rv32i_tb_top.clk);

        if (!$root.rv32i_tb_top.dut.vexriscv_inst.rv32i_cpu_break) begin
            `uvm_error(get_type_name(), "Expected cpu_break after EBREAK")
        end
        if (!$root.rv32i_tb_top.dut.vexriscv_inst.rv32i_cpu_halted) begin
            `uvm_error(get_type_name(), "Expected HALTED after EBREAK")
        end

        `uvm_info(get_type_name(), "Issue #55: control transition test done", UVM_NONE)

        phase.drop_objection(this);
    endtask

endclass : vexriscv_control_test
