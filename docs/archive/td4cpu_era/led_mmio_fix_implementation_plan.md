# LED MMIO Address Fix - Implementation Plan (Option 1)

**Document Version:** 1.0  
**Date:** December 31, 2025  
**Author:** GitHub Copilot  
**Status:** Ready for Implementation

## Executive Summary

This document provides worker-level implementation instructions for fixing the LED MMIO test failure by relocating the LED MMIO register from address 0x1044 to 0x101F. This change resolves the architectural limitation where the ST instruction's 6-bit signed offset (-32 to +31) cannot reach address 0x1044.

**Estimated Duration:** 30-45 minutes  
**Risk Level:** Low  
**Impact:** Fixes 1 failing test, achieves 100% regression pass rate

---

## Problem Statement

### Root Cause
- **Issue:** axiuart_cpu_mmio_led_test fails with 8 UVM errors
- **Cause:** LED MMIO address 0x1044 requires offset +68 from MMIO base 0x1000
- **Limitation:** ST instruction supports only 6-bit signed offset (range: -32 to +31)
- **Calculation:** 68 > 31 → Address UNREACHABLE

### Current Test Status
```
Full Regression: 85.7% pass (6/7 tests)
- axiuart_reset_test: PASS
- axiuart_basic_test: PASS
- axiuart_reg_rw_test: PASS
- axiuart_cpu_simple_mem_test: PASS
- axiuart_cpu_memory_test: PASS
- axiuart_cpu_debug_test: PASS
- axiuart_cpu_mmio_led_test: FAIL (8 UVM errors)
```

---

## Solution Design

### Approach
Move LED MMIO register to address 0x101F (offset +31 from base 0x1000), the maximum reachable address with ST instruction's 6-bit signed offset.

### Design Rationale
1. **Preserves ISA:** No instruction format changes required
2. **Minimal Changes:** 2 files, 3 code locations
3. **Sufficient Address Space:** 32 MMIO addresses (0x1000-0x101F) adequate for current design
4. **Industry Standard:** ARM Cortex-M and RISC-V use similar dense peripheral mapping

### Address Calculation
```
MMIO BASE:       0x1000 (4096 decimal)
New LED address: 0x101F (4127 decimal)
Offset:          0x101F - 0x1000 = 31 (0x1F)
Verification:    31 ≤ 31 (max offset) ✓ REACHABLE
```

---

## Implementation Steps

### Step 1: Modify RTL - td4cpu_core.sv

**File:** `rtl/cpu/td4cpu_core.sv`  
**Line:** 88  
**Change Type:** Constant value modification

**Current Code:**
```systemverilog
localparam logic [15:0] MMIO_BASE = 16'h1000;
localparam logic [15:0] MMIO_LED = 16'h1044;  // ← Change this line
```

**New Code:**
```systemverilog
localparam logic [15:0] MMIO_BASE = 16'h1000;
localparam logic [15:0] MMIO_LED = 16'h101F;  // Maximum reachable with 6-bit offset
```

**Action Checklist:**
- [ ] Open file: `rtl/cpu/td4cpu_core.sv`
- [ ] Navigate to line 88
- [ ] Change `16'h1044` to `16'h101F`
- [ ] Add comment: `// Maximum reachable with 6-bit offset`
- [ ] Save file
- [ ] Verify no syntax errors introduced

**Verification:**
```bash
grep -n "MMIO_LED" rtl/cpu/td4cpu_core.sv
# Expected output: Line 88 showing 16'h101F
```

---

### Step 2: Modify Test - axiuart_cpu_mmio_led_test.sv (Part A)

**File:** `sim/tests/axiuart_cpu_mmio_led_test.sv`  
**Lines:** ~20-30 (constant definition section)  
**Change Type:** Constant value modification

**Current Code:**
```systemverilog
// LED MMIO address (TD4CPU MMIO space)
localparam bit [15:0] LED_MMIO_ADDR = 16'h1044;
```

**New Code:**
```systemverilog
// LED MMIO address (TD4CPU MMIO space - maximum reachable with ST offset)
localparam bit [15:0] LED_MMIO_ADDR = 16'h101F;
```

**Action Checklist:**
- [ ] Open file: `sim/tests/axiuart_cpu_mmio_led_test.sv`
- [ ] Locate LED_MMIO_ADDR constant definition
- [ ] Change `16'h1044` to `16'h101F`
- [ ] Update comment to reflect design constraint
- [ ] Save file

**Verification:**
```bash
grep -n "LED_MMIO_ADDR" sim/tests/axiuart_cpu_mmio_led_test.sv
# Expected output: Line showing 16'h101F
```

---

### Step 3: Modify Test - Address Construction Logic (Part B)

**File:** `sim/tests/axiuart_cpu_mmio_led_test.sv`  
**Lines:** Test 1 address construction sequence (~line 100-130)  
**Change Type:** Instruction parameter modification

