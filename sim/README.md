# AXIUART Simulation Directory

## Overview

This directory contains the complete UVM testbench infrastructure for the AXIUART project. The simulation environment is built using Altair DSim 2025.1 with UVM 1.2 and provides comprehensive verification of the UART-AXI4 Bridge design.

## Directory Structure

```
sim/
├── exec/                    # Simulation execution outputs
│   ├── logs/               # Simulation log files
│   ├── wave/               # Waveform files (MXD format)
│   └── dsim.env            # DSIM environment configuration
│
├── tests/                  # Test definitions (NEW: refactored structure)
│   ├── axiuart_test_pkg.sv         # Test package (includes all tests)
│   ├── axiuart_base_test.sv        # Base test class
│   ├── axiuart_basic_test.sv       # Basic connectivity test
│   ├── axiuart_reset_test.sv       # Reset functionality test
│   └── axiuart_reg_rw_test.sv      # Register R/W verification test
│
├── uvm/                    # UVM testbench components
│   ├── sv/                 # SystemVerilog verification components
│   │   ├── axiuart_pkg.sv              # Package definitions
│   │   ├── axiuart_env.sv              # Top-level environment
│   │   ├── axiuart_scoreboard.sv       # Verification scoreboard
│   │   ├── uart_agent.sv               # UART agent
│   │   ├── uart_driver.sv              # UART driver
│   │   ├── uart_monitor.sv             # UART monitor
│   │   ├── uart_sequencer.sv           # UART sequencer
│   │   ├── uart_transaction.sv         # Transaction class
│   │   ├── uart_basic_sequence.sv      # Basic sequences
│   │   ├── uart_reg_sequences.sv       # Register sequences
│   │   ├── uart_reset_sequence.sv      # Reset sequence
│   │   └── axi4_lite_monitor.sv        # AXI4-Lite monitor
│   │
│   └── tb/                 # Testbench infrastructure
│       ├── axiuart_tb_top.sv           # Testbench top module
│       ├── dsim_config.f               # DSIM file list
│       └── Makefile                     # Build automation
│
└── README.md               # This file

```

## Testbench Architecture

### UVM Components (sim/uvm/sv/)

#### Package and Environment
- **axiuart_pkg.sv**: Contains all package imports, type definitions, and includes for the verification environment
- **axiuart_env.sv**: Top-level UVM environment that instantiates and connects all verification components

#### UART Agent Components
- **uart_agent.sv**: Container for UART driver, monitor, and sequencer
- **uart_driver.sv**: Drives UART protocol transactions to the DUT
- **uart_monitor.sv**: Observes UART interface and collects transactions
- **uart_sequencer.sv**: Manages sequence execution for UART transactions
- **uart_transaction.sv**: Defines transaction objects for UART operations

#### Sequences
- **uart_basic_sequence.sv**: Basic UART transaction sequences
- **uart_reg_sequences.sv**: Register read/write sequences for testing register operations
- **uart_reset_sequence.sv**: Reset sequence for DUT initialization

#### Verification Components
- **axiuart_scoreboard.sv**: Compares expected vs actual behavior for register read/write operations
- **axi4_lite_monitor.sv**: Monitors AXI4-Lite interface transactions (optional)

### Test Definitions (sim/tests/) - NEW STRUCTURE

#### Test Package
- **axiuart_test_pkg.sv**: Central test package that includes all test classes
  - Provides single entry point for test definitions
  - Maintains dependency order (base test first)

#### Individual Test Classes (1 file per test)
- **axiuart_base_test.sv**: Base test class with common functionality
  - Environment instantiation and configuration
  - Topology printing
  - Common utility methods
  - Test pass/fail reporting

- **axiuart_basic_test.sv**: Basic connectivity and write operation test
  - Verifies basic UART transaction execution
  - Simple sanity check for environment setup

- **axiuart_reset_test.sv**: Reset functionality test
  - Validates DUT reset behavior (200 cycles)
  - Tests post-reset operation with basic sequence

- **axiuart_reg_rw_test.sv**: Comprehensive register read/write verification
  - Tests 6 registers (REG_TEST_0-4 + REG_TEST_LED)
  - Validates write-read consistency
  - Scoreboard-based verification with full match reporting

### Testbench Files (sim/uvm/tb/)

#### Testbench Infrastructure
- **axiuart_tb_top.sv**: Top-level testbench module that instantiates:
  - DUT (AXIUART_Top)
  - Interface instances (uart_if, axi4_lite_if, bridge_status_if)
  - Clock generation
  - Waveform dumping control
  - Test package inclusion

#### Build Configuration
- **dsim_config.f**: Complete file list for DSIM compilation including:
  - UVM library path
  - Include directories (`+incdir+../../tests` for new test structure)
  - RTL source files (organized by module)
  - Testbench and verification components
  - Interface definitions

