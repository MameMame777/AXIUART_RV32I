"""
TD4CPU Test Cases - Hardware Validation Suite

Based on UVM verification tests (sim/tests/axiuart_cpu_logic_test.sv)
17 ALU operation tests validated in simulation, now running on real hardware.
"""

from dataclasses import dataclass
from typing import List, Tuple
from . import isa


@dataclass
class TestCase:
    """Single CPU test case"""
    name: str
    description: str
    setup: List[Tuple[int, int]]  # [(reg_index, value), ...]
    instruction: int  # Single 16-bit instruction to execute
    expected_result: int  # Expected value in destination register
    expected_flags: int  # Expected Z, N, C flags (bits 2:0)
    
    def __str__(self):
        return f"{self.name}: {self.description}"


# ALU Test Suite (17 tests matching UVM)
ALU_TESTS = [
    # ========== Arithmetic Tests ==========
    TestCase(
        name="ADD_BASIC",
        description="ADD: Basic (1+2=3)",
        setup=[(1, 0x0001), (2, 0x0002)],
        instruction=isa.ADD(1, 2),  # R1 = R1 + R2
        expected_result=0x0003,
        expected_flags=0b000  # No flags
    ),
    
    TestCase(
        name="ADD_ZERO",
        description="ADD: Zero (0+0=0, Z=1)",
        setup=[(1, 0x0000), (2, 0x0000)],
        instruction=isa.ADD(1, 2),
        expected_result=0x0000,
        expected_flags=0b100  # Z flag
    ),
    
    TestCase(
        name="ADD_CARRY",
        description="ADD: Carry (FFFF+1=0, Z=1, C=1)",
        setup=[(1, 0xFFFF), (2, 0x0001)],
        instruction=isa.ADD(1, 2),
        expected_result=0x0000,
        expected_flags=0b101  # Z and C flags
    ),
    
    TestCase(
        name="ADD_NEGATIVE",
        description="ADD: Negative (7FFF+1=8000, N=1)",
        setup=[(1, 0x7FFF), (2, 0x0001)],
        instruction=isa.ADD(1, 2),
        expected_result=0x8000,
        expected_flags=0b010  # N flag
    ),
    
    TestCase(
        name="SUB_BASIC",
        description="SUB: Basic (5-2=3, C=1)",
        setup=[(1, 0x0005), (2, 0x0002)],
        instruction=isa.SUB(1, 2),  # R1 = R1 - R2
        expected_result=0x0003,
        expected_flags=0b001  # C flag (no borrow)
    ),
    
    TestCase(
        name="SUB_ZERO",
        description="SUB: Zero (3-3=0, Z=1, C=1)",
        setup=[(1, 0x0003), (2, 0x0003)],
        instruction=isa.SUB(1, 2),
        expected_result=0x0000,
        expected_flags=0b101  # Z and C flags
    ),
    
    TestCase(
        name="SUB_BORROW",
        description="SUB: Borrow (2-5=FFFD, N=1, C=0)",
        setup=[(1, 0x0002), (2, 0x0005)],
        instruction=isa.SUB(1, 2),
        expected_result=0xFFFD,
        expected_flags=0b010  # N flag only (borrow occurred)
    ),
    
    # ========== Logical Tests ==========
    TestCase(
        name="AND_ALTERNATING",
        description="AND: Alternating (AAAA&5555=0, Z=1)",
        setup=[(1, 0xAAAA), (2, 0x5555)],
        instruction=isa.AND_(1, 2),
        expected_result=0x0000,
        expected_flags=0b100  # Z flag
    ),
    
    TestCase(
        name="AND_ALL_ONES",
        description="AND: All Ones (FFFF&FFFF=FFFF, N=1)",
        setup=[(1, 0xFFFF), (2, 0xFFFF)],
        instruction=isa.AND_(1, 2),
        expected_result=0xFFFF,
        expected_flags=0b010  # N flag
    ),
    
    TestCase(
        name="OR_ALTERNATING",
        description="OR: Alternating (AAAA|5555=FFFF, N=1)",
        setup=[(1, 0xAAAA), (2, 0x5555)],
        instruction=isa.OR_(1, 2),
        expected_result=0xFFFF,
        expected_flags=0b010  # N flag
    ),
    
    TestCase(
        name="XOR_SELF",
        description="XOR: Self (1234^1234=0, Z=1)",
        setup=[(1, 0x1234), (2, 0x1234)],
        instruction=isa.XOR(1, 2),
        expected_result=0x0000,
        expected_flags=0b100  # Z flag
    ),
    
    # ========== Comparison Tests ==========
    TestCase(
        name="CMP_EQUAL",
        description="CMP: Equal (1234==1234, Z=1, C=1)",
        setup=[(1, 0x1234), (2, 0x1234)],
        instruction=isa.CMP(1, 2),
        expected_result=0x0000,  # CMP doesn't write result, but flags updated
        expected_flags=0b101  # Z and C flags
    ),
    
    TestCase(
        name="CMP_GREATER",
        description="CMP: Greater (1000>0100, Z=0, C=1)",
        setup=[(1, 0x1000), (2, 0x0100)],
        instruction=isa.CMP(1, 2),
        expected_result=0x0F00,  # Subtraction result (not written to reg)
        expected_flags=0b001  # C flag only
    ),
    
    TestCase(
        name="CMP_LESS",
        description="CMP: Less (0100<1000, N=1, C=0)",
        setup=[(1, 0x0100), (2, 0x1000)],
        instruction=isa.CMP(1, 2),
        expected_result=0xF100,  # Subtraction result
        expected_flags=0b010  # N flag only
    ),
    
    # ========== Shift Tests ==========
    TestCase(
        name="SHL1_BASIC",
        description="SHL1: Basic (4000<<1=8000, N=1)",
        setup=[(1, 0x4000)],
        instruction=isa.SHL1(1),
        expected_result=0x8000,
        expected_flags=0b010  # N flag
    ),
    
    TestCase(
        name="SHL1_CARRY",
        description="SHL1: Carry (8001<<1=0002, C=1)",
        setup=[(1, 0x8001)],
        instruction=isa.SHL1(1),
        expected_result=0x0002,
        expected_flags=0b001  # C flag
    ),
    
    TestCase(
        name="SHR1_BASIC",
        description="SHR1: Basic (0002>>1=0001)",
        setup=[(1, 0x0002)],
        instruction=isa.SHR1(1),
        expected_result=0x0001,
        expected_flags=0b000  # No flags
    ),
]


