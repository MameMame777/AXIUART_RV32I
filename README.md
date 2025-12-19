# AXIUART - UART to AXI4-Lite Bridge

UART-AXI4 bridge with comprehensive verification environment and Python control software.

## Project Overview

AXIUART provides a production-ready hardware interface between UART serial communication (115200 baud) and AXI4-Lite memory-mapped registers, enabling software control of FPGA peripherals through a simple serial connection.

**Key Features:**
- UART protocol with CRC-8 error detection
- AXI4-Lite master interface for register access
- 4-bit LED control register (REG_TEST_LED at 0x1044)
- Comprehensive UVM testbench with protocol coverage
- Python driver with interactive control applications
- Real-time waveform analysis and debugging support

## Register Management

**Centralized Register Map (Single Source of Truth):**

All register definitions are maintained in a single JSON file and automatically generated into multiple target formats:

```
register_map/axiuart_registers.json (SSOT)
            ↓
    gen_registers.py
            ↓
    ┌───────┴────────┬─────────────────┐
    ↓                ↓                 ↓
Python           SystemVerilog      Markdown
registers.py     axiuart_reg_pkg.sv REGISTER_MAP.md
```

**Key Benefits:**
- Eliminates hard-coded addresses scattered across RTL, UVM, and software
- Prevents address mismatches between hardware and software
- Single edit updates all layers automatically
- Validation ensures alignment and uniqueness

**Regenerate after editing JSON:**
```bash
python software/axiuart_driver/tools/gen_registers.py \
  --in register_map/axiuart_registers.json
```

**Generated Artifacts:**
- `software/axiuart_driver/registers.py` - Python constants for driver
- `rtl/register_block/axiuart_reg_pkg.sv` - SystemVerilog package for RTL/UVM
- `software/axiuart_driver/REGISTER_MAP.md` - Human-readable documentation

**Documentation:** [software/axiuart_driver/REGISTER_MAP.md](software/axiuart_driver/REGISTER_MAP.md)

## Architecture

### Hardware (SystemVerilog RTL)

**UART-AXI4 Bridge Core:**
- UART RX/TX with 115200 baud (fixed)
- CRC-8 error detection and frame parsing
- AXI4-Lite master interface
- Register block with LED control

**Key Modules:**
- `AXIUART_Top.sv` - Top-level integration with 4-bit LED output
- `Uart_Axi4_Bridge.sv` - Protocol conversion bridge
- `Register_Block.sv` - AXI4-Lite register file (base: 0x1000)
- `Uart_Rx.sv` / `Uart_Tx.sv` - UART transceivers
- `Frame_Parser.sv` / `Frame_Builder.sv` - Protocol handlers

**Documentation:** [rtl/README.md](rtl/README.md)

### Verification (UVM Testbench)

**UVM 1.2 Environment:**
- Modular agent architecture (Driver, Monitor, Sequencer, Scoreboard)
- Protocol-aware transactions with automatic CRC generation
- Comprehensive sequence library (reset, read, write, burst)
- Register R/W verification with read-back checking

**Available Tests:**
- `axiuart_basic_test` - Basic connectivity and reset test
- `axiuart_reg_rw_test` - 6-register read/write verification (including LED)

**Simulation Infrastructure:**
- Altair DSim 2025.1 with UVM support
- MXD waveform generation for debugging
- FastMCP server for automated test execution
- JSON-based result analysis and reporting

**Documentation:** [sim/README.md](sim/README.md) | [sim/uvm/UVM_ARCHITECTURE.md](sim/uvm/UVM_ARCHITECTURE.md)

### Software (Python Driver)

**AXIUARTDriver Class:**
- High-level register read/write APIs
- UART protocol implementation with CRC-8
- Context manager support for clean resource handling
- Built-in timeout and error handling

**LED Control Application:**
- LEDController class for 4-bit LED manipulation
- Interactive command-line interface
- Animation patterns (binary count, knight rider, blink)
- Individual bit control and toggle operations