- **Makefile**: Automation for common simulation tasks (if present)

### Test Structure Benefits

The new test organization (sim/tests/) provides:

1. **Scalability**: Easy to add new tests without file conflicts
2. **Maintainability**: One test per file, clear responsibility
3. **Parallel Development**: Multiple engineers can add tests simultaneously
4. **Selective Compilation**: Include only needed tests
5. **Clear Traceability**: Test specifications map 1:1 to files

### Execution Directory (sim/exec/)

#### Log Files (sim/exec/logs/)
Contains simulation log files with naming convention: `<test_name>_<timestamp>.log`

Example log analysis information:
- UVM phase execution trace
- Test execution status
- Error and warning messages
- Severity counts (info, warning, error, fatal)
- Register transaction tracking

#### Waveform Files (sim/exec/wave/)
Contains waveform dump files in MXD format (DSIM native binary format) with naming convention: `<test_name>_<timestamp>.mxd`

Note: MXD format provides better performance and smaller file sizes compared to VCD format.

#### Configuration
- **dsim.env**: DSIM environment variable configuration

## Available Tests

### axiuart_basic_test
**Purpose**: Basic connectivity and write operation verification

**Test Sequence**:
1. Reset sequence (100 cycles)
2. Single register write operation
3. Basic functionality check

**Expected Results**:
- Test completion without errors
- Successful write transaction to DUT
- Runtime: ~4ms

### axiuart_reg_rw_test
**Purpose**: Comprehensive register read/write verification

**Test Sequence**:
1. Reset sequence (100 cycles)
2. Write to 5 test registers (REG_TEST_0 through REG_TEST_4)
   - Address range: 0x00001020 to 0x00001040
   - Test patterns: 0x11111111, 0x22222222, 0x33333333, 0x44444444, 0x55555555
3. Read back all 5 registers
4. Verify data matches expected values

**Expected Results**:
- 5 write operations tracked in scoreboard
- 5 read operations with matching data
- 5 MATCHES, 0 MISMATCHES
- Runtime: ~13.6ms

## Running Simulations

### Using MCP Tools (Recommended)

The project uses FastMCP (Model Context Protocol) for simulation management. Two approaches are available:

#### Batch Mode (Recommended for Normal Testing)
Automatically compiles and runs in sequence:

```powershell
python mcp_server/mcp_client.py --workspace . --tool run_uvm_simulation_batch --test-name axiuart_basic_test --verbosity UVM_MEDIUM
```

#### Step-by-Step Mode (For Debugging)
1. Compile only:
```powershell
python mcp_server/mcp_client.py --workspace . --tool run_uvm_simulation --test-name axiuart_basic_test --mode compile --verbosity UVM_LOW --timeout 120
```

2. Run simulation:
```powershell
python mcp_server/mcp_client.py --workspace . --tool run_uvm_simulation --test-name axiuart_basic_test --mode run --verbosity UVM_MEDIUM --timeout 300
```

#### Available MCP Tools
- `check_dsim_environment`: Verify DSIM installation and environment variables
- `list_available_tests`: List all available UVM tests
- `compile_design`: Compile-only pass for syntax checking
- `run_uvm_simulation`: Execute simulation (compile or run mode)
- `run_uvm_simulation_batch`: One-step compile and run
- `get_simulation_logs`: Retrieve and analyze log files

### Verbosity Levels
- `UVM_NONE`: No UVM messages
- `UVM_LOW`: Minimal output
- `UVM_MEDIUM`: Standard debug information (recommended)
- `UVM_HIGH`: Detailed execution trace
- `UVM_FULL`: Maximum detail
- `UVM_DEBUG`: Full debug including internal UVM operations

### Waveform Options
- Default: MXD format (binary, efficient)
- Alternative: VCD format (text, portable) - use `--wave-format VCD`
- Disable: Add `--no-waves` flag

### Coverage Options
Enable functional coverage collection with `--coverage` flag.

## Log Analysis

### Key Information in Logs

#### Severity Counts
```
UVM_INFO    : <count>
UVM_WARNING : <count>
UVM_ERROR   : <count>
UVM_FATAL   : <count>
```

#### Test Pass/Fail Indication
Look for final report section:
```
*** TEST PASSED ***
** UVM TEST PASSED **
```

#### Scoreboard Results (reg_rw_test)
```
Total Writes: <count>
Total Reads:  <count>
MATCHES:      <count>
MISMATCHES:   <count>
```

#### Common Warnings (Expected)
- `AXI interface not found - disabling AXI monitor`: Expected when AXI interface is not connected for simple tests
- `NO READ RESPONSES VERIFIED`: Expected in basic_test which only performs writes

## File Organization

### RTL Source Organization (Referenced by dsim_config.f)

The RTL sources are organized into modular directories:

