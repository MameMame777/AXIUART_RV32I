`timescale 1ns / 1ps

// AXIUART Register Package
//
// AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
// Generated from: register_map/axiuart_registers.json
// Generation time: 2025-12-18T22:27:25.198213
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

    // Register count
    parameter int REGISTER_COUNT = 17;

endpackage : axiuart_reg_pkg