def get_flag_string(flags: int) -> str:
    """Convert flag bits to readable string"""
    z = 'Z' if (flags & 0b100) else '-'
    n = 'N' if (flags & 0b010) else '-'
    c = 'C' if (flags & 0b001) else '-'
    return f"{z}{n}{c}"


def format_test_result(test: TestCase, actual_result: int, actual_flags: int) -> dict:
    """
    Compare test results and return formatted output
    
    Returns:
        dict with 'passed', 'result_match', 'flags_match', 'message'
    """
    result_match = (actual_result == test.expected_result)
    flags_match = (actual_flags == test.expected_flags)
    passed = result_match and flags_match
    
    exp_flags_str = get_flag_string(test.expected_flags)
    act_flags_str = get_flag_string(actual_flags)
    
    if passed:
        msg = f"✓ PASS: Result=0x{actual_result:04X}, Flags={act_flags_str}"
    else:
        msg = f"✗ FAIL:"
        if not result_match:
            msg += f" Result: expected 0x{test.expected_result:04X}, got 0x{actual_result:04X}"
        if not flags_match:
            msg += f" Flags: expected {exp_flags_str}, got {act_flags_str}"
    
    return {
        'passed': passed,
        'result_match': result_match,
        'flags_match': flags_match,
        'message': msg,
        'expected_result': test.expected_result,
        'actual_result': actual_result,
        'expected_flags': test.expected_flags,
        'actual_flags': actual_flags
    }
