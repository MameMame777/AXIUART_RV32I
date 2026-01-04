# RV32I Instruction Fetch (IF) Stage Specification

**Module Name:** `rv32i_if`  
**File:** `rtl/cpu/rv32i_if.sv`  
**Version:** 1.0  
**Date:** January 4, 2026  
**Assertion Module:** `sim/assertions/rv32i_if_timing_spec.sv`

---

## Table of Contents

1. [Overview](#overview)
2. [Block Diagram](#block-diagram)
3. [Interface Signals](#interface-signals)
4. [Functional Description](#functional-description)
5. [Timing Diagrams](#timing-diagrams)
6. [Exception Conditions](#exception-conditions)
7. [Verification Points](#verification-points)
8. [References](#references)

---

## Overview

The Instruction Fetch (IF) stage is responsible for managing the Program Counter (PC), fetching instructions from Block RAM Port A, and detecting hardware breakpoints. It represents the first stage of the 5-stage RV32I pipeline.

### Responsibilities

1. **PC Management:** Maintain and update 32-bit Program Counter
2. **Instruction Fetch:** Generate RAM addresses and capture fetched instructions
3. **PC Redirection:** Handle branch/jump targets and exception trap vectors
4. **Breakpoint Detection:** Check PC against 4 hardware breakpoint registers
5. **Pipeline Control:** Respond to stall and flush signals from hazard unit

### Key Features

- **PC Increment:** Default +4 bytes (sequential execution)
- **Branch Handling:** Redirect to calculated branch/jump target
- **Trap Handling:** Redirect to CSR trap vector on exception
- **MRET Handling:** Restore PC from mepc CSR
- **Breakpoint Hit:** Set flag when PC matches enabled breakpoint
- **Stall Support:** Freeze PC when if_stall asserted
- **Flush Support:** Inject bubble (invalid instruction) when if_flush asserted

---

## Block Diagram

```mermaid
graph TB
    subgraph "rv32i_if Module"
        PC_REG[PC Register<br/>32-bit FF]
        PC_MUX{PC Source<br/>Multiplexer}
        PC_ADDER[PC + 4<br/>Adder]
        BP_CHECKER[Breakpoint<br/>Comparators x4]
        VALID_CTRL[Valid<br/>Control Logic]
        
        PC_REG --> PC_ADDER
        PC_REG --> BP_CHECKER
        PC_ADDER --> |pc_next = pc+4| PC_MUX
        
        BRANCH_TGT[branch_target] --> PC_MUX
        TRAP_VEC[trap_vector] --> PC_MUX
        
        PC_MUX --> |selected_pc| PC_REG
        
        BP_CHECKER --> BP_HIT[dbg_bp_hit[3:0]]
        
        VALID_CTRL --> IF_ID_VALID[if_id_valid]
        
        PC_REG --> |insn_ram_addr<br/>=pc[12:2]| RAM_ADDR[RAM Port A<br/>Address]
        
        RAM_DATA[insn_ram_rdata] --> IF_ID_INSN[if_id_insn]
        PC_REG --> IF_ID_PC[if_id_pc]
    end
    
    subgraph "Control Inputs"
        IF_STALL[if_stall<br/>from hazard]
        IF_FLUSH[if_flush<br/>from hazard]
        BRANCH_TAKEN[branch_taken<br/>from EX]
        TRAP_REDIR[trap_redirect<br/>from CSR]
    end
    
    subgraph "IF/ID Pipeline Register Outputs"
        IF_ID_VALID
        IF_ID_PC
        IF_ID_INSN
    end
    
    subgraph "Memory Interface"
        RAM_ADDR
        RAM_DATA
    end
    
    subgraph "Debug Interface"
        DBG_BP_EN[dbg_bp_enable[3:0]]
        DBG_BP_ADDR[dbg_bp_addr[4]]
        BP_HIT
    end
    
    IF_STALL -.stall_pc.-> PC_REG
    IF_FLUSH -.clear_valid.-> VALID_CTRL
    BRANCH_TAKEN -.select_branch.-> PC_MUX
    TRAP_REDIR -.select_trap.-> PC_MUX
    
    DBG_BP_EN --> BP_CHECKER
    DBG_BP_ADDR --> BP_CHECKER
    
    style PC_REG fill:#ffd700
    style PC_MUX fill:#87ceeb
    style BP_CHECKER fill:#ffb6c1
    style RAM_ADDR fill:#d3d3d3
    style IF_ID_VALID fill:#98fb98
```

---

## Interface Signals

### Input Signals

| Signal | Width | Source | Description |
|--------|-------|--------|-------------|
| `clk` | 1 | System | System clock (positive edge triggered) |
| `rst_n` | 1 | System | Active-low asynchronous reset |
| **Control Inputs** ||||
| `if_stall` | 1 | rv32i_hazard | Stall IF stage (freeze PC, hold outputs) |
| `if_flush` | 1 | rv32i_hazard | Flush IF stage (inject bubble, clear valid) |
| **PC Redirection** ||||
| `branch_taken` | 1 | rv32i_ex | Branch/jump condition met in EX stage |
| `branch_target` | 32 | rv32i_ex | Target PC for branch/jump instructions |
| `trap_redirect` | 1 | rv32i_csr | Exception trap occurred |
| `trap_vector` | 32 | rv32i_csr | Trap handler PC from mtvec CSR |
| `mret_req` | 1 | rv32i_mem | MRET instruction in MEM stage |
| `mret_pc` | 32 | rv32i_csr | Return PC from mepc CSR |
| **Memory Interface** ||||
| `insn_ram_rdata` | 32 | Block RAM | Instruction data from Port A |
| **Debug Interface** ||||
| `dbg_bp_enable` | 4 | Debug | Breakpoint enable flags [3:0] |
| `dbg_bp_addr` | 32×4 | Debug | Breakpoint addresses (array of 4) |
| `running` | 1 | Top | CPU running status (not halted) |

### Output Signals

| Signal | Width | Destination | Description |
|--------|-------|-------------|-------------|
| **Memory Interface** ||||
| `insn_ram_addr` | 11 | Block RAM | Word address for Port A (pc[12:2]) |
| **Debug Interface** ||||
| `dbg_bp_hit` | 4 | Debug | Breakpoint hit flags [3:0] |
| `cpu_break` | 1 | Top | EBREAK or breakpoint detected |
| **IF/ID Pipeline Register** ||||
| `if_id_valid` | 1 | rv32i_id | Instruction valid (not flushed) |
| `if_id_pc` | 32 | rv32i_id | Program Counter of fetched instruction |
| `if_id_insn` | 32 | rv32i_id | Fetched instruction word |

---

## Functional Description

### 4.1 PC Update Logic

The PC is updated every clock cycle according to the following priority (highest first):

```systemverilog
// Priority encoding for PC source selection
always_comb begin
    if (trap_redirect)
        pc_next = trap_vector;          // Priority 1: Exception trap
    else if (mret_req)
        pc_next = mret_pc;              // Priority 2: MRET return
    else if (branch_taken)
        pc_next = branch_target;        // Priority 3: Branch/jump
    else
        pc_next = pc_reg + 4;           // Priority 4: Sequential (default)
end

// PC register update
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        pc_reg <= 32'h0000_0000;        // Reset vector
    else if (!if_stall)
        pc_reg <= pc_next;              // Update if not stalled
    // else: hold current value
end
```

**Key Points:**
- Reset vector is 0x0000_0000 (start of Block RAM)
- PC frozen when `if_stall` asserted (load-use hazard, memory contention)
- PC always aligned to 4-byte boundary (instruction word size)

---

### 4.2 Instruction RAM Address Generation

```systemverilog
// Convert byte address to word address for Block RAM
assign insn_ram_addr = pc_reg[12:2];  // Extract bits [12:2] for 11-bit word address

// Valid address range: 0x000 - 0x7FF (2048 words = 8KB)
```

**Address Mapping:**
```
PC Byte Address    Word Address    Block RAM Location
0x0000_0000   -->  0x000      -->  ram[0]
0x0000_0004   -->  0x001      -->  ram[1]
0x0000_0008   -->  0x002      -->  ram[2]
...
0x0000_1FFC   -->  0x7FF      -->  ram[2047]
```

---

### 4.3 Hardware Breakpoint Detection

```systemverilog
// Breakpoint hit detection (combinational)
generate
    for (genvar i = 0; i < 4; i++) begin : gen_bp_detect
        assign dbg_bp_hit[i] = dbg_bp_enable[i] && 
                               (pc_reg == dbg_bp_addr[i]) && 
                               running;
    end
endgenerate

// CPU break flag (any breakpoint hit triggers halt)
assign cpu_break = |dbg_bp_hit;  // OR reduction
```

**Behavior:**
- **Breakpoint Hit:** `dbg_bp_hit[i]` asserted when:
  1. Breakpoint enabled (`dbg_bp_enable[i] = 1`)
  2. PC matches breakpoint address (`pc_reg == dbg_bp_addr[i]`)
  3. CPU is running (not already halted)
- **Halt Trigger:** `cpu_break` flag causes CPU to transition to HALTED state
- **Priority:** Breakpoints checked every cycle, take effect on next clock

---

### 4.4 Valid Signal Control

```systemverilog
// IF/ID pipeline register valid logic
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        if_id_valid <= 1'b0;
    else if (if_flush)
        if_id_valid <= 1'b0;            // Inject bubble (invalid instruction)
    else if (!if_stall)
        if_id_valid <= 1'b1;            // Normal instruction propagation
    // else: hold previous value (stall)
end
```

**Bubble Injection Scenarios:**
1. **Reset:** All instructions invalid until first fetch
2. **Flush (if_flush):** Branch misprediction, trap redirect
3. **Stall (if_stall):** Valid bit held (instruction re-presented to ID stage)

---

### 4.5 IF/ID Pipeline Register

```systemverilog
// Pipeline register update
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        if_id_pc   <= 32'h0;
        if_id_insn <= 32'h0000_0013;    // NOP (ADDI x0, x0, 0)
    end else if (!if_stall) begin
        if_id_pc   <= pc_reg;
        if_id_insn <= insn_ram_rdata;
    end
    // else: hold previous values (stall)
end
```

**Reset Value:**
- `if_id_insn = 0x0000_0013` (NOP instruction to avoid spurious decode)

---

## Timing Diagrams

### 5.1 Normal Sequential Execution

```
Clock    : ___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___
           
pc_reg   : 0x0000 | 0x0004 | 0x0008 | 0x000C | 0x0010
           
if_stall : _____________________________________________
if_flush : _____________________________________________
           
insn_ram_: 0x000  | 0x001  | 0x002  | 0x003  | 0x004
addr     :        |        |        |        |
           
insn_ram_: ????   | INSN_0 | INSN_1 | INSN_2 | INSN_3
rdata    :        | (0x000)| (0x004)| (0x008)| (0x00C)
           
if_id_pc : 0x0000 | 0x0000 | 0x0004 | 0x0008 | 0x000C
           
if_id_   : NOP    | INSN_0 | INSN_1 | INSN_2 | INSN_3
insn     : (reset)|        |        |        |
           
if_id_   : 0      | 1      | 1      | 1      | 1
valid    :        |        |        |        |
```

**Description:** PC increments by 4 each cycle, instructions fetched sequentially.

---

### 5.2 Branch Taken (Pipeline Flush)

```
Clock    : ___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___
           
Cycle    :    0   |   1   |   2   |   3   |   4
           
pc_reg   : 0x0000 | 0x0004 | 0x0008 | 0x0100 | 0x0104
                                    \_______/
                                    branch_target
           
branch_  : ___________________/‾‾‾‾‾\_______________
taken    :                    (cycle 2)
           
branch_  : xxxxxxxxxxxxxxxxxx|0x0100|xxxxxxxxxxxxx
target   :                    |      |
           
if_flush : _______________________/‾‾‾‾‾\_________
           :                      (cycle 3)
           
if_id_pc : 0x0000 | 0x0004 | 0x0008 | 0x0008 | 0x0100
                                      \______/
                                      flushed
           
if_id_   : INSN_0 | INSN_1 | INSN_2 | INSN_2 | INSN_TGT
insn     :        |        |        | (flush)|
           
if_id_   : 1      | 1      | 1      | 0      | 1
valid    :        |        |        | BUBBLE |
```

**Description:** 
1. Branch taken detected in cycle 2
2. PC redirected to branch_target (0x0100) in cycle 3
3. IF stage flushed (bubble injected) in cycle 3
4. New instruction from target fetched in cycle 4

**Branch Penalty:** 2 cycles (1 for detection, 1 for flush)

---

### 5.3 Load-Use Stall

```
Clock    : ___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___
           
Cycle    :    0   |   1   |   2   |   3   |   4
           
pc_reg   : 0x0000 | 0x0004 | 0x0004 | 0x0004 | 0x0008
                            \_____/ \_____/
                            stalled stalled
           
if_stall : ___________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_________
           :          (cycles 1-2)
           
insn_ram_: 0x000  | 0x001  | 0x001  | 0x001  | 0x002
addr     :        |        | (held) | (held) |
           
if_id_pc : 0x0000 | 0x0000 | 0x0004 | 0x0004 | 0x0004
                            \_____/ \_____/
                            repeated repeated
           
if_id_   : NOP    | INSN_0 | INSN_1 | INSN_1 | INSN_1
insn     : (reset)|        | (held) | (held) |
           
if_id_   : 0      | 1      | 1      | 1      | 1
valid    :        |        | (held) | (held) |
```

**Description:**
1. IF stage stalled in cycles 1-2 (load-use hazard in ID stage)
2. PC frozen at 0x0004
3. IF/ID register outputs held (instruction re-presented to ID stage)
4. Stall released in cycle 3, PC resumes incrementing

---

### 5.4 Hardware Breakpoint Hit

```
Clock    : ___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___
           
Cycle    :    0   |   1   |   2   |   3   |   4
           
pc_reg   : 0x0000 | 0x0004 | 0x0008 | 0x0008 | 0x0008
                                      \_____/ \_____/
                                      frozen  frozen
           
dbg_bp_  : 0      | 0      | 0      | 1      | 1
hit[0]   :        |        |        | (BP hit)|
           
cpu_     : ___________________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
break    :                    (asserted, triggers halt)
           
running  : 1      | 1      | 1      | 0      | 0
           :        |        |        | HALTED | HALTED
           
if_id_   : INSN_0 | INSN_1 | INSN_2 | INSN_2 | INSN_2
insn     :        |        |        | (frozen)| (frozen)
```

**Description:**
1. PC reaches breakpoint address (0x0008) in cycle 2
2. `dbg_bp_hit[0]` asserts in cycle 2
3. `cpu_break` flag triggers halt transition
4. CPU enters HALTED state in cycle 3
5. PC and pipeline frozen

---

### 5.5 Exception Trap Redirect

```
Clock    : ___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___
           
Cycle    :    0   |   1   |   2   |   3   |   4
           
pc_reg   : 0x0000 | 0x0004 | 0x0008 | 0x1000 | 0x1004
                                      \_____/
                                      trap_vector
           
trap_    : ___________________/‾‾‾‾‾\_______________
redirect :                    (cycle 2)
           
trap_    : xxxxxxxxxxxxxxxxxxxx|0x1000|xxxxxxxxxxxxx
vector   :                     |      |
           
if_flush : _______________________/‾‾‾‾‾\_________
           :                      (cycle 3)
           
if_id_pc : 0x0000 | 0x0004 | 0x0008 | 0x0008 | 0x1000
                                      \_____/
                                      flushed
           
if_id_   : INSN_0 | INSN_1 | INSN_2 | INSN_2 | TRAP_HDL
insn     :        |        |        | (flush)|
           
if_id_   : 1      | 1      | 1      | 0      | 1
valid    :        |        |        | BUBBLE |
```

**Description:**
1. Exception detected in MEM stage (cycle 1)
2. `trap_redirect` asserts in cycle 2
3. PC redirected to `trap_vector` (0x1000) in cycle 3
4. IF stage flushed (bubble injected)
5. Trap handler instruction fetched in cycle 4

---

## Exception Conditions

### 6.1 Instruction Address Misalignment

**Condition:** PC not aligned to 4-byte boundary (pc[1:0] != 2'b00)

**Detection Location:** Not detected in IF stage (architectural assumption)

**Note:** RISC-V allows misaligned PC in theory, but this implementation assumes 4-byte alignment. If misalignment support needed, add assertion:

```systemverilog
assert_pc_aligned: assert property (
    @(posedge clk) disable iff (!rst_n)
    (pc_reg[1:0] == 2'b00)
) else $error("[IF_SPEC] PC misaligned: 0x%08X", pc_reg);
```

---

### 6.2 Instruction Access Fault

**Condition:** PC exceeds Block RAM range (pc >= 0x2000)

**Detection Location:** Not explicitly detected in IF stage

**Mitigation:** Address bits [12:2] naturally wrap within 11-bit range. Out-of-range access returns unpredictable data.

**Enhancement Option:** Add range check in MEM stage exception detection.

---

## Verification Points

### 7.1 Assertion Checklist

The following properties are verified by `rv32i_if_timing_spec.sv`:

#### **SPEC-IF-1: PC Sequential Increment**
```systemverilog
// Without stall/flush/redirect, PC increments by 4
property pc_increments_sequentially;
    @(posedge clk) disable iff (!rst_n)
    (!if_stall && !if_flush && !branch_taken && !trap_redirect && !mret_req)
    |=> (pc_reg == $past(pc_reg) + 4);
endproperty
```

#### **SPEC-IF-2: Branch Redirection**
```systemverilog
// PC redirected to branch_target when branch_taken
property pc_redirects_on_branch;
    logic [31:0] expected_target;
    @(posedge clk) disable iff (!rst_n)
    (branch_taken, expected_target = branch_target)
    |=> (pc_reg == expected_target);
endproperty
```

#### **SPEC-IF-3: Trap Vector Redirect**
```systemverilog
// PC redirected to trap_vector when trap_redirect
property pc_redirects_on_trap;
    logic [31:0] expected_vector;
    @(posedge clk) disable iff (!rst_n)
    (trap_redirect, expected_vector = trap_vector)
    |=> (pc_reg == expected_vector);
endproperty
```

#### **SPEC-IF-4: PC Stall Behavior**
```systemverilog
// PC frozen when if_stall asserted
property pc_freezes_on_stall;
    logic [31:0] stalled_pc;
    @(posedge clk) disable iff (!rst_n)
    (if_stall, stalled_pc = pc_reg)
    |=> (pc_reg == stalled_pc);
endproperty
```

#### **SPEC-IF-5: Breakpoint Hit Detection**
```systemverilog
// Breakpoint hit when enabled and PC matches
generate
    for (genvar i = 0; i < 4; i++) begin : gen_bp_assertions
        property bp_hit_detected;
            @(posedge clk) disable iff (!rst_n)
            (dbg_bp_enable[i] && (pc_reg == dbg_bp_addr[i]) && running)
            |-> (dbg_bp_hit[i] == 1'b1);
        endproperty
        
        assert_bp_hit: assert property (bp_hit_detected);
    end
endgenerate
```

#### **SPEC-IF-6: Valid Bit Flush**
```systemverilog
// Valid cleared when if_flush asserted
property valid_cleared_on_flush;
    @(posedge clk) disable iff (!rst_n)
    if_flush |=> (if_id_valid == 1'b0);
endproperty
```

#### **SPEC-IF-7: RAM Address Correctness**
```systemverilog
// RAM address matches PC word address
property ram_addr_matches_pc;
    @(posedge clk) disable iff (!rst_n)
    (insn_ram_addr == pc_reg[12:2]);
endproperty
```

---

### 7.2 Coverage Goals

1. **PC Redirect Coverage:**
   - Sequential execution (baseline)
   - Branch taken
   - Jump (JAL/JALR)
   - Trap redirect
   - MRET return

2. **Stall/Flush Coverage:**
   - Normal operation (no stall, no flush)
   - Stall only
   - Flush only
   - Stall + flush simultaneously

3. **Breakpoint Coverage:**
   - Each breakpoint [3:0] hit individually
   - Multiple breakpoints hit simultaneously
   - Breakpoint hit while stalled
   - Breakpoint disabled (no false hits)

4. **Edge Cases:**
   - PC wraparound (0x1FFC → 0x0000)
   - Rapid stall/flush toggling
   - Redirect during stall

---

## References

### Related Documents
- **[rv32i_modular_architecture_spec.md](../../docs/rv32i_modular_architecture_spec.md)** - Overall architecture
- **[rv32i_pipeline_interfaces.md](../../docs/rv32i_pipeline_interfaces.md)** - Pipeline register structures
- **[rv32i_hazard_spec.md](rv32i_hazard_spec.md)** - Hazard unit (stall/flush generation)
- **[rv32i_ex_spec.md](rv32i_ex_spec.md)** - EX stage (branch decision)
- **[rv32i_csr_spec.md](rv32i_csr_spec.md)** - CSR module (trap vector)

### Assertion Modules
- **[rv32i_if_timing_spec.sv](../../sim/assertions/rv32i_if_timing_spec.sv)** - IF stage timing assertions
- **[bind_rv32i_if_spec.sv](../../sim/assertions/bind_rv32i_if_spec.sv)** - Assertion binding file

### Test Cases
- **rv32i_basic_test.sv** - Sequential execution
- **rv32i_breakpoint_test.sv** - Hardware breakpoint functionality
- **rv32i_exception_handler_test.sv** - Trap vector redirect

---

**Specification Version:** 1.0  
**Last Updated:** 2026-01-04  
**Status:** Design Phase - Pre-Implementation
