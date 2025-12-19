"""
AXIUART Hardware Driver
Production-ready driver for register access over UART
"""

import serial
import struct
import time
import logging
from typing import Optional, List, Union
from .protocol import FrameBuilder, FrameParser, StatusCode, CommandField
from . import registers


class AXIUARTException(Exception):
    """Base exception for AXIUART driver errors"""
    pass


class AXIUARTDriver:
    """
    AXIUART Bridge Driver
    
    Provides register read/write access to AXI4-Lite address space
    through UART-based protocol defined in docs/axiuart_bus_protocol.md
    
    Example:
        driver = AXIUARTDriver('/dev/ttyUSB0', baudrate=115200)
        driver.open()
        
        # Write 32-bit register
        driver.write_reg32(0x1000, 0xDEADBEEF)
        
        # Read 32-bit register
        value = driver.read_reg32(0x1000)
        
        driver.close()
    """
    
    # Default parameters per protocol spec
    DEFAULT_BAUD = 115200
    DEFAULT_TIMEOUT = 1.0  # 1 second response timeout
    
    # Register map (imported from auto-generated module)
    # See register_map/axiuart_registers.json for source of truth
    BASE_ADDR = registers.BASE_ADDR
    REG_CONTROL = registers.REG_CONTROL
    REG_STATUS = registers.REG_STATUS
    REG_CONFIG = registers.REG_CONFIG
    REG_DEBUG = registers.REG_DEBUG
    REG_TX_COUNT = registers.REG_TX_COUNT
    REG_RX_COUNT = registers.REG_RX_COUNT
    REG_FIFO_STAT = registers.REG_FIFO_STAT
    REG_VERSION = registers.REG_VERSION
    REG_TEST_0 = registers.REG_TEST_0
    REG_TEST_1 = registers.REG_TEST_1
    REG_TEST_2 = registers.REG_TEST_2
    REG_TEST_3 = registers.REG_TEST_3
    REG_TEST_4 = registers.REG_TEST_4
    REG_TEST_LED = registers.REG_TEST_LED
    REG_TEST_5 = registers.REG_TEST_5
    REG_TEST_6 = registers.REG_TEST_6
    REG_TEST_7 = registers.REG_TEST_7
    
    def __init__(self, port: str, baudrate: int = DEFAULT_BAUD, 
                 timeout: float = DEFAULT_TIMEOUT, debug: bool = False):
        """
        Initialize AXIUART driver
        
        Args:
            port: Serial port device (e.g., '/dev/ttyUSB0', 'COM3')
            baudrate: UART baud rate (default 115200)
            timeout: Response timeout in seconds
            debug: Enable debug logging
        """
        self.port = port
        self.baudrate = baudrate
        self.timeout = timeout
        self.serial: Optional[serial.Serial] = None
        
        # Setup logging
        self.logger = logging.getLogger(__name__)
        if debug:
            self.logger.setLevel(logging.DEBUG)
            if not self.logger.handlers:
                handler = logging.StreamHandler()
                handler.setFormatter(logging.Formatter(
                    '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
                ))
                self.logger.addHandler(handler)
    
    def open(self) -> None:
        """Open serial port connection"""
        try:
            self.serial = serial.Serial(
                port=self.port,
                baudrate=self.baudrate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=self.timeout
            )
            self.logger.info(f"Opened {self.port} at {self.baudrate} baud")
            
            # Flush buffers
            self.serial.reset_input_buffer()
            self.serial.reset_output_buffer()
            
        except serial.SerialException as e:
            raise AXIUARTException(f"Failed to open port {self.port}: {e}")
    
    def close(self) -> None:
        """Close serial port connection"""
        if self.serial and self.serial.is_open:
            self.serial.close()
            self.logger.info(f"Closed {self.port}")
    
    def __enter__(self):
        """Context manager entry"""
        self.open()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.close()
    
    def _send_frame(self, frame: bytes) -> None:
        """Send frame to device"""
        if not self.serial or not self.serial.is_open:
            raise AXIUARTException("Serial port not open")
        
        self.logger.debug(f"TX: {frame.hex()}")
        self.serial.write(frame)
        self.serial.flush()
    
    def _receive_response(self, min_length: int = 4, max_length: int = 128) -> bytes:
        """
        Receive response frame from device
        
        Args:
            min_length: Minimum expected frame length
            max_length: Maximum frame length to read
        
        Returns:
            Complete response frame
        """
        if not self.serial or not self.serial.is_open:
            raise AXIUARTException("Serial port not open")
        
        # Wait for SOF
        sof = self.serial.read(1)
        if len(sof) == 0:
            raise AXIUARTException("Response timeout: no SOF received")
        
        if sof[0] != FrameParser.SOF_DEVICE:
            raise AXIUARTException(f"Invalid SOF: 0x{sof[0]:02X} (expected 0x5A)")
        
        # Read STATUS + CMD
        header = self.serial.read(2)
        if len(header) < 2:
            raise AXIUARTException("Response timeout: incomplete header")
        
        status = header[0]
        cmd_echo = header[1]
        
        # Determine expected frame length based on command type
        rw, inc, size, length = CommandField.decode(cmd_echo)
        
        if rw and status == StatusCode.SUCCESS:
            # Read response with payload: SOF + STATUS + CMD + ADDR(4) + DATA + CRC
            beat_size = CommandField.get_beat_size(size)
            payload_len = (length + 1) * beat_size
            remaining = 4 + payload_len + 1  # ADDR + DATA + CRC
        else:
            # Write ACK or error response: SOF + STATUS + CMD + CRC
            remaining = 1  # Just CRC
        
        # Read remaining bytes
        tail = self.serial.read(remaining)
        if len(tail) < remaining:
            raise AXIUARTException(
                f"Response timeout: expected {remaining} bytes, got {len(tail)}"
            )
        
        response = sof + header + tail
        self.logger.debug(f"RX: {response.hex()}")
        
        return response
    
    def write_reg32(self, addr: int, value: int) -> None:
        """
        Write 32-bit register
        
        Args:
            addr: Register address (must be 4-byte aligned)
            value: 32-bit value to write
        
        Raises:
            AXIUARTException: On protocol error or device error
        """
        if addr & 0x3:
            raise AXIUARTException(f"Address 0x{addr:08X} not 32-bit aligned")
        
        # Pack value as little-endian 32-bit
        data = struct.pack('<I', value & 0xFFFFFFFF)
        
        # Build and send write frame
        frame = FrameBuilder.build_write_frame(addr, data, size=CommandField.SIZE_32BIT, inc=False)
        self._send_frame(frame)
        
        # Receive and parse response
        response = self._receive_response()
        status, cmd_echo, addr_echo, payload = FrameParser.parse_response(response)
        
        if status != StatusCode.SUCCESS:
            raise AXIUARTException(
                f"Write failed at 0x{addr:08X}: status={status.name} (0x{status:02X})"
            )
        
        self.logger.debug(f"Write 0x{addr:08X} = 0x{value:08X}")
    
    def read_reg32(self, addr: int) -> int:
        """
        Read 32-bit register
        
        Args:
            addr: Register address (must be 4-byte aligned)
        
        Returns:
            32-bit register value
        
        Raises:
            AXIUARTException: On protocol error or device error
        """
        if addr & 0x3:
            raise AXIUARTException(f"Address 0x{addr:08X} not 32-bit aligned")
        
        # Build and send read frame
        frame = FrameBuilder.build_read_frame(addr, num_beats=1, size=CommandField.SIZE_32BIT, inc=False)
        self._send_frame(frame)
        
        # Receive and parse response
        response = self._receive_response()
        status, cmd_echo, addr_echo, payload = FrameParser.parse_response(response)
        
        if status != StatusCode.SUCCESS:
            raise AXIUARTException(
                f"Read failed at 0x{addr:08X}: status={status.name} (0x{status:02X})"
            )
        
        if payload is None or len(payload) != 4:
            raise AXIUARTException(f"Invalid read response: payload={payload}")
        
        value = struct.unpack('<I', payload)[0]
        self.logger.debug(f"Read 0x{addr:08X} = 0x{value:08X}")
        
        return value
    
    def write_burst(self, addr: int, values: List[int], inc: bool = True) -> None:
        """
        Write multiple 32-bit registers in burst
        
        Args:
            addr: Starting register address (must be 4-byte aligned)
            values: List of 32-bit values (max 16)
            inc: Auto-increment addressing
        
        Raises:
            AXIUARTException: On protocol error or device error
        """
        if not (1 <= len(values) <= 16):
            raise AXIUARTException(f"Burst length {len(values)} out of range (1-16)")
        
        if addr & 0x3:
            raise AXIUARTException(f"Address 0x{addr:08X} not 32-bit aligned")
        
        # Pack values as little-endian 32-bit
        data = b''.join(struct.pack('<I', v & 0xFFFFFFFF) for v in values)
        
        # Build and send write frame
        frame = FrameBuilder.build_write_frame(addr, data, size=CommandField.SIZE_32BIT, inc=inc)
        self._send_frame(frame)
        
        # Receive and parse response
        response = self._receive_response()
        status, cmd_echo, addr_echo, payload = FrameParser.parse_response(response)
        
        if status != StatusCode.SUCCESS:
            raise AXIUARTException(
                f"Burst write failed at 0x{addr:08X}: status={status.name} (0x{status:02X})"
            )
        
        self.logger.debug(f"Burst write 0x{addr:08X}: {len(values)} words")
    
    def read_burst(self, addr: int, count: int, inc: bool = True) -> List[int]:
        """
        Read multiple 32-bit registers in burst
        
        Args:
            addr: Starting register address (must be 4-byte aligned)
            count: Number of 32-bit words to read (1-16)
            inc: Auto-increment addressing
        
        Returns:
            List of 32-bit values
        
        Raises:
            AXIUARTException: On protocol error or device error
        """
        if not (1 <= count <= 16):
            raise AXIUARTException(f"Burst count {count} out of range (1-16)")
        
        if addr & 0x3:
            raise AXIUARTException(f"Address 0x{addr:08X} not 32-bit aligned")
        
        # Build and send read frame
        frame = FrameBuilder.build_read_frame(addr, num_beats=count, size=CommandField.SIZE_32BIT, inc=inc)
        self._send_frame(frame)
        
        # Receive and parse response
        response = self._receive_response()
        status, cmd_echo, addr_echo, payload = FrameParser.parse_response(response)
        
        if status != StatusCode.SUCCESS:
            raise AXIUARTException(
                f"Burst read failed at 0x{addr:08X}: status={status.name} (0x{status:02X})"
            )
        
        if payload is None or len(payload) != count * 4:
            raise AXIUARTException(f"Invalid burst read response: expected {count * 4} bytes, got {len(payload) if payload else 0}")
        
        # Unpack little-endian 32-bit values
        values = [struct.unpack('<I', payload[i:i+4])[0] for i in range(0, len(payload), 4)]
        
        self.logger.debug(f"Burst read 0x{addr:08X}: {count} words")
        
        return values
    
    def soft_reset(self) -> None:
        """
        Send RESET command (0xFF) to device
        
        Per Section 3.1: Soft reset clears RX/TX FIFOs and state machines,
        but preserves configuration registers
        """
        # Build and send reset frame
        frame = FrameBuilder.build_reset_frame()
        self._send_frame(frame)
        
        # Receive and parse response
        response = self._receive_response()
        status, cmd_echo, addr_echo, payload = FrameParser.parse_response(response)
        
        if status != StatusCode.SUCCESS:
            raise AXIUARTException(f"Reset failed: status={status.name} (0x{status:02X})")
        
        if cmd_echo != CommandField.CMD_RESET:
            raise AXIUARTException(f"Reset command echo mismatch: 0x{cmd_echo:02X}")
        
        self.logger.info("Soft reset completed")
    
    def get_version(self) -> int:
        """Read VERSION register"""
        return self.read_reg32(self.REG_VERSION)
    
    def get_status(self) -> int:
        """Read STATUS register"""
        return self.read_reg32(self.REG_STATUS)
    
    def get_tx_count(self) -> int:
        """Read TX counter"""
        return self.read_reg32(self.REG_TX_COUNT)
    
    def get_rx_count(self) -> int:
        """Read RX counter"""
        return self.read_reg32(self.REG_RX_COUNT)
    
    def get_fifo_status(self) -> int:
        """Read FIFO status"""
        return self.read_reg32(self.REG_FIFO_STAT)
