# RTL Branch Behavior - Detailed Analysis
**Date**: 2026-01-02  
**File**: `rtl/cpu/td4cpu_core.sv`  
**Purpose**: Document actual RTL branch implementation to fix test specification mismatches

---

## 1. Current State Machine Overview

### Branch Flags
- `branch_delay_slot_active`: Branch decoded, delay slot should execute next
- `branch_pending`: Delay slot executing/executed, target should be applied next
- `branch_target_pending`: Target PC calculated during branch decode

### State Transitions
```
Normal → Branch Decode → Delay Slot Wait → Branch Apply → Normal
         (set flags)     (transition)      (fetch target)
```

---

## 2. Detailed Cycle-by-Cycle Behavior

### Scenario: BR.AL +2 at PC=3

#### **Cycle N (Branch Decode at PC=3)**
**Conditions**: 
- `insn_decoded_valid = 1`
- Opcode = OP_BR, condition = true
- Current PC = 3

**Actions in BR decode (line ~1213)**:
```systemverilog
branch_target_pending <= br_target_pc;      // = 3 + 2 = 5
branch_delay_slot_active <= 1'b1;
```

**Actions in fetch block (line ~903, normal fetch executes SAME CYCLE)**:
- **CRITICAL**: Branch decode happens in `insn_decoded_valid` block
- **CRITICAL**: Normal fetch happens in `running && !insn_valid` block
- **CRITICAL**: Both blocks execute in SAME CYCLE (parallel)
- Fetch condition: `running && !insn_valid && !branch_delay_slot_active`
  - At start of cycle: `branch_delay_slot_active = 0` (not set yet)
  - Normal fetch RUNS this cycle
  - Fetches PC=3 → reads ram[2]
  - **Sets PC = 4** (delay slot address)
  - Sets `ram_rd_en = 1`

**End of Cycle N State**:
- PC = 4 (delay slot address)
- `branch_delay_slot_active = 1`
- `branch_target_pending = 5`
- RAM fetch issued for delay slot (ram[3])

---

#### **Cycle N+1 (Delay Slot Wait)**
**Conditions**:
- `running && !insn_valid && !ram_rd_en`
- `branch_delay_slot_active = 1`

**Actions (line ~841-851)**:
```systemverilog
branch_delay_slot_active <= 1'b0;  // Clear
branch_pending <= 1'b1;            // Set
// NO fetch, NO PC change - just state transition
```

**Purpose**: Wait for delay slot instruction to complete execution

**End of Cycle N+1 State**:
- PC = 4 (unchanged)
- `branch_delay_slot_active = 0`
- `branch_pending = 1`
- Delay slot instruction executing

---

#### **Cycle N+2 (Branch Target Fetch)**
**Conditions**:
- `running && !insn_valid && !ram_rd_en`
- `branch_pending = 1`

**Actions (line ~854-884)**:
```systemverilog
branch_pending <= 1'b0;
ram_addr_next <= (branch_target_pending <= 16'd1) ? 16'd0 : (branch_target_pending - 16'd1);
ram_rd_en <= 1'b1;
exec_pc <= branch_target_pending;  // = 5
pc <= branch_target_pending;       // = 5 (CURRENT CODE)
```

**CRITICAL BUG**: Setting `pc <= branch_target_pending` directly

**End of Cycle N+2 State**:
- PC = 5 (target)
- `branch_pending = 0`
- RAM fetch issued for target (ram[4])
- `ram_rd_en = 1`

---

#### **Cycle N+3 (Normal Fetch After Branch)**
**Conditions**:
- `running && !insn_valid && !ram_rd_en` (after `ram_rd_en` clears)
- `branch_delay_slot_active = 0`
- `branch_pending = 0`
- Normal fetch block executes

**Actions (line ~903-916)**:
```systemverilog
ram_addr_next <= (pc <= 16'd1) ? 16'd0 : (pc - 16'd1);  // ram[4]
ram_rd_en <= 1'b1;
exec_pc <= pc;       // = 5
pc <= pc + 16'd1;    // 5 → 6 !!!
```

**BUG IDENTIFIED**: PC increments from 5 → 6, but instruction at PC=5 hasn't executed yet!

