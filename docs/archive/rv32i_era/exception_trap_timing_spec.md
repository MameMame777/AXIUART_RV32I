# RV32I Exception Trap Timing Specification

## Overview
This document defines the precise timing requirements for exception trap handling in the RV32I core, with focus on CSR initialization and PC redirection.

## Critical Issue Being Debugged
**Symptom**: Exception trap redirects PC to 0x0000 instead of 0x0100 (expected trap_vector from mtvec CSR)  
**Root Cause Hypothesis**: CSR write (CSRW instruction) may not complete before exception (EBREAK) executes  
**Bootstrap Sequence**: Cycles 0-6 execute initialization, EBREAK at cycle 6/7

## Pipeline Stage Definitions

### 5-Stage Pipeline
1. **IF (Instruction Fetch)**: Read instruction from memory at PC
2. **ID (Instruction Decode)**: Decode instruction, read register file
3. **EX (Execute)**: ALU operations, branch resolution
4. **MEM (Memory)**: Load/store operations, exception detection
5. **WB (Write Back)**: Write results to register file or CSRs

### Pipeline Register Naming
- `if_id_reg`: IF→ID pipeline register
- `id_ex_reg`: ID→EX pipeline register  
- `ex_mem_reg`: EX→MEM pipeline register
- `mem_wb_reg`: MEM→WB pipeline register

## CSR Write Timing Specification

### CSRW Instruction Pipeline Flow
```
Cycle N+0: IF stage  - Fetch CSRW instruction from memory
Cycle N+1: ID stage  - Decode CSRW, read source register (rs1)
Cycle N+2: EX stage  - Forward CSR write data through ALU
Cycle N+3: MEM stage - CSR write request propagates
Cycle N+4: WB stage  - CSR register update occurs HERE ✓
```

### CSR Update Timing Rules
1. **CSR Write Completion**: CSR register (e.g., mtvec_reg) is updated during WB stage
2. **Earliest Visible Cycle**: CSR value visible to subsequent instructions at cycle N+5 (after WB completes)
3. **Pipeline Forwarding**: NO forwarding exists for CSR reads - must wait for WB completion
4. **Write Priority**: Exception trap has higher priority than normal CSR write

### Critical Timing Constraint
**REQUIREMENT**: Minimum 4 cycles (pipeline depth) must elapse between CSRW and any instruction that depends on the CSR value.

**Example - Incorrect (Current Bootstrap)**:
```
0x0000: ADDI x31, x0, 1     # Cycle 0
0x0004: SLLI x31, x31, 8    # Cycle 1
0x0008: CSRW mtvec, x31     # Cycle 2 (IF), Cycle 6 (WB) ← Update here
0x000C: JAL x0, +16         # Cycle 3
...
0x001C: ADDI x1, x0, 1      # Cycle 6
0x0020: EBREAK              # Cycle 7 (IF), Cycle 11 (MEM) ← Trap here
```

**Timing Analysis**:
- CSRW enters WB at cycle 6
- EBREAK enters MEM (exception detection) at cycle 11
- **Gap: 5 cycles** - SHOULD be sufficient!
- **Issue**: If mtvec_reg still reads 0x00000000, CSR write logic has a bug

## Exception Detection Timing Specification

### Exception Detection Stage
**Stage**: MEM stage (ex_mem_reg.valid && exception conditions)  
**Signal**: `exception_trap` (single-cycle pulse)  
**Detection Point**: Lines 1147-1207 in rv32i_core.sv

### Exception Types Detected in MEM Stage
```systemverilog
assign exception_insn_misalign    = ex_mem_reg.pc[1:0] != 2'b00;
assign exception_illegal_insn     = ex_mem_reg.ctrl.is_illegal;
assign exception_breakpoint       = ex_mem_reg.ctrl.is_ebreak;  // ← EBREAK detection
assign exception_load_misalign    = /* load address check */;
assign exception_store_misalign   = /* store address check */;
assign exception_ecall            = ex_mem_reg.ctrl.is_ecall;
```

### Exception Trap Pulse Timing
- **Pulse Cycle**: Exception detected in MEM stage → exception_trap asserts for 1 cycle
- **Next Cycle Effect**: PC redirect occurs (pc_if updated to trap_vector)
- **Pipeline Flush**: IF, ID, EX stages flushed (instructions canceled)

## PC Redirection Specification

