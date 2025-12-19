# DSIM UVM MCP Server (FastMCP Edition)

## Status — October 15, 2025

- FastMCP 2.12.4 server (`dsim_fastmcp_server.py`) is the only MCP entry point.
- Reference DSIM integration lives in `dsim_uvm_server.py` and is validated on Windows selector event loop.
- Legacy helper scripts were removed; the MCP tools now expose all required operations directly.

## Key Components

- `dsim_fastmcp_server.py` – FastMCP server definition and tool registry.
- `dsim_uvm_server.py` – DSIM command orchestration, logging, and analysis utilities.
- `mcp_client.py` – Standard MCP stdio client for local execution/testing.
- `setup.py` / `setup_dsim_env.py` – Dependency install and DSIM environment verification helpers.
- `requirements.txt` – Python package list required by the server.
- `dsim.env` – Optional environment snapshot used by CI tasks.

## Getting Started


1. Install dependencies (once per environment):

   ```powershell
   cd e:\Nautilus\workspace\fpgawork\AXIUART_\mcp_server
   python setup.py
   ```

2. Ensure DSIM variables are defined (`DSIM_HOME`, `DSIM_ROOT`, `DSIM_LIB_PATH`, `DSIM_LICENSE`). The `setup_dsim_env.py` helper can validate these.

3. Start the server (VS Code task **“🚀 Start Enhanced MCP Server (FastMCP Edition)”** runs this automatically):

   ```powershell
   python dsim_fastmcp_server.py --workspace e:\Nautilus\workspace\fpgawork\AXIUART_
   ```

## Using the MCP Client

All tooling is exposed through `mcp_client.py`. Examples below assume the workspace root.

```powershell
# Environment diagnostics
python mcp_server\mcp_client.py --workspace . --tool check_dsim_environment

# Discover registered UVM tests
python mcp_server\mcp_client.py --workspace . --tool list_available_tests

# Compile-only run
python mcp_server\mcp_client.py --workspace . --tool compile_design_only --test-name uart_axi4_basic_test --verbosity UVM_LOW --timeout 120

# Full simulation
python mcp_server\mcp_client.py --workspace . --tool run_uvm_simulation --test-name uart_axi4_basic_test --mode run --verbosity UVM_MEDIUM --timeout 300

# Waveform generation (MXD)
python mcp_server\mcp_client.py --workspace . --tool generate_waveforms --test-name uart_axi4_basic_test --timeout 300
```

Outputs are returned as structured JSON; `mcp_client.py` prints a prettified view if content is JSON-serialisable.

## Available MCP Tools

| Tool Name             | Description                                  |
|-----------------------|----------------------------------------------|
| `check_dsim_environment` | Validates DSIM installation and workspace structure |
| `list_available_tests` | Enumerates discovered `_test.sv` files with metadata |
| `compile_design_only`  | Generates a DSIM image without running simulation |
| `run_uvm_simulation`   | Runs compile/elaborate/run depending on `mode` |
| `run_simulation`       | Executes an existing DSIM image (post-compile) |
| `generate_waveforms`   | Runs simulation with MXD waveform dumping |
| `get_simulation_logs`  | Returns tail content for recent DSIM logs |

## Legacy Cleanup (October 2025)

The following scripts were retired and removed: `check_dsim_env.py`, `dsim_mcp_simplified.py`, `fastmcp_client.py`, `fastmcp_final_test.py`, `list_available_tests.py`, `run_uvm_simulation.py`. All functionality now exists within the MCP server itself. Update any external references to use `mcp_client.py` commands instead.

## Troubleshooting

- **Server fails to launch** – confirm `python dsim_fastmcp_server.py --debug` and inspect logs for missing environment variables.
- **Client cannot connect** – ensure the VS Code task is running or start the server manually, then re-run `mcp_client.py`.
- **DSIM compilation errors** – review `sim/exec/logs/*.log` or call `get_simulation_logs` to surface the most recent diagnostics.

For detailed verification procedures refer to `docs/uvm_verification_quality_assurance_instructions_mcp_2025-10-13.md`.

