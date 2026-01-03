"""
RV32I CPU Test Cases

Hardware validation test suite for RV32I CPU.
Each test verifies a specific instruction or CPU behavior.
"""

from dataclasses import dataclass
from typing import List, Tuple
from . import isa


@dataclass
class TestCase:
    """Single RV32I CPU test case"""
    name: str
    description: str
    program: List[int]  # List of 32-bit instructions
    expected_led: int  # Expected LED value after execution
    timeout: float = 2.0  # Max execution time
    
    def __str__(self):
        return f"{self.name}: {self.description}"


# =============================================================================
# Test Suite: ALU Operations
# =============================================================================

ALU_TESTS = [
    TestCase(
        name="ADD_BASIC",
        description="ADD: Basic addition (2+3=5)",
        program=[
            isa.ADDI('a0', 'zero', 2),      # a0 = 2
            isa.ADDI('a1', 'zero', 3),      # a1 = 3
            isa.ADD('a2', 'a0', 'a1'),      # a2 = a0 + a1 = 5
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a2', 'a3', 0x7C),       # LED = a2
            isa.EBREAK()
        ],
        expected_led=5
    ),
    
    TestCase(
        name="SUB_BASIC",
        description="SUB: Basic subtraction (7-3=4)",
        program=[
            isa.ADDI('a0', 'zero', 7),      # a0 = 7
            isa.ADDI('a1', 'zero', 3),      # a1 = 3
            isa.SUB('a2', 'a0', 'a1'),      # a2 = a0 - a1 = 4
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a2', 'a3', 0x7C),       # LED = a2
            isa.EBREAK()
        ],
        expected_led=4
    ),
    
    TestCase(
        name="AND_MASK",
        description="AND: Bit masking (0xF & 0xA = 0xA)",
        program=[
            isa.ADDI('a0', 'zero', 0xF),    # a0 = 15
            isa.ADDI('a1', 'zero', 0xA),    # a1 = 10
            isa.AND('a2', 'a0', 'a1'),      # a2 = a0 & a1 = 10
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a2', 'a3', 0x7C),       # LED = a2
            isa.EBREAK()
        ],
        expected_led=10
    ),
    
    TestCase(
        name="OR_COMBINE",
        description="OR: Bit combining (0x5 | 0xA = 0xF)",
        program=[
            isa.ADDI('a0', 'zero', 0x5),    # a0 = 5
            isa.ADDI('a1', 'zero', 0xA),    # a1 = 10
            isa.OR('a2', 'a0', 'a1'),       # a2 = a0 | a1 = 15
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a2', 'a3', 0x7C),       # LED = a2
            isa.EBREAK()
        ],
        expected_led=15
    ),
    
    TestCase(
        name="XOR_TOGGLE",
        description="XOR: Bit toggling (0xF ^ 0x6 = 0x9)",
        program=[
            isa.ADDI('a0', 'zero', 0xF),    # a0 = 15
            isa.ADDI('a1', 'zero', 0x6),    # a1 = 6
            isa.XOR('a2', 'a0', 'a1'),      # a2 = a0 ^ a1 = 9
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a2', 'a3', 0x7C),       # LED = a2
            isa.EBREAK()
        ],
        expected_led=9
    ),
    
    TestCase(
        name="SLL_SHIFT",
        description="SLL: Logical left shift (1 << 3 = 8)",
        program=[
            isa.ADDI('a0', 'zero', 1),      # a0 = 1
            isa.ADDI('a1', 'zero', 3),      # a1 = 3 (shift amount)
            isa.SLL('a2', 'a0', 'a1'),      # a2 = a0 << a1 = 8
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a2', 'a3', 0x7C),       # LED = a2
            isa.EBREAK()
        ],
        expected_led=8
    ),
    
    TestCase(
        name="SRL_SHIFT",
        description="SRL: Logical right shift (12 >> 2 = 3)",
        program=[
            isa.ADDI('a0', 'zero', 12),     # a0 = 12
            isa.ADDI('a1', 'zero', 2),      # a1 = 2 (shift amount)
            isa.SRL('a2', 'a0', 'a1'),      # a2 = a0 >> a1 = 3
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a2', 'a3', 0x7C),       # LED = a2
            isa.EBREAK()
        ],
        expected_led=3
    ),
]

# =============================================================================
# Test Suite: Immediate Operations
# =============================================================================

IMMEDIATE_TESTS = [
    TestCase(
        name="ADDI_IMM",
        description="ADDI: Add immediate (5 + 7 = 12)",
        program=[
            isa.ADDI('a0', 'zero', 5),      # a0 = 5
            isa.ADDI('a1', 'a0', 7),        # a1 = a0 + 7 = 12
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a1', 'a3', 0x7C),       # LED = a1
            isa.EBREAK()
        ],
        expected_led=12
    ),
    
    TestCase(
        name="ANDI_MASK",
        description="ANDI: AND with immediate (0xFF & 0x0F = 0x0F)",
        program=[
            isa.ADDI('a0', 'zero', 0xFF),   # a0 = 255
            isa.ANDI('a1', 'a0', 0x0F),     # a1 = a0 & 15 = 15
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a1', 'a3', 0x7C),       # LED = a1
            isa.EBREAK()
        ],
        expected_led=15
    ),
    
    TestCase(
        name="ORI_SET",
        description="ORI: OR with immediate (0x5 | 0x8 = 0xD)",
        program=[
            isa.ADDI('a0', 'zero', 0x5),    # a0 = 5
            isa.ORI('a1', 'a0', 0x8),       # a1 = a0 | 8 = 13
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a1', 'a3', 0x7C),       # LED = a1
            isa.EBREAK()
        ],
        expected_led=13
    ),
    
    TestCase(
        name="XORI_FLIP",
        description="XORI: XOR with immediate (0xF ^ 0x6 = 0x9)",
        program=[
            isa.ADDI('a0', 'zero', 0xF),    # a0 = 15
            isa.XORI('a1', 'a0', 0x6),      # a1 = a0 ^ 6 = 9
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a1', 'a3', 0x7C),       # LED = a1
            isa.EBREAK()
        ],
        expected_led=9
    ),
    
    TestCase(
        name="SLLI_SHIFT",
        description="SLLI: Shift left immediate (1 << 2 = 4)",
        program=[
            isa.ADDI('a0', 'zero', 1),      # a0 = 1
            isa.SLLI('a1', 'a0', 2),        # a1 = a0 << 2 = 4
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a1', 'a3', 0x7C),       # LED = a1
            isa.EBREAK()
        ],
        expected_led=4
    ),
]

