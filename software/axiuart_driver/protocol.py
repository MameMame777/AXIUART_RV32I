"""
AXIUART Bus Protocol Implementation
Compliant with docs/axiuart_bus_protocol.md specification
"""

from enum import IntEnum
from typing import List, Optional, Tuple
import struct


class StatusCode(IntEnum):
    """Device status codes per Section 5 of protocol spec"""
    SUCCESS = 0x00
    CRC_ERROR = 0x01
    INVALID_CMD = 0x02
    ADDR_ALIGN = 0x03
    TIMEOUT = 0x04
    AXI_ERROR = 0x05
    BUSY = 0x06
    LEN_RANGE = 0x07


class CRC8:
    """
    CRC-8 calculator using polynomial 0x07
    Per Section 7 of protocol spec:
    - Polynomial: x^8 + x^2 + x + 1 (0x07)
    - Initial value: 0x00
    - No reflection, no final XOR
    """
    POLYNOMIAL = 0x07
    
    @staticmethod
    def calculate(data: bytes) -> int:
        """Calculate CRC-8 over byte sequence"""
        crc = 0x00
        for byte in data:
            crc ^= byte
            for _ in range(8):
                if crc & 0x80:
                    crc = (crc << 1) ^ CRC8.POLYNOMIAL
                else:
                    crc = crc << 1
            crc &= 0xFF
        return crc


class CommandField:
    """Command byte layout per Section 3.1"""
    
    # Size field encoding
    SIZE_8BIT = 0b00
    SIZE_16BIT = 0b01
    SIZE_32BIT = 0b10
    SIZE_RESERVED = 0b11
    
    # Special command
    CMD_RESET = 0xFF
    
    @staticmethod
    def encode(rw: bool, inc: bool, size: int, length: int) -> int:
        """
        Encode command byte
        Args:
            rw: True for read, False for write
            inc: True for auto-increment addressing
            size: 0=8bit, 1=16bit, 2=32bit
            length: Beat count minus 1 (0-15 for 1-16 beats)
        Returns:
            Packed CMD byte
        """
        if size not in [0, 1, 2]:
            raise ValueError(f"Invalid size: {size} (must be 0/1/2)")
        if not (0 <= length <= 15):
            raise ValueError(f"Invalid length: {length} (must be 0-15)")
        
        cmd = 0
        cmd |= (1 << 7) if rw else 0
        cmd |= (1 << 6) if inc else 0
        cmd |= (size & 0x3) << 4
        cmd |= (length & 0xF)
        return cmd
    
    @staticmethod
    def decode(cmd: int) -> Tuple[bool, bool, int, int]:
        """
        Decode command byte
        Returns:
            (rw, inc, size, length)
        """
        rw = bool(cmd & 0x80)
        inc = bool(cmd & 0x40)
        size = (cmd >> 4) & 0x3
        length = cmd & 0xF
        return rw, inc, size, length
    
    @staticmethod
    def get_beat_size(size: int) -> int:
        """Get beat size in bytes from SIZE field"""
        return [1, 2, 4][size] if size < 3 else 0


class FrameBuilder:
    """Host-to-Device frame builder per Section 3"""
    
    SOF_HOST = 0xA5
    
    @staticmethod
    def build_write_frame(addr: int, data: bytes, size: int = 2, inc: bool = True) -> bytes:
        """
        Build write command frame
        Args:
            addr: 32-bit AXI address
            data: Payload bytes (1-64 bytes)
            size: 0=8bit, 1=16bit, 2=32bit
            inc: Auto-increment addressing
        Returns:
            Complete frame bytes
        """
        if not (1 <= len(data) <= 64):
            raise ValueError(f"Invalid data length: {len(data)} (must be 1-64)")
        
        beat_size = CommandField.get_beat_size(size)
        if len(data) % beat_size != 0:
            raise ValueError(f"Data length {len(data)} not aligned to beat size {beat_size}")
        
        num_beats = len(data) // beat_size
        if num_beats > 16:
            raise ValueError(f"Too many beats: {num_beats} (max 16)")
        
        # Build frame
        frame = bytearray()
        frame.append(FrameBuilder.SOF_HOST)
        
        cmd = CommandField.encode(rw=False, inc=inc, size=size, length=num_beats - 1)
        frame.append(cmd)
        
        frame.extend(struct.pack('<I', addr))  # Little-endian address
        frame.extend(data)
        
        # Calculate CRC over CMD + ADDR + DATA
        crc_data = frame[1:]  # Exclude SOF
        crc = CRC8.calculate(bytes(crc_data))
        frame.append(crc)
        
        return bytes(frame)
    
    @staticmethod
    def build_read_frame(addr: int, num_beats: int, size: int = 2, inc: bool = True) -> bytes:
        """
        Build read command frame
        Args:
            addr: 32-bit AXI address
            num_beats: Number of beats (1-16)
            size: 0=8bit, 1=16bit, 2=32bit
            inc: Auto-increment addressing
        Returns:
            Complete frame bytes
        """
        if not (1 <= num_beats <= 16):
            raise ValueError(f"Invalid beat count: {num_beats} (must be 1-16)")
        
        # Build frame
        frame = bytearray()
        frame.append(FrameBuilder.SOF_HOST)
        
        cmd = CommandField.encode(rw=True, inc=inc, size=size, length=num_beats - 1)
        frame.append(cmd)
        
        frame.extend(struct.pack('<I', addr))  # Little-endian address
        
        # Calculate CRC over CMD + ADDR (no DATA for reads)
        crc_data = frame[1:]  # Exclude SOF
        crc = CRC8.calculate(bytes(crc_data))
        frame.append(crc)
        
        return bytes(frame)
    
    @staticmethod
    def build_reset_frame() -> bytes:
        """
        Build RESET command frame per Section 3.1
        Returns:
            RESET frame: SOF (0xA5) | CMD (0xFF) | CRC (0x58)
        """
        frame = bytearray()
        frame.append(FrameBuilder.SOF_HOST)
        frame.append(CommandField.CMD_RESET)
        crc = CRC8.calculate(bytes([CommandField.CMD_RESET]))
        frame.append(crc)
        return bytes(frame)


