"""
AXIUART Driver Package
Production-ready driver for AXIUART Bridge register access over UART
"""

from .axiuart_driver import AXIUARTDriver, AXIUARTException
from .protocol import FrameBuilder, FrameParser, StatusCode, CRC8

__version__ = "1.0.0"
__all__ = ["AXIUARTDriver", "AXIUARTException", "FrameBuilder", "FrameParser", "StatusCode", "CRC8"]
