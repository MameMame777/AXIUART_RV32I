"""
VexRiscv Intel HEX File Loader with Address Translation

This module loads VexRiscv ISA test programs (Intel HEX format) and translates
addresses from standard RISC-V memory map (0x80000000) to bare-metal map (0x00000000).

Usage:
    loader = VexRiscvHexLoader("rv32ui-p-add.hex", address_offset=-0x80000000)
    memory = loader.parse_hex()
    word_data = loader.get_word_aligned_data()
    special_addrs = loader.translate_special_addresses()
"""

import re
from pathlib import Path
from typing import Dict, Tuple


class VexRiscvHexLoader:
    """
    Load VexRiscv Intel HEX files with address translation.
    
    VexRiscv tests expect boot at 0x80000000 (standard RISC-V).
    Our hardware boots at 0x00000000 (bare-metal).
    This loader translates addresses automatically.
    """
    
    def __init__(self, hex_file: str, address_offset: int = -0x80000000):
        """
        Initialize hex loader.
        
        Args:
            hex_file: Path to Intel HEX file
            address_offset: Address translation offset (default: -0x80000000)
        """
        self.hex_file = Path(hex_file)
        self.address_offset = address_offset
        self.memory: Dict[int, int] = {}  # {byte_addr: byte_value}
        self.extended_linear_addr = 0
        
        if not self.hex_file.exists():
            raise FileNotFoundError(f"Hex file not found: {self.hex_file}")
    
    def parse_hex(self) -> Dict[int, int]:
        """
        Parse Intel HEX format and apply address translation.
        
        Intel HEX format:
            :LLAAAATT[DD...]CC
            LL = byte count
            AAAA = address (16-bit)
            TT = record type (00=data, 01=EOF, 04=extended linear address)
            DD = data bytes
            CC = checksum
        
        Returns:
            Dictionary mapping byte addresses to byte values
        """
        self.memory = {}
        self.extended_linear_addr = 0
        
        with open(self.hex_file, 'r') as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                
                # Skip empty lines and comments
                if not line or line.startswith('#'):
                    continue
                
                # Validate start code
                if not line.startswith(':'):
                    raise ValueError(
                        f"Line {line_num}: Invalid Intel HEX format (missing ':')"
                    )
                
                # Parse record
                try:
                    byte_count = int(line[1:3], 16)
                    address = int(line[3:7], 16)
                    record_type = int(line[7:9], 16)
                    data = line[9:9+byte_count*2]
                    checksum = int(line[9+byte_count*2:11+byte_count*2], 16)
                    
                    # Verify checksum
                    calc_checksum = self._calculate_checksum(line[1:-2])
                    if calc_checksum != checksum:
                        raise ValueError(
                            f"Line {line_num}: Checksum mismatch "
                            f"(expected {checksum:02X}, got {calc_checksum:02X})"
                        )
                    
                    # Process record
                    self._process_record(record_type, address, data, byte_count)
                    
                    # EOF record
                    if record_type == 0x01:
                        break
                        
                except (ValueError, IndexError) as e:
                    raise ValueError(f"Line {line_num}: Parse error - {e}")
        
        return self.memory
    
    def _calculate_checksum(self, hex_data: str) -> int:
        """
        Calculate Intel HEX checksum.
        
        Checksum = Two's complement of sum of all bytes
        """
        total = sum(int(hex_data[i:i+2], 16) for i in range(0, len(hex_data), 2))
        return (-total) & 0xFF
    
    def _process_record(self, record_type: int, address: int, 
                       data: str, byte_count: int):
        """
        Process Intel HEX record based on type.
        
        Args:
            record_type: 00=data, 01=EOF, 04=extended linear address
            address: 16-bit address field
            data: Hex string of data bytes
            byte_count: Number of data bytes
        """
        if record_type == 0x00:  # Data record
            # Calculate full 32-bit address
            full_addr = (self.extended_linear_addr << 16) + address
            
            # Apply address translation
            translated_addr = full_addr + self.address_offset
            
            # Reject negative addresses (invalid translation)
            if translated_addr < 0:
                raise ValueError(
                    f"Address translation resulted in negative address: "
                    f"0x{full_addr:08X} + {self.address_offset:+08X} = {translated_addr:+08X}"
                )
            
            # Store data bytes
            for i in range(0, len(data), 2):
                byte_val = int(data[i:i+2], 16)
                self.memory[translated_addr + i//2] = byte_val
        
        elif record_type == 0x04:  # Extended Linear Address
            # Upper 16 bits of address
            self.extended_linear_addr = int(data, 16)
        
        elif record_type == 0x01:  # EOF
            pass
        
        else:
            # Ignore other record types (0x02, 0x03, 0x05)
            pass
    
    def get_word_aligned_data(self) -> Dict[int, int]:
        """
        Convert byte memory to word-aligned dictionary.
        
        Returns:
            Dictionary mapping word addresses to 32-bit values
            Format: {word_addr: 32bit_value}
            
        Example:
            Byte memory: {0: 0x13, 1: 0x00, 2: 0x50, 3: 0x00}
            Word memory: {0: 0x00500013}  (little-endian)
        """
        if not self.memory:
            raise RuntimeError("No memory data loaded. Call parse_hex() first.")
        
        word_data = {}
        sorted_addrs = sorted(self.memory.keys())
        
        if not sorted_addrs:
            return word_data
        
        # Find min/max addresses (aligned to word boundaries)
        min_addr = (sorted_addrs[0] // 4) * 4
        max_addr = ((sorted_addrs[-1] // 4) + 1) * 4
        
        # Convert to word-aligned data (little-endian)
        for byte_addr in range(min_addr, max_addr, 4):
            word = 0
            for i in range(4):
                if byte_addr + i in self.memory:
                    word |= self.memory[byte_addr + i] << (i * 8)
            
            word_addr = byte_addr >> 2  # Divide by 4 for word address
            word_data[word_addr] = word
        
        return word_data
    
    def translate_special_addresses(self) -> Dict[str, int]:
        """
        Translate special VexRiscv test addresses.
        
        VexRiscv tests use specific addresses for communication:
        - tohost (0x80001000): Test writes result here (1=PASS, other=FAIL)
        - fromhost (0x80001040): Host-to-test communication
        - begin_signature (0x80002000): Test signature start
        - end_signature (0x80003000): Test signature end
        
        Returns:
            Dictionary of translated addresses
        """
        return {
            'tohost': 0x80001000 + self.address_offset,
            'fromhost': 0x80001040 + self.address_offset,
            'begin_signature': 0x80002000 + self.address_offset,
            'end_signature': 0x80003000 + self.address_offset
        }
    
    def get_memory_range(self) -> Tuple[int, int]:
        """
        Get min and max addresses in loaded memory.
        
        Returns:
            Tuple of (min_addr, max_addr)
        """
        if not self.memory:
            return (0, 0)
        
        sorted_addrs = sorted(self.memory.keys())
        return (sorted_addrs[0], sorted_addrs[-1])
    
    def dump_memory_map(self, output_file: str = None) -> str:
        """
        Generate human-readable memory map.
        
        Args:
            output_file: Optional file path to write output
        
        Returns:
            Memory map string
        """
        if not self.memory:
            return "Memory empty (no data loaded)"
        
        lines = []
        lines.append("=" * 60)
        lines.append(f"VexRiscv Memory Map: {self.hex_file.name}")
        lines.append(f"Address Translation: {self.address_offset:+08X}")
        lines.append("=" * 60)
        
        # Get word-aligned data
        word_data = self.get_word_aligned_data()
        
        # Print memory contents (16 bytes per line)
        sorted_word_addrs = sorted(word_data.keys())
        for i in range(0, len(sorted_word_addrs), 4):
            line_addrs = sorted_word_addrs[i:i+4]
            byte_addr = line_addrs[0] * 4
            
            # Address
            line = f"0x{byte_addr:08X}:  "
            
            # Words (hex)
            words_hex = []
            for word_addr in line_addrs:
                word_val = word_data[word_addr]
                words_hex.append(f"{word_val:08X}")
            line += "  ".join(words_hex)
            
            lines.append(line)
        
        # Statistics
        lines.append("=" * 60)
        min_addr, max_addr = self.get_memory_range()
        lines.append(f"Memory Range: 0x{min_addr:08X} - 0x{max_addr:08X}")
        lines.append(f"Total Bytes: {len(self.memory)}")
        lines.append(f"Total Words: {len(word_data)}")
        
        # Special addresses
        special = self.translate_special_addresses()
        lines.append("")
        lines.append("Special Addresses:")
        for name, addr in special.items():
            lines.append(f"  {name:20s}: 0x{addr:08X}")
        lines.append("=" * 60)
        
        output = "\n".join(lines)
        
        # Write to file if requested
        if output_file:
            with open(output_file, 'w') as f:
                f.write(output)
        
        return output
    
    @staticmethod
    def validate_hex_file(hex_file: str) -> bool:
        """
        Quick validation of Intel HEX file format.
        
        Args:
            hex_file: Path to hex file
        
        Returns:
            True if valid, False otherwise
        """
        try:
            loader = VexRiscvHexLoader(hex_file, address_offset=0)
            loader.parse_hex()
            return True
        except Exception:
            return False


def main():
    """
    Command-line interface for hex loader.
    
    Usage:
        python vexriscv_hex_loader.py <hex_file> [--offset OFFSET] [--dump]
    """
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Load VexRiscv Intel HEX files with address translation"
    )
    parser.add_argument("hex_file", help="Path to Intel HEX file")
    parser.add_argument(
        "--offset", type=lambda x: int(x, 0), default=-0x80000000,
        help="Address translation offset (default: -0x80000000)"
    )
    parser.add_argument(
        "--dump", action="store_true",
        help="Dump memory map to stdout"
    )
    parser.add_argument(
        "--output", help="Write memory map to file"
    )
    
    args = parser.parse_args()
    
    try:
        # Load hex file
        print(f"Loading: {args.hex_file}")
        print(f"Address offset: {args.offset:+08X}")
        
        loader = VexRiscvHexLoader(args.hex_file, address_offset=args.offset)
        memory = loader.parse_hex()
        
        print(f"✓ Loaded {len(memory)} bytes")
        
        # Get word-aligned data
        word_data = loader.get_word_aligned_data()
        print(f"✓ Converted to {len(word_data)} words")
        
        # Get special addresses
        special = loader.translate_special_addresses()
        print(f"✓ tohost address: 0x{special['tohost']:08X}")
        
        # Dump memory map if requested
        if args.dump or args.output:
            map_str = loader.dump_memory_map(args.output)
            if args.dump:
                print("\n" + map_str)
        
        print("\n✓ Success")
        return 0
        
    except Exception as e:
        print(f"\n✗ Error: {e}")
        return 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
