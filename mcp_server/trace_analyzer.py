#!/usr/bin/env python3
"""
RV32I Extended Trace Analyzer
==============================
Automated bug detection tool for RV32I CPU trace logs.
Analyzes extended CSV trace format with operand values and forwarding control.

Features:
- Parse extended CSV trace format (15 columns)
- Calculate expected ALU results based on operands
- Compare actual vs expected rd_value
- Detect forwarding anomalies
- Flag suspicious patterns (zeros, garbage values)
- Generate HTML bug report

Author: GitHub Copilot
Date: 2026-01-11
"""

import csv
import sys
import argparse
from typing import List, Dict, Tuple, Optional
from dataclasses import dataclass
from enum import Enum


class ForwardSource(Enum):
    """Forwarding source enumeration"""
    RF = "RF"    # Register file
    EX = "EX"    # EX stage forward
    MEM = "MEM"  # MEM stage forward
    WB = "WB"    # WB stage forward


@dataclass
class TraceEntry:
    """Extended trace entry with all debug fields"""
    line_num: int
    pc: int
    encoding: int
    instruction: str
    operands: str
    rd: int
    rd_value: int
    rs1: int
    rs1_value: int
    rs2: int
    rs2_value: int
    fwd_rs1: ForwardSource
    fwd_rs2: ForwardSource
    stall: int
    flush: int
    timestamp: int
    
    @property
    def opcode(self) -> int:
        return self.encoding & 0x7F
    
    @property
    def funct3(self) -> int:
        return (self.encoding >> 12) & 0x7
    
    @property
    def funct7(self) -> int:
        return (self.encoding >> 25) & 0x7F
    
    def is_rtype(self) -> bool:
        """Check if instruction is R-type ALU"""
        return self.opcode == 0x33
    
    def is_itype_alu(self) -> bool:
        """Check if instruction is I-type ALU"""
        return self.opcode == 0x13
    
    def is_load(self) -> bool:
        """Check if instruction is load"""
        return self.opcode == 0x03
    
    def is_store(self) -> bool:
        """Check if instruction is store"""
        return self.opcode == 0x23
    
    def is_branch(self) -> bool:
        """Check if instruction is branch"""
        return self.opcode == 0x63
    
    def is_lui(self) -> bool:
        """Check if instruction is LUI"""
        return self.opcode == 0x37
    
    def is_auipc(self) -> bool:
        """Check if instruction is AUIPC"""
        return self.opcode == 0x17
    
    def is_jal(self) -> bool:
        """Check if instruction is JAL"""
        return self.opcode == 0x6F
    
    def is_jalr(self) -> bool:
        """Check if instruction is JALR"""
        return self.opcode == 0x67


class BugType(Enum):
    """Bug classification"""
    CRITICAL = "CRITICAL"
    MAJOR = "MAJOR"
    MINOR = "MINOR"
    WARNING = "WARNING"


@dataclass
class Bug:
    """Bug report entry"""
    line_num: int
    bug_type: BugType
    category: str
    message: str
    expected: Optional[int] = None
    actual: Optional[int] = None
    trace_entry: Optional[TraceEntry] = None


