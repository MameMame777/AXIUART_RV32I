# VexRiscv ALU Test Failure Analysis
**Date**: 2026-01-20  
**Test**: vexriscv_alu_test  
**Waveform**: sim/exec/wave/vexriscv_alu_test_20260120_212941.mxd  
**Log**: sim/exec/logs/vexriscv_alu_test_20260120_212941.log

---

## Test Summary
- **Total ALU Operations**: 33
- **Failed Operations**: 11
- **Passed Operations**: 22
- **Success Rate**: 66.7%

---

## Failed Operations Analysis

### Category 1: Arithmetic Operations (2 failures)
| Reg | Expected | Actual | Instruction | Operation | Status |
|-----|----------|--------|-------------|-----------|--------|
| x5  | 0x00000018 | 0x00000000 | 0x002082b3 | ADD x5, x1, x2 | **FAIL** |
| x8  | 0x0000000d | 0x00000000 | 0xffd08413 | ADDI x8, x1, -3 | **FAIL** |

**Pattern**: Both failing arithmetic operations return 0x00000000 instead of computed result.

**Hypothesis**: 
- ALU_CTRL may not be set to ADD_SUB (2'b00) correctly
- Or ALU result not being written to register file
- Hazard forwarding issue preventing writeback

---

### Category 2: Comparison Operations (1 failure)
| Reg | Expected | Actual | Instruction | Operation | Status |
|-----|----------|--------|-------------|-----------|--------|
| x18 | 0x00000001 | 0x00000000 | 0x0030b933 | SLTU x18, x1, x3 | **FAIL** |

**Pattern**: SLTU (unsigned comparison) fails when comparing 16 < 0xFFFFFFFF (should be true).

**Hypothesis**:
- `SRC_LESS_UNSIGNED` signal not set correctly for SLTU
- Comparison logic in execute stage incorrectly handling unsigned comparison
- Expected: x18=1 (16 < 0xFFFFFFFF unsigned = TRUE)
- Got: x18=0 (FALSE)

---

### Category 3: Shift Operations (5 failures)
| Reg | Expected | Actual | Instruction | Operation | Status |
|-----|----------|--------|-------------|-----------|--------|
| x23 | 0x00000040 | 0x00000010 | 0x00209b93 | SLLI x23, x1, 2 | **FAIL** |
| x24 | 0x00000010 | 0x00000000 | 0x00111c13 | SLLI x24, x2, 1 | **FAIL** |
| x25 | 0x00000004 | 0x00000000 | 0x00115c93 | SRLI x25, x2, 1 | **FAIL** |
| x26 | 0x00ffffff | 0x00000008 | 0x0021dd33 | SRL x26, x3, x2 | **FAIL** |
| x27 | 0xffffffff | 0x00000000 | 0x4021dd93 | SRAI x27, x3, 2 | **FAIL** |

**Pattern**: ALL shift operations fail - both immediate (SLLI, SRLI, SRAI) and register (SRL).

**Observations**:
- SLLI x23: Expected 16<<2=64, Got 16 (no shift applied)
- SLLI x24: Expected 8<<1=16, Got 0
- SRLI x25: Expected 8>>1=4, Got 0
- SRL x26: Expected 0xFFFFFFFF>>8=0x00FFFFFF, Got 8 (shift amount?)
- SRAI x27: Expected -1>>>2=-1, Got 0

**Hypothesis**:
- **CRITICAL**: `SHIFT_CTRL` decoder output not working correctly
- Multi-cycle shifter may not be executing
- Shift operations appear to either:
  - Not execute at all (returns 0)
  - Return operand unchanged (x23 returns source value)
  - Return shift amount (x26 returns 8 which is x2's value)

---

### Category 4: Upper Immediate Operations (2 failures)
| Reg | Expected | Actual | Instruction | Operation | Status |
|-----|----------|--------|-------------|-----------|--------|
| x29 | 0x12345000 | 0x00000000 | 0x12345eb7 | LUI x29, 0x12345 | **FAIL** |
| x30 | 0x00000074 | 0x00000000 | 0x00000f17 | AUIPC x30, 0 | **FAIL** |

**Pattern**: Both LUI and AUIPC return 0x00000000.

**Hypothesis**:
- `SRC1_CTRL` not selecting immediate correctly
- LUI should use `SRC1_IMU` (2'b01) but may be getting wrong source
- AUIPC should compute PC + (imm<<12), but PC is 0x80000074, expected result is 0x74

**CRITICAL BUG IDENTIFIED**: AUIPC test expects x30=0x00000074, which suggests the test is checking for PC value (0x80000074 truncated). But instruction is at PC=0x80000078, so expected=0x78 would be more accurate. **Test expectation may be incorrect**, OR AUIPC implementation is wrong.

---

### Category 5: Edge Cases (1 failure)
| Reg | Expected | Actual | Instruction | Operation | Status |
|-----|----------|--------|-------------|-----------|--------|
| x31 | 0x0000000f | 0x00000000 | 0xfff08f93 | ADDI x31, x1, -1 | **FAIL** |

**Pattern**: ADDI with negative immediate fails (16-1=15), returns 0.

**Hypothesis**: Same as x8 failure - immediate ALU operations not working.

---

## Failure Pattern Summary

### By Category:
1. **Shift Operations**: 5/5 failures (100% fail rate) - **HIGHEST PRIORITY**
2. **Arithmetic (Immediate)**: 2/3 failures (66% fail rate)
3. **Upper Immediate**: 2/2 failures (100% fail rate)
4. **Comparison**: 1/4 failures (25% fail rate)

### By Instruction Type:
- **I-type immediate ALU**: 3 failures (ADDI x8, ADDI x31, SLTU)
- **I-type shift**: 3 failures (SLLI x23, SLLI x24, SRLI x25)
- **I-type SRAI**: 1 failure (SRAI x27)
- **R-type shift**: 1 failure (SRL x26)
- **R-type arithmetic**: 1 failure (ADD x5)
- **U-type**: 2 failures (LUI, AUIPC)

### Common Patterns:
1. **Most results are 0x00000000** (9 out of 11 failures)
2. **Shift operations completely broken**
3. **Immediate operations affected more than register operations**
4. **Writeback to register file appears to fail for affected instructions**

---

## Critical Findings

### Finding 1: Shift Logic Completely Non-Functional
- **Evidence**: All 5 shift operations fail
- **Severity**: CRITICAL
- **Affected Instructions**: SLLI, SRLI, SRAI, SRL (possibly SRA and SLL too)
- **Next Step**: Inspect `SHIFT_CTRL` decoder output and `vexriscv_execute` shifter logic

### Finding 2: Immediate Source Selection Issue
- **Evidence**: ADDI fails but ADD passes
- **Severity**: HIGH
- **Affected Instructions**: All I-type ALU operations
- **Next Step**: Verify `SRC2_CTRL` selects IMI for I-type instructions

### Finding 3: Upper Immediate Handling Broken
- **Evidence**: Both LUI and AUIPC return 0
- **Severity**: HIGH
- **Affected Instructions**: LUI, AUIPC
- **Next Step**: Verify `SRC1_CTRL` and immediate value propagation

### Finding 4: Register Writeback Suspicious
- **Evidence**: Most failures return 0x00000000 (register x0 value?)
- **Hypothesis**: Instructions may be decoding incorrectly causing `REGFILE_WRITE_VALID=0`
- **Next Step**: Check decoder `REGFILE_WRITE_VALID` signal for failing instructions

---

## Waveform Analysis Targets

Priority signals to inspect in waveform:

### Decoder Stage (for each failing instruction):
1. `decode_INSTRUCTION` - Confirm instruction encoding
2. `decode_ALU_CTRL` - Should match operation type
3. `decode_SHIFT_CTRL` - Critical for shift failures
4. `decode_SRC1_CTRL` / `decode_SRC2_CTRL` - Source mux selection
5. `decode_REGFILE_WRITE_VALID` - Must be 1 for writeback
6. Pattern matchers: `when_Decoder_l112_XX` - Verify instruction detection

### Execute Stage:
1. `execute_INSTRUCTION` - Pipeline propagation
2. `execute_ALU_CTRL`, `execute_SHIFT_CTRL` - Control signals after pipeline
3. `execute_SRC1`, `execute_SRC2` - Operand values
4. `src1_muxed`, `src2_muxed` - After mux selection
5. `execute_SRC_ADD_SUB` - ALU adder output
6. `execute_LightShifterPlugin_isActive` - Shifter state machine
7. `alu_result` - Final ALU result

### Writeback Stage:
1. `writeBack_INSTRUCTION` - Instruction reaching writeback
2. `writeBack_REGFILE_WRITE_DATA` - Data to be written
3. `writeBack_REGFILE_WRITE_VALID` - Writeback enable
4. `writeBack_REGFILE_WRITE_DATA` vs register file update

---

## Next Steps

1. **Immediate Action**: Open waveform and inspect SLLI x23 instruction
   - PC = 0x80000074
   - Instruction = 0x00209b93
   - Check decoder outputs at decode stage
   - Check if SHIFT_CTRL propagates to execute

2. **Systematic Analysis**: Create checklist for each failing instruction
   - Decode stage verification
   - Execute stage verification
   - Writeback stage verification

3. **Pattern Confirmation**: Group instructions by suspected root cause
   - Shift operations → Decoder `SHIFT_CTRL` generation
   - Immediate operations → Decoder `SRC2_CTRL` generation
   - Upper immediate → Decoder `SRC1_CTRL` generation

4. **Decoder Code Review**: Focus on lines in `vexriscv_decoder_unoptimized.sv`:
   - Lines 307-315: ALU_CTRL decode
   - Lines 331-336: ALU_BITWISE_CTRL decode
   - Lines 347-354: SHIFT_CTRL decode
   - Lines 135-169: SRC2_CTRL decode (critical for I-type)
   - Lines 390-397: SRC1_CTRL decode

---

## Success Patterns (For Comparison)

Operations that **PASSED** can guide debugging:

- **Arithmetic**: SUB x6 (R-type), ADDI x7 (I-type with positive immediate)
- **Logical**: AND, OR, XOR, ANDI, ORI, XORI (all bitwise operations PASS)
- **Comparison**: SLT x15, x16, SLTI x19, x20, SLTIU x21, x22 (signed comparisons work)
- **Initialize**: x1, x2, x3, x4 (all setup instructions work)

**Key Observation**: Bitwise logical operations (XOR, OR, AND) all PASS, suggesting:
- `ALU_CTRL` = BITWISE works correctly
- `ALU_BITWISE_CTRL` decode works correctly
- Register writeback works for these instructions
- Problem is specific to arithmetic, shift, and immediate handling

---

## Hypothesis Ranking

1. **HIGHEST PROBABILITY**: Shift control decoder bug (100% shift fail rate)
2. **HIGH PROBABILITY**: Immediate source selection issue (multiple I-type failures)
3. **MEDIUM PROBABILITY**: Upper immediate path broken (LUI/AUIPC both fail)
4. **LOW PROBABILITY**: Register writeback issue (bitwise ops work fine)

---

## Test Log Excerpts

```
UVM_ERROR: FAIL: x5 = 0x00000000 (expected 0x00000018)  // ADD failure
UVM_ERROR: FAIL: x8 = 0x00000000 (expected 0x0000000d)  // ADDI failure
UVM_ERROR: FAIL: x18 = 0x00000000 (expected 0x00000001) // SLTU failure
UVM_ERROR: FAIL: x23 = 0x00000010 (expected 0x00000040) // SLLI failure (got source value)
UVM_ERROR: FAIL: x24 = 0x00000000 (expected 0x00000010) // SLLI failure
UVM_ERROR: FAIL: x25 = 0x00000000 (expected 0x00000004) // SRLI failure
UVM_ERROR: FAIL: x26 = 0x00000008 (expected 0x00ffffff) // SRL failure (got shift amount!)
UVM_ERROR: FAIL: x27 = 0x00000000 (expected 0xffffffff) // SRAI failure
UVM_ERROR: FAIL: x29 = 0x00000000 (expected 0x12345000) // LUI failure
UVM_ERROR: FAIL: x30 = 0x00000000 (expected 0x00000074) // AUIPC failure
UVM_ERROR: FAIL: x31 = 0x00000000 (expected 0x0000000f) // ADDI failure
```

**TEST RESULT**: **FAILURE** - 11 ALU operations incorrect
