# VexRiscv Test Infrastructure - Quick Start Guide

**Created**: 2026-01-18  
**Status**: Stage 1 Complete (9 tests), Stage 2 Ready (169 ISA tests available)

---

## Overview

Complete VexRiscv CPU verification infrastructure with 3 implementation stages:
- **Stage 1**: Foundation unit tests (9 tests, <70s) - ✅ **COMPLETE**
- **Stage 2**: Integration tests (180+ ISA tests) - ⏳ Ready to execute
- **Stage 3**: Assertion modules (5 modules) - ⏳ Optional debug aids

---

## Quick Commands

### List Available VexRiscv Tests
```powershell
# List available tests
Get-ChildItem sim\tests\*.sv | Select-Object Name
```

### Run Stage 1 Regression Suites
```powershell
# Run Stage 1 regression (all foundation tests)
.\scripts\run_regression.ps1 -Stage 1 -Verbosity UVM_LOW

# Run specific tests
.\scripts\run_regression.ps1 -Tests vexriscv_regfile_test,vexriscv_pipeline_flow_test -Verbosity UVM_LOW
```

### Run Individual Tests
```powershell
# Standard workflow
.\scripts\run_test.ps1 vexriscv_regfile_test -Verbosity UVM_MEDIUM

# With waveforms
.\scripts\run_test.ps1 vexriscv_regfile_test -Verbosity UVM_MEDIUM -Waves
```

---

## Stage 1 Test Inventory

### Smoke Tests (Foundation Validation)

| Test | File | Purpose | Expected Duration |
|------|------|---------|-------------------|
| 1.1 Register File | [vexriscv_regfile_test.sv](../sim/tests/vexriscv_regfile_test.sv) | Register R/W + x0 hardwiring | ~5s |
| 1.2 Pipeline Flow | [vexriscv_pipeline_flow_test.sv](../sim/tests/vexriscv_pipeline_flow_test.sv) | 4-stage pipeline progression | ~5s |
| 1.3 Memory Access | [vexriscv_memory_access_test.sv](../sim/tests/vexriscv_memory_access_test.sv) | LW/SW operations | ~8s |

**Total**: 3 tests, <20s

### Hazard Tests (Data Forwarding Validation)

| Test | File | Purpose | Critical Feature |
|------|------|---------|------------------|
| 1.4 EX Bypass | [vexriscv_ex_bypass_test.sv](../sim/tests/vexriscv_ex_bypass_test.sv) | EX→EX forwarding | No stall (3 cycles) |
| 1.5 MEM Bypass | [vexriscv_mem_bypass_test.sv](../sim/tests/vexriscv_mem_bypass_test.sv) | MEM→EX forwarding | No stall (4 cycles) |
| 1.6 WB Bypass | [vexriscv_wb_bypass_test.sv](../sim/tests/vexriscv_wb_bypass_test.sv) | WB→EX forwarding | **bypassWriteBackBuffer=true** |
| 1.7 Load-Use Stall | [vexriscv_load_use_stall_test.sv](../sim/tests/vexriscv_load_use_stall_test.sv) | Mandatory stall | Exactly 1-cycle stall |

**Total**: 4 tests, <30s  
**Critical**: Test 1.6 validates the bypassWriteBackBuffer fix

### Bus Protocol Tests

| Test | File | Purpose | Expected Duration |
|------|------|---------|-------------------|
| 1.8 IBus Fetch | [vexriscv_ibus_fetch_test.sv](../sim/tests/vexriscv_ibus_fetch_test.sv) | Instruction fetch protocol | ~8s |
| 1.9 DBus Access | [vexriscv_dbus_access_test.sv](../sim/tests/vexriscv_dbus_access_test.sv) | Byte/halfword/word accesses | ~10s |

**Total**: 2 tests, <20s

---

## Stage 2 Integration Tests (Ready to Execute)

### Available ISA Tests (180+ tests from VexRiscv upstream)

**Location**: `vexriscv_reference/source/src/test/resources/hex/`

