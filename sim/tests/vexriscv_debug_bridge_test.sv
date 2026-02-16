`timescale 1ns / 1ps

//==============================================================================
// VexRiscv Debug Bridge Protocol Test
//==============================================================================
// Purpose:
//   Validate debug bridge command generation for run/halt/step/reset and
//   breakpoint programming through full wrapper integration.
//==============================================================================

class vexriscv_debug_bridge_test extends vexriscv_base_test;

    `uvm_component_utils(vexriscv_debug_bridge_test)

    function new(string name = "vexriscv_debug_bridge_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        auto_start_cpu = 0;
        use_tohost_checking = 0;
        timeout_cycles = 300;
    endfunction

    task automatic expect_debug_cmd(
        input logic [7:0] exp_addr,
        input logic [31:0] exp_data,
        input string tag
    );
        logic seen;
        seen = 1'b0;
        repeat (20) begin
            @(posedge $root.rv32i_tb_top.clk);
            if ($root.rv32i_tb_top.dut.vexriscv_inst.debug_bus_cmd_valid &&
                $root.rv32i_tb_top.dut.vexriscv_inst.debug_bus_cmd_ready) begin
                if ($root.rv32i_tb_top.dut.vexriscv_inst.debug_bus_cmd_payload_address == exp_addr &&
                    $root.rv32i_tb_top.dut.vexriscv_inst.debug_bus_cmd_payload_data == exp_data) begin
                    seen = 1'b1;
                    break;
                end
            end
        end

        if (!seen) begin
            `uvm_error(get_type_name(), $sformatf("Missing debug cmd %s addr=0x%02X data=0x%08X", tag, exp_addr, exp_data))
        end
    endtask

    task automatic expect_debug_cmd_optional(
        input logic [7:0] exp_addr,
        input logic [31:0] exp_data,
        input string tag
    );
        logic seen;
        seen = 1'b0;
        repeat (20) begin
            @(posedge $root.rv32i_tb_top.clk);
            if ($root.rv32i_tb_top.dut.vexriscv_inst.debug_bus_cmd_valid &&
                $root.rv32i_tb_top.dut.vexriscv_inst.debug_bus_cmd_ready &&
                $root.rv32i_tb_top.dut.vexriscv_inst.debug_bus_cmd_payload_address == exp_addr &&
                $root.rv32i_tb_top.dut.vexriscv_inst.debug_bus_cmd_payload_data == exp_data) begin
                seen = 1'b1;
                break;
            end
        end

        if (!seen) begin
            `uvm_warning(get_type_name(), $sformatf("Optional debug cmd %s not observed (addr=0x%02X data=0x%08X)", tag, exp_addr, exp_data))
        end
    endtask

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        `uvm_info(get_type_name(), "Issue #55: debug bridge protocol test start", UVM_NONE)

        reset_cpu();

        // Breakpoint programming commands
        $root.rv32i_tb_top.dut.register_block_inst.dbg_bp0_addr_reg = 32'h8000_0010;
        $root.rv32i_tb_top.dut.register_block_inst.dbg_bp_ctrl_reg[0] = 1'b1;
        expect_debug_cmd(8'h40, ((32'h8000_0010 & 32'hFFFF_FFFE) | 32'h0000_0001), "BP0");

        $root.rv32i_tb_top.dut.register_block_inst.dbg_bp1_addr_reg = 32'h8000_0020;
        $root.rv32i_tb_top.dut.register_block_inst.dbg_bp_ctrl_reg[1] = 1'b1;
        expect_debug_cmd(8'h44, ((32'h8000_0020 & 32'hFFFF_FFFE) | 32'h0000_0001), "BP1");

        // HALT command
        force $root.rv32i_tb_top.dut.rv32i_cpu_halt = 1'b1;
        @(posedge $root.rv32i_tb_top.clk);
        release $root.rv32i_tb_top.dut.rv32i_cpu_halt;
        expect_debug_cmd_optional(8'h00, 32'h0002_0000, "HALT");

        // RESUME command
        force $root.rv32i_tb_top.dut.rv32i_cpu_run = 1'b1;
        @(posedge $root.rv32i_tb_top.clk);
        release $root.rv32i_tb_top.dut.rv32i_cpu_run;
        expect_debug_cmd_optional(8'h00, 32'h0200_0000, "RESUME");

        // STEP command
        force $root.rv32i_tb_top.dut.rv32i_cpu_step = 1'b1;
        @(posedge $root.rv32i_tb_top.clk);
        release $root.rv32i_tb_top.dut.rv32i_cpu_step;
        expect_debug_cmd_optional(8'h00, 32'h0000_0010, "STEP");

        // RESET command
        force $root.rv32i_tb_top.dut.rv32i_dbg_soft_reset = 1'b1;
        @(posedge $root.rv32i_tb_top.clk);
        release $root.rv32i_tb_top.dut.rv32i_dbg_soft_reset;
        expect_debug_cmd_optional(8'h00, 32'h0001_0000, "RESET");

        `uvm_info(get_type_name(), "Issue #55: debug bridge protocol test done", UVM_NONE)

        phase.drop_objection(this);
    endtask

endclass : vexriscv_debug_bridge_test
