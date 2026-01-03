# RV32I CPU Python Driver

Complete Python driver package for hardware control and validation of the RV32I CPU over UART/AXI4-Lite bridge.

## Features

- **Full RV32I ISA Encoder**: All 40 base integer instructions + common pseudo-instructions
- **Hardware Control**: CPU halt/run, reset, breakpoint detection
- **Memory Access**: Word-aligned and byte-granular read/write
- **Program Loading**: Binary and instruction list formats
- **Comprehensive Test Suite**: 20+ hardware-validated test cases
- **Debug MMIO**: LED register access for visual feedback
- **Automated Test Runner**: Colorful console output with pass/fail tracking

## Architecture

```
RV32I CPU (5-stage pipeline)
    ↕ Debug Interface (halt/run, memory access, breakpoint)
AXIUART Register Block
    ↕ AXI4-Lite Master
UART Rx/Tx (115200 baud default)
    ↕ USB UART Bridge
Python Driver (this package)
```

## Quick Start

### 1. Installation

```bash
# Install dependencies
pip install pyserial

# Add to Python path
export PYTHONPATH="${PYTHONPATH}:/path/to/TD4UART/software"
```

### 2. Quick Hardware Test

```python
from rv32i import RV32ICPUDriver

# Open connection
driver = RV32ICPUDriver('COM3')  # or '/dev/ttyUSB0' on Linux
driver.open()

# Run quick test (4 instructions, LED=5)
driver.quick_test()

# Close
driver.close()
```

### 3. Run Full Test Suite

```bash
# Run all 20+ tests
python cpu_test_runner.py --port COM3

# Run specific suite
python cpu_test_runner.py --port COM3 --suite alu
python cpu_test_runner.py --port COM3 --suite mem
```

## API Reference

### RV32ICPUDriver Class

#### Initialization
```python
driver = RV32ICPUDriver(
    port='COM3',           # Serial port
    baudrate=115200,       # UART baud rate
    timeout=2.0            # Communication timeout (seconds)
)
driver.open()
```

#### CPU Control
```python
driver.halt_cpu()                    # Halt CPU execution
driver.run_cpu()                     # Resume CPU execution
driver.reset_cpu()                   # Reset CPU state
driver.is_halted()                   # Check if CPU is halted (bool)
driver.is_break()                    # Check if breakpoint hit (bool)
driver.wait_for_breakpoint(timeout=5.0)  # Wait for EBREAK
```

#### Memory Access (Word-Aligned)
```python
# Write 32-bit word to address
driver.write_memory_word(addr=0x0000, data=0x12345678)

# Read 32-bit word from address
value = driver.read_memory_word(addr=0x0000)
```

#### Memory Access (Byte-Granular)
```python
# Write bytes to address (any length, any alignment)
driver.write_memory_bytes(addr=0x0001, data=b'\x12\x34\x56')

# Read bytes from address
data = driver.read_memory_bytes(addr=0x0001, length=3)
```

#### Program Loading
```python
from rv32i.isa import *

# Load instruction list
program = [
    ADDI('x10', 'x0', 5),    # x10 = 5
    ADDI('x11', 'x0', 3),    # x11 = 3
    ADD('x12', 'x10', 'x11'), # x12 = x10 + x11 = 8
    EBREAK()                  # Halt
]
driver.load_program(program)

# Load binary file (little-endian words)
driver.load_binary('firmware.bin')
```

#### Memory Dump
```python
# Dump memory region (formatted hex output)
driver.dump_memory(start_addr=0x0000, length=64)
```

#### MMIO Access
```python
# Write LED register (4-bit value)
driver.write_led(0xA)

# Read LED register
value = driver.read_led()
```

## ISA Module (rv32i.isa)

### Instruction Encoding

All 40 RV32I instructions supported:

**ALU Operations:**
```python
ADD('x3', 'x1', 'x2')    # x3 = x1 + x2
SUB('x3', 'x1', 'x2')    # x3 = x1 - x2
AND('x3', 'x1', 'x2')    # x3 = x1 & x2
OR('x3', 'x1', 'x2')     # x3 = x1 | x2
XOR('x3', 'x1', 'x2')    # x3 = x1 ^ x2
SLL('x3', 'x1', 'x2')    # x3 = x1 << x2
SRL('x3', 'x1', 'x2')    # x3 = x1 >> x2 (logical)
SRA('x3', 'x1', 'x2')    # x3 = x1 >> x2 (arithmetic)
SLT('x3', 'x1', 'x2')    # x3 = (x1 < x2) ? 1 : 0 (signed)
SLTU('x3', 'x1', 'x2')   # x3 = (x1 < x2) ? 1 : 0 (unsigned)
```

