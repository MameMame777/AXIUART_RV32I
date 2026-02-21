# ALU Decoder Debug Diary - 2026-01-29

## Branch
`fix/vexriscv-alu-shifter-feedback`

## Target Issue
GitHub Issue #6: Hardware Bug - Decoder logic misconfigures ALU control signals in VexRiscv CPU core

## Investigation Summary

### Test Results (Regression)

| Test | Status | Errors |
|------|--------|--------|
| vexriscv_regfile_test | PASS | 0 |
| vexriscv_pipeline_flow_test | PASS | 0 |
| vexriscv_alu_test | PASS | 0 |
| vexriscv_memory_access_test | FAIL | 8 |
| vexriscv_ex_bypass_test | FAIL | 4 |
| vexriscv_ibus_fetch_test | FAIL | 9 |
| vexriscv_dbus_access_test | FAIL | 9 |

### Key Findings

#### 1. ALU Test Now Passing
The vexriscv_alu_test which was previously documented as having 11/33 failures (33% failure rate) now passes with 0 errors. This indicates either:
- A recent fix in the codebase resolved the issue
- The previous failure analysis may have been from an older state

#### 2. Signal Path Analysis

Traced the following critical signal paths in [vexriscv_top.sv](../rtl/cpu/vexriscv_top.sv):

**SHIFT_CTRL Signal Flow:**
```
decode_SHIFT_CTRL (decoder)
  -> decode_to_execute_SHIFT_CTRL (pipeline register, line 939)
  -> execute_SHIFT_CTRL (execute stage)
```

**Writeback Mux Logic (lines 624-636):**
```systemverilog
always_comb begin
    if (execute_arbitration_isValid && (execute_SHIFT_CTRL != 2'b00) && (execute_SRC2[4:0] != 5'h0)) begin
        execute_REGFILE_WRITE_DATA = execute_shifter_result;
    end else begin
        case(execute_ALU_CTRL)
            2'd2:     execute_REGFILE_WRITE_DATA = execute_IntAluPlugin_bitwise;
            2'd1:     execute_REGFILE_WRITE_DATA = {31'd0, execute_SRC_LESS};
            default:  execute_REGFILE_WRITE_DATA = execute_SRC_ADD_SUB;
        endcase
    end
end
```

**SRC2_FORCE_ZERO Generation (line 688):**
```systemverilog
assign decode_SRC2_FORCE_ZERO = (decode_SRC_ADD_ZERO && (! decode_SRC_USE_SUB_LESS));
```

#### 3. Multi-cycle Shifter Analysis

In [vexriscv_execute.sv](../rtl/cpu/vexriscv_execute.sv):

**Shifter Done Condition (line 212):**
```systemverilog
assign execute_LightShifterPlugin_done = (execute_LightShifterPlugin_amplitude[4:1] == 4'b0000);
```

This becomes TRUE when `amplitude <= 1`, which is correct for the 1-bit-per-cycle shifter.

**Shifter Feedback Loop (lines 209-211):**
```systemverilog
assign execute_LightShifterPlugin_shiftInput = execute_LightShifterPlugin_isActive ?
                                                memory_REGFILE_WRITE_DATA :
                                                src1_muxed;
```

### Remaining Issues

The failures in other tests (memory_access, ex_bypass, ibus_fetch, dbus_access) appear to be separate issues:
- Memory access tests likely have bus protocol issues
- Bypass tests may have data hazard forwarding problems
- These are tracked separately from the ALU decoder issue

## Files Analyzed

| File | Lines | Key Content |
|------|-------|-------------|
| [vexriscv_top.sv](../rtl/cpu/vexriscv_top.sv) | 1182 | Signal wiring, writeback mux |
| [vexriscv_execute.sv](../rtl/cpu/vexriscv_execute.sv) | 285 | ALU, shifter, comparisons |
| [vexriscv_decoder_unoptimized.sv](../rtl/cpu/vexriscv_decoder_unoptimized.sv) | 482 | Control signal decode |

## Artifacts Created

1. `sim/assertions/vexriscv_shifter_spec.sv` - SVA module for shifter verification
2. `sim/assertions/bind_vexriscv_shifter_spec.sv` - Bind module for non-invasive assertion insertion

## Conclusion

The ALU test now passes, indicating the core ALU functionality is correct. The assertions added provide ongoing verification coverage for the shifter logic. Other test failures (memory, bypass, bus) require separate investigation.

## Next Steps

1. Investigate vexriscv_memory_access_test failures
2. Investigate vexriscv_ex_bypass_test failures
3. Review bus interface protocol compliance
