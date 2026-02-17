# TD4 CPU PC Control Specification

## Overview
This document defines the precise Program Counter (PC) control behavior for the TD4 CPU, particularly during branch operations with delay slots.

## Architecture: MIPS/SPARC-Style Branch Delay Slots

### Core Principle
The instruction **immediately after** a branch instruction **ALWAYS executes** before the branch is taken.

```
PC=N:   BR target      ; Branch decodes, target calculated
PC=N+1: <instruction>  ; DELAY SLOT - ALWAYS executes
PC=N+2: <skipped>      ; Should NOT execute
...
PC=target: <target>    ; Branch target executes here
```

## PC State Machine Timing

### Normal Execution (No Branch)

**Cycle N:**
```
State: running=1, branch_delay_slot_active=0, branch_pending=0
Actions:
  - Fetch: ram_addr_next = (pc-1), ram_rd_en = 1
  - PC Update: pc <= pc + 1
  - exec_pc Update: exec_pc <= pc (before increment)
Result: Instruction at old PC fetched, PC advanced by 1
```

**Cycle N+1:**
```
State: insn_valid=1 (from previous fetch)
Actions:
  - Execute: Instruction decoded and executed
  - Fetch blocked: insn_valid=1 blocks new fetch
Result: Execution completes
```

**Cycle N+2:**
```
State: insn_valid=0 (cleared after execution)
Actions:
  - Resume fetch cycle
```

### Branch Execution (3-Cycle Sequence)

#### Cycle 1: Branch Decode
```
State: Branch instruction decodes
Actions:
  - Branch decode: Calculate target, set flags
    * branch_delay_slot_active <= 1
    * branch_target_pending <= calculated_target
  - Normal fetch continues: Fetches delay slot (PC+1)
    * ram_addr_next = (pc-1)  ; Fetches PC+1 instruction
    * pc <= pc + 1            ; PC advances normally
    * exec_pc <= pc           ; Labels delay slot with PC+1
Result: Delay slot instruction enters pipeline, PC = PC_BR+1
```

#### Cycle 2: Delay Slot Transition
```
State: branch_delay_slot_active=1
Actions:
  - State transition ONLY (no fetch, no PC change):
    * branch_delay_slot_active <= 0
    * branch_pending <= 1
  - NO ram_rd_en (delay slot already fetched in Cycle 1)
  - NO PC update (PC stays at PC_BR+1)
Result: Wait for delay slot execution, prepare for branch
```

#### Cycle 3: Branch Target Application
```
State: branch_pending=1
Actions:
  - Apply branch target:
    * branch_pending <= 0
    * ram_addr_next = (target-1)  ; Fetch target instruction
    * ram_rd_en <= 1
    * exec_pc <= target           ; Label with target PC
    * pc <= target                ; Set PC to target
Result: Target instruction fetched, PC = target
```

#### Cycle 4: Resume Normal Execution
```
State: branch_pending=0, insn_valid=1 (target instruction)
Actions:
  - Execute target instruction
  - Normal fetch cycle resumes
Result: Execution continues from target
```

## Critical PC Control Rules

### Rule 1: PC Increment Timing
**Normal fetch ALWAYS increments PC:**
```systemverilog
pc <= pc + 16'd1;  // Every normal fetch
```

**Branch handlers DO NOT increment PC:**
```systemverilog
// Delay slot transition: NO PC change
// Branch application: pc <= target (absolute assignment)
```

### Rule 2: Fetch Blocking
**Conditions that MUST block fetch:**
1. `!running` - CPU halted
2. `insn_valid` - Instruction in pipeline
3. `mem_op_executing` - Memory operation active
4. `mem_op_pending` - Memory operation pending
5. `ram_rd_en` - RAM read active (prevents double-fetch)
6. `step_pending && step_insn_fetched` - Single-step mode

**Branch-specific blocking:**
- During `branch_delay_slot_active`: NO fetch (delay slot already fetched)
- During `branch_pending`: Fetch target ONCE
- After branch target fetch: Resume normal fetch

### Rule 3: Delay Slot Architecture
**The delay slot instruction was ALREADY fetched during branch decode:**
- Branch decode happens at Cycle N
- Normal fetch logic runs: Fetches PC+1 (delay slot)
- Delay slot transition (Cycle N+1) does NOT fetch again
- This is why `branch_delay_slot_active` handler has NO `ram_rd_en`

