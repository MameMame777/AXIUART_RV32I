# Load-Use Stall Test

**Test Name**: `rv32i_load_use_stall_test`  
**Created**: 2026-01-05  
**Priority**: HIGH  

## Purpose

Comprehensive verification of load-use hazard detection and 1-cycle pipeline stall insertion.

## Background

**Load-Use Hazard**:
When an instruction immediately following a LOAD tries to use the loaded value, the pipeline must stall for 1 cycle because load data is not available until MEM stage completes.

**Pipeline Behavior**:
```
Normal:      IF → ID → EX → MEM → WB
Load-use:    LW in MEM (data available)
             ADD in ID (needs data) → STALL 1 cycle
             ADD retries in ID → EX (data forwarded from MEM)
```

## Test Scenarios

1. **Basic load-use**: `LW` → `ADD` (uses both rs1 and rs2)
2. **Dependent calculation**: `ADD` result used by next `ADD`
3. **Memory store/load cycle**: Store → Load → Use

## Expected Behavior

- Load-use detected: `if_stall=1`, `id_stall=1` for 1 cycle
- Pipeline bubble inserted in EX stage
- Correct data forwarded from MEM stage after stall
- No incorrect data used in calculations

## Test Program

```assembly
0x0000: ADDI x1, x0, 0x100      # x1 = 0x100 (memory base)
0x0004: ADDI x2, x0, 42         # x2 = 42
0x0008: SW   x2, 0(x1)          # mem[0x100] = 42
0x000C: LW   x3, 0(x1)          # x3 = mem[0x100] = 42
0x0010: ADD  x4, x3, x3         # x4 = 84 (LOAD-USE STALL HERE)
0x0014: ADDI x5, x0, 99         # x5 = 99
0x0018: ADD  x6, x4, x5         # x6 = 183
0x001C: EBREAK                  # Halt
```

## Verification Points

1. **x3 = 42** - Load completed correctly
2. **x4 = 84** - Load-use stall occurred, correct forwarding (42 + 42)
3. **x5 = 99** - Execution continued after stall
4. **x6 = 183** - Dependent calculation correct (84 + 99)
5. **mem[0x100] = 42** - Store/load cycle worked

## Critical Checks

If **x4 ≠ 84**:
- **x4 = 0**: Stall did not occur OR forwarding failed
- **x4 = other**: Data corruption in forwarding path

## Execution

```powershell
# Compile + Run
python mcp_server/mcp_client.py --workspace . --tool run_uvm_simulation `
  --test-name rv32i_load_use_stall_test --mode run --verbosity UVM_MEDIUM --waves
```

## Success Criteria

- All assertions pass
- x4 = 84 (proves stall occurred and MEM-to-EX forwarding worked)
- All register values match expected
- Trace buffer shows LW followed by ADD with correct results

## Related Documentation

- [docs/cpu/03_hazard_unit.md](../../docs/cpu/03_hazard_unit.md) - Hazard detection logic
- [docs/cpu/04_ex_stage.md](../../docs/cpu/04_ex_stage.md) - Forwarding implementation
- [docs/cpu/08_integration.md](../../docs/cpu/08_integration.md) - Load-use stall example