**Current Address Construction:**
```systemverilog
// Build address 0x1044 in R1
// Step 1: LDI R1, #0x100 (immediate can only load low byte)
asm_seq.push_back({LDI, 3'd1, 3'd0, 6'd0});  // R1 = 0x0000
// Step 2-17: 16x ADDI R1, #0x100 to reach 0x1000
for (int i = 0; i < 16; i++) begin
    asm_seq.push_back({ADDI, 3'd1, 3'd0, 6'd1});  // R1 += 0x100
end
// Step 18: ADDI R1, #0x44 to reach 0x1044
asm_seq.push_back({ADDI, 3'd1, 3'd0, 6'd4});  // R1 += 0x44
```

**New Address Construction:**
```systemverilog
// Build address 0x101F in R1 (maximum reachable with ST offset)
// Step 1: LDI R1, #0x100 (immediate can only load low byte)
asm_seq.push_back({LDI, 3'd1, 3'd0, 6'd0});  // R1 = 0x0000
// Step 2-17: 16x ADDI R1, #0x100 to reach 0x1000
for (int i = 0; i < 16; i++) begin
    asm_seq.push_back({ADDI, 3'd1, 3'd0, 6'd1});  // R1 += 0x100
end
// Step 18: ADDI R1, #0x1F to reach 0x101F
asm_seq.push_back({ADDI, 3'd1, 3'd0, 6'd31});  // R1 += 0x1F (31 decimal)
```

**Important Notes:**
- The offset parameter in ADDI is decimal, not hex
- Old: `6'd4` (0x44 hex was incorrectly encoded - this was part of the bug!)
- New: `6'd31` (0x1F = 31 decimal)
- This change applies to ALL test scenarios that build LED address

**Action Checklist:**
- [ ] Open file: `sim/tests/axiuart_cpu_mmio_led_test.sv`
- [ ] Search for all occurrences of address construction logic
- [ ] Locate ADDI instruction building offset to LED address
- [ ] Change final ADDI parameter from `6'd4` to `6'd31`
- [ ] Update comments to reflect new address 0x101F
- [ ] Verify all 5 test scenarios updated consistently
- [ ] Save file

**Verification:**
```bash
grep -n "ADDI.*R1.*6'd" sim/tests/axiuart_cpu_mmio_led_test.sv
# Review all ADDI instructions building R1 address
# Confirm final ADDI uses 6'd31
```

---

## Verification Plan

### Phase 1: Syntax Check
**Objective:** Ensure no compilation errors introduced

**Commands:**
```powershell
cd <repo-root>
.\scripts\run_test.ps1 -Help
```

**Success Criteria:**
- PowerShell script displays help information
- No missing dependencies

---

### Phase 2: Single Test Verification
**Objective:** Verify LED MMIO test passes in isolation

**Commands:**
```bash
python mcp_server/mcp_client.py --workspace . --tool run_uvm_simulation --test-name axiuart_cpu_mmio_led_test --mode compile --verbosity UVM_LOW
python mcp_server/mcp_client.py --workspace . --tool run_uvm_simulation --test-name axiuart_cpu_mmio_led_test --mode run --verbosity UVM_MEDIUM --waves
```

**Success Criteria:**
- Compilation: 0 errors, 0 warnings
- Simulation: 0 UVM_ERROR messages
- All 5 test scenarios PASS
- LED register updates correctly observed in waves

**Log Files to Review:**
- `sim/exec/logs/axiuart_cpu_mmio_led_test_<timestamp>.log`
- Check for patterns:
  ```
  [PASS] Test 1: Basic ST to LED MMIO
  [PASS] Test 2: LD from LED MMIO
  [PASS] Test 3: LED Counter Pattern
  [PASS] Test 4: Negative Offset Addressing
  [PASS] Test 5: RAM/MMIO Boundary Test
  ```

---

### Phase 3: Full Regression Verification
**Objective:** Ensure no regressions in other tests

**Commands:**
```bash
python mcp_server/run_regression.py --suite full --format json
python mcp_server/run_regression.py --suite full --format html
```

**Success Criteria:**
- **Pass Rate:** 100% (7/7 tests)
- **Test Results:**
  - axiuart_reset_test: PASS
  - axiuart_basic_test: PASS
  - axiuart_reg_rw_test: PASS
  - axiuart_cpu_simple_mem_test: PASS
  - axiuart_cpu_memory_test: PASS
  - axiuart_cpu_debug_test: PASS
  - axiuart_cpu_mmio_led_test: PASS ← **Primary verification target**
- **Error Count:** 0 UVM_ERROR across all tests
- **Execution Time:** ~500-600 seconds (similar to previous runs)

**Report Files:**
- `sim/reports/regression_report_<timestamp>.json`
- `sim/reports/regression_report_<timestamp>.html`

---

### Phase 4: Waveform Analysis (Optional but Recommended)
**Objective:** Visual confirmation of LED MMIO writes

