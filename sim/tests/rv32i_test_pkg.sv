//------------------------------------------------------------------------------
// RV32I Test Package
//------------------------------------------------------------------------------
// Centralized include file for all RV32I test classes
// Usage: Include this file in testbench top to enable all tests
// Following AXIUART pattern (include guards, not SystemVerilog package)
//
// Author: GitHub Copilot
// Date: 2026-01-02
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

`ifndef RV32I_TEST_PKG_SV
`define RV32I_TEST_PKG_SV

// UVM Components (not needed for VexRiscv tests - use vexriscv_base_test instead)
// `include "rv32i_transaction.sv"  // Old UVM components - not used
// `include "rv32i_monitor.sv"  // Old UVM components - not used
// `include "rv32i_scoreboard.sv"  // Old UVM components - not used
// `include "rv32i_env.sv"  // Old UVM components - not used

// Test classes (base first, then derived)
// Note: Only include tests that exist (Issue #52 implementation)
// `include "rv32i_base_test.sv"  // Old base test - replaced by vexriscv_base_test
// `include "rv32i_basic_test.sv"  // File not present
// `include "rv32i_basic_imm_test.sv"  // File not present
// `include "rv32i_upper_imm_test.sv"  // File not present
// `include "rv32i_imm_logic_test.sv"  // File not present
// `include "rv32i_shift_imm_test.sv"  // File not present
// `include "rv32i_reg_alu_test.sv"  // File not present
// `include "rv32i_reg_shift_test.sv"  // File not present
// `include "rv32i_debug_load_test.sv"  // File not present

// Exception and CSR tests (Issue #52 - verified to exist)
`include "rv32i_perfcount_test.sv"
`include "rv32i_ebreak_simple_test.sv"
`include "rv32i_exception_handler_test.sv"

// Other tests (commented out - files not present)
// `include "rv32i_breakpoint_test.sv"
// `include "rv32i_wb_forward_timing_test.sv"
// `include "rv32i_led_mmio_simple_test.sv"
// `include "rv32i_led_complex_pattern_test.sv"
// `include "rv32i_led_fast_pattern_test.sv"
// `include "rv32i_minimal_led_test.sv"
// `include "rv32i_comprehensive_test.sv"
// `include "rv32i_store_simple_test.sv"
// `include "rv32i_load_simple_test.sv"

`endif // RV32I_TEST_PKG_SV
