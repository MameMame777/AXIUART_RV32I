# WB Forwarding Timing Test

**Test Name**: `rv32i_wb_forward_timing_test`  
**Created**: 2026-01-05  
**Priority**: CRITICAL  

## Purpose

Verifies the WB forwarding timing fix documented in [docs/cpu/06_wb_stage.md](../../docs/cpu/06_wb_stage.md).

## Background

**Initial Bug (2026/1/3)**:
- `wb_result` computed by `always_comb` changes immediately when WB stage advances to next instruction
- EX stage needs cycle N result in cycle N+1, but `wb_result` already shows cycle N+1 result
- Causes incorrect data forwarding to EX stage

**Fix (2026/1/5)**:
```systemverilog
always_ff @(posedge clk) begin
    wb_result_fwd <= wb_result;  // Hold cycle N result for cycle N+1 use
end
```

## Test Scenario

```
Cycle N:   ADDI x27, x0, 7    in WB → wb_result = 0x7
Cycle N+1: LUI  x15, 0x4000   in WB → wb_result = 0x4000000
           SW   x27, 0(x15)   in EX → needs x27 forwarding

Expected (After Fix):  EX receives wb_result_fwd = 0x7 ✓
Bug (Before Fix):      EX receives wb_result = 0x4000000 ✗
```

## Test Program

```assembly
0x0000: ADDI x27, x0, 7         # x27 = 7
0x0004: LUI  x15, 0x4000        # x15 = 0x40000000
0x0008: SW   x27, 0x7C(x15)     # mem[0x4000007C] = x27 (LED register)
0x000C: ADDI x1, x0, 0xAA       # Marker: x1 = 0xAA
0x0010: EBREAK                  # Halt
```

## Verification Points

1. **x27 = 0x00000007** - ADDI result preserved
2. **x15 = 0x40000000** - LUI result
3. **LED output = 0x7** - SW used correct x27 value via wb_result_fwd (CRITICAL)
4. **x1 = 0xAA** - Execution continued correctly

If LED ≠ 0x7, the WB forwarding timing fix is NOT working correctly.

## Execution

```powershell
# Compile + Run
.\scripts\run_test.ps1 rv32i_wb_forward_timing_test -Verbosity UVM_MEDIUM -Waves
```

## Success Criteria

- All assertions pass
- LED output = 0x7 (proves wb_result_fwd holds correct value)
- Register values match expected
- Trace buffer shows correct instruction sequence

## Related Documentation

- [docs/cpu/06_wb_stage.md](../../docs/cpu/06_wb_stage.md) - Complete timing fix explanation
- [docs/cpu/00_overview.md](../../docs/cpu/00_overview.md) - Architecture overview with fix summary
- [docs/cpu/08_integration.md](../../docs/cpu/08_integration.md) - Pipeline timing analysis
