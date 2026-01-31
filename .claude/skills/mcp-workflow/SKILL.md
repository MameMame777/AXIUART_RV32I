---
name: dsim-workflow
description: DSIM UVM test execution workflow using PowerShell scripts. Use when compiling tests, running simulations, executing regression suites, or troubleshooting DSIM issues.
---

# DSIM UVM Test Workflow

PowerShell script-based workflow for the AXIUART_RV32I verification environment.

## When to Use This Skill

- Compiling or running UVM tests
- Executing regression test suites
- Troubleshooting DSIM environment issues
- Understanding VS Code task integration

## Primary Workflow (MANDATORY)

**Use PowerShell scripts** in [scripts/](../../scripts/)

| Script | Purpose |
|--------|---------|
| `run_test.ps1` | Single test execution |
| `run_regression.ps1` | Batch test execution |

**Note:** MCP-based execution has been deprecated. The `deprecated_mcp_server/` directory is retained for reference only.

## Standard UVM Test Sequence

### 1. Run Single Test

```powershell
.\scripts\run_test.ps1 <test_name> [-Verbosity <level>] [-Waves] [-Seed <n>]
```

**Examples:**

```powershell
# Basic test execution
.\scripts\run_test.ps1 vexriscv_regfile_test

# With waveform capture
.\scripts\run_test.ps1 vexriscv_alu_test -Waves

# With higher verbosity
.\scripts\run_test.ps1 vexriscv_pipeline_flow_test -Verbosity UVM_MEDIUM
```

### 2. Run Regression Suite

```powershell
.\scripts\run_regression.ps1 [-Stage <n>] [-Tests <list>] [-Verbosity <level>] [-Waves] [-StopOnFail]
```

**Examples:**

```powershell
# Run all Stage 1 tests
.\scripts\run_regression.ps1 -Stage 1

# Run specific tests
.\scripts\run_regression.ps1 -Tests vexriscv_regfile_test,vexriscv_alu_test

# Stop on first failure
.\scripts\run_regression.ps1 -Stage 1 -StopOnFail
```

## Available Tests (Stage 1)

| Test Name | Purpose |
|-----------|---------|
| `vexriscv_regfile_test` | Register file read/write |
| `vexriscv_alu_test` | ALU operations |
| `vexriscv_pipeline_flow_test` | Pipeline instruction flow |
| `vexriscv_ibus_fetch_test` | Instruction bus fetching |
| `vexriscv_memory_access_test` | Load/Store operations |
| `vexriscv_ex_bypass_test` | EX stage forwarding |
| `vexriscv_mem_bypass_test` | MEM stage forwarding |
| `vexriscv_wb_bypass_test` | WB stage forwarding |
| `vexriscv_load_use_stall_test` | Load-use hazard stall |
| `vexriscv_dbus_access_test` | Data bus access |

## Script Parameters

### run_test.ps1

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-TestName` | string | (required) | UVM test class name |
| `-Verbosity` | enum | UVM_LOW | UVM_LOW, UVM_MEDIUM, UVM_HIGH, UVM_DEBUG |
| `-Waves` | switch | false | Enable waveform capture (.mxd) |
| `-Seed` | int | 1 | Random seed |
| `-CompileOnly` | switch | false | Compile without running |
| `-RunOnly` | switch | false | Run using existing compiled image |

### run_regression.ps1

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Stage` | int | 0 | Run tests for specific stage (1, 2, etc.) |
| `-Tests` | string[] | @() | Comma-separated list of specific tests |
| `-Verbosity` | enum | UVM_LOW | UVM verbosity level |
| `-Waves` | switch | false | Enable waveform capture for all tests |
| `-StopOnFail` | switch | false | Stop regression on first failure |
| `-ReportFile` | string | auto | Custom report file path |

## VS Code Task Integration

Use VS Code tasks from the Command Palette (Ctrl+Shift+P > "Tasks: Run Task"):

| Task | Description |
|------|-------------|
| `DSIM: Run Single Test` | Run selected test with chosen verbosity |
| `DSIM: Run Single Test with Waves` | Run with waveform capture |
| `DSIM: Run Stage 1 Regression` | Run all Stage 1 tests |
| `DSIM: Run Selected Tests` | Run comma-separated test list |
| `DSIM: Run regfile_test` | Quick access to regfile test |
| `DSIM: Run alu_test` | Quick access to ALU test |

