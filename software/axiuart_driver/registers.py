r"""
AXIUART Register Map

AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
Generated from: register_map/axiuart_registers.json
Generation time: 2026-02-21T20:45:42.866415

To regenerate:
    python software/axiuart_driver/tools/gen_registers.py --in register_map/axiuart_registers.json
"""


# Register block base address
BASE_ADDR = 0x1000

# Register offsets (absolute addresses)
REG_CONTROL = 0x1000  # RW - Control register - includes bridge reset control
REG_STATUS = 0x1004  # RO - Status register - bridge busy and error code
REG_CONFIG = 0x1008  # RW - Configuration register - baud rate and timeout
REG_DEBUG = 0x100C  # RW - Debug control register - debug mode selection
REG_TX_COUNT = 0x1010  # RO - TX transaction counter (read-only)
REG_RX_COUNT = 0x1014  # RO - RX transaction counter (read-only)
REG_FIFO_STAT = 0x1018  # RO - FIFO status flags (read-only)
REG_VERSION = 0x101C  # RO - Hardware version register (read-only)
REG_TEST_0 = 0x1020  # RW - Test register 0 - pure read/write test
REG_TEST_1 = 0x1024  # RW - Test register 1 - pattern test
REG_TEST_2 = 0x1028  # RW - Test register 2 - increment test
REG_TEST_3 = 0x102C  # RW - Test register 3 - mirror test
REG_TEST_4 = 0x1040  # RW - Test register 4 - gap test
REG_CPU_MEM_ADDR = 0x2228  # RW - RV32I CPU memory address (32-bit byte address, converted to word address [12:2] internally for 8KB RAM)
REG_CPU_MEM_WDATA = 0x222C  # RW - RV32I CPU memory write data (full 32-bit data)
REG_CPU_MEM_RDATA = 0x2230  # RO - RV32I CPU memory read data (full 32-bit data, captured after read operation)
REG_CPU_MEM_CTRL = 0x2234  # RW - RV32I CPU control and memory access: [3:0]=byte_enables, [4]=read_req(W1P), [5]=write_req(W1P), [6]=busy(RO), [7]=cpu_run, [8]=cpu_halt, [9]=cpu_halted(RO), [10]=cpu_break(RO)
REG_REVISION = 0x223C  # RO - Hardware revision (RV32I-only design, date: 2026-01-03)
REG_DBG_BP0_ADDR = 0x2240  # RW - Hardware breakpoint 0 address (32-bit PC value, halts CPU when PC matches)
REG_DBG_BP1_ADDR = 0x2244  # RW - Hardware breakpoint 1 address (32-bit PC value, halts CPU when PC matches)
REG_DBG_BP2_ADDR = 0x2248  # RW - Hardware breakpoint 2 address (32-bit PC value, halts CPU when PC matches)
REG_DBG_BP3_ADDR = 0x224C  # RW - Hardware breakpoint 3 address (32-bit PC value, halts CPU when PC matches)
REG_DBG_BP_CTRL = 0x2250  # RW - Breakpoint control: [3:0]=bp_enable(RW), [7:4]=bp_hit_flags(RO), cleared on cpu_run
REG_PERF_CYCLE_COUNT = 0x2260  # RO - Performance counter: total cycles executed (counts when CPU running)
REG_PERF_INSN_COUNT = 0x2264  # RO - Performance counter: total instructions committed (WB stage valid)
REG_PERF_STALL_COUNT = 0x2268  # RO - Performance counter: total pipeline stalls (IF or ID stage stalled)
REG_PERF_FLUSH_COUNT = 0x226C  # RO - Performance counter: total pipeline flushes (branch/jump taken)
REG_DBG_RF_ADDR = 0x2270  # RW - Register file read address: [4:0]=register_address (0-31), read DBG_RF_DATA after setting
REG_DBG_RF_DATA = 0x2274  # RO - Register file read data: 32-bit value of register specified by DBG_RF_ADDR (x0 always returns 0)
REG_TRACE_READ_ADDR = 0x2280  # RW - Trace buffer read address: [5:0]=entry_index (0-63), read TRACE_DATA_* registers after setting
REG_TRACE_DATA_LOW = 0x2284  # RO - Trace entry data [31:0]: lower 32 bits of trace data
REG_TRACE_DATA_MID = 0x2288  # RO - Trace entry data [63:32]: middle-low 32 bits (rd_value)
REG_TRACE_DATA_HI0 = 0x228C  # RO - Trace entry data [95:64]: middle-high 32 bits (instruction opcode)
REG_TRACE_DATA_HI1 = 0x2290  # RO - Trace entry data [127:96]: upper 32 bits (PC address)
REG_TRACE_STATUS = 0x2294  # RO - Trace buffer status: [5:0]=write_ptr, [13:8]=entry_count, [16]=buffer_full_flag
REG_DBG_RESET_CTRL = 0x2298  # RW - Debug reset control: [0]=soft_reset(W1P), [1]=reset_done(RO), [2]=cpu_step(W1P)
REG_TRACE_DATA_HI2 = 0x229C  # RO - Trace entry data [159:128]: extended trace flags
REG_TRACE_DATA_HI3 = 0x22A0  # RO - Trace entry data [191:160]: extended trace upper

# Register count
REGISTER_COUNT = 38
