# Default Environment Configuration

**Effective Date:** 2025-12-07  
**Default Environment:** `sim/uvm_simplified` (UBUS-style)

## Overview

The DSIM UVM simulation environment now defaults to the **simplified environment** (`sim/uvm_simplified`). This provides faster compilation, easier debugging, and clearer structure for UART core verification.

## Default Settings

### MCP Server Defaults
- **use_simplified:** `True` (changed from `False`)
- **test_name:** `axiuart_basic_test` (changed from `uart_axi4_basic_test`)
- **environment:** `sim/uvm_simplified/tb`

### Files Modified
1. **dsim_uvm_server.py** - Line 447: `use_simplified: bool = True`
2. **dsim_fastmcp_server.py** - Line 320: `use_simplified: bool = True`
3. **dsim_fastmcp_server.py** - Line 381: `use_simplified: bool = True` (batch mode)
4. **mcp_client.py** - Line 64: Default test name changed to `axiuart_basic_test`

## Usage

### Run with Default (Simplified Environment)
```bash
# No flag needed - defaults to simplified
python mcp_server/mcp_client.py --tool run_uvm_simulation --test-name axiuart_basic_test

# Or via batch mode
python mcp_server/mcp_client.py --tool run_uvm_simulation_batch --test-name axiuart_basic_test
```

### Use Full Environment (Opt-in)
To use the full environment (`sim/uvm`), add `--no-use-simplified` or explicitly pass the parameter:

```bash
# Using mcp_client (requires code modification for --no-use-simplified flag)
# Currently: manually specify full environment test
python mcp_server/mcp_client.py --tool run_uvm_simulation --test-name uart_axi4_basic_test
```

**Note:** To properly support `--no-use-simplified`, you would need to modify `mcp_client.py` to pass `use_simplified=False` when the flag is not present. Currently, the workaround is to use different test names:
- `axiuart_basic_test` → simplified environment (default)
- `uart_axi4_basic_test` → full environment (requires explicit setup)

## Environment Comparison

| Aspect | Simplified (Default) | Full Environment |
|--------|---------------------|------------------|
| **Path** | `sim/uvm_simplified/tb` | `sim/uvm` |
| **Top Module** | `axiuart_tb_top` | `uart_axi4_tb_top` |
| **Test Name** | `axiuart_basic_test` | `uart_axi4_basic_test` |
| **Components** | UART Agent + Scoreboard | UART + AXI4 Agents + Scoreboard |
| **Compilation Time** | ~5 seconds | ~10-15 seconds |
| **Use Case** | UART core verification | Full UART-AXI4 bridge verification |

## Rationale

### Why Simplified as Default?

1. **Faster Development Cycle**
   - Compilation: ~5s vs ~10-15s
   - Easier to debug (fewer components)
   - Clearer test structure

2. **UBUS Pattern Compliance**
   - Follows Accellera UBUS reference architecture
   - Industry-standard structure
   - Better maintainability

3. **Focused Testing**
   - UART core functionality isolated
   - Clearer pass/fail criteria
   - Simpler waveform analysis

4. **Educational Value**
   - Easier for new team members
   - Clear separation of concerns
   - Better documentation reference

### When to Use Full Environment?

Use `sim/uvm` when you need:
- AXI4-Lite master functionality verification
- Register read/write via AXI4 protocol
- Cross-protocol (UART ↔ AXI4) transaction checking
- Coverage of full bridge behavior
- Integration-level testing

## Migration Guide

### For Existing Scripts

If you have scripts calling the MCP server directly, they will now default to simplified. To keep using the full environment:

**Option 1:** Change test name
```python
# Old (now runs in simplified)
result = await run_uvm_simulation(test_name="uart_axi4_basic_test")

# New (explicitly use full env - requires manual env selection)
# Currently not fully supported via use_simplified flag alone
```

**Option 2:** Add environment detection logic
```python
def determine_environment(test_name: str) -> bool:
    """Determine if simplified environment should be used"""
    # Simplified tests
    if test_name.startswith("axiuart_"):
        return True
    # Full environment tests
    elif test_name.startswith("uart_axi4_"):
        return False
    # Default
    return True
```

### For VS Code Tasks

Update `tasks.json` to reflect new defaults:

```json
{
    "label": "DSIM: Run Basic Test (Default Simplified)",
    "type": "shell",
    "command": "python",
    "args": [
        "${workspaceFolder}/mcp_server/mcp_client.py",
        "--workspace", "${workspaceFolder}",
        "--tool", "run_uvm_simulation",
        "--test-name", "axiuart_basic_test"
        // No --use-simplified needed - it's the default
    ]
}
```

## Verification

To verify the current default environment:

```bash
# Check what runs by default
python mcp_server/mcp_client.py --tool run_uvm_simulation --test-name axiuart_basic_test --mode compile

# Check log output for:
# - "Run directory: .../sim/uvm_simplified/tb" ✅
# - "Top-level modules: axiuart_tb_top" ✅
```

## Rollback Instructions

To revert to full environment as default:

```bash
# Revert the changes in these files:
git diff mcp_server/dsim_uvm_server.py        # Line 447: False
git diff mcp_server/dsim_fastmcp_server.py    # Lines 320, 381: False
git diff mcp_server/mcp_client.py             # Line 64: uart_axi4_basic_test

# Or manually edit:
# use_simplified: bool = False  (in all 3 locations)
# return args.test_name or "uart_axi4_basic_test"
```

## Summary

**Default Changed:** `sim/uvm` → `sim/uvm_simplified`  
**Impact:** Faster, simpler, UBUS-compliant testing by default  
**Opt-out:** Use different test names or modify scripts  
**Verification:** Check log files for "Run directory" and "Top-level modules"

---

**Last Updated:** 2025-12-07  
**Author:** DSIM UVM Team  
**Status:** Active