## Memory Mapping: PC to RAM Address

```
PC = 0:  Invalid (no fetch, immediate halt)
PC = 1:  ram[0]  ; First valid instruction
PC = 2:  ram[1]
PC = N:  ram[N-1]
```

**RAM address calculation:**
```systemverilog
ram_addr_next <= (pc <= 16'd1) ? 16'd0 : (pc - 16'd1);
```

## Branch Target Calculation

```systemverilog
// BR instruction: {OP_BR[4bit], condition[3bit], offset[9bit]}
signed_offset = {{7{insn[8]}}, insn[8:0]};  // Sign-extend 9-bit to 16-bit
branch_target = br_insn_pc + signed_offset;

// CRITICAL: br_insn_pc MUST be the PC of the branch instruction itself
// Use insn_fetched_pc (captured at fetch time), NOT exec_pc (global state)
```

## Example: Forward Branch

```
Memory Layout:
ram[0] = 0x1005  ; PC=1: LDI R0, #5
ram[1] = 0x5003  ; PC=2: BR.AL +3 (target = 2+3 = 5)
ram[2] = 0x1e16  ; PC=3: LDI R7, #22 (DELAY SLOT)
ram[3] = 0x100a  ; PC=4: LDI R0, #10 (SKIPPED)
ram[4] = 0x12ff  ; PC=5: LDI R1, #255 (TARGET)
ram[5] = 0x0000  ; PC=6: BRK
```

**Execution Trace:**

| Cycle | State | Action | PC | exec_pc | Instruction | Notes |
|-------|-------|--------|-----|---------|-------------|-------|
| 1 | Normal | Fetch PC=1 | 1→2 | 1 | LDI R0, #5 | Execute R0=5 |
| 2 | Normal | Fetch PC=2 | 2→3 | 2 | BR.AL +3 | Branch decode, set delay_slot_active=1, target=5 |
| 3 | Normal | Fetch PC=3 | 3→4 | 3 | LDI R7, #22 | Delay slot fetched during branch decode |
| 4 | Delay transition | State change | 4 | 3 | - | delay_slot_active→0, branch_pending→1 |
| 5 | Branch pending | Fetch target | 4→5 | 5 | LDI R7, #22 | Delay slot executes (R7=22) |
| 6 | Target fetch | Fetch PC=5 | 5 | 5 | LDI R1, #255 | Target fetched, pc=5 |
| 7 | Normal | Execute | 5→6 | 5 | LDI R1, #255 | Target executes (R1=255) |
| 8 | Normal | Fetch PC=6 | 6→7 | 6 | BRK | Continue from PC=6 |

**Key Observations:**
1. PC=4 (ram[3]) is NEVER fetched or executed (skipped correctly)
2. Delay slot (PC=3) executes BEFORE target (PC=5)
3. PC advances naturally: 1→2→3→4 (during delay slot)→5 (branch applied)

## Example: Backward Branch (Loop)

```
Memory Layout:
ram[50] = 0x1000  ; PC=51: LDI R0, #0
ram[51] = 0x1103  ; PC=52: LDI R1, #3
ram[52] = 0x3010  ; PC=53: CMP R0, R1
ram[53] = 0x5FFF  ; PC=54: BR.NZ -1 (offset=-1, target=54-1=53)
ram[54] = 0x2001  ; PC=55: ADDI R0, #1 (DELAY SLOT)
ram[55] = 0x0000  ; PC=56: BRK
```

**Execution Trace (First Iteration):**

| Cycle | State | Action | PC | exec_pc | R0 | Instruction | Notes |
|-------|-------|--------|-----|---------|-----|-------------|-------|
| 1 | Normal | Fetch PC=51 | 51→52 | 51 | 0 | LDI R0, #0 | R0=0 |
| 2 | Normal | Fetch PC=52 | 52→53 | 52 | 0 | LDI R1, #3 | R1=3 |
| 3 | Normal | Fetch PC=53 | 53→54 | 53 | 0 | CMP R0, R1 | Z=0 (0≠3) |
| 4 | Normal | Fetch PC=54 | 54→55 | 54 | 0 | BR.NZ -1 | Branch taken, target=53 |
| 5 | Delay transition | State change | 55 | 54 | 0 | - | delay_slot_active→0, branch_pending→1 |
| 6 | Branch pending | Fetch target | 55→53 | 55 | 0→1 | ADDI R0, #1 | Delay slot executes, R0=1 |
| 7 | Target fetch | Fetch PC=53 | 53 | 53 | 1 | CMP R0, R1 | Back to CMP |
| 8 | Normal | Execute | 53→54 | 53 | 1 | CMP R0, R1 | Z=0 (1≠3) |