class TraceAnalyzer:
    """Main trace analyzer class"""
    
    def __init__(self, trace_file: str):
        self.trace_file = trace_file
        self.trace: List[TraceEntry] = []
        self.bugs: List[Bug] = []
        
    def parse_trace(self) -> None:
        """Parse extended CSV trace file"""
        with open(self.trace_file, 'r') as f:
            reader = csv.reader(f)
            header = next(reader)
            
            # Verify header format
            expected_header = ["#", "PC", "Encoding", "Instruction", "Operands", "rd", "rd_value",
                             "rs1", "rs1_val", "rs2", "rs2_val", "fwd_rs1", "fwd_rs2", "stall", "flush", "Time_ps"]
            if header != expected_header:
                print(f"Warning: Unexpected CSV header")
                print(f"Expected: {expected_header}")
                print(f"Got: {header}")
            
            for row in reader:
                if len(row) < 16:
                    continue
                    
                try:
                    entry = TraceEntry(
                        line_num=int(row[0]),
                        pc=int(row[1], 16),
                        encoding=int(row[2], 16),
                        instruction=row[3],
                        operands=row[4].strip('"'),
                        rd=int(row[5].replace('x', '')),
                        rd_value=int(row[6], 16),
                        rs1=int(row[7].replace('x', '')),
                        rs1_value=int(row[8], 16),
                        rs2=int(row[9].replace('x', '')),
                        rs2_value=int(row[10], 16),
                        fwd_rs1=ForwardSource(row[11]),
                        fwd_rs2=ForwardSource(row[12]),
                        stall=int(row[13]),
                        flush=int(row[14]),
                        timestamp=int(row[15])
                    )
                    self.trace.append(entry)
                except Exception as e:
                    print(f"Warning: Failed to parse line {row[0]}: {e}")
    
    def calculate_alu_result(self, entry: TraceEntry) -> Optional[int]:
        """Calculate expected ALU result for R-type and I-type instructions"""
        if not (entry.is_rtype() or entry.is_itype_alu()):
            return None
        
        rs1 = self.to_signed32(entry.rs1_value)
        rs2 = self.to_signed32(entry.rs2_value) if entry.is_rtype() else self.get_i_immediate(entry.encoding)
        
        funct3 = entry.funct3
        funct7 = entry.funct7
        
        result = None
        
        # ADD / ADDI
        if funct3 == 0x0:
            if entry.is_rtype() and funct7 == 0x20:
                result = rs1 - rs2  # SUB
            else:
                result = rs1 + rs2  # ADD / ADDI
        
        # SLT / SLTI (signed comparison)
        elif funct3 == 0x2:
            result = 1 if rs1 < rs2 else 0
        
        # SLTU / SLTIU (unsigned comparison)
        elif funct3 == 0x3:
            urs1 = entry.rs1_value
            urs2 = entry.rs2_value if entry.is_rtype() else (rs2 & 0xFFFFFFFF)
            result = 1 if urs1 < urs2 else 0
        
        # XOR / XORI
        elif funct3 == 0x4:
            result = rs1 ^ rs2
        
        # OR / ORI
        elif funct3 == 0x6:
            result = rs1 | rs2
        
        # AND / ANDI
        elif funct3 == 0x7:
            result = rs1 & rs2
        
        # SLL / SLLI (logical left shift)
        elif funct3 == 0x1:
            shamt = rs2 & 0x1F
            result = (entry.rs1_value << shamt) & 0xFFFFFFFF
        
        # SRL / SRLI / SRA / SRAI (logical/arithmetic right shift)
        elif funct3 == 0x5:
            shamt = rs2 & 0x1F
            if (entry.is_rtype() and funct7 == 0x20) or (entry.is_itype_alu() and (entry.encoding & 0x40000000)):
                # SRA / SRAI (arithmetic)
                result = rs1 >> shamt
            else:
                # SRL / SRLI (logical)
                result = entry.rs1_value >> shamt
        
        return result & 0xFFFFFFFF if result is not None else None
    
    @staticmethod
    def to_signed32(value: int) -> int:
        """Convert 32-bit unsigned to signed"""
        if value & 0x80000000:
            return value - 0x100000000
        return value
    
    @staticmethod
    def get_i_immediate(encoding: int) -> int:
        """Extract I-type immediate (sign-extended)"""
        imm = (encoding >> 20) & 0xFFF
        if imm & 0x800:
            imm -= 0x1000
        return imm
    
    def analyze_entry(self, entry: TraceEntry) -> None:
        """Analyze single trace entry for bugs"""
        
        # Skip x0 writes (always zero)
        if entry.rd == 0:
            return
        
        # Check for ALU result mismatch
        expected = self.calculate_alu_result(entry)
        if expected is not None:
            if entry.rd_value != expected:
                self.bugs.append(Bug(
                    line_num=entry.line_num,
                    bug_type=BugType.CRITICAL,
                    category="ALU_MISMATCH",
                    message=f"{entry.instruction}: Expected x{entry.rd}=0x{expected:08X}, got 0x{entry.rd_value:08X}",
                    expected=expected,
                    actual=entry.rd_value,
                    trace_entry=entry
                ))
        
        # Check for zero result on non-zero operands (suspicious)
        if entry.is_rtype() or entry.is_itype_alu():
            if entry.rd_value == 0 and entry.rs1_value != 0:
                # Check if this is a valid zero result (e.g., SUB equal values)
                if not (entry.instruction == "SUB" and entry.rs1_value == entry.rs2_value):
                    if "AND" not in entry.instruction:  # AND can legitimately produce zero
                        self.bugs.append(Bug(
                            line_num=entry.line_num,
                            bug_type=BugType.MAJOR,
                            category="SUSPICIOUS_ZERO",
                            message=f"{entry.instruction}: Result is zero with non-zero operands (rs1=0x{entry.rs1_value:08X}, rs2=0x{entry.rs2_value:08X})",
                            trace_entry=entry
                        ))
        
        # Check for garbage values (high entropy, unexpected patterns)
        if self.is_garbage_value(entry.rd_value) and entry.instruction not in ["LUI", "AUIPC"]:
            self.bugs.append(Bug(
                line_num=entry.line_num,
                bug_type=BugType.MAJOR,
                category="GARBAGE_VALUE",
                message=f"{entry.instruction}: Suspicious garbage result 0x{entry.rd_value:08X}",
                trace_entry=entry
            ))
        
        # Check forwarding consistency
        if entry.rs1 != 0:  # Skip x0
            prev_writers = self.find_previous_writers(entry.line_num, entry.rs1, lookback=3)
            if prev_writers and entry.fwd_rs1 == ForwardSource.RF:
                self.bugs.append(Bug(
                    line_num=entry.line_num,
                    bug_type=BugType.WARNING,
                    category="FORWARDING_ANOMALY",
                    message=f"{entry.instruction}: rs1=x{entry.rs1} should forward from recent writer (line {prev_writers[0]}), but using RF",
                    trace_entry=entry
                ))
    
    def is_garbage_value(self, value: int) -> bool:
        """Detect garbage values with high bit entropy"""
        if value == 0:
            return False
        # Check for alternating bit patterns or high entropy
        hex_str = f"{value:08X}"
        unique_chars = len(set(hex_str))
        # Garbage values often have high entropy (many unique hex digits)
        return unique_chars >= 6 and value > 0xF0000000
    
    def find_previous_writers(self, current_line: int, register: int, lookback: int = 3) -> List[int]:
        """Find previous instructions that wrote to register"""
        writers = []
        for i in range(len(self.trace) - 1, -1, -1):
            entry = self.trace[i]
            if entry.line_num >= current_line:
                continue
            if entry.rd == register and entry.rd != 0:
                writers.append(entry.line_num)
                if len(writers) >= lookback:
                    break
        return writers
    
    def analyze_all(self) -> None:
        """Analyze entire trace"""
        print(f"Analyzing {len(self.trace)} trace entries...")
        for entry in self.trace:
            self.analyze_entry(entry)
        print(f"Found {len(self.bugs)} potential bugs")
    
    def generate_report(self, output_file: str = "trace_analysis_report.html") -> None:
        """Generate HTML bug report"""
        critical = [b for b in self.bugs if b.bug_type == BugType.CRITICAL]
        major = [b for b in self.bugs if b.bug_type == BugType.MAJOR]
        minor = [b for b in self.bugs if b.bug_type == BugType.MINOR]
        warnings = [b for b in self.bugs if b.bug_type == BugType.WARNING]
        
        html = f"""<!DOCTYPE html>
<html>
<head>
    <title>RV32I Trace Analysis Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; }}
        h1 {{ color: #333; }}
        h2 {{ color: #666; margin-top: 30px; }}
        .summary {{ background: #f0f0f0; padding: 15px; border-radius: 5px; margin: 20px 0; }}
        .bug {{ border-left: 4px solid #ccc; padding: 10px; margin: 10px 0; background: #fafafa; }}
        .critical {{ border-left-color: #d32f2f; }}
        .major {{ border-left-color: #f57c00; }}
        .minor {{ border-left-color: #fbc02d; }}
        .warning {{ border-left-color: #0288d1; }}
        .code {{ font-family: monospace; background: #eee; padding: 2px 4px; }}
        table {{ border-collapse: collapse; width: 100%; margin: 10px 0; }}
        th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
        th {{ background: #333; color: white; }}
    </style>
</head>
<body>
    <h1>RV32I Trace Analysis Report</h1>
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Trace file:</strong> {self.trace_file}</p>
        <p><strong>Total instructions:</strong> {len(self.trace)}</p>
        <p><strong>Total bugs found:</strong> {len(self.bugs)}</p>
        <ul>
            <li>Critical: {len(critical)}</li>
            <li>Major: {len(major)}</li>
            <li>Minor: {len(minor)}</li>
            <li>Warnings: {len(warnings)}</li>
        </ul>
    </div>
"""
        
        for bug_list, title, css_class in [(critical, "Critical Bugs", "critical"),
                                             (major, "Major Issues", "major"),
                                             (minor, "Minor Issues", "minor"),
                                             (warnings, "Warnings", "warning")]:
            if bug_list:
                html += f"<h2>{title} ({len(bug_list)})</h2>\n"
                for bug in bug_list:
                    html += f'<div class="bug {css_class}">\n'
                    html += f'<strong>Line {bug.line_num}:</strong> [{bug.category}] {bug.message}<br>\n'
                    if bug.expected is not None and bug.actual is not None:
                        html += f'Expected: <span class="code">0x{bug.expected:08X}</span>, '
                        html += f'Actual: <span class="code">0x{bug.actual:08X}</span><br>\n'
                    if bug.trace_entry:
                        e = bug.trace_entry
                        html += f'<details><summary>Trace Details</summary>\n'
                        html += f'<table>\n'
                        html += f'<tr><th>Field</th><th>Value</th></tr>\n'
                        html += f'<tr><td>PC</td><td class="code">0x{e.pc:08X}</td></tr>\n'
                        html += f'<tr><td>Instruction</td><td class="code">{e.instruction} {e.operands}</td></tr>\n'
                        html += f'<tr><td>rs1</td><td class="code">x{e.rs1} = 0x{e.rs1_value:08X} [{e.fwd_rs1.value}]</td></tr>\n'
                        html += f'<tr><td>rs2</td><td class="code">x{e.rs2} = 0x{e.rs2_value:08X} [{e.fwd_rs2.value}]</td></tr>\n'
                        html += f'<tr><td>rd</td><td class="code">x{e.rd} = 0x{e.rd_value:08X}</td></tr>\n'
                        html += f'<tr><td>Flags</td><td class="code">stall={e.stall} flush={e.flush}</td></tr>\n'
                        html += f'</table></details>\n'
                    html += '</div>\n'
        
        html += """
</body>
</html>
"""
        
        with open(output_file, 'w') as f:
            f.write(html)
        print(f"HTML report generated: {output_file}")