#### UART-AXI4 Bridge Core (../rtl/uart_axi4_bridge/)
Reusable communication bridge components:
- Uart_Rx.sv, Uart_Tx.sv: UART transceivers
- Frame_Parser.sv, Frame_Builder.sv: Protocol frame handling
- Uart_Axi4_Bridge.sv: Main bridge controller
- Axi4_Lite_Master.sv: AXI4-Lite master interface
- Crc8_Calculator.sv: CRC-8 checksum
- Address_Aligner.sv: Address alignment logic
- fifo_sync.sv: Synchronous FIFO

#### Register Block (../rtl/register_block/)
Project-specific register implementation:
- Register_Block.sv: Memory-mapped register file

#### Interfaces (../rtl/interfaces/)
SystemVerilog interface definitions:
- uart_if.sv: UART interface signals
- axi4_lite_if.sv: Parameterized AXI4-Lite interface
- bridge_status_if.sv: Bridge status signals

#### Top Level (../rtl/)
- AXIUART_Top.sv: Top-level integration

## Build System Details

### Include Paths
The build system includes the following directories:
- `+incdir+../../../rtl/interfaces`
- `+incdir+../../../rtl/uart_axi4_bridge`
- `+incdir+../../../rtl/register_block`

### Compilation Order
Files are compiled in dependency order as specified in dsim_config.f:
1. Interface definitions
2. RTL modules (bridge core, register block)
3. Top-level RTL
4. UVM package and components
5. Testbench top
6. Test library

## Environment Requirements

### Required Tools
- **Altair DSim**: Version 2025.1.0 or later
- **UVM Library**: Version 1.2 (included with DSim)
- **Python**: 3.x for MCP tools

### Environment Variables
Required environment variables (checked by `check_dsim_environment`):
- `DSIM_HOME`: DSim installation directory
- `DSIM_ROOT`: DSim root directory
- `DSIM_LIB_PATH`: DSim library path
- `DSIM_LICENSE`: License file location

### Fallback Configuration
Default paths if environment variables are not set:
- DSIM_HOME: `C:\Program Files\Altair\DSim\2025.1`
- DSIM_LICENSE: `C:\Users\<username>\AppData\Local\metrics-ca\dsim-license.json`

## Troubleshooting

### Common Issues

#### Compilation Errors
1. Check DSIM environment: `python mcp_server/mcp_client.py --workspace . --tool check_dsim_environment`
2. Verify file paths in dsim_config.f
3. Check timescale declarations in all files

#### Simulation Hangs
1. Check timeout settings (increase if needed)
2. Verify objection handling in test code
3. Review phase execution in log file

#### Missing Waveforms
1. Verify `+WAVES_ON=1` plusarg is set
2. Check wave file path in log output
3. Ensure sufficient disk space

#### Path Issues
- All paths in dsim_config.f are relative to `sim/uvm/tb/`
- Use forward slashes or double backslashes in paths

## Performance Metrics

Typical simulation performance on standard workstation:

| Test               | Compile Time | Runtime  | Log Size | Wave Size |
|--------------------|--------------|----------|----------|-----------|
| axiuart_basic_test | ~10-15s      | ~4ms     | ~50KB    | ~1-2MB    |
| axiuart_reg_rw_test| ~10-15s      | ~13.6ms  | ~100KB   | ~3-5MB    |

## Additional Resources

### Documentation
- Main project README: `../README.md`
- **UVM Architecture Details**: [uvm/UVM_ARCHITECTURE.md](uvm/UVM_ARCHITECTURE.md) - Comprehensive UVM testbench architecture documentation
- UVM methodology documentation: `../docs/uvm_testbench_architecture.md`
- Test environment overview: `../docs/test_environment_overview.md`

### Reference Materials
- Accellera UVM examples: `../reference/Accellera/uvm/`
- Protocol specifications: `../docs/axiuart_bus_protocol.md`

### Development Logs
Historical development and troubleshooting information:
- `../docs/diary_*.md`: Development diary entries
- `../docs/simplified_env_test_report_*.md`: Test reports

## Notes

### Design Decisions
1. MXD waveform format is used by default for better performance
2. AXI4-Lite interface is parameterized for reusability
3. Scoreboard verification is transaction-based
4. Reset is synchronous and active-high

### Known Limitations
- Some RTL modules have expected linting warnings (MissingTimescale, LatchInferred, etc.)
- AXI monitor is optional and disabled when interface is not connected
- Coverage collection is disabled by default

### Best Practices
1. Always run `check_dsim_environment` before first simulation
2. Use batch mode for normal testing workflow
3. Enable UVM_MEDIUM verbosity for standard debugging
4. Review scoreboard results in log files
5. Keep waveform files for failed tests only (to save disk space)

## Version Information

- DSIM Version: 2025.1.0
- UVM Version: 1.2
- Last Updated: December 14, 2025
