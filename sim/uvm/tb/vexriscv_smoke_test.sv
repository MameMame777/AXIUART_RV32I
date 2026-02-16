`timescale 1ns / 1ps

//==============================================================================
// VexRiscv Smoke Test (legacy/full-suite compatibility)
//==============================================================================

class vexriscv_smoke_test extends vexriscv_base_test;

	`uvm_component_utils(vexriscv_smoke_test)

	function new(string name = "vexriscv_smoke_test", uvm_component parent = null);
		super.new(name, parent);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		auto_start_cpu = 0;
		use_tohost_checking = 0;
		timeout_cycles = 120;
	endfunction

	virtual task run_phase(uvm_phase phase);
		bit [31:0] x1_val;

		phase.raise_objection(this);

		`uvm_info(get_type_name(), "Legacy smoke compatibility test start", UVM_NONE)

		reset_cpu();

		// Program: addi x1, x0, 1 ; ebreak
		write_memory_backdoor(32'h8000_0000, 32'h0010_0093);
		write_memory_backdoor(32'h8000_0004, 32'h0010_0073);

		start_cpu();
		repeat (20) @(posedge $root.rv32i_tb_top.clk);

		halt_cpu();
		read_cpu_reg(1, x1_val);

		if (x1_val !== 32'h0000_0001) begin
			`uvm_error(get_type_name(), $sformatf("FAIL: x1=0x%08X expected 0x00000001", x1_val))
		end else begin
			`uvm_info(get_type_name(), "PASS: legacy smoke compatibility", UVM_NONE)
		end

		phase.drop_objection(this);
	endtask

endclass : vexriscv_smoke_test