**Immediate Operations:**
```python
ADDI('x2', 'x1', 100)    # x2 = x1 + 100
ANDI('x2', 'x1', 0xFF)   # x2 = x1 & 0xFF
ORI('x2', 'x1', 0x10)    # x2 = x1 | 0x10
XORI('x2', 'x1', -1)     # x2 = x1 ^ -1 (invert)
SLTI('x2', 'x1', 10)     # x2 = (x1 < 10) ? 1 : 0
SLTIU('x2', 'x1', 10)    # x2 = (x1 < 10) ? 1 : 0 (unsigned)
SLLI('x2', 'x1', 5)      # x2 = x1 << 5
SRLI('x2', 'x1', 5)      # x2 = x1 >> 5 (logical)
SRAI('x2', 'x1', 5)      # x2 = x1 >> 5 (arithmetic)
```

**Upper Immediate:**
```python
LUI('x2', 0x12345)       # x2 = 0x12345000
AUIPC('x2', 0x1000)      # x2 = PC + 0x1000000
```

**Load/Store:**
```python
LW('x2', 'x1', 0)        # x2 = mem[x1+0] (word)
LH('x2', 'x1', 0)        # x2 = mem[x1+0] (halfword, sign-extend)
LB('x2', 'x1', 0)        # x2 = mem[x1+0] (byte, sign-extend)
LHU('x2', 'x1', 0)       # x2 = mem[x1+0] (halfword, zero-extend)
LBU('x2', 'x1', 0)       # x2 = mem[x1+0] (byte, zero-extend)

SW('x2', 'x1', 0)        # mem[x1+0] = x2 (word)
SH('x2', 'x1', 0)        # mem[x1+0] = x2 (halfword)
SB('x2', 'x1', 0)        # mem[x1+0] = x2 (byte)
```

**Branch:**
```python
BEQ('x1', 'x2', 16)      # if (x1 == x2) PC += 16
BNE('x1', 'x2', 16)      # if (x1 != x2) PC += 16
BLT('x1', 'x2', 16)      # if (x1 < x2) PC += 16 (signed)
BGE('x1', 'x2', 16)      # if (x1 >= x2) PC += 16 (signed)
BLTU('x1', 'x2', 16)     # if (x1 < x2) PC += 16 (unsigned)
BGEU('x1', 'x2', 16)     # if (x1 >= x2) PC += 16 (unsigned)
```

**Jump:**
```python
JAL('x1', 20)            # x1 = PC+4; PC += 20
JALR('x1', 'x2', 0)      # x1 = PC+4; PC = x2 + 0
```

**System:**
```python
ECALL()                  # Environment call
EBREAK()                 # Breakpoint (used for test completion)
FENCE()                  # Memory fence
```

### Pseudo-Instructions
```python
NOP()                    # No operation (ADDI x0, x0, 0)
MV('x2', 'x1')          # Copy register (ADDI x2, x1, 0)
NOT('x2', 'x1')         # Bitwise NOT (XORI x2, x1, -1)
NEG('x2', 'x1')         # Negate (SUB x2, x0, x1)
LI('x2', 12345)         # Load immediate (LUI + ADDI)
J(offset)               # Jump (JAL x0, offset)
JR('x1')                # Jump register (JALR x0, x1, 0)
RET()                   # Return (JALR x0, x1, 0)
```

### Register Names

Both numeric (x0-x31) and ABI names supported:
```python
# Equivalent
ADDI('x10', 'x0', 5)
ADDI('a0', 'zero', 5)

# ABI names
zero = x0   # Hard-wired zero
ra = x1     # Return address
sp = x2     # Stack pointer
gp = x3     # Global pointer
tp = x4     # Thread pointer
t0-t6       # Temporaries
s0-s11      # Saved registers
a0-a7       # Arguments/return values
```

## Test Suite

### Test Categories

**ALU Tests (7 tests):**
- ADD, SUB, AND, OR, XOR, SLL, SRL

**Immediate Tests (5 tests):**
- ADDI, ANDI, ORI, XORI, SLLI

**Memory Tests (3 tests):**
- SW/LW (word access)
- SH/LH (halfword access)
- SB/LB (byte access)

**Branch Tests (2 tests):**
- BEQ (branch if equal)
- BNE (branch if not equal)

**Jump Tests (1 test):**
- JAL (jump and link)

**Upper Immediate Tests (1 test):**
- LUI (load upper immediate)

### Test Structure

Each test:
1. Loads instruction sequence into memory
2. Runs CPU from address 0
3. Waits for EBREAK (breakpoint)
4. Reads LED register for result
5. Compares with expected value

