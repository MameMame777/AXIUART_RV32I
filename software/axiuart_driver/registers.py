r"""
AXIUART Register Map

AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
Generated from: register_map/axiuart_registers.json
Generation time: 2025-12-29T19:43:38.683007

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
REG_CPU_DBG_CTRL = 0x1200  # RW - CPU debug control: halt/run/step requests, halt_on_reset, breakpoint global enable
REG_CPU_DBG_STATUS = 0x1204  # RO - CPU debug status: halted/running, break/brk hit, halt reason
REG_CPU_PC = 0x1208  # RW - CPU program counter (word address). Write allowed only when halted
REG_CPU_SP = 0x120C  # RW - CPU stack pointer (word address). Write allowed only when halted
REG_CPU_FLAGS = 0x1210  # RW - CPU flags (Z/N/C in low bits). Write allowed only when halted
REG_CPU_REG_INDEX = 0x1214  # RW - CPU register index selector (0..7)
REG_CPU_REG_DATA = 0x1218  # RW - CPU selected register data (16-bit). Write allowed only when halted
REG_CPU_BP0_PC = 0x121C  # RW - Breakpoint 0 PC match value (word address)
REG_CPU_BP1_PC = 0x1220  # RW - Breakpoint 1 PC match value (word address)
REG_CPU_BP_CTRL = 0x1224  # RW - Breakpoint control (BP0_EN/BP1_EN/BP_MATCH_FETCH)
REG_CPU_MEM_ADDR = 0x1228  # RW - Debug memory address (word address)
REG_CPU_MEM_WDATA = 0x122C  # RW - Debug memory write data (16-bit in low bits)
REG_CPU_MEM_RDATA = 0x1230  # RO - Debug memory read data (16-bit in low bits)
REG_CPU_MEM_CTRL = 0x1234  # RW - Debug memory control: read/write request, auto-inc, busy/err
REG_CPU_TRACE_ADDR = 0x1238  # RW - Trace buffer read address (entry index 0-255)
REG_CPU_TRACE_RDATA = 0x123C  # RO - Trace buffer read data (32-bit: [31:16]=insn, [15:0]=result)
REG_CPU_TRACE_CTRL = 0x1240  # RW - Trace control: [0]=enable (default 1), [1]=clear_pulse
REG_CPU_TRACE_PTR = 0x1244  # RO - Trace buffer write pointer (0-255, increments on each execution)
REG_CPU_ID = 0x1248  # RO - CPU identification/version (ASCII 'TD31' placeholder)
REG_REVISION = 0x124C  # RO - Hardware revision (date-based: 0xYYYYMMDD)

# Register count
REGISTER_COUNT = 33
