#!/usr/bin/env python3
"""
RV32I CPU Driver

Python driver for RV32I CPU via UART debug interface.
Provides memory access, register control, and program execution.

Features:
- Debug memory access (8KB RAM, byte-granular)
- CPU control (halt, run, breakpoint detection)
- Program loading from binary or instruction list
- Register inspection (via memory dumps)
- LED MMIO control
- Trace buffer access (future)

Usage:
    from rv32i import RV32ICPUDriver, isa
    
    driver = RV32ICPUDriver(port='COM3')
    driver.open()
    
    # Load and run program
    program = [
        isa.LUI('a0', 0x4000),  # a0 = 0x4000
        isa.ADDI('a1', 'zero', 5),  # a1 = 5
        isa.SW('a1', 'a0', 0x7C),  # LED = 5
        isa.EBREAK()
    ]
    driver.load_program(program)
    driver.run_cpu()
    driver.wait_for_breakpoint()
    
    led_val = driver.read_led()
    print(f"LED = {led_val}")
"""

import sys
import time
from pathlib import Path
from typing import List, Optional, Union

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from axiuart_driver import AXIUARTDriver, registers


class RV32ICPUDriver:
    """
    RV32I CPU Hardware Driver
    
    Provides high-level interface to RV32I CPU via AXIUART debug interface.
    """
    
    # Memory map constants
    RAM_BASE = 0x0000_0000
    RAM_SIZE = 8192  # 8KB = 2048 words
    MMIO_BASE = 0x0000_4000
    LED_ADDR = 0x0000_407C
    
    def __init__(self, port: str, baudrate: int = 115200, timeout: float = 2.0):
        """
        Initialize RV32I CPU driver
        
        Args:
            port: Serial port name (e.g., 'COM3' or '/dev/ttyUSB0')
            baudrate: UART baud rate (default: 115200)
            timeout: Communication timeout in seconds (default: 2.0)
        """
        self.driver = AXIUARTDriver(port, baudrate=baudrate, timeout=timeout)
        self.port = port
        self.baudrate = baudrate
        
    def open(self):
        """Open UART connection"""
        print(f"Opening {self.port} @ {self.baudrate} baud...")
        self.driver.open()
        time.sleep(0.1)  # Let hardware stabilize
        
    def close(self):
        """Close UART connection"""
        self.driver.close()
        
    # =========================================================================
    # CPU Control
    # =========================================================================
    
    def halt_cpu(self):
        """Halt CPU execution
        
        Writes to CPU_MEM_CTRL to halt the CPU.
        Safe for debug memory access.
        """
        # Bit 8: halt
        ctrl = self.driver.read_reg32(registers.REG_CPU_MEM_CTRL)
        self.driver.write_reg32(registers.REG_CPU_MEM_CTRL, ctrl | (1 << 8))
        time.sleep(0.01)  # Allow halt to take effect
        
    def run_cpu(self):
        """Start/resume CPU execution
        
        Clears halt bit, sets run bit.
        """
        # Bit 7: run
        ctrl = self.driver.read_reg32(registers.REG_CPU_MEM_CTRL)
        self.driver.write_reg32(registers.REG_CPU_MEM_CTRL, (ctrl | (1 << 7)) & ~(1 << 8))
        
    def reset_cpu(self):
        """Reset CPU to initial state
        
        Halts CPU and clears all memory.
        Note: Does not clear register file (read-only via debug interface).
        """
        print("Resetting CPU...")
        self.halt_cpu()
        
        # Clear RAM (first 256 words for speed)
        for word_addr in range(256):
            self.write_memory_word(word_addr * 4, 0x00000000)
        
        print("CPU reset complete")
        
    def is_halted(self) -> bool:
        """Check if CPU is halted
        
        Returns:
            True if CPU is halted, False if running
        """
        ctrl = self.driver.read_reg32(registers.REG_CPU_MEM_CTRL)
        return bool(ctrl & (1 << 9))  # Bit 9: halted (read-only)
        
    def is_break(self) -> bool:
        """Check if CPU hit breakpoint (EBREAK)
        
        Returns:
            True if EBREAK was executed
        """
        ctrl = self.driver.read_reg32(registers.REG_CPU_MEM_CTRL)
        return bool(ctrl & (1 << 10))  # Bit 10: break (read-only)
        
    def wait_for_breakpoint(self, timeout: float = 5.0, poll_interval: float = 0.05):
        """Wait for CPU to hit breakpoint
        
        Args:
            timeout: Maximum wait time in seconds
            poll_interval: Polling interval in seconds
            
        Returns:
            True if breakpoint hit, False if timeout
        """
        start_time = time.time()
        while (time.time() - start_time) < timeout:
            if self.is_break():
                return True
            time.sleep(poll_interval)
        return False
        
    # =========================================================================
    # Debug Memory Access (Word-level)
    # =========================================================================
    
    def write_memory_word(self, byte_addr: int, value: int):
        """Write 32-bit word to CPU memory
        
        Args:
            byte_addr: Byte address (must be word-aligned)
            value: 32-bit value to write
            
        Raises:
            ValueError: If address is not word-aligned or out of range
        """
        if byte_addr & 0x3:
            raise ValueError(f"Address 0x{byte_addr:08X} is not word-aligned")
        if byte_addr < 0 or byte_addr >= self.RAM_SIZE:
            raise ValueError(f"Address 0x{byte_addr:08X} out of RAM range")
            
        # Ensure CPU is halted
        if not self.is_halted():
            self.halt_cpu()
            
        # Set address
        self.driver.write_reg32(registers.REG_CPU_MEM_ADDR, byte_addr)
        time.sleep(0.001)
        
        # Set write data
        self.driver.write_reg32(registers.REG_CPU_MEM_WDATA, value & 0xFFFFFFFF)
        time.sleep(0.001)
        
        # Issue write request (bit 5, all byte enables)
        self.driver.write_reg32(registers.REG_CPU_MEM_CTRL, (1 << 5) | 0xF)
        time.sleep(0.005)  # Wait for write to complete
        
    def read_memory_word(self, byte_addr: int) -> int:
        """Read 32-bit word from CPU memory
        
        Args:
            byte_addr: Byte address (must be word-aligned)
            
        Returns:
            32-bit value
            
        Raises:
            ValueError: If address is not word-aligned or out of range
        """
        if byte_addr & 0x3:
            raise ValueError(f"Address 0x{byte_addr:08X} is not word-aligned")
        if byte_addr < 0 or byte_addr >= self.RAM_SIZE:
            raise ValueError(f"Address 0x{byte_addr:08X} out of RAM range")
            
        # Ensure CPU is halted
        if not self.is_halted():
            self.halt_cpu()
            
        # Set address
        self.driver.write_reg32(registers.REG_CPU_MEM_ADDR, byte_addr)
        time.sleep(0.001)
        
        # Issue read request (bit 4)
        self.driver.write_reg32(registers.REG_CPU_MEM_CTRL, (1 << 4))
        time.sleep(0.005)  # Wait for read to complete
        
        # Read data
        return self.driver.read_reg32(registers.REG_CPU_MEM_RDATA)
        
    # =========================================================================
    # Debug Memory Access (Byte-level)
    # =========================================================================
    
    def write_memory_bytes(self, byte_addr: int, data: bytes):
        """Write bytes to CPU memory
        
        Handles unaligned writes and arbitrary byte counts.
        
        Args:
            byte_addr: Starting byte address
            data: Bytes to write
        """
        offset = 0
        while offset < len(data):
            # Calculate word address and byte offset within word
            word_addr = (byte_addr + offset) & ~0x3
            byte_offset = (byte_addr + offset) & 0x3
            
            # Read current word if not writing full word
            if byte_offset != 0 or (len(data) - offset) < 4:
                word = self.read_memory_word(word_addr)
            else:
                word = 0
                
            # Insert new bytes
            for i in range(4):
                if byte_offset + i < 4 and offset + i < len(data):
                    byte_mask = 0xFF << ((byte_offset + i) * 8)
                    word = (word & ~byte_mask) | (data[offset + i] << ((byte_offset + i) * 8))
                    
            # Write modified word
            self.write_memory_word(word_addr, word)
            
            # Advance to next word
            bytes_written = min(4 - byte_offset, len(data) - offset)
            offset += bytes_written
            
    def read_memory_bytes(self, byte_addr: int, count: int) -> bytes:
        """Read bytes from CPU memory
        
        Handles unaligned reads and arbitrary byte counts.
        
        Args:
            byte_addr: Starting byte address
            count: Number of bytes to read
            
        Returns:
            Bytes read from memory
        """
        result = bytearray()
        offset = 0
        
        while offset < count:
            # Calculate word address and byte offset
            word_addr = (byte_addr + offset) & ~0x3
            byte_offset = (byte_addr + offset) & 0x3
            
            # Read word
            word = self.read_memory_word(word_addr)
            
            # Extract bytes
            for i in range(4):
                if byte_offset + i < 4 and offset + i < count:
                    result.append((word >> ((byte_offset + i) * 8)) & 0xFF)
                    
            # Advance to next word
            bytes_read = min(4 - byte_offset, count - offset)
            offset += bytes_read
            
        return bytes(result)
        
    # =========================================================================
    # Program Loading
    # =========================================================================
    
    def load_program(self, instructions: List[int], start_addr: int = 0):
        """Load program into CPU memory
        
        Args:
            instructions: List of 32-bit instructions
            start_addr: Starting byte address (default: 0)
        """
        print(f"Loading {len(instructions)} instructions at 0x{start_addr:08X}...")
        
        self.halt_cpu()
        
        for i, insn in enumerate(instructions):
            byte_addr = start_addr + (i * 4)
            self.write_memory_word(byte_addr, insn)
            
        print(f"Program loaded ({len(instructions)} words, {len(instructions)*4} bytes)")
        
    def load_binary(self, filename: str, start_addr: int = 0):
        """Load binary file into CPU memory
        
        Binary file should contain raw 32-bit instructions (little-endian).
        
        Args:
            filename: Path to binary file
            start_addr: Starting byte address (default: 0)
        """
        with open(filename, 'rb') as f:
            data = f.read()
            
        # Convert bytes to 32-bit words (little-endian)
        instructions = []
        for i in range(0, len(data), 4):
            if i + 3 < len(data):
                word = (data[i] |
                       (data[i+1] << 8) |
                       (data[i+2] << 16) |
                       (data[i+3] << 24))
                instructions.append(word)
                
        self.load_program(instructions, start_addr)
        
    # =========================================================================
    # Memory Dump
    # =========================================================================
    
    def dump_memory(self, start_addr: int, word_count: int = 16):
        """Dump memory contents to console
        
        Args:
            start_addr: Starting byte address (word-aligned)
            word_count: Number of 32-bit words to dump
        """
        print(f"\nMemory Dump: 0x{start_addr:08X} - 0x{start_addr + word_count*4:08X}")
        print("Address    +0        +4        +8        +C        ASCII")
        print("-" * 70)
        
        for i in range(0, word_count, 4):
            addr = start_addr + (i * 4)
            words = []
            ascii_str = ""
            
            for j in range(4):
                if i + j < word_count:
                    word = self.read_memory_word(addr + j*4)
                    words.append(f"{word:08X}")
                    
                    # Build ASCII representation
                    for k in range(4):
                        byte = (word >> (k * 8)) & 0xFF
                        ascii_str += chr(byte) if 32 <= byte <= 126 else '.'
                else:
                    words.append("        ")
                    
            print(f"0x{addr:08X}  {' '.join(words)}  {ascii_str}")
            
    # =========================================================================
    # MMIO Access
    # =========================================================================
    
    def write_led(self, value: int):
        """Write to LED MMIO register
        
        Args:
            value: 4-bit LED value (0-15)
        """
        self.write_memory_word(self.LED_ADDR, value & 0xF)
        
    def read_led(self) -> int:
        """Read LED MMIO register
        
        Returns:
            4-bit LED value
        """
        return self.read_memory_word(self.LED_ADDR) & 0xF
        
    # =========================================================================
    # Convenience Methods
    # =========================================================================
    
    def quick_test(self):
        """Quick hardware test - load and run simple LED program"""
        from . import isa
        
        print("\n" + "="*70)
        print("RV32I Quick Hardware Test")
        print("="*70)
        
        # Simple program: Write 0x5 to LED, then EBREAK
        program = [
            isa.LUI('a0', 0x4000 << 12),      # a0 = 0x4000
            isa.ADDI('a1', 'zero', 5),        # a1 = 5
            isa.SW('a1', 'a0', 0x7C),         # mem[0x407C] = 5 (LED)
            isa.EBREAK()                       # Breakpoint
        ]
        
        print(f"\nProgram ({len(program)} instructions):")
        for i, insn in enumerate(program):
            print(f"  [{i}] 0x{insn:08X}")
            
        # Load and execute
        self.load_program(program)
        print("\nStarting CPU...")
        self.run_cpu()
        
        print("Waiting for breakpoint...")
        if self.wait_for_breakpoint(timeout=2.0):
            print("✓ Breakpoint hit!")
            
            # Check LED value
            led_val = self.read_led()
            expected = 5
            
            if led_val == expected:
                print(f"✓ LED value correct: {led_val} (expected {expected})")
                print("\n*** TEST PASSED ***")
                return True
            else:
                print(f"✗ LED value mismatch: {led_val} (expected {expected})")
                print("\n*** TEST FAILED ***")
                return False
        else:
            print("✗ Timeout waiting for breakpoint")
            print("\n*** TEST FAILED ***")
            return False


# =============================================================================
# Command-line Interface
# =============================================================================

def main():
    """Command-line interface for RV32I driver"""
    import argparse
    
    parser = argparse.ArgumentParser(description='RV32I CPU Driver')
    parser.add_argument('--port', required=True, help='Serial port (e.g., COM3)')
    parser.add_argument('--baudrate', type=int, default=115200, help='UART baud rate')
    parser.add_argument('--test', action='store_true', help='Run quick hardware test')
    parser.add_argument('--dump', type=lambda x: int(x, 0), help='Dump memory at address (hex)')
    parser.add_argument('--words', type=int, default=16, help='Number of words to dump')
    
    args = parser.parse_args()
    
    # Create driver
    driver = RV32ICPUDriver(args.port, baudrate=args.baudrate)
    driver.open()
    
    try:
        if args.test:
            driver.quick_test()
        elif args.dump is not None:
            driver.halt_cpu()
            driver.dump_memory(args.dump, args.words)
        else:
            print("Use --test or --dump. See --help for options.")
    finally:
        driver.close()


if __name__ == '__main__':
    main()
