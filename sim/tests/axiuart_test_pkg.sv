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

// CPU test base class (template for CPU tests)
`include "axiuart_cpu_test_base.sv"

// All concrete test implementations
`include "axiuart_basic_test.sv"
`include "axiuart_reset_test.sv"
`include "axiuart_reg_rw_test.sv"
`include "axiuart_cpu_debug_test.sv"
`include "axiuart_cpu_memory_test.sv"
`include "axiuart_cpu_simple_mem_test.sv"
`include "axiuart_cpu_mem_simple_rw_test.sv"
`include "axiuart_cpu_logic_test.sv"  // Unified CPU ALU and logic verification
`include "axiuart_trace_buffer_read_test.sv"  // Trace buffer register read test
`include "axiuart_cpu_mmio_led_test.sv"  // CPU MMIO LED control via LD/ST instructions
`include "axiuart_cpu_basic_inst_test.sv"  // Basic CPU instruction test (LDI/ADDI/ST/LD)

`endif // AXIUART_TEST_PKG_SV