# =============================================================================
# Test Suite: Load/Store
# =============================================================================

MEMORY_TESTS = [
    TestCase(
        name="SW_LW_BASIC",
        description="SW/LW: Store and load word",
        program=[
            isa.ADDI('a0', 'zero', 7),      # a0 = 7
            isa.SW('a0', 'zero', 0x100),    # mem[0x100] = 7
            isa.LW('a1', 'zero', 0x100),    # a1 = mem[0x100] = 7
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a1', 'a3', 0x7C),       # LED = a1
            isa.EBREAK()
        ],
        expected_led=7
    ),
    
    TestCase(
        name="SH_LH_BASIC",
        description="SH/LH: Store and load halfword",
        program=[
            isa.ADDI('a0', 'zero', 0xC),    # a0 = 12
            isa.SH('a0', 'zero', 0x200),    # mem[0x200][15:0] = 12
            isa.LH('a1', 'zero', 0x200),    # a1 = sign_extend(mem[0x200][15:0])
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a1', 'a3', 0x7C),       # LED = a1
            isa.EBREAK()
        ],
        expected_led=12
    ),
    
    TestCase(
        name="SB_LB_BASIC",
        description="SB/LB: Store and load byte",
        program=[
            isa.ADDI('a0', 'zero', 0xE),    # a0 = 14
            isa.SB('a0', 'zero', 0x300),    # mem[0x300][7:0] = 14
            isa.LB('a1', 'zero', 0x300),    # a1 = sign_extend(mem[0x300][7:0])
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a1', 'a3', 0x7C),       # LED = a1
            isa.EBREAK()
        ],
        expected_led=14
    ),
]

# =============================================================================
# Test Suite: Branch Instructions
# =============================================================================

BRANCH_TESTS = [
    TestCase(
        name="BEQ_TAKEN",
        description="BEQ: Branch if equal (taken)",
        program=[
            isa.ADDI('a0', 'zero', 5),      # a0 = 5
            isa.ADDI('a1', 'zero', 5),      # a1 = 5
            isa.BEQ('a0', 'a1', 8),         # if a0==a1, skip next instruction
            isa.ADDI('a2', 'zero', 1),      # (skipped) a2 = 1
            isa.ADDI('a2', 'zero', 6),      # a2 = 6
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a2', 'a3', 0x7C),       # LED = a2
            isa.EBREAK()
        ],
        expected_led=6
    ),
    
    TestCase(
        name="BNE_TAKEN",
        description="BNE: Branch if not equal (taken)",
        program=[
            isa.ADDI('a0', 'zero', 3),      # a0 = 3
            isa.ADDI('a1', 'zero', 7),      # a1 = 7
            isa.BNE('a0', 'a1', 8),         # if a0!=a1, skip next instruction
            isa.ADDI('a2', 'zero', 2),      # (skipped) a2 = 2
            isa.ADDI('a2', 'zero', 11),     # a2 = 11
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a2', 'a3', 0x7C),       # LED = a2
            isa.EBREAK()
        ],
        expected_led=11
    ),
]

# =============================================================================
# Test Suite: Jump Instructions
# =============================================================================

JUMP_TESTS = [
    TestCase(
        name="JAL_BASIC",
        description="JAL: Jump and link",
        program=[
            isa.JAL('ra', 12),              # Jump forward 12 bytes (3 instructions)
            isa.ADDI('a0', 'zero', 1),      # (skipped)
            isa.ADDI('a0', 'zero', 2),      # (skipped)
            isa.ADDI('a0', 'zero', 3),      # (skipped)
            isa.ADDI('a0', 'zero', 10),     # a0 = 10
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a0', 'a3', 0x7C),       # LED = a0
            isa.EBREAK()
        ],
        expected_led=10
    ),
]

# =============================================================================
# Test Suite: Upper Immediate
# =============================================================================

UPPER_IMM_TESTS = [
    TestCase(
        name="LUI_BASIC",
        description="LUI: Load upper immediate",
        program=[
            isa.LUI('a0', 0xA << 12),       # a0 = 0xA000
            isa.SRLI('a1', 'a0', 12),       # a1 = a0 >> 12 = 0xA
            isa.LUI('a3', 0x4 << 12),       # a3 = 0x4000
            isa.SW('a1', 'a3', 0x7C),       # LED = a1
            isa.EBREAK()
        ],
        expected_led=10
    ),
]

# =============================================================================
# Combined Test Suite
# =============================================================================

ALL_TESTS = (
    ALU_TESTS +
    IMMEDIATE_TESTS +
    MEMORY_TESTS +
    BRANCH_TESTS +
    JUMP_TESTS +
    UPPER_IMM_TESTS
)
