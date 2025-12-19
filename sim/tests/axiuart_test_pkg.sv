//------------------------------------------------------------------------------
// AXIUART Test Package
// Purpose: Centralized include file for all test classes
// Usage: Include this file in testbench top to enable all tests
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

`ifndef AXIUART_TEST_PKG_SV
`define AXIUART_TEST_PKG_SV

// Base test must be included first (dependency for all derived tests)
`include "axiuart_base_test.sv"

// All concrete test implementations
`include "axiuart_basic_test.sv"
`include "axiuart_reset_test.sv"
`include "axiuart_reg_rw_test.sv"

`endif // AXIUART_TEST_PKG_SV
