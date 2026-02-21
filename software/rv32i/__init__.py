"""RV32I Instruction Encoding Package

Provides RV32I base instruction set encoding.

This package provides:
- Instruction encoding (encoder.py)
- LED blink bring-up script (led_blink.py)

Basic usage:
    from rv32i import RV32IInstructionEncoder

    encoder = RV32IInstructionEncoder()
    insn = encoder.addi(rd=10, rs1=0, imm=42)  # x10 = x0 + 42
"""

from .encoder import RV32IInstructionEncoder

__version__ = "0.1.0"
__all__ = [
    "RV32IInstructionEncoder",
]
