"""RV32I Instruction Encoding and CPU Control Package

Provides RV32I instruction encoding and FPGA CPU control utilities.

Modules:
  encoder  - RV32I 命令エンコーダ (pure Python, 外部依存なし)
  cpu      - CPU 制御 + BRAM アクセス (axiuart_driver 必要)

Basic usage:
    from rv32i import RV32IInstructionEncoder
    from rv32i.cpu import halt_cpu, run_cpu, write_program

    encoder = RV32IInstructionEncoder()
    insn = encoder.addi(rd=10, rs1=0, imm=42)  # x10 = x0 + 42
"""

from .encoder import RV32IInstructionEncoder
from . import cpu

__version__ = "0.2.0"
__all__ = [
    "RV32IInstructionEncoder",
    "cpu",
]