| Category | Count | Examples | Purpose |
|----------|-------|----------|---------|
| **ISA** | 40 | rv32ui-p-add, rv32ui-p-sub, rv32ui-p-and | RV32I instruction validation |
| **Compliance** | 55 | I-ADD-01, I-SUB-01, I-AND-01 | RISC-V compliance suite |
| **Benchmarks** | 4 | dhrystone, coremark | Performance validation |
| **Custom** | 70 | Various | Additional test programs |

### Execute ISA Test (via MCP tool)
```bash
# Run single ISA test
.\scripts\run_test.ps1 rv32ui-p-add -Verbosity UVM_LOW -Waves
```

### Test Protocol
- **Pass/Fail**: tohost register write (0x00001000)
  - Value = 1: **PASS**
  - Value ≠ 1: **FAIL** (error code)
- **Address Translation**: Automatic (0x80000000 → 0x00000000)
- **Format**: Intel HEX with Python loader

---

## Implementation Architecture

### Test Infrastructure Components

```
Foundation (✅ Complete):
├── Python Hex Loader
│   └── mcp_server/tools/vexriscv_hex_loader.py
│       - Intel HEX parser
│       - Address translation (-0x80000000 offset)
│       - tohost/fromhost address mapping
│
├── UVM Base Test
│   └── sim/uvm/sv/vexriscv_base_test.sv
│       - Extends axiuart_base_test
│       - load_hex_file(path, translate)
│       - wait_for_tohost(max_cycles)
│       - CPU control methods
│
├── tohost Monitor
│   └── sim/uvm/sv/vexriscv_tohost_monitor.sv
│       - UVM monitor for tohost writes
│       - Pass/fail detection
│       - Event-driven completion
│
└── MCP Tools
    ├── list_vexriscv_tests(category)
    └── run_vexriscv_isa_test(name, timeout, waves)
```

### Test Organization

```
sim/tests/
├── vexriscv_regfile_test.sv           # 1.1 Smoke
├── vexriscv_pipeline_flow_test.sv     # 1.2 Smoke
├── vexriscv_memory_access_test.sv     # 1.3 Smoke
├── vexriscv_ex_bypass_test.sv         # 1.4 Hazard
├── vexriscv_mem_bypass_test.sv        # 1.5 Hazard
├── vexriscv_wb_bypass_test.sv         # 1.6 Hazard (CRITICAL)
├── vexriscv_load_use_stall_test.sv    # 1.7 Hazard
├── vexriscv_ibus_fetch_test.sv        # 1.8 Bus
└── vexriscv_dbus_access_test.sv       # 1.9 Bus
```

---

## Configuration Files

### Regression Suites ([sim/regression_tests.json](../sim/regression_tests.json))

Four VexRiscv test suites defined:
- `vexriscv_smoke` - 3 smoke tests
- `vexriscv_hazard` - 4 hazard tests
- `vexriscv_bus` - 2 bus tests
- `vexriscv_stage1` - All 9 Stage 1 tests

### Test Timing ([sim/tests/test_timing_config.json](../sim/tests/test_timing_config.json))

All 9 tests configured with:
- `timeout`: null (no hard timeout, uses cycle-based)
- `recommended_verbosity`: UVM_LOW
- `category`: "fast"
- `waves_recommended`: false (use for debug only)

---

## Assertion Modules (Optional Debug Aids)

### Status: ⏳ Not Yet Implemented

**Location**: `sim/assertions/spec/` (to be created)

| Module | Purpose | Signals Monitored |
|--------|---------|-------------------|
| vexriscv_pipeline_arbitration_spec.sv | Pipeline stage progression | isValid, isStuck, removeIt, flushNext |
| vexriscv_hazard_plugin_spec.sv | RAW hazard detection + bypass | RS1/RS2_USE, RD_WRITE, forward_mux |
| vexriscv_stream_fifo_spec.sv | FIFO protocol compliance | valid, ready, payload, full, empty |
| vexriscv_jump_arbitration_spec.sv | Branch/jump handling | BRANCH_DO, flushNext, PC updates |
| vexriscv_regfile_bypass_spec.sv | Register file bypass | rd_write, rs1/rs2_data, x0 hardwiring |

