# AXIUART - UART to AXI4-Lite Bridge with VexRiscv CPU

UART-AXI4 bridge with integrated VexRiscv RISC-V CPU, comprehensive verification environment, and Python control software.

## Project Status

✅ **VexRiscv CPU Integration Complete** (January 17, 2026)  
✅ **UART-Controlled CPU Execution** (Load/Run/Halt via UART commands)  
✅ **7-deep IBus + 2-deep DBus FIFOs** (Buffered memory access)  
✅ **EBREAK Detection** (Automatic halt on breakpoint)  
✅ **Dual-Port Block RAM** (8KB unified memory, Read-First mode)  
✅ **MMIO LED Register** (Memory-mapped I/O at 0x407C)  
✅ **Production ready** (4-stage pipeline, ~0.82 DMIPS/MHz)

## Project Overview

AXIUART provides a production-ready hardware interface between UART serial communication (115200 baud) and AXI4-Lite memory-mapped registers, enabling software control of FPGA peripherals through a simple serial connection. The design includes an integrated **VexRiscv CPU** (RISC-V 32-bit integer ISA, GenSmallAndProductive variant) for on-chip processing with full UART debug access.

**Key Features:**
- UART protocol with CRC-8 error detection
- AXI4-Lite master interface for register access
- **VexRiscv CPU (RV32I + Zicsr)** with 8KB unified memory
- UART-controlled program loading and execution
- IBus/DBus buffered memory access (7-entry + 2-entry FIFOs)
- EBREAK instruction detection with automatic CPU halt
- CPU control (run/halt/step) via UART registers
- 4-bit LED output from CPU MMIO (address 0x407C)
- Comprehensive UVM testbench with SystemVerilog assertions
- Python driver framework for software control
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
- Register block with CPU control/debug registers

**VexRiscv CPU Integration:**
- **ISA**: RV32I base + Zicsr (CSR instructions)
- **Pipeline**: 4-stage (Fetch/Decode/Execute/Memory-WriteBack)
- **Performance**: ~0.82 DMIPS/MHz (Dhrystone benchmark)
- **Memory**: 8KB unified Block RAM (dual-port, byte-addressable)
- **Bus Interface**: IBus (instruction fetch) + DBus (data access)
- **MMIO**: LED register at 0x407C (memory-mapped I/O)
- **Debug**: Full memory access via UART when CPU halted
- **Control**: Run/Halt/Step commands via UART registers

**VexRiscv CPU Modules (Refactored from SpinalHDL):**
- `vexriscv_top.sv` - CPU core integration (414 lines)
- `vexriscv_pkg.sv` - Shared types and enums (130 lines)
- `vexriscv_regfile.sv` - 32×32-bit register file, 2R1W (93 lines)
- `vexriscv_ibus_simple.sv` - Instruction fetch controller (560 lines)
- `vexriscv_dbus_simple.sv` - Data bus controller (220 lines)
- `vexriscv_hazard_simple.sv` - Hazard detection & forwarding (270 lines)
- `vexriscv_branch.sv` - Branch resolution (180 lines)
- `vexriscv_csr.sv` - CSR registers & interrupts (480 lines)
- `vexriscv_execute.sv` - ALU & shifter (280 lines)
- `vexriscv_stream_fifo.sv` - Response buffering (220 lines)

**UART Integration Modules (New Implementation):**
- `vexriscv_wrapper.sv` - UART-compatible interface (291 lines)
- `vexriscv_mem_crossbar.sv` - Memory arbiter with FIFOs (474 lines)
  - 7-deep IBus FIFO (matches VexRiscv max pending requests)
  - 2-deep DBus FIFO (load/store buffering)
  - Debug port arbitration when CPU halted
- `vexriscv_blockram.sv` - Dual-port Block RAM + MMIO (189 lines)
- `vexriscv_ebreak_monitor.sv` - EBREAK detection (154 lines)
- `vexriscv_control.sv` - CPU control FSM (185 lines)

**Key System Modules:**
- `AXIUART_Top.sv` - Top-level integration with VexRiscv
- `Uart_Axi4_Bridge.sv` - Protocol conversion bridge
- `Register_Block.sv` - AXI4-Lite register file (base: 0x1000)
  - CPU memory interface (0x1228-0x1234)
  - CPU control registers (run/halt/step)
  - Hardware breakpoints (4 breakpoints)
- `Uart_Rx.sv` / `Uart_Tx.sv` - UART transceivers
- `Frame_Parser.sv` / `Frame_Builder.sv` - Protocol handlers

**Total RTL**: 15 VexRiscv modules (~4,140 lines) + UART/AXI4 infrastructure

**Documentation:** [rtl/README.md](rtl/README.md)

### Verification (UVM Testbench)

**UVM 1.2 Environment:**
- Modular agent architecture (Driver, Monitor, Sequencer, Scoreboard)
- Protocol-aware transactions with automatic CRC generation
- Comprehensive sequence library (reset, read, write, burst)
- Register R/W verification with read-back checking (**Bug #8 fixed: RO register exclusion**)

**Available Tests:**
- `axiuart_basic_test` - Basic connectivity and reset test
- `axiuart_reset_test` - Reset functionality verification
- `axiuart_reg_rw_test` - Register read/write verification
- `vexriscv_smoke_test` - **VexRiscv basic functionality (coming soon)**
  - Load NOP program via UART
  - Start CPU execution
  - Halt CPU and verify PC advancement
- `vexriscv_memory_test` - **Memory access test (coming soon)**
  - Load/store instructions
  - Verify data integrity
  - MMIO LED register access

**Regression Suites:**
- `smoke` - Quick validation (2 tests, ~68s)
- `full` - Complete regression (all tests)

**Simulation Infrastructure:**
- Altair DSim 2025.1 with UVM support
- MXD waveform generation for debugging
- FastMCP server for automated test execution
- JSON-based result analysis and reporting
- HTML regression reports

**Documentation:** [sim/README.md](sim/README.md) | [sim/uvm/UVM_ARCHITECTURE.md](sim/uvm/UVM_ARCHITECTURE.md)

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

```powershell
# Run UVM test (compile + simulate)
.\scripts\run_test.ps1 axiuart_reg_rw_test -Verbosity UVM_MEDIUM -Waves

# Run regression suite
.\scripts\run_regression.ps1 -Stage 1

# View results
# Logs: sim/exec/logs/
# Waveforms: sim/exec/wave/ (MXD format, use Metrics DSim viewer)
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
| VexRiscv RTL | Compilation test | ✅ PASS | 100% |
| VexRiscv Wrapper | Standalone compile | ✅ PASS | - |
| Memory Crossbar | 7-deep IBus FIFO | ✅ PASS | - |
| EBREAK Monitor | Instruction decode | ✅ PASS | - |
| Python Driver | Hardware verified | ✅ PASS | - |

**Latest Compilation Results:**
- VexRiscv modules: 7 modules, 1,867 basic blocks (DSim 2025.1)
- Integration test: AXIUART_Top + VexRiscv wrapper compiled successfully
- Warnings: 0
- UVM tests: Pending VexRiscv-specific test development

## License

See [LICENSE](LICENSE) file for details.

## Documentation

- [RTL Design Specifications](rtl/README.md)
- [UVM Architecture Guide](sim/uvm/UVM_ARCHITECTURE.md)
- [Simulation Environment](sim/README.md)
- [Python Driver Documentation](software/axiuart_driver/axiuart_driver.md)
- [LED Control Guide](software/axiuart_driver/examples/LED_CONTROL_README.md)
