# TD4CPU MMIO LED Control Test

Hardware validation for CPU Memory-Mapped IO LED control at address 0x101F.

## Overview

This test validates that the TD4 CPU can:
1. Build the MMIO address 0x101F using arithmetic instructions
2. Execute ST (store) instruction to write to MMIO space
3. Successfully control 4-bit LED register via CPU instructions (not UART)

**Key Architecture Point**: The LED at 0x101F is **CPU-only** accessible. Unlike the old REG_TEST_LED (0x1044) which was accessible via UART, the new MMIO LED can only be controlled by CPU instructions executing LD/ST operations.

## Hardware Requirements

- FPGA with TD4UART design deployed (feature/cpu-mmio-led branch)
- UART connection to host PC
- Physical LEDs connected to top-level LED outputs (4 bits)

## Quick Start

### 1. Single LED Value Test (Default)

Test LED value 0xA (binary 1010):

```bash
# Windows
python test_mmio_led.py --port COM3

# Linux
python test_mmio_led.py --port /dev/ttyUSB0
```

Expected output:
```
======================================================================
Testing LED value: 10 (0xA, 0b1010)
======================================================================
Opening COM3 @ 115200 baud...
Resetting CPU...
Building LED program for value 0xA...
Loading 35 instructions to RAM...
Verifying program...
✓ Program loaded and verified
Running CPU...
✓ CPU halted (BRK executed)
Register state after execution:
  R0 = 0x000A (expected 0x000A)
  R1 = 0x1000 (expected 0x1000)
✓ TEST PASSED
```

### 2. Binary Counting Pattern (0-15)

Visual test showing all LED combinations:

```bash
python test_mmio_led.py --port COM3 --pattern count --delay 0.5
```

This will:
- Test all 16 LED values (0x0 to 0xF)
- Load and execute CPU program for each value
- Verify CPU registers after each execution
- Display pass/fail for each test

Watch the physical LEDs count from 0000 to 1111 in binary!

### 3. Knight Rider Pattern

Fun demo showing a single LED "scanning" left to right:

```bash
python test_mmio_led.py --port COM3 --pattern knight --delay 0.3
```

Pattern sequence: 0001 → 0010 → 0100 → 1000 → 0100 → 0010 (repeat)

### 4. Custom LED Value

Test any specific 4-bit value:

```bash
# Test LED = 0x5 (binary 0101)
python test_mmio_led.py --port COM3 --value 5

# Test LED = 0xF (binary 1111 - all on)
python test_mmio_led.py --port COM3 --value 15
```

## What the Test Does

### Program Logic

For each test, the script:

1. **Resets CPU** - Halts CPU and clears all registers
2. **Builds Program** - Creates instruction sequence in Python:
   ```
   LDI R0, #<LED_VALUE>     ; Load LED pattern into R0
   LDI R1, #128             ; Start building address in R1
   ADDI R1, #128 (x31)      ; R1 = 128 + 31×128 = 4096 = 0x1000
   ST R0, [R1+31]           ; Store R0 to [0x1000+0x1F] = 0x101F (LED MMIO)
   SYS BRK                  ; Halt CPU
   ```

3. **Loads to RAM** - Writes instructions to CPU RAM addresses 0x0000-0x0022 via UART
4. **Verifies Load** - Reads back RAM to confirm correct loading
5. **Executes** - Sets PC=0x0000 and runs CPU freely (not single-step)
6. **Waits for Halt** - Polls CPU_DBG_STATUS until BRK instruction halts CPU
7. **Validates Results**:
   - R0 should contain LED value
   - R1 should contain 0x1000 (address base)
   - Physical LEDs should display the pattern

### Why 35 Instructions?

The program needs 35 instructions total:
- 1 instruction: LDI R0, #LED_VALUE
- 1 instruction: LDI R1, #128
- 31 instructions: ADDI R1, #128 (repeated to reach 0x1000)
- 1 instruction: ST R0, [R1+31]
- 1 instruction: SYS BRK