**Usage**: 
- Default: OFF (no performance impact)
- Debug: Compile with `+define+ENABLE_ASSERTIONS`
- Bind: Separate modules, bound to DUT (non-intrusive)

### Create Assertions (when needed)
```bash
# Create all 5 assertion modules + bind files
# (To be implemented following docs/forCopilot-assertions.md pattern)
```

---

## Success Criteria

### Stage 1 Completion Requirements

- [x] **Tests Created**: 9/9 tests implemented
- [x] **Configuration**: regression_tests.json + test_timing_config.json updated
- [x] **MCP Tools**: list_vexriscv_tests() + run_vexriscv_isa_test() working
- [x] **Python Loader**: Intel HEX parsing + address translation validated
- [ ] **Execution**: Tests pass with actual VexRiscv DUT
- [ ] **Validation**: Cycle counts and behaviors match specification

### Stage 1 Metrics (Target)

| Metric | Target | Current |
|--------|--------|---------|
| Total Tests | 9 | ✅ 9 |
| Pass Rate | 100% | ⏳ Pending execution |
| Duration (smoke) | <20s | ⏳ TBD |
| Duration (hazard) | <30s | ⏳ TBD |
| Duration (bus) | <20s | ⏳ TBD |
| Duration (total) | <70s | ⏳ TBD |

---

## Troubleshooting

### Tests Not Running

**Issue**: vexriscv_base_test methods not connected to DUT

**Solution**: Implement backdoor access in base test class:
```systemverilog
// In vexriscv_base_test.sv, override these methods:
virtual function bit read_memory_backdoor(bit [31:0] addr, output bit [31:0] data);
    data = top.u_blockram.mem[addr[12:2]];  // Adjust hierarchical path
    return 1;
endfunction

virtual function bit [31:0] read_regfile_backdoor(int reg_num);
    return top.u_vexriscv.decode_RegFilePlugin_regFile[reg_num];
endfunction
```

### tohost Monitoring Not Working

**Issue**: tohost_monitor not observing memory writes

**Solution**: Connect monitor in testbench:
```systemverilog
// In testbench, bind tohost monitor to memory controller
bind vexriscv_mem_crossbar vexriscv_tohost_monitor u_tohost_monitor (
    .clk(clk),
    .rst_n(~reset),
    .tohost_addr(32'h00001000)
);
```

### Address Translation Issues

**Test**: Verify hex loader
```powershell
python tools\vexriscv_hex_loader.py `
  vexriscv_reference/source/src/test/resources/hex/rv32ui-p-add.hex `
  --dump
```

---

## Next Steps

1. **Immediate** (Hours):
   - Connect vexriscv_base_test backdoor access to actual DUT
   - Run first smoke test: `vexriscv_regfile_test`
   - Validate cycle counts match expectations

2. **Short-term** (Days):
   - Execute complete Stage 1 regression (`vexriscv_stage1`)
   - Achieve 100% pass rate
   - Measure actual durations vs targets

3. **Medium-term** (Weeks):
   - Begin Stage 2 ISA integration (40 ISA tests first)
   - Create assertion modules for debug (optional)
   - Execute compliance tests (55 tests)

4. **Long-term** (Months):
   - Complete Stage 2 (180+ tests)
   - Run benchmark tests (dhrystone, coremark)
   - Document performance metrics

---

## References

- **Test Plan**: [docs/vexriscv_test_plan.md](vexriscv_test_plan.md) - Complete 3-stage strategy
- **Assertion Guidelines**: docs/forCopilot-assertions.md - Bind-only pattern rules
- **MCP Server**: [mcp_server/dsim_fastmcp_server.py](../mcp_server/dsim_fastmcp_server.py) - Tool implementations
- **VexRiscv Upstream**: vexriscv_reference/ - 180+ pre-compiled test programs

---

**Status**: ✅ Stage 1 infrastructure complete, ready for DUT connection and execution  
**Last Updated**: 2026-01-18 11:41