def main():
    parser = argparse.ArgumentParser(description="RV32I Extended Trace Analyzer")
    parser.add_argument("trace_file", help="Extended CSV trace file to analyze")
    parser.add_argument("-o", "--output", default="trace_analysis_report.html",
                       help="Output HTML report file (default: trace_analysis_report.html)")
    parser.add_argument("-v", "--verbose", action="store_true",
                       help="Verbose output")
    
    args = parser.parse_args()
    
    analyzer = TraceAnalyzer(args.trace_file)
    analyzer.parse_trace()
    analyzer.analyze_all()
    analyzer.generate_report(args.output)
    
    # Print summary to console
    print("\n" + "="*60)
    print("ANALYSIS SUMMARY")
    print("="*60)
    critical = len([b for b in analyzer.bugs if b.bug_type == BugType.CRITICAL])
    major = len([b for b in analyzer.bugs if b.bug_type == BugType.MAJOR])
    minor = len([b for b in analyzer.bugs if b.bug_type == BugType.MINOR])
    warnings = len([b for b in analyzer.bugs if b.bug_type == BugType.WARNING])
    
    print(f"Critical: {critical}")
    print(f"Major:    {major}")
    print(f"Minor:    {minor}")
    print(f"Warnings: {warnings}")
    print(f"Total:    {len(analyzer.bugs)}")
    print("="*60)
    
    if critical > 0:
        print("\n⚠️  CRITICAL BUGS DETECTED - Immediate attention required")
        for bug in [b for b in analyzer.bugs if b.bug_type == BugType.CRITICAL][:5]:
            print(f"  Line {bug.line_num}: {bug.message}")
    
    return 0 if critical == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