**Loop continues until R0=3, then Z=1, branch NOT taken, continues to PC=56 (BRK)**

**Key Observations:**
1. Delay slot (ADDI R0, #1) executes EVERY iteration
2. PC jumps backward: 55→53
3. Loop termination: When Z=1 (R0=3), BR.NZ not taken, continues to PC=55→56

## Current RTL Issues (To Be Fixed)

### Issue 1: branch_fetch_done Deadlock
**Problem:**
```systemverilog
// Line 887: Set after branch target fetch
branch_fetch_done <= 1'b1;

// Line 843: Blocks ALL fetches
if (!branch_fetch_done && ...) begin

// Line 942: Cleared only when insn_valid
if (ram_rd_en && running) begin
    branch_fetch_done <= 1'b0;
```

**Deadlock Scenario:**
1. Branch target fetched: `branch_fetch_done=1`
2. Next cycle: Fetch blocked by `!branch_fetch_done`
3. But `insn_valid=0` because previous instruction executed
4. Need fetch to get `insn_valid=1`, but fetch blocked
5. **Infinite loop: PC never advances**

**Solution:** Remove `branch_fetch_done` flag entirely. Use existing `branch_pending` state.

### Issue 2: Duplicate Declaration
```systemverilog
// Line 183 & 184: Duplicate declarations
logic branch_fetch_done;
logic branch_fetch_done;
```

**Solution:** Remove duplicate declaration.

### Issue 3: PC Increment After Branch
**Current behavior:** After setting `pc <= target`, next normal fetch does `pc <= pc + 1`

**Expected behavior:** Target instruction executes at PC=target, THEN PC increments to target+1

**Root cause:** `insn_valid` blocks fetch, but when it clears, normal fetch runs and increments PC

**Solution:** Ensure branch target execution completes before next fetch cycle resumes

## Correct Implementation

### State Machine
```
NORMAL → (Branch decode) → DELAY_SLOT_ACTIVE
DELAY_SLOT_ACTIVE → (State transition) → BRANCH_PENDING
BRANCH_PENDING → (Fetch target) → NORMAL
```

### Fetch Control Logic
```systemverilog
if (running && !insn_valid && !mem_op_executing && 
    !mem_op_pending && !ram_rd_en && 
    !(step_pending && step_insn_fetched)) begin
    
    if (branch_delay_slot_active) begin
        // State transition only - NO fetch
        branch_delay_slot_active <= 1'b0;
        branch_pending <= 1'b1;
        // NO ram_rd_en, NO PC change
        
    end else if (branch_pending) begin
        // Fetch branch target
        branch_pending <= 1'b0;
        ram_addr_next <= (target <= 16'd1) ? 16'd0 : (target - 16'd1);
        ram_rd_en <= 1'b1;
        exec_pc <= target;
        pc <= target;  // Absolute assignment (NO increment)
        
    end else begin
        // Normal fetch
        ram_addr_next <= (pc <= 16'd1) ? 16'd0 : (pc - 16'd1);
        ram_rd_en <= 1'b1;
        exec_pc <= pc;
        pc <= pc + 16'd1;  // Increment
    end
end
```

## Test Case Validation

### Test 1: Forward Branch
**Expected:** PC=1→2→3→4(delay)→5(target)→6
**Actual:** TBD after fix

### Test 5: Backward Branch Loop
**Expected:** Loop 3 iterations (R0: 0→1→2→3), then exit
**Actual:** Infinite loop PC=43→44→45→46→43... (WRONG)

**Root cause:** `branch_fetch_done` prevents PC advancement after branch

## Conclusion

The current implementation has a **fetch control deadlock** caused by:
1. `branch_fetch_done` flag blocking fetches indefinitely
2. Condition `!branch_fetch_done` in Line 843 is too restrictive
3. Flag only clears when `insn_valid=1`, but fetch is blocked

**Solution:** Remove `branch_fetch_done` entirely and rely on existing state machine (`branch_pending`, `branch_delay_slot_active`) to control fetch timing.
