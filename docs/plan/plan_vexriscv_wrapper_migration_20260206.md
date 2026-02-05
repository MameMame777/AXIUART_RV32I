# VexRiscv Generated RTL Wrapper Migration Plan

**Date**: 2026-02-06  
**Branch**: vexriscvwrap  
**Status**: Implementation

## Overview

Migrate from hand-written SystemVerilog CPU modules (`rtl/cpu/`, 16 files, ~5000 lines) to SpinalHDL-generated VexRiscv RTL (`VexRiscv.v`, ~3500 lines) with adapter infrastructure for AXI_UART integration.

## Key Decisions

| Item | Decision |
|------|----------|
| Reset architecture | Shared reset (same as system) |
| EBREAK handling | Keep `vexriscv_ebreak_monitor.sv` |
| Reset vector | 0x80000000 (matches existing tests) |
| Performance counters | Use CsrPlugin `mcycle`/`minstret` |
| Trace buffer | Add debug probes via hierarchical refs |
| DebugPlugin | Enable with shared ClockDomain |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    vexriscv_wrapper.sv                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   VexRiscv   │  │  iBus_adapter │  │  dBus_adapter │          │
│  │   (generated)│←→│  (PC FIFO)    │←→│  (passthrough)│          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│         ↑                  ↓                  ↓                 │
│  ┌──────────────┐  ┌──────────────────────────────────┐        │
│  │ debug_bridge │  │       vexriscv_mem_crossbar       │        │
│  │ (Reg→DebugBus)│  │  (IBus/DBus/Debug arbitration)    │        │
│  └──────────────┘  └──────────────────────────────────┘        │
│         ↓                          ↓                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ trace_probe  │  │  blockram    │  │ ebreak_monitor│          │
│  │ (hierarchical)│  │  (8KB BRAM)  │  │ (EBREAK det.) │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                            ↑                                    │
│                    ┌──────────────┐                            │
│                    │   control    │                            │
│                    │ (run/halt FSM)│                            │
│                    └──────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    Register_Block (AXI_UART)
```

## VexRiscv Interface Signals (to be exposed)

### IBus (Instruction Bus)
| Signal | Dir | Width | Description |
|--------|-----|-------|-------------|
| `iBus_cmd_valid` | out | 1 | Fetch request valid |
| `iBus_cmd_ready` | in | 1 | Memory ready |
| `iBus_cmd_payload_pc` | out | 32 | PC byte address |
| `iBus_rsp_valid` | in | 1 | Instruction returned |
| `iBus_rsp_payload_error` | in | 1 | Bus error |
| `iBus_rsp_payload_inst` | in | 32 | Fetched instruction |

### DBus (Data Bus)
| Signal | Dir | Width | Description |
|--------|-----|-------|-------------|
| `dBus_cmd_valid` | out | 1 | Load/store request |
| `dBus_cmd_ready` | in | 1 | Memory ready |
| `dBus_cmd_payload_wr` | out | 1 | 1=store, 0=load |
| `dBus_cmd_payload_mask` | out | 4 | Byte enables |
| `dBus_cmd_payload_address` | out | 32 | Byte address |
| `dBus_cmd_payload_data` | out | 32 | Write data |
| `dBus_cmd_payload_size` | out | 2 | 0=byte, 1=half, 2=word |
| `dBus_rsp_ready` | in | 1 | Response valid |
| `dBus_rsp_error` | in | 1 | Bus error |
| `dBus_rsp_data` | in | 32 | Read data |

### Debug Bus (from DebugPlugin)
| Signal | Dir | Width | Description |
|--------|-----|-------|-------------|
| `debug_bus_cmd_valid` | in | 1 | Debug command valid |
| `debug_bus_cmd_ready` | out | 1 | Debug ready |
| `debug_bus_cmd_payload_wr` | in | 1 | Write enable |
| `debug_bus_cmd_payload_address` | in | 8 | Register address |
| `debug_bus_cmd_payload_data` | in | 32 | Write data |
| `debug_bus_rsp_data` | out | 32 | Read data |
| `debug_resetOut` | out | 1 | CPU reset request |

## Implementation Steps

### Step 1: Modify SpinalHDL Config
- Edit `vexriscv_reference/config/GenSmallOptimized.scala`
- Remove `setAsDirectionLess()` calls to expose IBus/DBus
- Add `DebugPlugin(ClockDomain.current)`
- Configure CsrPlugin with `mcycleAccess`/`minstretAccess`
- Set `resetVector = 0x80000000l`
- Run `.\tools\build_vexriscv.ps1 -Config GenSmallOptimized -Clean`

### Step 2: Create rtl/vexriscvwrap/ Directory
New modules:
- `vexriscv_ibus_adapter.sv` - PC tracking FIFO for `iBus_rsp_payload_pc`
- `vexriscv_dbus_adapter.sv` - DBus passthrough (minimal)
- `vexriscv_debug_bridge.sv` - Register_Block → DebugPlugin protocol
- `vexriscv_trace_probe.sv` - Hierarchical signal taps for trace buffer
- `vexriscv_wrapper.sv` - Top integration

### Step 3: Port Infrastructure Modules
Copy from `rtl/cpu/`:
- `vexriscv_blockram.sv`
- `vexriscv_mem_crossbar.sv`
- `vexriscv_ebreak_monitor.sv`
- `vexriscv_control.sv`
- `vexriscv_stream_fifo.sv`

### Step 4: Delete rtl/cpu/ Directory
Remove all 16 files after new wrapper compiles.

### Step 5: Update Integration
- Modify `rtl/AXIUART_Top.sv` to instantiate from `rtl/vexriscvwrap/`
- Update `test_vexriscv.f` filelist

### Step 6: Regression Testing
```powershell
.\scripts\run_regression.ps1 -Stage 1 -Tests vexriscv_smoke,vexriscv_hazard
```

## Module Summary

| Module | Lines (est) | Purpose |
|--------|-------------|---------|
| `VexRiscv.v` | 3500 | Generated CPU core |
| `vexriscv_ibus_adapter.sv` | 100 | PC FIFO for response tracking |
| `vexriscv_dbus_adapter.sv` | 50 | DBus passthrough |
| `vexriscv_debug_bridge.sv` | 150 | Reg→Debug protocol |
| `vexriscv_trace_probe.sv` | 100 | Signal taps for trace |
| `vexriscv_wrapper.sv` | 350 | Top integration |
| `vexriscv_blockram.sv` | 250 | 8KB BRAM (ported) |
| `vexriscv_mem_crossbar.sv` | 450 | Bus arbitration (ported) |
| `vexriscv_ebreak_monitor.sv` | 150 | EBREAK detection (ported) |
| `vexriscv_control.sv` | 220 | Run/halt FSM (ported) |
| `vexriscv_stream_fifo.sv` | 220 | Generic FIFO (ported) |
| **Total** | **~5540** | |

## Risk Mitigation

1. **IBus timing mismatch**: Adapter adds PC FIFO to regenerate `iBus_rsp_payload_pc`
2. **Debug protocol complexity**: Bridge translates simple register commands to VexRiscv debug bus
3. **Trace signal access**: Use hierarchical references (`core.decode_PC`, etc.) with `(* keep = "true" *)` attributes
4. **CsrPlugin counter access**: Map CSR reads to performance counter outputs

## Success Criteria

- [ ] VexRiscv.v generates with exposed IBus/DBus/Debug
- [ ] All vexriscvwrap modules compile without errors
- [ ] `vexriscv_smoke` tests pass
- [ ] `vexriscv_hazard` tests pass
- [ ] Performance counters report correct values
- [ ] Trace buffer captures instruction flow