This is because the ST instruction's offset field is only 6 bits signed (-32 to +31), so we need to build the base address 0x1000 in a register first.

## Expected LED Behavior

| Value | Binary | LED Display | Description |
|-------|--------|-------------|-------------|
| 0x0   | 0000   | ○○○○       | All off |
| 0x1   | 0001   | ○○○●       | LED0 only |
| 0x5   | 0101   | ○●○●       | LED0, LED2 |
| 0xA   | 1010   | ●○●○       | LED1, LED3 |
| 0xF   | 1111   | ●●●●       | All on |

(● = ON, ○ = OFF, assuming LSB = LED0)

## Troubleshooting

### "Serial port not found"
- Check device manager (Windows) or `ls /dev/ttyUSB*` (Linux)
- Ensure FPGA is powered and UART cable connected
- Verify correct port name

### "CPU did not halt within timeout"
- Check FPGA is programmed with correct bitstream (feature/cpu-mmio-led branch)
- Verify CPU clock is running
- Try increasing timeout: modify `wait_for_halt(timeout=1.0)` in script

### "RAM verification failed"
- UART communication error
- Try lower baud rate: `--baudrate 57600`
- Check UART connections (TX/RX not swapped)

### "R1 mismatch (address build failed)"
- CPU ALU error - check ADDI instruction implementation
- May indicate CPU is not executing correctly
- Run basic CPU tests first: `python cpu_test_runner.py --port COM3`

### "LEDs don't match expected pattern"
- Check MMIO address decode logic in RTL
- Verify led_out port is connected to top-level LED pins
- Use `--verbose` flag for detailed debug output

## Advanced Options

```bash
# Verbose mode (shows all UART transactions)
python test_mmio_led.py --port COM3 --value 10 --verbose

# Custom baud rate
python test_mmio_led.py --port COM3 --baudrate 57600 --pattern count

# Faster pattern animation
python test_mmio_led.py --port COM3 --pattern knight --delay 0.1
```

## Architecture Notes

### MMIO Address Space

```
0x0000 - 0x0FFF : Internal CPU RAM (4096 words)
0x1000 - 0x1FFF : Memory-Mapped IO space
  0x101F        : LED register (4-bit, CPU write only)
  0x1200+       : CPU debug registers (UART accessible only)
```

### Why LED is at 0x101F

- Fits within 6-bit ST offset range when base is 0x1000
- Simple address decode: `(addr >= 0x1000) && (addr[4:0] == 5'h1F)`
- Not a power-of-2 boundary (makes decode logic more interesting!)

### Comparison: Old vs New LED Control

| Feature | Old (REG_TEST_LED) | New (MMIO LED) |
|---------|-------------------|----------------|
| Address | 0x1044 | 0x101F |
| Access Method | UART → Register Block | CPU LD/ST only |
| Use Case | External control | CPU program output |
| Test Method | Direct register write | CPU program execution |

This design demonstrates true memory-mapped IO where CPU instructions directly access peripheral registers.

## Related Files

- **RTL**: `rtl/cpu/td4cpu_core.sv` - CPU with MMIO address decode
- **Test**: `sim/tests/axiuart_cpu_mmio_led_test.sv` - UVM simulation test
- **Design Doc**: `docs/cpu_mmio_design.md` - MMIO architecture specification
- **ISA**: `isa/td4cpu_isa.json` - Instruction set (LD/ST definitions)

## Development Notes

This test validates the same functionality as the UVM testbench `axiuart_cpu_mmio_led_test`, but runs on real hardware. Key differences:

- **Simulation**: Waveform debugging, cycle-accurate, fast feedback
- **Hardware**: Real timing, actual LEDs, end-to-end validation

Both tests build R1=0x1000 and execute ST R0, [R1+31] to write to LED MMIO.

## License

Part of TD4UART project. See LICENSE file in repository root.