### PC Update Logic (Line 437-449)
```systemverilog
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        pc_if <= 32'h0000_0000;
    end else if (exception_trap) begin
        pc_if <= trap_vector;  // ← Should be 0x0100, reads 0x0000!
    end else if (mret_detected) begin
        pc_if <= mret_pc;
    end else if (branch_taken) begin
        pc_if <= branch_target;
    end else begin
        pc_if <= pc_if + 32'd4;
    end
end
```

### Priority Order (Highest to Lowest)
1. **Reset**: PC = 0x00000000
2. **Exception Trap**: PC = trap_vector (mtvec_reg)  ← FAILING HERE
3. **MRET**: PC = mret_pc (mepc_reg)
4. **Branch**: PC = branch_target
5. **Sequential**: PC = PC + 4

### CSR Connection to PC Logic
```systemverilog
// rv32i_csr.sv outputs
assign trap_vector = mtvec_reg;  // Line 154
assign mret_pc = mepc_reg;       // Line 155

// rv32i_core.sv instantiation
rv32i_csr csr_inst (
    .trap_vector(trap_vector),   // Connected to PC redirect logic
    ...
);
```

## Debug Requirements

### Assertion Points
1. **CSR Write Completion**:
   - Assert: When mem_wb_reg.valid && mem_wb_reg.ctrl.is_csr && csr_wen, mtvec_reg must update
   
2. **CSR Value at Exception**:
   - Assert: When exception_trap pulses, trap_vector must equal 0x0100 (not 0x0000)
   
3. **Pipeline Ordering**:
   - Assert: CSRW instruction reaches WB before EBREAK reaches MEM
   
4. **Write Enable Logic**:
   - Assert: csr_wen asserts when CSR write instruction is in WB stage

### Critical Signals to Monitor
```systemverilog
// CSR Module Signals
logic        csr_wen;          // CSR write enable
logic [11:0] csr_waddr;        // CSR write address (0x305 for mtvec)
logic [31:0] csr_wdata;        // CSR write data
logic [31:0] mtvec_reg;        // mtvec register value
logic [31:0] trap_vector;      // Output to PC redirect logic

// Exception Signals
logic        exception_trap;    // Exception pulse
logic        exception_breakpoint;  // EBREAK detected
logic [31:0] exception_pc;     // PC of trapped instruction

// Pipeline Stage Signals
logic        mem_wb_reg.valid;      // WB stage valid
logic        mem_wb_reg.ctrl.is_csr; // WB stage is CSR instruction
logic        ex_mem_reg.valid;      // MEM stage valid
logic        ex_mem_reg.ctrl.is_ebreak;  // MEM stage is EBREAK
```

## Expected Behavior (Correct Operation)

### Bootstrap Execution Timeline
```
Cycle 0: IF: ADDI x31,x0,1  | ID: (flush) | EX: (flush) | MEM: (flush) | WB: (flush)
Cycle 1: IF: SLLI x31,x31,8 | ID: ADDI    | EX: (flush) | MEM: (flush) | WB: (flush)
Cycle 2: IF: CSRW mtvec,x31 | ID: SLLI    | EX: ADDI    | MEM: (flush) | WB: (flush)
Cycle 3: IF: JAL x0,+16     | ID: CSRW    | EX: SLLI    | MEM: ADDI    | WB: (flush)
Cycle 4: IF: (0x0010)       | ID: JAL     | EX: CSRW    | MEM: SLLI    | WB: ADDI (x31=1)
Cycle 5: IF: (0x0014)       | ID: (0x10)  | EX: JAL     | MEM: CSRW    | WB: SLLI (x31=0x100)
Cycle 6: IF: 0x001C (ADDI)  | ID: (0x14)  | EX: (0x10)  | MEM: JAL     | WB: CSRW (mtvec=0x100 ✓)
Cycle 7: IF: 0x0020 (EBREAK)| ID: ADDI    | EX: (0x14)  | MEM: (0x10)  | WB: JAL
Cycle 8: IF: 0x0024         | ID: EBREAK  | EX: ADDI    | MEM: (0x14)  | WB: (0x10)
Cycle 9: IF: 0x0028         | ID: (0x24)  | EX: EBREAK  | MEM: ADDI    | WB: (0x14)
Cycle 10: IF: 0x002C        | ID: (0x28)  | EX: (0x24)  | MEM: EBREAK  | WB: ADDI (x1=1)
                                                          ↑ exception_trap=1
Cycle 11: IF: 0x0100 (TRAP) | ID: (flush) | EX: (flush) | MEM: (flush) | WB: (flush)
          ↑ PC redirected to trap_vector (should be 0x0100, currently 0x0000!)
```

