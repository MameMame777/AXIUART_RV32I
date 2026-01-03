`timescale 1ns / 1ps

// AXIUART Register Package
//
// AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
// Generated from: register_map/axiuart_registers.json
// Generation time: 2026-01-03T09:07:18.657612
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
    parameter int REG_CPU_MEM_ADDR = 32'h00002228;  // RW - RV32I CPU memory address (32-bit byte address, converted to word address [12:2] internally for 8KB RAM)
    parameter int REG_CPU_MEM_WDATA = 32'h0000222C;  // RW - RV32I CPU memory write data (full 32-bit data)
    parameter int REG_CPU_MEM_RDATA = 32'h00002230;  // RO - RV32I CPU memory read data (full 32-bit data, captured after read operation)
    parameter int REG_CPU_MEM_CTRL = 32'h00002234;  // RW - RV32I CPU control and memory access: [3:0]=byte_enables, [4]=read_req(W1P), [5]=write_req(W1P), [6]=busy(RO), [7]=cpu_run, [8]=cpu_halt, [9]=cpu_halted(RO), [10]=cpu_break(RO)
    parameter int REG_REVISION     = 32'h0000223C;  // RO - Hardware revision (RV32I-only design, date: 2026-01-03)

    // Register count
    parameter int REGISTER_COUNT = 18;

endpackage : axiuart_reg_pkg
