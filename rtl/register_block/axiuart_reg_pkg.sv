`timescale 1ns / 1ps

// AXIUART Register Package
//
// AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
// Generated from: register_map/axiuart_registers.json
// Generation time: 2026-02-04T04:42:25.227793
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
    parameter int REG_DBG_BP0_ADDR = 32'h00002240;  // RW - Hardware breakpoint 0 address (32-bit PC value, halts CPU when PC matches)
    parameter int REG_DBG_BP1_ADDR = 32'h00002244;  // RW - Hardware breakpoint 1 address (32-bit PC value, halts CPU when PC matches)
    parameter int REG_DBG_BP2_ADDR = 32'h00002248;  // RW - Hardware breakpoint 2 address (32-bit PC value, halts CPU when PC matches)
    parameter int REG_DBG_BP3_ADDR = 32'h0000224C;  // RW - Hardware breakpoint 3 address (32-bit PC value, halts CPU when PC matches)
    parameter int REG_DBG_BP_CTRL  = 32'h00002250;  // RW - Breakpoint control: [3:0]=bp_enable(RW), [7:4]=bp_hit_flags(RO), cleared on cpu_run
    parameter int REG_PERF_CYCLE_COUNT = 32'h00002260;  // RO - Performance counter: total cycles executed (counts when CPU running)
    parameter int REG_PERF_INSN_COUNT = 32'h00002264;  // RO - Performance counter: total instructions committed (WB stage valid)
    parameter int REG_PERF_STALL_COUNT = 32'h00002268;  // RO - Performance counter: total pipeline stalls (IF or ID stage stalled)
    parameter int REG_PERF_FLUSH_COUNT = 32'h0000226C;  // RO - Performance counter: total pipeline flushes (branch/jump taken)
    parameter int REG_DBG_RF_ADDR  = 32'h00002270;  // RW - Register file read address: [4:0]=register_address (0-31), read DBG_RF_DATA after setting
    parameter int REG_DBG_RF_DATA  = 32'h00002274;  // RO - Register file read data: 32-bit value of register specified by DBG_RF_ADDR (x0 always returns 0)
    parameter int REG_TRACE_READ_ADDR = 32'h00002280;  // RW - Trace buffer read address: [5:0]=entry_index (0-63), read TRACE_DATA_* registers after setting
    parameter int REG_TRACE_DATA_LOW = 32'h00002284;  // RO - Trace entry data [31:0]: lower 32 bits of trace data
    parameter int REG_TRACE_DATA_MID = 32'h00002288;  // RO - Trace entry data [63:32]: middle-low 32 bits (rd_value)
    parameter int REG_TRACE_DATA_HI0 = 32'h0000228C;  // RO - Trace entry data [95:64]: middle-high 32 bits (instruction opcode)
    parameter int REG_TRACE_DATA_HI1 = 32'h00002290;  // RO - Trace entry data [127:96]: upper 32 bits (PC address)
    parameter int REG_TRACE_STATUS = 32'h00002294;  // RO - Trace buffer status: [5:0]=write_ptr, [13:8]=entry_count, [16]=buffer_full_flag
    parameter int REG_DBG_RESET_CTRL = 32'h00002298;  // RW - Debug reset control: [0]=soft_reset(W1P), [1]=reset_done(RO), [2]=cpu_step(W1P)
    parameter int REG_TRACE_DATA_HI2 = 32'h0000229C;  // RO - Trace entry data [159:128]: extended trace flags
    parameter int REG_TRACE_DATA_HI3 = 32'h000022A0;  // RO - Trace entry data [191:160]: extended trace upper

    // Register count
    parameter int REGISTER_COUNT = 38;

endpackage : axiuart_reg_pkg