### Key Observation
**CSRW completes at Cycle 6 WB**, **EBREAK traps at Cycle 10 MEM** → **4 cycle gap is sufficient**.

If PC still redirects to 0x0000, the issue is NOT timing-related but:
1. CSR write logic not functioning (csr_wen not asserting)
2. CSR address decode error (writing to wrong register)
3. trap_vector connection broken (mtvec_reg → trap_vector → pc_if)

## Verification Strategy

### Phase 1: CSR Write Verification
1. Monitor csr_wen signal during CSRW instruction WB stage
2. Verify csr_waddr = 0x305 (mtvec)
3. Verify csr_wdata = 0x00000100
4. Verify mtvec_reg updates to 0x00000100 after WB cycle

### Phase 2: Exception Trap Verification
1. Monitor exception_trap pulse at EBREAK MEM stage
2. Verify trap_vector = 0x00000100 (not 0x00000000)
3. Verify pc_if updates to trap_vector in next cycle
4. Verify pipeline flush (if_flush, id_flush, ex_flush = 1)

### Phase 3: Root Cause Isolation
- **If mtvec_reg = 0x00000000**: CSR write logic failure
- **If mtvec_reg = 0x00000100 but trap_vector = 0x00000000**: Connection issue
- **If trap_vector = 0x00000100 but pc_if = 0x00000000**: PC redirect priority issue

## Assertion Specification

### rv32i_csr_timing_spec.sv
```systemverilog
// Assertion 1: CSR write enable during WB stage
property csr_write_enable;
    @(posedge clk) disable iff (rst)
    (mem_wb_reg.valid && mem_wb_reg.ctrl.is_csr && csr_waddr == 12'h305)
    |-> csr_wen;
endproperty
assert_csr_wen: assert property(csr_write_enable)
    else $error("[CSR_TIMING] CSR write enable not asserted for mtvec write");

// Assertion 2: mtvec update on write enable
property mtvec_update;
    @(posedge clk) disable iff (rst)
    (csr_wen && csr_waddr == 12'h305) |=> (mtvec_reg == $past(csr_wdata));
endproperty
assert_mtvec_update: assert property(mtvec_update)
    else $error("[CSR_TIMING] mtvec_reg not updated correctly");

// Assertion 3: trap_vector reflects mtvec_reg
property trap_vector_connection;
    @(posedge clk) disable iff (rst)
    trap_vector == mtvec_reg;
endproperty
assert_trap_vector: assert property(trap_vector_connection)
    else $error("[CSR_TIMING] trap_vector does not match mtvec_reg");
```

### rv32i_exception_trap_spec.sv
```systemverilog
// Assertion 4: PC redirect to trap_vector on exception
property pc_redirect_on_exception;
    @(posedge clk) disable iff (rst)
    exception_trap |=> (pc_if == $past(trap_vector));
endproperty
assert_pc_redirect: assert property(pc_redirect_on_exception)
    else $error("[EXCEPTION_TRAP] PC not redirected to trap_vector (expected 0x%08X, got 0x%08X)",
                $past(trap_vector), pc_if);

// Assertion 5: trap_vector must be non-zero when exception occurs
property trap_vector_initialized;
    @(posedge clk) disable iff (rst)
    exception_trap |-> (trap_vector != 32'h0);
endproperty
assert_trap_vector_init: assert property(trap_vector_initialized)
    else $error("[EXCEPTION_TRAP] trap_vector is zero at exception (mtvec not initialized)");

// Assertion 6: Pipeline flush on exception
property pipeline_flush_on_exception;
    @(posedge clk) disable iff (rst)
    exception_trap |-> (if_flush && id_flush && ex_flush);
endproperty
assert_pipeline_flush: assert property(pipeline_flush_on_exception)
    else $error("[EXCEPTION_TRAP] Pipeline not flushed on exception");
```

## Success Criteria

Test PASSES when:
1. ✅ mtvec_reg = 0x00000100 after CSRW completes
2. ✅ trap_vector = 0x00000100 when exception_trap pulses
3. ✅ pc_if = 0x00000100 after exception redirect
4. ✅ All assertions pass with no violations
5. ✅ Trap handler executes at 0x00000100
6. ✅ CSR values (mepc, mcause, mtval) correctly captured
7. ✅ MRET returns to correct address

## References
- rv32i_core.sv: Lines 1147-1207 (exception detection), 437-449 (PC redirect)
- rv32i_csr.sv: Lines 95-122 (CSR write logic), 154-155 (output connections)
- RISC-V Privileged Spec v1.11: Section 3.1.7 (mtvec), 3.1.15 (trap handling)