**End of Cycle N+3 State**:
- PC = 6 (WRONG - should stay at 5 until instruction executes)
- Fetching ram[4] (PC=5's instruction)
- **Next cycle will fetch PC=6, skipping execution of target**

---

## 3. Root Cause Analysis

### Problem: Double PC Increment
1. **Cycle N+2**: Branch handler sets `pc = target` and fetches target instruction
2. **Cycle N+3**: Normal fetch increments `pc = target + 1` and fetches AGAIN
3. **Result**: Target instruction fetched but never associated with correct PC

### Why This Causes Infinite Loop (PC=43,44,45,46,43...)

**Test 4 Program**:
```
PC=0x43 (0x42 in ram): BR.N +1        ; Branch to PC=0x44
PC=0x44 (0x43 in ram): LDI R7, #0x99  ; Delay slot
PC=0x45 (0x44 in ram): LDI R4, #0x44  ; Branch target
PC=0x46 (0x45 in ram): BRK
```

**Actual Execution**:
```
Cycle N:   Decode BR at PC=43
           Normal fetch: PC=43→44, fetch delay slot (ram[43])
           
Cycle N+1: Delay slot wait (state transition)
           PC=44 (unchanged)
           
Cycle N+2: Branch handler: 
           pc <= 44+1 = 45 (target)
           Fetch ram[44] (PC=45's instruction)
           
Cycle N+3: Normal fetch:
           pc <= 45+1 = 46 ❌
           Fetch ram[45] (PC=46's instruction) ❌
           
Cycle N+4: PC=46 instruction executes
           But wait - this is where BRK should be!
           Instead, we've double-fetched and lost synchronization
```

**The real issue**: We're fetching twice in quick succession after branch, causing PC to race ahead of actual execution.

---

## 4. Fix Strategy Options

### Option A: Don't Increment in Normal Fetch After Branch
**Idea**: Add flag `pc_updated_by_branch` to skip next normal increment

**Problems**:
- Complex state tracking
- Already tried conditional increment - caused system hang

### Option B: Set PC to (target - 1) in Branch Handler ❌ FAILED
**Idea**: Pre-decrement PC so normal increment reaches target

**Problems**:
- Backward branches break (PC underflows)
- Forward branches work but backward branches loop infinitely

### Option C: Restructure Fetch Logic
**Current Issue**: Branch handler fetches, then normal fetch fetches again same cycle

**Solution**: Prevent double-fetch by checking if `ram_rd_en` was just set by branch handler

---

## 5. Correct Fix Implementation

### Approach: Use `ram_rd_en` as Fetch Gate

**Observation**: The fetch condition already checks `!ram_rd_en`:
```systemverilog
if (running && !insn_valid && !mem_op_executing && !mem_op_pending && !ram_rd_en && ...)
```

**Problem**: `ram_rd_en` is only active for 1 cycle, then cleared by RAM controller

**Fix**: Add persistent flag `fetch_pending` that stays set until instruction becomes valid

### Proposed Changes:

```systemverilog
// Add new flag
logic fetch_pending;  // Fetch issued, waiting for instruction to become valid

// In reset:
fetch_pending <= 1'b0;

// In branch_pending handler:
ram_rd_en <= 1'b1;
fetch_pending <= 1'b1;  // Mark fetch in progress
pc <= branch_target_pending;  // Set PC to target

// In normal fetch:
if (!fetch_pending) begin  // Only fetch if no fetch in progress
    ram_rd_en <= 1'b1;
    fetch_pending <= 1'b1;
    pc <= pc + 16'd1;
end

// When instruction becomes valid:
if (ram_data_valid) begin
    insn_valid <= 1'b1;
    fetch_pending <= 1'b0;  // Clear fetch pending
end
```

---

## 6. Alternative: Simpler PC Management

### Key Insight: PC Should Only Increment in Normal Fetch

**Rule**: PC increments ONLY in normal fetch block, NEVER in branch handler

**Implementation**:
```systemverilog
// In branch_pending handler:
ram_addr_next <= (target <= 16'd1) ? 16'd0 : (target - 16'd1);
ram_rd_en <= 1'b1;
exec_pc <= target;
// DON'T SET PC HERE - let it stay at delay slot address

// In normal fetch:
if (no branch active) begin
    ram_addr_next <= (pc <= 16'd1) ? 16'd0 : (pc - 16'd1);
    ram_rd_en <= 1'b1;
    exec_pc <= pc;
    pc <= pc + 16'd1;  // ONLY place PC increments
end
```

**But**: This means after branch, PC is still at delay slot address (PC=44), but we fetched target (ram[44] = PC=45 instruction). Next normal fetch would increment PC=44→45 and try to fetch ram[44] AGAIN.

**Still broken**: Same double-fetch problem.

---

## 7. Real Solution: Decouple PC from Fetch Address

### Core Issue: PC Represents "Next Fetch" Not "Current Execution"

**Current Model**:
- PC = address to fetch next
- After fetch: PC++
- Problem: Branch sets PC to target, but fetch already happened

**Better Model**:
- PC = address of currently executing instruction
- Fetch uses PC as base
- PC only updates when instruction completes

### Required Changes: Major Refactoring (Not Viable)

---

## 8. Pragmatic Fix: Block Double-Fetch

### Simplest Solution: Prevent Normal Fetch Immediately After Branch Fetch

**Implementation**:
```systemverilog
// Add flag
logic branch_fetch_done;  // Branch fetched this cycle, skip normal fetch

// In branch_pending handler:
ram_rd_en <= 1'b1;
pc <= branch_target_pending;
branch_fetch_done <= 1'b1;  // Mark that we fetched

// In normal fetch condition:
if (running && !insn_valid && !branch_fetch_done && ...) begin
    // Normal fetch
    pc <= pc + 16'd1;
end

// Clear flag when instruction becomes valid:
if (insn_valid or instruction executes) begin
    branch_fetch_done <= 1'b0;
end
```

**This prevents**:
- Cycle N+2: Branch fetches target, sets `branch_fetch_done=1`, PC=target
- Cycle N+3: Normal fetch blocked by `!branch_fetch_done`
- Cycle N+4: Instruction becomes valid, clears `branch_fetch_done`
- Cycle N+5: Normal fetch resumes with PC=target (no increment yet)

**Result**: Target instruction executes at correct PC, then PC increments normally.

---

## 9. Test Specification Issues

### Current Test Expectations May Be Wrong

**Test assumes**: Branch target executes immediately at target PC  
**RTL reality**: Branch target execches, but PC management is complex

### Need to verify:
1. What PC value should `exec_pc` have when target executes?
2. Should PC increment happen before or after target execution?
3. Does delay slot architecture require special PC handling?

---

## Conclusion

**Root Cause**: Branch handler fetches target and sets PC=target, then normal fetch runs next cycle and increments PC before target executes, causing PC to race ahead.

**Fix Required**: Add state flag to prevent normal fetch from running immediately after branch fetch completes.

**Test Impact**: Need to verify test expectations match actual RTL PC progression during branch sequences.
