r"""
AXIUART Register Map

AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
Generated from: register_map/axiuart_registers.json
Generation time: 2025-12-18T22:27:25.197208

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
REG_TEST_LED = 0x1044  # RW - 4-bit LED control register
REG_TEST_5 = 0x1050  # RW - Test register 5 - larger gap test
REG_TEST_6 = 0x1080  # RW - Test register 6 - even larger gap test
REG_TEST_7 = 0x1100  # RW - Test register 7 - different range test

# Register count
REGISTER_COUNT = 17