## Output Locations

| Output Type | Location |
|-------------|----------|
| **Test logs** | [sim/exec/logs/<test_name>_<timestamp>.log](../../sim/exec/logs/) |
| **Result JSON** | [sim/exec/logs/<test_name>_<timestamp>_result.json](../../sim/exec/logs/) |
| **Waveforms** | [sim/exec/wave/<test_name>_<timestamp>.mxd](../../sim/exec/wave/) |
| **Regression report** | [sim/exec/logs/regression_<timestamp>.txt](../../sim/exec/logs/) |
| **Regression JSON** | [sim/exec/logs/regression_<timestamp>.json](../../sim/exec/logs/) |

## Result JSON Format

### Single Test Result

```json
{
  "test_name": "vexriscv_regfile_test",
  "status": "success",
  "exit_code": 0,
  "log_file": "sim/exec/logs/vexriscv_regfile_test_20260131_111315.log",
  "wave_file": "",
  "timestamp": "20260131_111315"
}
```

### Regression Result

```json
{
  "timestamp": "20260131_111114",
  "total_tests": 3,
  "passed": 3,
  "failed": 0,
  "skipped": 0,
  "status": "PASS",
  "results": {
    "vexriscv_regfile_test": "PASS",
    "vexriscv_alu_test": "PASS",
    "vexriscv_pipeline_flow_test": "PASS"
  }
}
```

## Common Workflows

### Quick Compile-Run Cycle

```powershell
# Compile only
.\scripts\run_test.ps1 my_test -CompileOnly

# Run using compiled image
.\scripts\run_test.ps1 my_test -RunOnly
```

### Debug with Waveforms

```powershell
.\scripts\run_test.ps1 vexriscv_memory_access_test -Waves -Verbosity UVM_DEBUG
```

### Full Stage 1 Regression

```powershell
.\scripts\run_regression.ps1 -Stage 1 -Verbosity UVM_LOW
```

## DSIM Environment

Scripts automatically configure DSIM environment:

- `DSIM_HOME`: C:\Program Files\Altair\DSim\2025.1
- License auto-discovery from standard locations
- PATH includes DSIM binaries and dependencies

### Environment Variables (Auto-configured)

| Variable | Value |
|----------|-------|
| `DSIM_HOME` | Installation directory |
| `DSIM_ROOT` | Same as DSIM_HOME |
| `DSIM_LIB_PATH` | DSIM_HOME/lib |
| `DSIM_LICENSE` | Auto-discovered license file |

## Troubleshooting

### DSIM Not Found

Verify DSIM installation:
```powershell
Test-Path "C:\Program Files\Altair\DSim\2025.1\bin\dsim.exe"
```

### License Issues

Check license file locations:
- `C:\Program Files\Altair\dsim-license.json`
- `C:\Program Files\Altair\DSim\2025.1\dsim-license.json`
- `$env:LOCALAPPDATA\metrics-ca\dsim-license.json`

### Test Not Found

Verify test exists in [sim/tests/](../../sim/tests/) and is listed in [sim/uvm/tb/dsim_config.f](../../sim/uvm/tb/dsim_config.f).

### Compilation Errors

See `dsim-debugging` skill for detailed troubleshooting.

## Deprecated MCP Server

The MCP server has been deprecated. Files are retained in `deprecated_mcp_server/` for reference only.

**Do not use:**
- `deprecated_mcp_server/mcp_client.py`
- `deprecated_mcp_server/dsim_fastmcp_server.py`
- `deprecated_mcp_server/run_regression.py`

## Summary

Workflow principles:
1. Use PowerShell scripts in [scripts/](../../scripts/) (mandatory)
2. Standard sequence: `run_test.ps1` for single tests, `run_regression.ps1` for batch
3. Use VS Code tasks for common operations
4. Consume JSON outputs from [sim/exec/logs/](../../sim/exec/logs/)
5. Check waveforms in [sim/exec/wave/](../../sim/exec/wave/) when debugging
6. See `dsim-debugging` skill for troubleshooting
