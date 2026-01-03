"""
RV32I CPU Driver Package

Python driver and test framework for RV32I CPU via UART interface.
Provides ISA encoding, memory access, debug control, and test execution.
"""

from .isa import *
from .cpu_driver import RV32ICPUDriver

__version__ = "1.0.0"
__all__ = ["RV32ICPUDriver"]
