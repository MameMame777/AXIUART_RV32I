`timescale 1ns / 1ps

// AXIUART Register Package
//
// AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
// Generated from: register_map/axiuart_registers.json
// Generation time: 2025-12-21T05:19:06.158716
//
// To regenerate:
//     python software/axiuart_driver/tools/gen_registers.py --in register_map/axiuart_registers.json

package axiuart_reg_pkg;

    // Register block: AXIUART_Register_Block
    parameter int BASE_ADDR = 32'h00001000;

    // Register offsets (absolute addresses)
    parameter int REG_CONTROL      = 32'h00001000;  // RW - Control register - includes bridge reset control
    parameter int REG_STATUS       = 32'h00001004;  // RO - Status register - bridge busy and error code
    parameter int REG_CONFIG       = 32'h00001008;  // RW - Configuration register - baud rate and timeout
    parameter int REG_DEBUG        = 32'h0000100C;  // RW - Debug control register - debug mode selection
    parameter int REG_TX_COUNT     = 32'h00001010;  // RO - TX transaction counter (read-only)
    parameter int REG_RX_COUNT     = 32'h00001014;  // RO - RX transaction counter (read-only)
    parameter int REG_FIFO_STAT    = 32'h00001018;  // RO - FIFO status flags (read-only)
    parameter int REG_VERSION      = 32'h0000101C;  // RO - Hardware version register (read-only)
    parameter int REG_TEST_0       = 32'h00001020;  // RW - Test register 0 - pure read/write test
    parameter int REG_TEST_1       = 32'h00001024;  // RW - Test register 1 - pattern test
    parameter int REG_TEST_2       = 32'h00001028;  // RW - Test register 2 - increment test
    parameter int REG_TEST_3       = 32'h0000102C;  // RW - Test register 3 - mirror test
    parameter int REG_TEST_4       = 32'h00001040;  // RW - Test register 4 - gap test
    parameter int REG_TEST_LED     = 32'h00001044;  // RW - 4-bit LED control register
    parameter int REG_TEST_5       = 32'h00001050;  // RW - Test register 5 - larger gap test
    parameter int REG_TEST_6       = 32'h00001080;  // RW - Test register 6 - even larger gap test
    parameter int REG_TEST_7       = 32'h00001100;  // RW - Test register 7 - different range test
    parameter int REG_CPU_DBG_CTRL = 32'h00001200;  // RW - CPU debug control: halt/run/step requests, halt_on_reset, breakpoint global enable
    parameter int REG_CPU_DBG_STATUS = 32'h00001204;  // RO - CPU debug status: halted/running, break/brk hit, halt reason
    parameter int REG_CPU_PC       = 32'h00001208;  // RW - CPU program counter (word address). Write allowed only when halted
    parameter int REG_CPU_SP       = 32'h0000120C;  // RW - CPU stack pointer (word address). Write allowed only when halted
    parameter int REG_CPU_FLAGS    = 32'h00001210;  // RW - CPU flags (Z/N/C in low bits). Write allowed only when halted
    parameter int REG_CPU_REG_INDEX = 32'h00001214;  // RW - CPU register index selector (0..7)
    parameter int REG_CPU_REG_DATA = 32'h00001218;  // RW - CPU selected register data (16-bit). Write allowed only when halted
    parameter int REG_CPU_BP0_PC   = 32'h0000121C;  // RW - Breakpoint 0 PC match value (word address)
    parameter int REG_CPU_BP1_PC   = 32'h00001220;  // RW - Breakpoint 1 PC match value (word address)
    parameter int REG_CPU_BP_CTRL  = 32'h00001224;  // RW - Breakpoint control (BP0_EN/BP1_EN/BP_MATCH_FETCH)
    parameter int REG_CPU_MEM_ADDR = 32'h00001228;  // RW - Debug memory address (word address)
    parameter int REG_CPU_MEM_WDATA = 32'h0000122C;  // RW - Debug memory write data (16-bit in low bits)
    parameter int REG_CPU_MEM_RDATA = 32'h00001230;  // RO - Debug memory read data (16-bit in low bits)
    parameter int REG_CPU_MEM_CTRL = 32'h00001234;  // RW - Debug memory control: read/write request, auto-inc, busy/err
    parameter int REG_CPU_ID       = 32'h00001238;  // RO - CPU identification/version (ASCII 'TD31' placeholder)
    parameter int REG_REVISION     = 32'h0000123C;  // RO - Hardware revision (date-based: 0xYYYYMMDD)
    parameter int REG_CPU_TRACE_CTRL = 32'h00001240;  // RW - Trace control: [0]=enable, [1]=clear_pulse
    parameter int REG_CPU_TRACE_PTR = 32'h00001244;  // RO - Trace buffer write pointer (0-255)
    parameter int REG_CPU_TRACE_BASE = 32'h00001300;  // RO - Trace buffer base (256 entries × 4 bytes = 0x1300-0x13FC)

    // Register count
    parameter int REGISTER_COUNT = 36;

endpackage : axiuart_reg_pkg
