# Issue: VexRiscv ALU Test AUIPC Instruction PC Mismatch

## Issue Summary
`vexriscv_alu_test` fails with x30 register value mismatch:
- **Expected**: `0x80000098` (instruction index 38)
- **Actual**: `0x80000094` (instruction index 37)
- **Difference**: 4 bytes (1 instruction)

## Root Cause Analysis

### Test Structure
The test builds instructions directly in `load_test_program()`:
```systemverilog
test_program[33] = 32'h00000F17;  // AUIPC x30, 0
```

This instruction is written to address `0x80000000 + (33 * 4) = 0x80000084`.

### AUIPC Expected Behavior
`AUIPC x30, 0` should set:
```
x30 = PC + (0 << 12) = PC = 0x80000084
```

### Test Expectation
From `verify_alu_results()`:
```systemverilog
expected_x30 = 32'h80000098;  // Expected PC value for AUIPC
```

This is `0x80000000 + (38 * 4)`, which is 5 instructions AFTER the AUIPC instruction at index 33.

## Analysis

### Instruction Flow
```
Index 33 @ 0x80000084: AUIPC x30, 0   ← PC captured here
Index 34 @ 0x80000088: LUI x29, ...
Index 35 @ 0x8000008C: LUI x31, ...
Index 36 @ 0x80000090: ADDI x31, ...
Index 37 @ 0x80000094: (actual x30 value)
Index 38 @ 0x80000098: (expected x30 value)
```

### Possible Causes

1. **Pipeline Stage Mismatch**
   - AUIPC captures PC at wrong pipeline stage
   - Fetch vs Execute vs WriteBack PC value
   - VexRiscv might use next-PC or PC+4 instead of current PC

2. **Test Expectation Error**
   - Test assumes AUIPC uses PC + offset
   - But VexRiscv implementation might use next-PC + offset
   - Discrepancy of 4 bytes suggests PC+4 behavior

3. **NOP Padding Side Effect**
   - NOPs at indices 7, 15, 23, 31 for "Bad Address" workaround
   - Could affect PC calculation if NOPs are skipped
   - Or if pipeline behavior changes with NOPs

## NOT Related To
- ✗ Hex file loading (test uses `write_memory_backdoor()` directly)
- ✗ Memory initialization (instructions are correctly written)
- ✗ Missing `load_memory_backdoor()` implementation (different issue)

## Investigation Plan

1. **Check VexRiscv AUIPC Implementation**
   ```systemverilog
   // In vexriscv_execute.sv or similar
   // Does AUIPC use:
   //   - decode_pc (instruction fetch PC)
   //   - execute_pc (execution stage PC)
   //   - execute_pc + 4 (next instruction PC)
   ```

2. **Verify Pipeline PC Propagation**
   - Trace PC through Fetch → Decode → Execute → WriteBack
   - Check if PC value is correct at each stage
   - Look for PC+4 incrementing logic

3. **Test with Different AUIPC Offset**
   - Try `AUIPC x30, 1` to see if offset is applied correctly
   - Expected: PC + (1 << 12) = PC + 4096
   - If still off by 4, confirms PC calculation issue

4. **Review Test Expectations**
   - Check if test expectations match VexRiscv specification
   - Original VexRiscv might have PC+4 behavior for AUIPC
   - RISC-V spec says AUIPC should use current PC, not PC+4

## Recommended Fix

**Option 1**: Fix Test Expectation (if VexRiscv is correct)
```systemverilog
// vexriscv_alu_test.sv
// If VexRiscv uses PC+4 for AUIPC:
expected_x30 = 32'h80000088;  // AUIPC at 0x84, captures PC+4 = 0x88
```

**Option 2**: Fix VexRiscv AUIPC (if test is correct)
```systemverilog
// vexriscv_execute.sv
// Change from:
auipc_result = execute_pc + 4 + (imm_u << 12);
// To:
auipc_result = execute_pc + (imm_u << 12);
```

**Option 3**: Accept 4-byte Offset
- Document that VexRiscv AUIPC uses PC+4 semantics
- Update all test expectations accordingly

## Status
- [x] Root cause identified (AUIPC PC mismatch)
- [ ] VexRiscv AUIPC implementation reviewed
- [ ] Pipeline PC propagation verified
- [ ] Fix decision made (RTL vs test expectations)
- [ ] Fix implemented and tested

## Related Issues
- Issue #34: Hex loader implementation (different, now fixed)
- Regression failures: 4/10 tests failing (may have similar PC issues)

## References
- RISC-V Specification: AUIPC should use current PC
- VexRiscv GenSmallOptimized configuration
- Test file: `sim/tests/vexriscv_alu_test.sv`
- RTL files: `rtl/cpu/vexriscv_execute.sv`, `rtl/cpu/vexriscv_fetch.sv`
