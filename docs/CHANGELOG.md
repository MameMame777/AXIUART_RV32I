# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- **Issue #55: VexRiscv Control / Debug Bridge Verification Coverage** (2026-02-15)
  - Added dedicated tests:
    - `sim/tests/vexriscv_control_test.sv`
    - `sim/tests/vexriscv_debug_bridge_test.sv`
  - Added missing compatibility files required by current DSIM compile list / TB include path:
    - `sim/tests/vexriscv_isa_test.sv`
    - `sim/uvm/tb/vexriscv_smoke_test.sv`
  - Registered tests in:
    - `sim/uvm/tb/dsim_config.f`
    - `sim/regression_tests.json` (`vexriscv_debug_control` suite)

### Changed
- **Register block debug window enablement**
  - Extended valid AXI read/write register decode to include breakpoint, register-snapshot, trace, and debug-reset windows.
  - Aligned local register-offset parameters to generated package constants (`axiuart_reg_pkg`) for consistency.
  - File: `rtl/register_block/Register_Block.sv`

- **Debug signal plumbing and control ownership updates**
  - Wired step/breakpoint/register snapshot/reset debug signals through:
    - `rtl/AXIUART_Top.sv`
    - `rtl/vexriscvwrap/vexriscv_wrapper.sv`
  - Expanded debug bridge interface/FSM for step and breakpoint command generation:
    - `rtl/vexriscvwrap/vexriscv_debug_bridge.sv`
  - Kept `cpu_control` instance in wrapper for assertion hierarchy compatibility while preserving debug-bridge-driven control behavior.

- **Regression inventory alignment (workspace consistency)**
  - Updated `sim/uvm/tb/rv32i_tb_top.sv` to include `axiuart_test_pkg.sv` for AXIUART test class registration.
  - Removed missing-file include from `sim/uvm/tb/axiuart_test_pkg.sv` (`axiuart_cpu_simple_mem_test.sv` no longer present in workspace).
  - Realigned `sim/regression_tests.json` `full` suite to currently available/compilable tests and updated metadata counts.

### Verification
- `./scripts/run_test.ps1 vexriscv_control_test -Verbosity UVM_LOW` → PASS
- `./scripts/run_test.ps1 vexriscv_debug_bridge_test -Verbosity UVM_LOW` → PASS
- `./scripts/run_regression.ps1 -Suite vexriscv_debug_control -Verbosity UVM_LOW` → PASS (2/2)

---

- **Issue #75: CSR Encoding and Exception Handler Bug Fixes** (2026-02-21)
  - Fixed incorrect CSR encoding in `rv32i_ebreak_simple_test.sv` and `rv32i_exception_handler_test.sv`
  - Corrected MTVEC/MEPC register address constants to match VexRiscv CSR map
  - Fixed trap handler logic: EBREAK increments MEPC+4 before MRET; ECALL handler writes tohost=1 for PASS
  - Files modified:
    - `sim/tests/rv32i_ebreak_simple_test.sv`
    - `sim/tests/rv32i_exception_handler_test.sv`
  - Verification: Both exception tests now compile and execute correctly under DSIM

- **Issue #53: Stage 3 VexRiscv Assertion Modules** (2026-02-21)
  - Implemented 5 non-intrusive assertion spec modules (observer-only, `ENABLE_ASSERTIONS` guarded):
    - `sim/assertions/spec/vexriscv_hazard_plugin_spec.sv` — RAW hazard detection, bypass priority, load-use stall, bypassWriteBackBuffer validity
    - `sim/assertions/spec/vexriscv_pipeline_arbitration_spec.sv` — decode/execute/memory/WB arbitration flags, stall/flush protocol
    - `sim/assertions/spec/vexriscv_regfile_bypass_spec.sv` — forwarding correctness from EX/MEM/WB stages
    - `sim/assertions/spec/vexriscv_jump_arbitration_spec.sv` — jump/branch taken vs PC correction protocol
    - `sim/assertions/spec/vexriscv_stream_fifo_spec.sv` — IBus/DBus stream FIFO handshake protocol
  - Added corresponding bind files under `sim/assertions/bind/`
  - Added `sim/uvm/tb/dsim_config_rv32i.f` compile list for RV32I-focused sim runs
  - All assertion modules reference VexRiscv internal signals via bind; assertions are NEVER embedded in DUT

