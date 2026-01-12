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

// UVM Components (must be included in dependency order)
`include "rv32i_transaction.sv"
`include "rv32i_monitor.sv"
`include "rv32i_scoreboard.sv"
`include "rv32i_env.sv"

// Test classes (base first, then derived)
`include "rv32i_base_test.sv"
`include "rv32i_basic_test.sv"
// `include "rv32i_hazard_test.sv"          // File not present
// `include "rv32i_load_store_test.sv"      // File not present
// `include "rv32i_branch_test.sv"          // File not present
// `include "rv32i_jump_test.sv"            // File not present
`include "rv32i_debug_load_test.sv"
`include "rv32i_ebreak_simple_test.sv"
`include "rv32i_breakpoint_test.sv"
`include "rv32i_perfcount_test.sv"

// Exception handling tests
`include "rv32i_exception_handler_test.sv"

// Pipeline timing and forwarding tests (2026-01-05)
`include "rv32i_wb_forward_timing_test.sv"

// LED MMIO tests (2026-01-05)
`include "rv32i_led_mmio_simple_test.sv"
`include "rv32i_led_complex_pattern_test.sv"
`include "rv32i_led_fast_pattern_test.sv"
`include "rv32i_minimal_led_test.sv"

// Branch debug tests (2026-01-05)
// `include "rv32i_bne_loop_test.sv"        // File not present

// Comprehensive test - All 40 RV32I instructions (2026-01-06)
`include "rv32i_comprehensive_test.sv"

// Simple isolated instruction tests (2026-01-12)
`include "rv32i_store_simple_test.sv"
`include "rv32i_load_simple_test.sv"

`endif // RV32I_TEST_PKG_SV