**Example Usage:**
```python
from axiuart_driver import AXIUARTDriver
from axiuart_driver.examples.led_control import LEDController

# Register access
with AXIUARTDriver('COM3') as driver:
    driver.write_reg32(0x1020, 0xDEADBEEF)
    value = driver.read_reg32(0x1020)

# LED control
with LEDController('COM3') as led:
    led.set_led(0xF)           # All LEDs on
    led.pattern_knight_rider() # Animation
```

**Documentation:** [software/axiuart_driver/axiuart_driver.md](software/axiuart_driver/axiuart_driver.md)

## Quick Start

### Hardware Simulation

```bash
# Check simulation environment
python mcp_server/mcp_client.py --workspace . --tool check_dsim_environment

# Run UVM test (compile + simulate)
python mcp_server/mcp_client.py --workspace . --tool run_uvm_simulation_batch \
  --test-name axiuart_reg_rw_test --verbosity UVM_MEDIUM --waves

# View results
# Logs: sim/exec/logs/
# Waveforms: sim/exec/wave/ (MXD format)
```

### Python Driver

```bash
# Install dependencies
pip install pyserial

# LED control demo (interactive mode)
cd software
python -m axiuart_driver.examples.led_control interactive

# LED animation patterns
python -m axiuart_driver.examples.led_control knight
python -m axiuart_driver.examples.led_control count

# Basic register test
python -m axiuart_driver.examples.example_basic
```

## Directory Structure

```
AXIUART_/
├── rtl/                    # SystemVerilog RTL design
│   ├── README.md          # RTL specifications
│   ├── AXIUART_Top.sv     # Top-level (4-bit LED)
│   ├── register_block/    # AXI4-Lite registers
│   └── uart_axi4_bridge/  # Protocol conversion
├── sim/                   # UVM verification
│   ├── README.md          # Simulation guide
│   ├── uvm/               # UVM testbench
│   │   ├── UVM_ARCHITECTURE.md
│   │   ├── tb/            # Tests and sequences
│   │   └── sv/            # UVM components
│   └── exec/              # Simulation outputs
├── software/              # Python control software
│   └── axiuart_driver/
│       ├── axiuart_driver.md    # Driver documentation
│       ├── axiuart_driver.py    # Core driver
│       ├── protocol.py          # UART protocol
│       └── examples/
│           ├── led_control.py          # LED application
│           ├── LED_CONTROL_README.md   # Usage guide
│           └── example_basic.py        # Basic example
├── mcp_server/            # FastMCP automation
│   ├── dsim_uvm_server.py
│   └── mcp_client.py
└── docs/                  # Documentation
```

## Development Environment

### Required Tools

- **DSIM**: Altair DSim 2025.1 (Metrics Design Automation)
- **Python**: 3.8+ with pyserial
- **SystemVerilog**: IEEE 1800-2017 compliant
- **UVM**: Version 1.2

### Environment Setup

```powershell
# Windows
$env:DSIM_HOME = "C:\Program Files\Altair\DSim\2025.1"
$env:DSIM_LICENSE = "C:\Users\<user>\AppData\Local\metrics-ca\dsim-license.json"

# Install Python dependencies
pip install pyserial
```

## Verification Status

| Component | Tests | Status | Coverage |
|-----------|-------|--------|----------|
| UART Protocol | Basic + Register R/W | ✅ PASS | 95% |
| AXI4-Lite Interface | Write/Read sequences | ✅ PASS | 92% |
| LED Control | 6-register test | ✅ PASS | 100% |
| Python Driver | Hardware verified | ✅ PASS | - |

**Latest Test Results:**
- UVM Simulation: 6 MATCHES, 0 MISMATCHES (15.319ms runtime)
- Hardware Test: COM3 @ 115200 baud - All patterns working
- LED Control: All 4 bits verified with animations

## License

See [LICENSE](LICENSE) file for details.

## Documentation

- [RTL Design Specifications](rtl/README.md)
- [UVM Architecture Guide](sim/uvm/UVM_ARCHITECTURE.md)
- [Simulation Environment](sim/README.md)
- [Python Driver Documentation](software/axiuart_driver/axiuart_driver.md)
- [LED Control Guide](software/axiuart_driver/examples/LED_CONTROL_README.md)