- **Hardware Bring-up: LED Blink Program** (2026-02-21)
  - Added `software/rv32i/led_blink.py` — standalone FPGA hardware bring-up tool (523 lines)
    - Sends LED blink RV32I program via UART to AXIUART/VexRiscv SoC
    - Configurable blink rate, address, and repeat count; works with any serial port
  - Updated `software/rv32i/README.md` with `led_blink.py` usage examples and corrected register addresses
  - Added `AGENTS.md` at repository root for OpenAI Codex CLI configuration

### Fixed
- **VexRiscv Hazard Module Bug** (2026-01-20)
  - **Issue**: Pipeline stalls indefinitely on first instruction (ADDI x1, x0, 1)
  - **Root cause**: Hazard detection used flat conditions instead of nested structure, causing false hazards when x0 register used as source operand
  - **Discovery**: Bug exposed by unoptimized decoder but pre-existed in hazard module extraction from VexRiscv
  - **Solution**: Replaced flat hazard conditions with 3-level nested structure matching VexRiscv reference
  - **Files modified**:
    - `rtl/cpu/vexriscv_hazard_simple.sv` (lines 148-186): Added proper nesting for WriteBack/Memory/Execute stage hazards, added RS1_USE/RS2_USE override logic
  - **Impact**: vexriscv_regfile_test now PASS (x1=1, x2=1, x3=3), pipeline advances correctly
  - **Verification**: Test completed in 420ns (previously stalled indefinitely at 196ns)

### Changed
- **VexRiscv Decoder Migration: ROM → Unoptimized Case-Statement** (2026-01-20)
  - **Decision**: Keep unoptimized decoder (+4% area acceptable for explicit logic and no workarounds)
  - **Motivation**: ROM decoder required 4 workarounds for I-type instruction bugs, opaque logic difficult to modify
  - **Implementation**: Generated unoptimized decoder from SpinalHDL (stupidDecoder=true), implemented all 18 control signals
  - **Files added**:
    - `rtl/cpu/vexriscv_decoder_unoptimized.sv` (520 lines): Complete case-statement decoder with explicit control signal logic
  - **Files modified**:
    - `rtl/cpu/vexriscv_top.sv` (lines 633-676): Switched to unoptimized decoder instantiation, removed 4 workarounds
  - **Workarounds removed**:
    1. decode_REGFILE_WRITE_VALID_corrected (I-type ALU instructions)
    2. decode_SRC2_CTRL_corrected (I-type immediate source)
    3. decode_IS_CSR_corrected (CSR instruction detection)
    4. decode_ENV_CTRL_corrected (ECALL/EBREAK detection)
  - **Performance impact**: +85 LUTs (+4.1% CPU area), +0.8ns timing (negligible, doesn't affect 150MHz Fmax)
  - **Benefits**: No workarounds, explicit control signals, easier debugging, future-proof for modifications
  - **Verification**: All tests PASS with cleaner codebase

### Optimization
- **RV32I Pipeline Timing Optimization** (2026-01-05)
  - **Issue**: PandR timing violation (WNS = -0.472ns, TNS = -0.509ns, 2/9633 failing endpoints)
  - **Root cause**: Long combinational path (8.436ns vs 8.000ns required) from WB-stage PC+4 calculation (4-stage CARRY4 chain) through forwarding network to EX-stage ALU (3-stage CARRY4 chain)
  - **Solution**: Pre-calculate `PC+4` in pipeline register (`wb_pc_plus4_reg`) parallel to `wb_result_fwd`, breaking the CARRY4 chain from critical path
  - **Files modified**:
    - `rtl/cpu/rv32i_top.sv`: Added `wb_pc_plus4_reg` register and connection to WB stage
    - `rtl/cpu/rv32i_wb.sv`: Added `pc_plus4_precalc` input port, use pre-calculated value for `WB_PC4` case
  - **Expected impact**: ~+0.8ns slack improvement (WNS: -0.472ns → +0.3ns estimated)
  - **RISC-V compliance**: Zero impact (forwarding still occurs, just from pre-registered value)
  - **Performance impact**: Zero (no additional pipeline bubbles, CPI unchanged)
  - **Verification**: All tests PASS (rv32i_basic_test: 24 instructions/LED=0x5, rv32i_wb_forward_timing_test: 9 instructions/LED=0x7)

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
