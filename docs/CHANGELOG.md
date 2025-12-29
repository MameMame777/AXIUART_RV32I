# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [1.1.0] - 2025-12-29

### Fixed

#### Bug #6: Register Read/Write Pulse Confusion
- **Critical bug**: R0 register corruption (0x0A → 0x00) before ST instruction
- **Root cause**: Single pulse signal for both read-latch and write operations
- **Solution**: Separated `cpu_reg_read_pulse_set` (read-latch) from `cpu_reg_write_pulse` (actual write)
- **Files modified**: 
  - `rtl/register_block/Register_Block.sv` (lines 139, 472-473, 550-551, 628-647, 742)
  - `rtl/cpu/td4cpu_core.sv` (lines 243-260, 599)
- **Impact**: Tests 1-2 now passing (ST/LD to LED MMIO)

#### Bug #7: Test Address Calculation Errors
- **Critical bug**: Tests 3-5 wrote to RAM 0x0044 instead of LED MMIO 0x1044
- **Root cause**: Missing ADDI sequences for 16-bit address construction (TD4 has 9-bit immediate limitation)
- **Solution**: Added ADDI loops (LDI R1,#0x100 + 15×ADDI + ADDI #0x44 = 0x1044)
- **Files modified**: `sim/tests/axiuart_cpu_mmio_led_test.sv` (Tests 3-5)
- **Impact**: Tests 3-5 now passing (LED Binary Counter, Negative Offset, RAM/MMIO Boundary)

#### Bug #8: Scoreboard UVM_ERROR from Read-Only Registers
- **Issue**: 87 UVM_ERROR messages despite tests passing
- **Root cause**: Scoreboard verified read-only status registers (REG_CPU_DBG_STATUS at 0x1204) against write shadow
- **Solution**: Excluded 10 read-only registers from scoreboard verification
- **Files modified**: `sim/uvm/sv/axiuart_scoreboard.sv` (lines 140-179)
- **Impact**: UVM_ERROR count: 87 → 0

### Added
- **CPU MMIO LED Test Suite** (`axiuart_cpu_mmio_led_test`)
  - Test 1: ST to LED MMIO (write 0xA)
  - Test 2: LD from LED MMIO (read-back 0xA)
  - Test 3: LED Binary Counter Pattern (4 patterns: 0x1→0x2→0x4→0x8)
  - Test 4: Negative Offset Addressing (LED=0xFF)
  - Test 5: RAM/MMIO Boundary Test (RAM[0xFF]=0x0F, LED[0x1044]=0x03)
- **Regression Test Framework**
  - MCP-based regression runner (`mcp_server/run_regression.py`)
  - HTML report generation
  - Smoke suite (2 tests, ~68s runtime)
  - Full suite support
- **Documentation**
  - Bug fix documentation (`docs/bug_fixes_20251229.md`)
  - Changelog (this file)
  - Updated README with project status

### Changed
- **Scoreboard Verification Logic**
  - Now excludes read-only registers: REG_CPU_DBG_STATUS, REG_VERSION, REG_TX_COUNT, REG_RX_COUNT, REG_FIFO_STAT, REG_CPU_REG_DATA, REG_CPU_TRACE_RDATA, REG_CPU_TRACE_PTR, REG_CPU_ID, REG_REVISION
  - Improved logging for status register reads
- **Register Block Control Signals**
  - Separated read-pulse and write-pulse for CPU debug interface
  - Added `cpu_reg_read_pulse_set` signal
  - Updated pulse clearing logic
- **Test Infrastructure**
  - Improved address construction for MMIO tests
  - Enhanced test logging and validation

## [1.0.0] - 2025-12-28

### Added
- Initial UART-AXI4 Bridge implementation
- TD4 CPU integration with MMIO support
- UVM testbench infrastructure
- Python driver software
- Register map generation framework
- Basic test suite (reset, basic, reg_rw)
- MCP server for test automation
- Documentation framework

---

## Version History

- **1.1.0** (2025-12-29): Bug fixes, CPU MMIO LED tests, regression framework
- **1.0.0** (2025-12-28): Initial release with TD4 CPU integration

---

*For detailed bug analysis, see: [docs/bug_fixes_20251229.md](bug_fixes_20251229.md)*