class FrameParser:
    """Device-to-Host frame parser per Section 4"""
    
    SOF_DEVICE = 0x5A
    
    @staticmethod
    def parse_response(data: bytes) -> Tuple[StatusCode, int, Optional[int], Optional[bytes]]:
        """
        Parse device response frame
        Args:
            data: Complete response frame
        Returns:
            (status, cmd_echo, addr_echo, payload)
            - addr_echo is None for write ACKs
            - payload is None for errors or writes
        Raises:
            ValueError: Invalid frame format or CRC mismatch
        """
        if len(data) < 4:
            raise ValueError(f"Frame too short: {len(data)} bytes (min 4)")
        
        if data[0] != FrameParser.SOF_DEVICE:
            raise ValueError(f"Invalid SOF: 0x{data[0]:02X} (expected 0x5A)")
        
        status = StatusCode(data[1])
        cmd_echo = data[2]
        
        # Decode command to determine frame type
        rw, inc, size, length = CommandField.decode(cmd_echo)
        
        if rw:  # Read response
            if status == StatusCode.SUCCESS:
                # Full read response with ADDR + DATA
                if len(data) < 8:
                    raise ValueError(f"Read response too short: {len(data)} bytes")
                
                addr_echo = struct.unpack('<I', data[3:7])[0]
                
                beat_size = CommandField.get_beat_size(size)
                expected_payload = (length + 1) * beat_size
                
                if len(data) != 8 + expected_payload:
                    raise ValueError(
                        f"Read payload length mismatch: got {len(data) - 8}, expected {expected_payload}"
                    )
                
                payload = data[7:-1]
                received_crc = data[-1]
                
                # Verify CRC over STATUS + CMD + ADDR + DATA
                crc_data = data[1:-1]
                expected_crc = CRC8.calculate(crc_data)
                if received_crc != expected_crc:
                    raise ValueError(
                        f"CRC mismatch: received 0x{received_crc:02X}, expected 0x{expected_crc:02X}"
                    )
                
                return status, cmd_echo, addr_echo, payload
            else:
                # Error read response: STATUS + CMD + CRC only
                if len(data) != 4:
                    raise ValueError(f"Error read response wrong length: {len(data)} bytes (expected 4)")
                
                received_crc = data[3]
                crc_data = data[1:3]
                expected_crc = CRC8.calculate(crc_data)
                if received_crc != expected_crc:
                    raise ValueError(
                        f"CRC mismatch: received 0x{received_crc:02X}, expected 0x{expected_crc:02X}"
                    )
                
                return status, cmd_echo, None, None
        else:  # Write ACK
            # Write ACK: STATUS + CMD + CRC only
            if len(data) != 4:
                raise ValueError(f"Write ACK wrong length: {len(data)} bytes (expected 4)")
            
            received_crc = data[3]
            crc_data = data[1:3]
            expected_crc = CRC8.calculate(crc_data)
            if received_crc != expected_crc:
                raise ValueError(
                    f"CRC mismatch: received 0x{received_crc:02X}, expected 0x{expected_crc:02X}"
                )
            
            return status, cmd_echo, None, None
