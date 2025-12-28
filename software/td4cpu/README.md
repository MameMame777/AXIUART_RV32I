# TD4CPU Hardware Test Runner

Real hardware validation tool for TD4 CPU via UART interface.

## Overview

This tool validates TD4 CPU functionality on real hardware by executing the same 17 ALU tests that passed UVM simulation. Results are displayed in a colorful console with real-time status updates.

## Features

- ✓ 17 ALU operation tests (ADD, SUB, AND, OR, XOR, CMP, SHL1, SHR1)
- ✓ Register setup and verification
- ✓ Flag checking (Zero, Negative, Carry)
- ✓ Single-step instruction execution
- ✓ Colorful console output with progress tracking
- ✓ Detailed pass/fail reporting
- ✓ Compatible with Windows (COM ports) and Linux (/dev/ttyUSB)

## Installation

```bash
# Install dependencies
pip install pyserial

# Ensure axiuart_driver is available
cd software/axiuart_driver
pip install -e .
```

## Usage

### Basic Usage

```bash
# Windows
python cpu_test_runner.py --port COM3

# Linux
python cpu_test_runner.py --port /dev/ttyUSB0
```

### Advanced Options

```bash
# Custom baud rate
python cpu_test_runner.py --port COM3 --baudrate 115200

# Verbose mode (shows UART protocol details)
python cpu_test_runner.py --port COM3 --verbose

# Custom timeout
python cpu_test_runner.py --port COM3 --timeout 3.0
```

## Expected Output

```
======================================================================
TD4 CPU Hardware Validation Suite
17 ALU Tests (validated in UVM simulation)
======================================================================

[1/17] ADD_BASIC
    ADD: Basic (1+2=3)
    Setup: R1 = 0x0001
    Setup: R2 = 0x0002
    Instruction: 0x0440
    ✓ PASS: Result=0x0003, Flags=---

[2/17] ADD_ZERO
    ADD: Zero (0+0=0, Z=1)
    Setup: R1 = 0x0000
    Setup: R2 = 0x0000
    Instruction: 0x0440
    ✓ PASS: Result=0x0000, Flags=Z--

...

======================================================================
Test Summary
======================================================================
Total Tests:  17
Passed:       17
Failed:       0
Elapsed Time: 3.42s

*** ALL TESTS PASSED ***
```

## Test Cases

All tests are defined in `test_cases.py`:

### Arithmetic Tests
- ADD_BASIC: 1 + 2 = 3
- ADD_ZERO: 0 + 0 = 0 (Z flag)
- ADD_CARRY: 0xFFFF + 1 = 0 (Z, C flags)
- ADD_NEGATIVE: 0x7FFF + 1 = 0x8000 (N flag)
- SUB_BASIC: 5 - 2 = 3 (C flag)
- SUB_ZERO: 3 - 3 = 0 (Z, C flags)
- SUB_BORROW: 2 - 5 = 0xFFFD (N flag, no C)

### Logical Tests
- AND_ALTERNATING: 0xAAAA & 0x5555 = 0 (Z flag)
- AND_ALL_ONES: 0xFFFF & 0xFFFF = 0xFFFF (N flag)
- OR_ALTERNATING: 0xAAAA | 0x5555 = 0xFFFF (N flag)
- XOR_SELF: 0x1234 ^ 0x1234 = 0 (Z flag)

### Comparison Tests
- CMP_EQUAL: 0x1234 == 0x1234 (Z, C flags)
- CMP_GREATER: 0x1000 > 0x0100 (C flag)
- CMP_LESS: 0x0100 < 0x1000 (N flag)

### Shift Tests
- SHL1_BASIC: 0x4000 << 1 = 0x8000 (N flag)
- SHL1_CARRY: 0x8001 << 1 = 0x0002 (C flag)
- SHR1_BASIC: 0x0002 >> 1 = 0x0001

## Architecture

```
cpu_test_runner.py (Main Test Runner)
    │
    ├── test_cases.py (17 Test Definitions)
    │   └── TestCase dataclass (setup, instruction, expected results)
    │
    ├── isa.py (Instruction Encoder)
    │   └── ADD(), SUB(), CMP(), etc.
    │
    └── axiuart_driver/ (UART Communication)
        ├── protocol.py (Frame encoding/decoding)
        └── registers.py (Register map)
```

## Test Flow

For each test:
1. **Reset CPU** - Clear all state
2. **Setup Registers** - Load initial values (R0-R7)
3. **Load Instruction** - Write single instruction to memory address 0
4. **Execute** - Single-step execution via CPU_CONTROL register
5. **Read Results** - Read destination register and flags
6. **Verify** - Compare actual vs. expected values
7. **Report** - Display pass/fail with color coding

## Troubleshooting

### Port Access Denied
```bash
# Windows: Run as administrator
# Linux: Add user to dialout group
sudo usermod -a -G dialout $USER
```

### Connection Timeout
- Check UART cable connection
- Verify FPGA bitstream is loaded
- Try lower baud rate: `--baudrate 9600`

### All Tests Fail
- Verify CPU is not stuck in reset
- Check register base addresses match RTL
- Enable verbose mode: `--verbose`

## Related Files

- `test_cases.py` - 17 test case definitions
- `isa.py` - TD4 instruction set encoding (auto-generated)
- `../axiuart_driver/` - UART protocol implementation
- `../../register_map/axiuart_registers.json` - Register address definitions
- `../../sim/tests/axiuart_cpu_logic_test.sv` - Original UVM test (simulation)

## Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed or fatal error occurred