**Steps:**
1. Open waveform: `sim/exec/wave/axiuart_cpu_mmio_led_test.mxd`
2. Navigate to LED register signal: `td4cpu_core.led_reg`
3. Verify LED updates at expected cycles:
   - Test 1: LED = 4'hA at ST instruction completion
   - Test 3: LED increments 4'h1 → 4'h2 → 4'h3 → 4'h4

**Tool:**
```bash
# If waveform viewer installed
mxdview sim/exec/wave/axiuart_cpu_mmio_led_test.mxd
```

---

## Rollback Plan

### If Verification Fails

**Scenario A: Compilation Errors**
- Review syntax at modified lines
- Check for typos in hex values (0x101F vs 0x10lF)
- Verify SystemVerilog syntax compliance

**Scenario B: Test Still Fails**
- Check offset calculation: 0x101F - 0x1000 = 31 (0x1F)
- Verify ADDI parameter is `6'd31` (decimal), not `6'h1F` (hex)
- Review all 5 test scenarios for consistent address usage

**Scenario C: Other Tests Regress**
- Unlikely scenario (LED address change isolated to MMIO logic)
- If occurs, review `st_is_led` comparison in td4cpu_core.sv line 902
- Rollback all changes and escalate for architectural review

**Rollback Commands:**
```bash
git diff rtl/cpu/td4cpu_core.sv
git diff sim/tests/axiuart_cpu_mmio_led_test.sv
git checkout rtl/cpu/td4cpu_core.sv sim/tests/axiuart_cpu_mmio_led_test.sv
```

---

## Post-Implementation Documentation

### Required Updates
1. **CHANGELOG.md**: Add entry describing LED MMIO address change
2. **cpu_mmio_design.md**: Update LED address specification
3. **Development Diary**: Create entry with implementation summary

### Changelog Entry Template
```markdown
## [Unreleased] - 2025-12-31

### Fixed
- LED MMIO address moved from 0x1044 to 0x101F to enable ST instruction access
  - Root cause: 6-bit signed offset limited range to ±31 bytes
  - Impact: Fixes axiuart_cpu_mmio_led_test (8 UVM errors eliminated)
  - Modified files: rtl/cpu/td4cpu_core.sv, sim/tests/axiuart_cpu_mmio_led_test.sv
  - Regression test result: 100% pass rate (7/7 tests)
```

---

## Implementation Checklist

**Pre-Implementation:**
- [ ] Read and understand this document completely
- [ ] Verify current branch: `feature/cpu-mmio-led` or create new branch
- [ ] Confirm latest code pulled from repository
- [ ] Backup current working state

**Implementation:**
- [ ] Step 1: Modify td4cpu_core.sv MMIO_LED constant
- [ ] Step 2: Modify axiuart_cpu_mmio_led_test.sv LED_MMIO_ADDR constant
- [ ] Step 3: Update test address construction logic (ADDI offsets)
- [ ] Review all changes with `git diff`

**Verification:**
- [ ] Phase 1: DSIM environment check
- [ ] Phase 2: Single test verification (LED MMIO test)
- [ ] Phase 3: Full regression suite
- [ ] Phase 4: Waveform analysis (optional)

**Documentation:**
- [ ] Update CHANGELOG.md
- [ ] Update cpu_mmio_design.md
- [ ] Create development diary entry
- [ ] Commit changes with descriptive message

**Sign-off:**
- [ ] All tests passing: 100% (7/7)
- [ ] No UVM_ERROR messages
- [ ] Code reviewed and approved
- [ ] Documentation complete

---

## Expected Results

### Before Implementation
```
Full Regression: 85.7% pass (6/7 tests)
axiuart_cpu_mmio_led_test: FAIL
- UVM_ERROR count: 8
- Test 1: FAIL (LED write failed)
- Test 2: N/A (skipped after Test 1 failure)
- Test 3: FAIL (4 pattern mismatches)
- Test 4: FAIL (negative offset addressing)
- Test 5: FAIL (boundary test)
```

### After Implementation
```
Full Regression: 100% pass (7/7 tests)
axiuart_cpu_mmio_led_test: PASS
- UVM_ERROR count: 0
- Test 1: PASS (LED = 0xA written successfully)
- Test 2: PASS (LED = 0xA read back correctly)
- Test 3: PASS (LED counter 0x1 → 0x2 → 0x3 → 0x4)
- Test 4: PASS (negative offset -16 works correctly)
- Test 5: PASS (RAM 0x0FFF / MMIO 0x101F boundary verified)
```

---

## Contact & Escalation

**Implementation Owner:** GitHub Copilot  
**Reviewer:** User (MameMame777)  
**Escalation Path:** If verification fails after 2 attempts, escalate for architectural review

**Questions During Implementation:**
- Review this document section-by-section
- Use `git diff` to verify changes before committing
- Run smoke tests before full regression if uncertain

---

**End of Document**
