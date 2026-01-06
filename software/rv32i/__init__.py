"""RV32I Control Package

Production-ready RV32I instruction generation and CPU control
for AXIUART-based RV32I core.

This package provides:
- Instruction encoding (encoder.py)
- CPU control functions (cpu_control.py)
- Memory access helpers (memory.py)
- LED pattern generators (patterns.py)
- Example scripts (examples/)

Basic usage:
    from rv32i import RV32IInstructionEncoder, halt_cpu, run_cpu
    from axiuart_driver import AXIUARTDriver
    
    with AXIUARTDriver('/dev/ttyUSB0', 115200) as driver:
        encoder = RV32IInstructionEncoder()
        instructions = [
            encoder.lui(15, 0x4),      # Load upper immediate
            encoder.addi(16, 15, 0x7C),  # Add immediate
            encoder.sw(16, 15, 0x7C),  # Store word
            encoder.ebreak()           # Breakpoint
        ]
        halt_cpu(driver)
        write_program(driver, instructions)
        run_cpu(driver)
"""

from .encoder import RV32IInstructionEncoder
from .cpu_control import halt_cpu, run_cpu, reset_cpu, write_program, get_cpu_status
from .memory import write_cpu_mem, read_cpu_mem, verify_memory
from .patterns import (
    generate_led_simple,
    generate_led_blink,
    generate_led_count,
    generate_led_knight_rider,
    generate_led_complex_pattern,
    generate_led_complex_pattern_fast
)

__version__ = "0.1.0"
__all__ = [
    # Encoder class
    "RV32IInstructionEncoder",
    
    # CPU control functions
    "halt_cpu",
    "run_cpu",
    "reset_cpu",
    "write_program",
    "get_cpu_status",
    
    # Memory access
    "write_cpu_mem",
    "read_cpu_mem",
    "verify_memory",
    
    # Pattern generators
    "generate_led_simple",
    "generate_led_blink",
    "generate_led_count",
    "generate_led_knight_rider",
    "generate_led_complex_pattern",
    "generate_led_complex_pattern_fast",
]