Example test:
```python
TestCase(
    name="ADD Test",
    description="Basic addition: 5 + 3 = 8",
    program=[
        ADDI('x10', 'x0', 5),     # x10 = 5
        ADDI('x11', 'x0', 3),     # x11 = 3
        ADD('x12', 'x10', 'x11'),  # x12 = 5 + 3 = 8
        SW('x12', 'x0', 0x407C),   # LED = x12
        EBREAK()                   # Halt
    ],
    expected_led=8,
    timeout=1.0
)
```

## Hardware Requirements

**FPGA Configuration:**
- Xilinx Zynq-7020 (or compatible)
- RV32I CPU core synthesized and running
- AXIUART bridge configured (115200 baud)
- USB UART cable connected to programming port

**Memory Map:**
- RAM: 0x0000_0000 - 0x0000_1FFF (8KB)
- MMIO: 0x0000_4000 - 0x0000_4FFF
  - LED Register: 0x0000_407C (4-bit output)

**Debug Interface:**
- CPU must be halted before memory access
- EBREAK instruction triggers breakpoint flag
- Trace buffer captures last 64 instructions

## Examples

### Example 1: Simple Arithmetic
```python
from rv32i import RV32ICPUDriver
from rv32i.isa import *

driver = RV32ICPUDriver('COM3')
driver.open()

# Compute 10 + 20 and display on LED
program = [
    ADDI('a0', 'zero', 10),   # a0 = 10
    ADDI('a1', 'zero', 20),   # a1 = 20
    ADD('a2', 'a0', 'a1'),    # a2 = 30
    SW('a2', 'zero', 0x407C), # LED = a2
    EBREAK()                  # Halt
]

driver.load_program(program)
driver.run_cpu()
driver.wait_for_breakpoint(timeout=1.0)

result = driver.read_led()
print(f"LED = {result} (expected 30 & 0xF = 14)")

driver.close()
```

### Example 2: Memory Operations
```python
# Write pattern to memory
for i in range(16):
    driver.write_memory_word(i*4, 0x10000000 + i)

# Read back and verify
for i in range(16):
    value = driver.read_memory_word(i*4)
    print(f"[{i*4:04X}] = {value:08X}")

# Dump entire region
driver.dump_memory(0x0000, 64)
```

### Example 3: Conditional Branch
```python
# Test branch logic
program = [
    ADDI('x1', 'x0', 5),      # x1 = 5
    ADDI('x2', 'x0', 5),      # x2 = 5
    BEQ('x1', 'x2', 8),       # if (x1 == x2) skip next instruction
    ADDI('x3', 'x0', 0),      # x3 = 0 (skipped)
    ADDI('x3', 'x0', 1),      # x3 = 1 (executed)
    SW('x3', 'x0', 0x407C),   # LED = x3
    EBREAK()
]

driver.load_program(program)
driver.run_cpu()
driver.wait_for_breakpoint(timeout=1.0)

result = driver.read_led()
print(f"Branch taken: LED = {result} (expected 1)")
```

## Troubleshooting

**Connection Issues:**
- Verify COM port name (`Device Manager` on Windows, `ls /dev/tty*` on Linux)
- Check baud rate matches FPGA configuration (default 115200)
- Ensure FPGA is programmed and UART bridge is functional

**Test Failures:**
- Run `driver.quick_test()` to verify basic functionality
- Check FPGA synthesis logs for CPU errors
- Examine waveforms (DSIM or Vivado ILA)
- Enable verbose output: `--verbose` flag

**Timeout Errors:**
- Increase timeout value in test cases
- Verify CPU is not stuck in infinite loop
- Check for pipeline hazards or stalls
- Inspect trace buffer for last executed instructions

**LED Mismatch:**
- Remember LED is 4-bit (values 0-15 only)
- Check MMIO address is correct (0x407C)
- Verify store instruction byte enables
- Confirm register block routing

## Related Documentation

- [RV32I_DOCUMENTATION.md](../../rtl/cpu/RV32I_DOCUMENTATION.md) - CPU architecture reference
- [ISA.md](../../docs/ISA.md) - Instruction set specification
- [AXIUART Registers](../../register_map/axiuart_registers.json) - Register map
- [UVM Tests](../../sim/tests/) - RTL verification tests

## Version History

**v1.0.0** (2025-01-XX)
- Initial release
- Full RV32I ISA support (40 instructions)
- 20+ hardware-validated test cases
- Automated test runner
- Byte-granular memory access

## License

See [LICENSE](../../LICENSE) for details.
