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
`include "rv32i_debug_load_test.sv"
`include "rv32i_ebreak_simple_test.sv"
`include "rv32i_breakpoint_test.sv"
`include "rv32i_perfcount_test.sv"

`endif // RV32I_TEST_PKG_SV
