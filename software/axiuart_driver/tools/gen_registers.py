#!/usr/bin/env python3
"""
AXIUART Register Map Generator

Generates Python constants, SystemVerilog package, and Markdown documentation
from a single JSON source of truth.

Usage:
    python gen_registers.py --in register_map/axiuart_registers.json

Generated files:
    - software/axiuart_driver/registers.py
    - sim/uvm/sv/axiuart_reg_pkg.sv
    - software/axiuart_driver/REGISTER_MAP.md
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List, Any
from datetime import datetime


class RegisterMapGenerator:
    """Generate register map artifacts from JSON source"""
    
    def __init__(self, json_path: Path, workspace_root: Path = None):
        self.json_path = json_path
        self.workspace_root = workspace_root
        self.data = self._load_and_validate(json_path)
        
    def _load_and_validate(self, json_path: Path) -> Dict[str, Any]:
        """Load JSON and perform comprehensive validation"""
        if not json_path.exists():
            raise FileNotFoundError(f"Register map not found: {json_path}")
        
        with open(json_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        # Validate required top-level fields
        required_fields = ['block_name', 'base_addr', 'addr_stride_bytes', 'registers']
        for field in required_fields:
            if field not in data:
                raise ValueError(f"Missing required field: {field}")
        
        # Parse and validate base address
        try:
            base_addr = int(data['base_addr'], 16)
        except ValueError:
            raise ValueError(f"Invalid base_addr format: {data['base_addr']}")
        
        # Validate stride
        stride = data['addr_stride_bytes']
        if not isinstance(stride, int) or stride <= 0:
            raise ValueError(f"Invalid addr_stride_bytes: {stride}")
        
        # Validate registers
        registers = data['registers']
        if not isinstance(registers, list) or len(registers) == 0:
            raise ValueError("registers must be a non-empty array")
        
        seen_offsets = set()
        seen_names = set()
        
        for idx, reg in enumerate(registers):
            # Check required fields
            required_reg_fields = ['name', 'offset', 'access', 'width_bits', 'description']
            for field in required_reg_fields:
                if field not in reg:
                    raise ValueError(f"Register {idx}: missing field '{field}'")
            
            # Validate name
            name = reg['name']
            if not name or not isinstance(name, str):
                raise ValueError(f"Register {idx}: invalid name")
            if name in seen_names:
                raise ValueError(f"Duplicate register name: {name}")
            seen_names.add(name)
            
            # Validate offset
            try:
                offset = int(reg['offset'], 16)
            except ValueError:
                raise ValueError(f"Register {name}: invalid offset format: {reg['offset']}")
            
            if offset in seen_offsets:
                raise ValueError(f"Register {name}: duplicate offset {reg['offset']}")
            seen_offsets.add(offset)
            
            # Validate 32-bit alignment
            if offset % 4 != 0:
                raise ValueError(f"Register {name}: offset {reg['offset']} not 4-byte aligned")
            
            # Validate access
            if reg['access'] not in ['RO', 'RW']:
                raise ValueError(f"Register {name}: invalid access '{reg['access']}' (must be RO or RW)")
            
            # Validate width
            if reg['width_bits'] != 32:
                raise ValueError(f"Register {name}: only 32-bit registers supported (got {reg['width_bits']})")
        
        return data
    
    def _sort_registers(self) -> List[Dict[str, Any]]:
        """Sort registers by offset then name for deterministic output"""
        return sorted(
            self.data['registers'],
            key=lambda r: (int(r['offset'], 16), r['name'])
        )
    
    def generate_python(self, output_path: Path) -> None:
        """Generate Python constants module"""
        base_addr = int(self.data['base_addr'], 16)
        registers = self._sort_registers()
        
        # Compute relative path from workspace root
        if self.workspace_root:
            try:
                rel_path = self.json_path.relative_to(self.workspace_root)
                json_path_str = str(rel_path).replace('\\', '/')
            except ValueError:
                json_path_str = self.json_path.name
        else:
            json_path_str = self.json_path.name
        
        lines = [
            'r"""',
            'AXIUART Register Map',
            '',
            'AUTO-GENERATED FILE - DO NOT EDIT MANUALLY',
            f'Generated from: {json_path_str}',
            f'Generation time: {datetime.now().isoformat()}',
            '',
            'To regenerate:',
            f'    python software/axiuart_driver/tools/gen_registers.py --in {json_path_str}',
            '"""',
            '',
            '',
            f'# Register block base address',
            f'BASE_ADDR = 0x{base_addr:04X}',
            '',
            '# Register offsets (absolute addresses)',
        ]
        
        for reg in registers:
            offset = int(reg['offset'], 16)
            addr = base_addr + offset
            access = reg['access']
            desc = reg['description']
            lines.append(f"REG_{reg['name']} = 0x{addr:04X}  # {access} - {desc}")
        
        lines.append('')
        lines.append('# Register count')
        lines.append(f'REGISTER_COUNT = {len(registers)}')
        lines.append('')
        
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines))
        
        print(f"Generated Python constants: {output_path}")
    
    def generate_systemverilog(self, output_path: Path) -> None:
        """Generate SystemVerilog package"""
        base_addr = int(self.data['base_addr'], 16)
        registers = self._sort_registers()
        block_name = self.data['block_name']
        
        # Compute relative path from workspace root
        if self.workspace_root:
            try:
                rel_path = self.json_path.relative_to(self.workspace_root)
                json_path_str = str(rel_path).replace('\\', '/')
            except ValueError:
                json_path_str = self.json_path.name
        else:
            json_path_str = self.json_path.name
        
        lines = [
            '`timescale 1ns / 1ps',
            '',
            '// AXIUART Register Package',
            '//',
            '// AUTO-GENERATED FILE - DO NOT EDIT MANUALLY',
            f'// Generated from: {json_path_str}',
            f'// Generation time: {datetime.now().isoformat()}',
            '//',
            '// To regenerate:',
            f'//     python software/axiuart_driver/tools/gen_registers.py --in {json_path_str}',
            '',
            'package axiuart_reg_pkg;',
            '',
            f'    // Register block: {block_name}',
            f'    parameter int BASE_ADDR = 32\'h{base_addr:08X};',
            '',
            '    // Register offsets (absolute addresses)',
        ]
        
        for reg in registers:
            offset = int(reg['offset'], 16)
            addr = base_addr + offset
            access = reg['access']
            desc = reg['description']
            lines.append(f"    parameter int REG_{reg['name']:<12} = 32'h{addr:08X};  // {access} - {desc}")
        
        lines.append('')
        lines.append(f'    // Register count')
        lines.append(f'    parameter int REGISTER_COUNT = {len(registers)};')
        lines.append('')
        lines.append('endpackage : axiuart_reg_pkg')
        lines.append('')
        
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines))
        
        print(f"Generated SystemVerilog package: {output_path}")
    
    def generate_markdown(self, output_path: Path) -> None:
        """Generate Markdown documentation"""
        base_addr = int(self.data['base_addr'], 16)
        registers = self._sort_registers()
        block_name = self.data['block_name']
        
        # Compute relative path from workspace root
        if self.workspace_root:
            try:
                rel_path = self.json_path.relative_to(self.workspace_root)
                json_path_str = str(rel_path).replace('\\', '/')
            except ValueError:
                json_path_str = self.json_path.name
        else:
            json_path_str = self.json_path.name
        
        lines = [
            f'# {block_name} Register Map',
            '',
            '**AUTO-GENERATED FILE - DO NOT EDIT MANUALLY**',
            '',
            f'- **Source:** `{json_path_str}`',
            f'- **Generated:** {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}',
            f'- **Base Address:** `0x{base_addr:04X}`',
            f'- **Stride:** {self.data["addr_stride_bytes"]} bytes',
            '',
            '## Register Summary',
            '',
            '| Name | Address | Offset | Access | Reset | Description |',
            '|------|---------|--------|--------|-------|-------------|',
        ]
        
        for reg in registers:
            offset = int(reg['offset'], 16)
            addr = base_addr + offset
            name = reg['name']
            access = reg['access']
            reset = reg.get('reset', 'N/A')
            desc = reg['description']
            lines.append(f"| {name} | `0x{addr:04X}` | `0x{offset:03X}` | {access} | `{reset}` | {desc} |")
        
        lines.extend([
            '',
            '## Regeneration Instructions',
            '',
            'To update this file after modifying the register map:',
            '',
            '```bash',
            f'python software/axiuart_driver/tools/gen_registers.py --in {json_path_str}',
            '```',
            '',
            '## Access Types',
            '',
            '- **RO:** Read-only',
            '- **RW:** Read-write',
            ''
        ])
        
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines))
        
        print(f"Generated Markdown documentation: {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description='Generate register map artifacts from JSON source',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Example:
    python gen_registers.py --in register_map/axiuart_registers.json

This will generate:
    - software/axiuart_driver/registers.py
    - sim/uvm/sv/axiuart_reg_pkg.sv
    - software/axiuart_driver/REGISTER_MAP.md
        """
    )
    parser.add_argument(
        '--in',
        dest='input_json',
        required=True,
        help='Path to register map JSON file'
    )
    
    args = parser.parse_args()
    
    try:
        # Determine workspace root (assume script is in software/axiuart_driver/tools/)
        script_dir = Path(__file__).parent
        workspace_root = script_dir.parent.parent.parent
        
        json_path = workspace_root / args.input_json
        
        print(f"Loading register map from: {json_path}")
        generator = RegisterMapGenerator(json_path, workspace_root)
        
        # Generate all outputs
        python_output = workspace_root / 'software' / 'axiuart_driver' / 'registers.py'
        sv_output = workspace_root / 'rtl' / 'register_block' / 'axiuart_reg_pkg.sv'
        md_output = workspace_root / 'software' / 'axiuart_driver' / 'REGISTER_MAP.md'
        
        generator.generate_python(python_output)
        generator.generate_systemverilog(sv_output)
        generator.generate_markdown(md_output)
        
        print("\nAll register map artifacts generated successfully!")
        print("\nReminder: Generated files should not be edited manually.")
        print("Edit the JSON source and regenerate instead.")
        
        return 0
        
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
