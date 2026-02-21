//------------------------------------------------------------------------------
// VexRiscv Test Package
//------------------------------------------------------------------------------
// Centralized include file for all VexRiscv UVM test classes.
// Include order: base class first, then derived tests.
//
// Search path setup (from dsim_config_rv32i.f):
//   +incdir+../sv      → sim/uvm/sv/   (vexriscv_base_test.sv)
//   +incdir+../../tests → sim/tests/   (stage 1+ tests)
//   Same dir            → sim/uvm/tb/  (vexriscv_smoke_test.sv)
//
// Author: GitHub Copilot
// Date: 2026-02-01
//------------------------------------------------------------------------------

`ifndef VEXRISCV_TEST_PKG_SV
`define VEXRISCV_TEST_PKG_SV

//----------------------------------------------------------------------
// Base class (must come before all derived tests)
//----------------------------------------------------------------------
`include "vexriscv_base_test.sv"

//----------------------------------------------------------------------
// Smoke test (sim/uvm/tb/)
//----------------------------------------------------------------------
`include "vexriscv_smoke_test.sv"

//----------------------------------------------------------------------
// Stage 1: Pipeline fundamentals (sim/tests/)
//----------------------------------------------------------------------
`include "vexriscv_regfile_test.sv"
`include "vexriscv_pipeline_flow_test.sv"
`include "vexriscv_memory_access_test.sv"
`include "vexriscv_ex_bypass_test.sv"
`include "vexriscv_mem_bypass_test.sv"
`include "vexriscv_wb_bypass_test.sv"
`include "vexriscv_load_use_stall_test.sv"
`include "vexriscv_ibus_fetch_test.sv"
`include "vexriscv_dbus_access_test.sv"

//----------------------------------------------------------------------
// Additional VexRiscv tests (sim/tests/)
//----------------------------------------------------------------------
`include "vexriscv_alu_test.sv"
`include "vexriscv_control_test.sv"
`include "vexriscv_debug_bridge_test.sv"
`include "vexriscv_led_uart_test.sv"

//----------------------------------------------------------------------
// ISA compliance tests (sim/tests/)
//----------------------------------------------------------------------
`include "vexriscv_isa_test.sv"
`include "vexriscv_isa_addi_test.sv"
`include "vexriscv_isa_add_test.sv"
`include "vexriscv_isa_andi_test.sv"
`include "vexriscv_isa_and_test.sv"
`include "vexriscv_isa_auipc_test.sv"
`include "vexriscv_isa_beq_test.sv"
`include "vexriscv_isa_bgeu_test.sv"
`include "vexriscv_isa_bge_test.sv"
`include "vexriscv_isa_bltu_test.sv"
`include "vexriscv_isa_blt_test.sv"
`include "vexriscv_isa_bne_test.sv"
`include "vexriscv_isa_jalr_test.sv"
`include "vexriscv_isa_jal_test.sv"
`include "vexriscv_isa_lbu_test.sv"
`include "vexriscv_isa_lb_test.sv"
`include "vexriscv_isa_lhu_test.sv"
`include "vexriscv_isa_lh_test.sv"
`include "vexriscv_isa_lui_test.sv"
`include "vexriscv_isa_lw_test.sv"
`include "vexriscv_isa_ori_test.sv"
`include "vexriscv_isa_or_test.sv"
`include "vexriscv_isa_sb_test.sv"
`include "vexriscv_isa_sh_test.sv"
`include "vexriscv_isa_slli_test.sv"
`include "vexriscv_isa_sll_test.sv"
`include "vexriscv_isa_sltiu_test.sv"
`include "vexriscv_isa_slti_test.sv"
`include "vexriscv_isa_sltu_test.sv"
`include "vexriscv_isa_slt_test.sv"
`include "vexriscv_isa_srai_test.sv"
`include "vexriscv_isa_sra_test.sv"
`include "vexriscv_isa_srli_test.sv"
`include "vexriscv_isa_srl_test.sv"
`include "vexriscv_isa_sub_test.sv"
`include "vexriscv_isa_sw_test.sv"
`include "vexriscv_isa_xori_test.sv"
`include "vexriscv_isa_xor_test.sv"

`endif // VEXRISCV_TEST_PKG_SV
