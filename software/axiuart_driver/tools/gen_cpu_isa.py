#!/usr/bin/env python3
"""TD4CPU ISA Generator (SSOT)

Generates SystemVerilog constants, Python helpers, and Markdown documentation
from a single JSON source of truth.

Usage:
    python software/axiuart_driver/tools/gen_cpu_isa.py --in isa/td4cpu_isa.json

Generated files:
    - rtl/cpu/td4cpu_isa_pkg.sv
    - software/td4cpu/isa.py
    - docs/ISA.md
"""

import argparse
import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


@dataclass(frozen=True)
class Field:
    name: str
    msb: int
    lsb: int


class IsaGenerator:
    """Generate ISA artifacts from JSON source"""

    def __init__(self, json_path: Path, workspace_root: Optional[Path] = None):
        self.json_path = json_path
        self.workspace_root = workspace_root
        self.data = self._load_and_validate(json_path)

    def _json_relpath(self) -> str:
        if self.workspace_root is None:
            return self.json_path.name
        try:
            rel = self.json_path.relative_to(self.workspace_root)
            return str(rel).replace('\\', '/')
        except ValueError:
            return self.json_path.name

    def _load_and_validate(self, json_path: Path) -> Dict[str, Any]:
        if not json_path.exists():
            raise FileNotFoundError(f"ISA file not found: {json_path}")

        with open(json_path, 'r', encoding='utf-8') as f:
            data = json.load(f)

        required = ["isa_name", "isa_version", "word_bits", "formats", "enums", "instructions"]
        for key in required:
            if key not in data:
                raise ValueError(f"Missing required field: {key}")

        if data["word_bits"] != 16:
            raise ValueError("v1 generator supports only word_bits=16")

        enums = data["enums"]
        for enum_name in ["OP", "COND", "FUNCT_R", "SYSOP"]:
            if enum_name not in enums or not isinstance(enums[enum_name], dict):
                raise ValueError(f"Missing enum: {enum_name}")

        # Validate formats exist
        formats = data["formats"]
        for fmt in ["R", "I", "M", "B", "S", "X", "SYS"]:
            if fmt not in formats:
                raise ValueError(f"Missing format: {fmt}")

        # Validate instruction encodings are unique by decode key
        used: set[Tuple[Any, ...]] = set()

        def op_value(op_name_or_int: Any) -> int:
            if isinstance(op_name_or_int, str):
                return int(enums["OP"][op_name_or_int])
            return int(op_name_or_int)

        for ins in data["instructions"]:
            if "mnemonic" not in ins or "format" not in ins or "op" not in ins:
                raise ValueError(f"Invalid instruction entry (missing fields): {ins}")

            fmt = ins["format"]
            op = op_value(ins["op"])

            if fmt == "R":
                funct = enums["FUNCT_R"][ins["funct"]]
                key = ("R", op, int(funct))
            elif fmt in ["I", "M", "B", "X"]:
                key = (fmt, op)
            elif fmt == "S":
                key = ("S", op, int(ins["dir"]))
            elif fmt == "SYS":
                sysop = enums["SYSOP"][ins["sysop"]]
                key = ("SYS", op, int(sysop))
            else:
                raise ValueError(f"Unknown instruction format: {fmt}")

            if key in used:
                raise ValueError(f"Duplicate encoding key {key} for {ins['mnemonic']}")
            used.add(key)

        return data

    def _sort_enum_items(self, items: Dict[str, Any]) -> List[Tuple[str, int]]:
        # Deterministic ordering by numeric value then name
        norm = [(k, int(v)) for k, v in items.items()]
        return sorted(norm, key=lambda kv: (kv[1], kv[0]))

    def generate_systemverilog(self, output_path: Path) -> None:
        enums = self.data["enums"]
        json_path_str = self._json_relpath()

        lines: List[str] = []
        lines += ["`timescale 1ns / 1ps", ""]
        lines += [
            "// TD4CPU ISA Package",
            "//",
            "// AUTO-GENERATED FILE - DO NOT EDIT MANUALLY",
            f"// Generated from: {json_path_str}",
            f"// Generation time: {datetime.now().isoformat()}",
            "//",
            "// To regenerate:",
            f"//     python software/axiuart_driver/tools/gen_cpu_isa.py --in {json_path_str}",
            "",
            "package td4cpu_isa_pkg;",
            "",
            "    // Opcodes",
        ]

        for name, val in self._sort_enum_items(enums["OP"]):
            lines.append(f"    localparam logic [3:0] OP_{name} = 4'h{val:X};")

        lines += ["", "    // R-format funct codes"]
        for name, val in self._sort_enum_items(enums["FUNCT_R"]):
            lines.append(f"    localparam logic [5:0] FUNCT_{name} = 6'h{val:02X};")

        lines += ["", "    // Branch conditions"]
        for name, val in self._sort_enum_items(enums["COND"]):
            lines.append(f"    localparam logic [2:0] COND_{name} = 3'd{val};")

        lines += ["", "    // SYS sub-ops"]
        for name, val in self._sort_enum_items(enums["SYSOP"]):
            lines.append(f"    localparam logic [2:0] SYSOP_{name} = 3'd{val};")

        lines += ["", "endpackage : td4cpu_isa_pkg", ""]

        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write("\n".join(lines))

        print(f"Generated SystemVerilog package: {output_path}")

    def generate_python(self, output_path: Path) -> None:
        enums = self.data["enums"]
        json_path_str = self._json_relpath()

        lines: List[str] = []
        lines += [
            'r"""',
            'TD4CPU ISA',
            '',
            'AUTO-GENERATED FILE - DO NOT EDIT MANUALLY',
            f'Generated from: {json_path_str}',
            f'Generation time: {datetime.now().isoformat()}',
            '',
            'To regenerate:',
            f'    python software/axiuart_driver/tools/gen_cpu_isa.py --in {json_path_str}',
            '"""',
            '',
            'WORD_MASK = 0xFFFF',
            '',
        ]

        lines += ['# Opcodes']
        for name, val in self._sort_enum_items(enums["OP"]):
            lines.append(f'OP_{name} = 0x{val:X}')

        lines += ['', '# R funct']
        for name, val in self._sort_enum_items(enums["FUNCT_R"]):
            lines.append(f'FUNCT_{name} = 0x{val:02X}')

        lines += ['', '# Cond']
        for name, val in self._sort_enum_items(enums["COND"]):
            lines.append(f'COND_{name} = {val}')

        lines += ['', '# SYS subops']
        for name, val in self._sort_enum_items(enums["SYSOP"]):
            lines.append(f'SYSOP_{name} = {val}')

        lines += [
            '',
            'def _mask16(x: int) -> int:',
            '    return x & WORD_MASK',
            '',
            'def encode_R(op: int, rd: int, rs: int, funct: int) -> int:',
            '    return _mask16((op << 12) | ((rd & 7) << 9) | ((rs & 7) << 6) | (funct & 0x3F))',
            '',
            'def encode_I(op: int, rd: int, imm9: int) -> int:',
            '    return _mask16((op << 12) | ((rd & 7) << 9) | (imm9 & 0x1FF))',
            '',
            'def encode_M(op: int, rD: int, rB: int, off6: int) -> int:',
            '    return _mask16((op << 12) | ((rD & 7) << 9) | ((rB & 7) << 6) | (off6 & 0x3F))',
            '',
            'def encode_B(op: int, cond: int, off9: int) -> int:',
            '    return _mask16((op << 12) | ((cond & 7) << 9) | (off9 & 0x1FF))',
            '',
            'def encode_S(op: int, r: int, dir_: int) -> int:',
            '    return _mask16((op << 12) | ((r & 7) << 9) | ((dir_ & 1) << 8))',
            '',
            'def encode_SYS(op: int, sysop: int) -> int:',
            '    return _mask16((op << 12) | (sysop & 7))',
            '',
            '# Convenience wrappers (word0 only for X-format)',
            'def ADD(rd: int, rs: int) -> int: return encode_R(OP_R_ALU, rd, rs, FUNCT_ADD)',
            'def SUB(rd: int, rs: int) -> int: return encode_R(OP_R_ALU, rd, rs, FUNCT_SUB)',
            'def AND_(rd: int, rs: int) -> int: return encode_R(OP_R_ALU, rd, rs, FUNCT_AND)',
            'def OR_(rd: int, rs: int) -> int: return encode_R(OP_R_ALU, rd, rs, FUNCT_OR)',
            'def XOR(rd: int, rs: int) -> int: return encode_R(OP_R_ALU, rd, rs, FUNCT_XOR)',
            'def CMP(rd: int, rs: int) -> int: return encode_R(OP_R_ALU, rd, rs, FUNCT_CMP)',
            'def SHL1(rd: int) -> int: return encode_R(OP_R_ALU, rd, 0, FUNCT_SHL1)',
            'def SHR1(rd: int) -> int: return encode_R(OP_R_ALU, rd, 0, FUNCT_SHR1)',
            'def MOV(rd: int, rs: int) -> int: return encode_R(OP_R_ALU, rd, rs, FUNCT_MOV)',
            'def LDI(rd: int, imm9: int) -> int: return encode_I(OP_LDI, rd, imm9)',
            'def ADDI(rd: int, imm9: int) -> int: return encode_I(OP_ADDI, rd, imm9)',
            'def LD(rD: int, rB: int, off6: int) -> int: return encode_M(OP_LD, rD, rB, off6)',
            'def ST(rD: int, rB: int, off6: int) -> int: return encode_M(OP_ST, rD, rB, off6)',
            'def BR(cond: int, off9: int) -> int: return encode_B(OP_BR, cond, off9)',
            'def RET() -> int: return encode_SYS(OP_SYS, SYSOP_RET)',
            'def BRK() -> int: return encode_SYS(OP_SYS, SYSOP_BRK)',
            'def PUSH(r: int) -> int: return encode_S(OP_STACK, r, 0)',
            'def POP(r: int) -> int: return encode_S(OP_STACK, r, 1)',
            'def JMP16_WORD0() -> int: return _mask16(OP_JMP16 << 12)',
            'def CALL16_WORD0() -> int: return _mask16(OP_CALL16 << 12)',
            '',
        ]

        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write("\n".join(lines))

        print(f"Generated Python module: {output_path}")

    def generate_markdown(self, output_path: Path) -> None:
        json_path_str = self._json_relpath()
        ts = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

        lines: List[str] = []
        lines += [
            '# TD4CPU ISA (AUTO-GENERATED)',
            '',
            '**AUTO-GENERATED FILE - DO NOT EDIT MANUALLY**',
            '',
            f'- Source: {json_path_str}',
            f'- Generated: {ts}',
            '',
            '## Opcodes',
            '',
            '| Name | Value |',
            '|------|-------|',
        ]

        for name, val in self._sort_enum_items(self.data['enums']['OP']):
            lines.append(f'| {name} | 0x{val:X} |')

        lines += [
            '',
            '## R-format funct',
            '',
            '| Mnemonic | funct |',
            '|----------|-------|',
        ]
        for name, val in self._sort_enum_items(self.data['enums']['FUNCT_R']):
            lines.append(f'| {name} | 0x{val:02X} |')

        lines += [
            '',
            '## Branch conditions',
            '',
            '| Cond | Value |',
            '|------|-------|',
        ]
        for name, val in self._sort_enum_items(self.data['enums']['COND']):
            lines.append(f'| {name} | {val} |')

        lines += [
            '',
            '## Instruction list',
            '',
            '| Mnemonic | Format | Words | Operands |',
            '|----------|--------|-------|----------|',
        ]
        for ins in self.data['instructions']:
            ops = ', '.join(ins.get('operands', []))
            lines.append(f"| {ins['mnemonic']} | {ins['format']} | {ins['length_words']} | {ops} |")

        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write("\n".join(lines) + "\n")

        print(f"Generated Markdown: {output_path}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='in_path', required=True)
    args = ap.parse_args()

    workspace_root = Path(__file__).resolve().parents[3]
    gen = IsaGenerator(Path(args.in_path), workspace_root=workspace_root)

    gen.generate_systemverilog(workspace_root / 'rtl' / 'cpu' / 'td4cpu_isa_pkg.sv')
    gen.generate_python(workspace_root / 'software' / 'td4cpu' / 'isa.py')
    gen.generate_markdown(workspace_root / 'docs' / 'ISA.md')


if __name__ == '__main__':
    main()
