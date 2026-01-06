r"""
AXIUART Register Map

AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
Generated from: register_map/axiuart_registers.json
Generation time: 2026-01-03T09:07:18.657612

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

# Register count
REGISTER_COUNT = 18
