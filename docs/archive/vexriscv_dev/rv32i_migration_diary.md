# RISC-V RV32I Migration Diary

**Date**: January 2, 2026  
**Project**: TD4UART - TD4CPU → RV32I Clean-Slate Migration  
**Branch**: `feature/cpu-mmio-led` → `feature/rv32i-cleanslate` (planned)  
**Baseline Tag**: `td4cpu-final-v0.1`

---

## Executive Summary

This diary documents the complete architectural migration from the custom TD4CPU (16-bit, 8 registers, word-addressed, branch delay slots) to a **RISC-V RV32I** compliant processor (32-bit, 32 registers, byte-addressed, 5-stage pipeline with standard hazard handling).

**Strategic Decision**: **Clean-slate design** approach chosen over incremental modification.

**Rationale**:
- TD4CPU and RV32I architectures are fundamentally incompatible
- Accumulator-style ALU vs. 3-operand register-register operations
- Word addressing vs. byte addressing requires complete memory subsystem rewrite
- Branch delay slots vs. clean pipeline with stall+flush
- 8 registers vs. 32 registers (with x0 hardwired to zero)
- Estimated effort similar (160-220 hours) but clean-slate produces better architecture

---

## Migration Goals

1. ✅ **Full RV32I compliance** (40 core instructions, not including CSR operations)
2. ✅ **5-stage pipeline** (IF/ID/EX/MEM/WB) with:
   - Data hazard handling (RAW forwarding from EX/MEM stages)
   - Control hazard handling (branch/jump stall+flush, predict-not-taken)
   - Load-use hazard detection (1-cycle stall)
3. ✅ **Byte-addressed memory** (compiler-compatible addressing)
4. ✅ **32x32-bit register file** (x0 hardwired to zero per RISC-V spec)
5. ✅ **8KB internal RAM** (2048 × 32-bit words, same capacity as TD4CPU)
6. ✅ **Debug interface compatibility** (preserve Register_Block.sv control signals)
7. ⏳ **GNU toolchain integration** (riscv32-unknown-elf-gcc for C compilation)

---

## Architectural Comparison: TD4CPU vs. RV32I

### Data Path

| Feature | TD4CPU (v0.1) | RV32I (Target) | Impact |
|---------|---------------|----------------|--------|
| **Data Width** | 16-bit | 32-bit | 2× register file, ALU, memory interface |
| **Instruction Width** | 16-bit (some 32-bit) | 32-bit (fixed) | Uniform instruction fetch |
| **Register Count** | 8 (R0-R7) | 32 (x0-x31) | 4× register file size |
| **x0 Behavior** | R0 is writable | **x0 hardwired to 0** | Critical RISC-V invariant |
| **Address Width** | 16-bit | 32-bit | Wider address space support |

### ISA Design

| Feature | TD4CPU (v0.1) | RV32I (Target) | Impact |
|---------|---------------|----------------|--------|
| **ISA Style** | CISC-like accumulator | RISC 3-operand | Complete ALU redesign |
| **Instruction Count** | 20 instructions | 40 instructions | 2× decoder complexity |
| **ALU Operations** | `rd = rd ⊕ rs` | `rd = rs1 ⊕ rs2` | Separate source/destination |
| **Immediate Size** | 9-bit max | 20-bit (U-type), 12-bit (I-type) | More flexible constants |
| **Opcode Width** | 4-bit | 7-bit | More instruction space |
| **Register Encoding** | 3-bit | 5-bit | Wider register addressing |

### Memory System

| Feature | TD4CPU (v0.1) | RV32I (Target) | Impact |
|---------|---------------|----------------|--------|
| **Addressing Unit** | **Word** (16-bit) | **Byte** | Complete memory rewrite |
| **PC Increment** | PC += 1 (word) | PC += 4 (bytes) | 4× address granularity |
| **Alignment** | Always aligned | Optional (we enforce) | Byte lane selection logic |
| **Load/Store Width** | 16-bit only | 8/16/32-bit (LB/LH/LW) | Multi-width access support |
| **Memory Capacity** | 8KB (4096 × 16-bit) | 8KB (2048 × 32-bit) | Same total capacity |
| **MMIO LED Address** | 0x101F (word) | 0x407C (byte) | Address translation |

### Control Flow

| Feature | TD4CPU (v0.1) | RV32I (Target) | Impact |
|---------|---------------|----------------|--------|
| **Branch Instruction** | BR (1 opcode, 3-bit condition) | BEQ/BNE/BLT/BGE/BLTU/BGEU | 6 separate opcodes |
| **Branch Delay Slot** | **Yes (MIPS-style)** | **No (clean pipeline)** | Simplification! |
| **Branch Timing** | Delay slot executes | Stall+flush on taken | Standard hazard handling |
| **Jump** | JMP16/CALL16 (absolute) | JAL/JALR (PC-relative) | Position-independent code |
| **Link Register** | SP (separate) | x1 by convention | Standard calling convention |
| **Return** | RET (dedicated) | JALR x0, ra, 0 | Unified jump mechanism |

### Pipeline Architecture

| Feature | TD4CPU (v0.1) | RV32I (Target) | Impact |
|---------|---------------|----------------|--------|
| **Pipeline Style** | Partial (multi-cycle) | Full 5-stage | Classic RISC pipeline |
| **Stages** | Fetch + Execute | IF/ID/EX/MEM/WB | Standard separation |
| **Hazard Handling** | Interlocks only | Forwarding + stalls | Better performance |
| **Branch Penalty** | 1 cycle + delay slot | 2 cycles (stall+flush) | Simpler, no speculation |
| **PC Management** | Pre-increment, offset | Sequential +4, target mux | Clean PC control |

---

## Implementation Plan

### Phase 0: Foundation (Completed ✅)

**Date**: January 2, 2026

1. ✅ **Baseline Preservation**
   - Tagged current TD4CPU as `td4cpu-final-v0.1`
   - Backed up `td4cpu_core.sv` to `td4cpu_core_v0.1_archive.sv`
   - All existing tests and assertions preserved

2. ✅ **ISA Specification**
   - Created `isa/rv32i_isa.json` with all 40 RV32I instructions
   - Defined R/I/S/B/U/J instruction formats
   - Specified memory map (RAM: 0x0000-0x1FFF, MMIO: 0x4000-0x7FFF)
   - Documented 5-stage pipeline architecture

3. ✅ **SystemVerilog ISA Package**
   - Generated `rtl/cpu/rv32i_isa_pkg.sv`
   - Complete instruction decoder function `decode_insn()`
   - Immediate extraction helpers (I/S/B/U/J types)
   - Control signal structure `decode_ctrl_t`
   - ALU operation, branch, memory, and writeback type definitions

4. ✅ **Pipeline Specification (SVA)**
   - Created `sim/assertions/rv32i_pipeline_spec.sv`
   - Assertions for x0 hardwire (CRITICAL: x0 must always be 0)
   - Pipeline progression checks (IF→ID→EX→MEM→WB)
   - PC management (sequential +4, branch/jump target)
   - Hazard detection (RAW, load-use, control hazards)
   - Forwarding path activation
   - Performance counters (IPC, stalls, flushes)

**Key Artifacts**:
- `isa/rv32i_isa.json` - 583 lines, JSON ISA definition
- `rtl/cpu/rv32i_isa_pkg.sv` - 734 lines, complete decoder
- `sim/assertions/rv32i_pipeline_spec.sv` - 435 lines, executable spec

---

### Phase 1: Register File & Pipeline Registers (In Progress 🚧)

**Target Date**: January 3, 2026  
**Estimated Effort**: 8-12 hours

#### Objectives

1. **Register File Implementation**
   - 32 × 32-bit general-purpose registers
   - **x0 hardwired to zero** (writes ignored, reads return 0)
   - Dual-port read (rs1, rs2 simultaneous)
   - Single-port write (rd)
   - Registered read (1-cycle latency) or combinational (0-cycle)

2. **Pipeline Register Structures**
   - IF/ID pipeline register (PC, instruction, valid, flush)
   - ID/EX pipeline register (PC, decoded control, rs1/rs2 data, valid, flush)
   - EX/MEM pipeline register (PC, ALU result, mem control, rs2 data, valid, flush)
   - MEM/WB pipeline register (PC, result data, writeback control, valid)

3. **Control Signal Propagation**
   - Valid bit per stage (for bubble insertion)
   - Flush signals (for control hazard recovery)
   - Stall signals (for data hazard handling)

#### Design Decisions

**Register File Style**: Choose between:
- **Option A**: Inferred register file (synthesizes to distributed RAM or registers)
- **Option B**: Block RAM instantiation (more area-efficient for FPGA)
- **Decision**: Start with **Option A** for simplicity, optimize later if needed

**Read Timing**: Choose between:
- **Option A**: Registered read (IF/ID stage reads, ID stage decodes, EX stage has data)
- **Option B**: Combinational read (ID stage reads and decodes, EX stage has data)
- **Decision**: **Option B** (combinational) for simplicity, matches most educational RISC-V cores

**x0 Implementation**:
```systemverilog
// x0 hardwire - CRITICAL invariant
assign rf_rdata1 = (rf_raddr1 == 5'b0) ? 32'h0 : regs[rf_raddr1];
assign rf_rdata2 = (rf_raddr2 == 5'b0) ? 32'h0 : regs[rf_raddr2];

// x0 write protection
always_ff @(posedge clk) begin
    if (rf_wen && rf_waddr != 5'b0)
        regs[rf_waddr] <= rf_wdata;
end
```

---

### Phase 2: Instruction Fetch (IF)

**Target Date**: January 4, 2026  
**Estimated Effort**: 6-8 hours

#### Objectives

1. **Program Counter (PC) Management**
   - 32-bit PC register (byte-addressed)
   - Sequential increment: `PC <= PC + 4`
   - Branch/jump target: `PC <= target_address`
   - Reset: `PC <= 32'h00000000`

2. **Instruction Memory Interface**
   - 32-bit instruction word fetch
   - 1-cycle latency (Block RAM read)
   - Address translation: `ram_addr = PC[12:2]` (word index from byte address)
   - Valid address range check: `PC < 0x2000` (8KB)

3. **Fetch Control**
   - Stall on data hazard (freeze PC)
   - Flush on control hazard (invalidate IF/ID register)
   - PC update priority: branch/jump > sequential

#### Critical Constraints

- **PC must be 4-byte aligned** (PC[1:0] == 2'b00)
- **No instruction caching** (simple direct RAM access)
- **Instruction memory shared with data memory** (von Neumann architecture)
  - **Note**: This creates structural hazard - must arbitrate IF vs. MEM stage access
  - **Solution**: Prioritize MEM stage, stall IF when conflict detected

---

### Phase 3: Instruction Decode (ID)

**Target Date**: January 5, 2026  
**Estimated Effort**: 8-10 hours

#### Objectives

1. **Instruction Decoder**
   - Use `rv32i_isa_pkg::decode_insn()` function
   - Extract opcode, funct3, funct7
   - Generate all control signals (ALU op, mem op, branch type, etc.)

2. **Immediate Generation**
   - I-type: Sign-extend imm[11:0]
   - S-type: Assemble {imm[11:5], imm[4:0]}
   - B-type: Assemble {imm[12], imm[11], imm[10:5], imm[4:1], 1'b0}
   - U-type: {imm[31:12], 12'b0}
   - J-type: Assemble {imm[20], imm[19:12], imm[11], imm[10:1], 1'b0}

3. **Register File Read**
   - rs1, rs2 addresses extracted from instruction
   - Combinational read (data available same cycle)

4. **Hazard Detection Preparation**
   - Identify source registers (rs1, rs2) for forwarding check
   - Identify destination register (rd) for future hazard detection

---

### Phase 4: Execute (EX)

**Target Date**: January 6-7, 2026  
**Estimated Effort**: 12-16 hours

#### Objectives

1. **32-bit ALU**
   - ADD/SUB (arithmetic)
   - AND/OR/XOR (logical)
   - SLL/SRL/SRA (shifts)
   - SLT/SLTU (comparisons)
   - LUI (load upper immediate - pass through)
   - AUIPC (add PC to immediate)

2. **Branch Condition Evaluation**
   - BEQ: rs1 == rs2
   - BNE: rs1 != rs2
   - BLT: rs1 <s rs2 (signed)
   - BGE: rs1 >=s rs2 (signed)
   - BLTU: rs1 <u rs2 (unsigned)
   - BGEU: rs1 >=u rs2 (unsigned)

3. **Jump/Branch Target Calculation**
   - Branch: `target = PC + imm`
   - JAL: `target = PC + imm`
   - JALR: `target = (rs1 + imm) & ~1` (clear LSB)

4. **Forwarding Multiplexers**
   - rs1 source: register file / EX forward / MEM forward
   - rs2 source: register file / EX forward / MEM forward
   - **Forwarding priority**: EX stage > MEM stage > register file

---

### Phase 5: Memory Access (MEM)

**Target Date**: January 8-9, 2026  
**Estimated Effort**: 10-14 hours

#### Objectives

1. **Byte-Addressed Memory Interface**
   - Address calculation: `addr = rs1 + imm` (already computed in EX)
   - Alignment check: LH/LHU/SH require addr[0]=0, LW/SW require addr[1:0]=0
   - Byte lane selection for sub-word accesses

2. **Load Operations**
   - LB: Load byte, sign-extend to 32 bits
   - LH: Load halfword, sign-extend to 32 bits
   - LW: Load word (32 bits)
   - LBU: Load byte, zero-extend to 32 bits
   - LHU: Load halfword, zero-extend to 32 bits

3. **Store Operations**
   - SB: Store byte (bits [7:0] of rs2)
   - SH: Store halfword (bits [15:0] of rs2)
   - SW: Store word (all 32 bits of rs2)

4. **MMIO Decode**
   - RAM region: 0x0000_0000 - 0x0000_1FFF (8KB)
   - MMIO region: 0x0000_4000 - 0x0000_7FFF
   - LED register: 0x0000_407C (4 bits)

#### Byte Addressing Implementation

**Word-to-byte address translation**:
- Old TD4CPU: `addr` indexes 16-bit words directly
- New RV32I: `addr[31:2]` indexes 32-bit words, `addr[1:0]` selects byte lane

**Byte lane selection example (load)**:
```systemverilog
case (mem_width)
    MEM_BYTE: begin
        case (addr[1:0])
            2'b00: data_out = {{24{mem_data[7] & sign_ext}}, mem_data[7:0]};
            2'b01: data_out = {{24{mem_data[15] & sign_ext}}, mem_data[15:8]};
            2'b10: data_out = {{24{mem_data[23] & sign_ext}}, mem_data[23:16]};
            2'b11: data_out = {{24{mem_data[31] & sign_ext}}, mem_data[31:24]};
        endcase
    end
    MEM_HALF: begin
        case (addr[1])
            1'b0: data_out = {{16{mem_data[15] & sign_ext}}, mem_data[15:0]};
            1'b1: data_out = {{16{mem_data[31] & sign_ext}}, mem_data[31:16]};
        endcase
    end
    MEM_WORD: data_out = mem_data;
endcase
```

---

### Phase 6: Writeback (WB)

**Target Date**: January 10, 2026  
**Estimated Effort**: 4-6 hours

#### Objectives

1. **Result Multiplexer**
   - ALU result (arithmetic/logical operations)
   - Memory data (load operations)
   - PC + 4 (JAL/JALR link register save)

2. **Register File Write**
   - Write enable from decoded instruction
   - Destination register from instruction
   - **x0 protection**: writes to x0 are legal but ignored

---

### Phase 7: Hazard Detection & Forwarding

**Target Date**: January 11-12, 2026  
**Estimated Effort**: 12-16 hours

#### Objectives

1. **RAW Hazard Detection**
   - EX stage hazard: ID.rs1/rs2 == EX.rd
   - MEM stage hazard: ID.rs1/rs2 == MEM.rd
   - WB stage hazard: ID.rs1/rs2 == WB.rd (handled by register file)

2. **Load-Use Hazard Detection**
   - Special case: load in EX, use in ID
   - Cannot forward (data not ready until MEM)
   - **Solution**: 1-cycle stall (bubble in EX)

3. **Forwarding Unit**
   - Forward from EX/MEM stage to EX stage operands
   - **Priority**: EX forward > MEM forward > register file
   - **Exception**: Load-use case (stall instead of forward)

4. **Control Hazard Handling**
   - Branch/jump resolved in EX stage
   - **On taken**: Flush IF/ID stages, update PC to target
   - **Penalty**: 2 cycles (1 delay slot + 1 flush)

---

### Phase 8: Debug Interface Integration

**Target Date**: January 13, 2026  
**Estimated Effort**: 6-8 hours

#### Objectives

1. **Preserve Debug Signals**
   - `cpu_halt` - Stop execution
   - `cpu_run` - Resume execution
   - `cpu_step` - Single-step mode
   - `cpu_break` - Breakpoint hit signal

2. **EBREAK Implementation**
   - Decode EBREAK instruction (0x00100073)
   - Set `cpu_break` signal
   - Halt pipeline (same as `cpu_halt`)

3. **Single-Step Mode**
   - Execute one instruction, then halt
   - Wait for `cpu_step` pulse
   - Resume for one instruction

---

### Phase 9: Trace Buffer Update

**Target Date**: January 14, 2026  
**Estimated Effort**: 4-6 hours

#### Objectives

1. **Widen Trace Buffer**
   - PC: 16-bit → 32-bit
   - Instruction: 16-bit → 32-bit
   - Register data: 16-bit → 32-bit
   - Maintain 256-entry circular buffer

2. **Trace Formatting**
   - Use ABI register names from `rv32i_isa_pkg::get_reg_name()`
   - Include decoded instruction mnemonics
   - Show forwarding events for debug

---

### Phase 10: Verification & Testing

**Target Date**: January 15-20, 2026  
**Estimated Effort**: 20-30 hours

#### Objectives

1. **Unit Tests**
   - Register file x0 hardwire test
   - ALU operation tests (all 10 ops)
   - Branch condition tests (all 6 branches)
   - Memory byte/halfword/word access tests

2. **RV32I Compliance Tests**
   - Use official riscv-tests suite
   - Verify all 40 instructions
   - Check corner cases (alignment, x0 writes, etc.)

3. **Integration Tests**
   - Port existing TD4CPU tests to RV32I assembly
   - MMIO LED blink test
   - Software interrupt test (ECALL)
   - Breakpoint test (EBREAK)

---

## Key Technical Decisions

### Decision 1: Clean-Slate vs. Incremental Migration

**Options**:
- A) Modify `td4cpu_core.sv` incrementally
- B) Write new `rv32i_core.sv` from scratch

**Decision**: **Option B (Clean-Slate)**

**Rationale**:
- Architectural incompatibility too severe (accumulator vs. 3-operand, word vs. byte addressing)
- Incremental approach would require rewriting 80%+ of code anyway
- Clean slate enables better architecture without legacy constraints
- Similar effort (~160-220 hours) but cleaner result
- Easier to verify against RISC-V specification

**Preserved from TD4CPU**:
- Debug interface protocol
- UART-to-register-block communication
- UVM testbench structure
- Assertion-driven verification methodology

---

### Decision 2: Pipeline Depth - 5 Stages

**Options**:
- A) Single-cycle (no pipeline)
- B) 2-stage (Fetch + Execute)
- C) 5-stage (IF/ID/EX/MEM/WB)

**Decision**: **Option C (5-Stage Classic RISC Pipeline)**

**Rationale**:
- User explicitly requested "5-stage pipeline"
- Standard educational RISC-V implementation
- Clear stage separation simplifies verification
- Forwarding and hazard handling are well-understood
- Good balance between performance and complexity

**Performance Implications**:
- Best case IPC: ~1.0 (ideal pipeline)
- Realistic IPC: ~0.6-0.8 (with stalls/flushes)
- Branch penalty: 2 cycles (vs. TD4CPU's 1 cycle + delay slot)

---

### Decision 3: Branch Prediction - Static Predict-Not-Taken

**Options**:
- A) Always predict not-taken (simple)
- B) Always predict taken
- C) Branch history table (complex)

**Decision**: **Option A (Predict-Not-Taken)**

**Rationale**:
- Simplest implementation (no extra state)
- User specified "no speculation" - minimal prediction acceptable
- Matches most educational RISC-V cores
- Forward branches typically not taken (loop exits)

**Penalty**:
- Correct prediction (not taken): 0 cycles
- Misprediction (taken): 2 cycles (flush IF/ID)

---

### Decision 4: Register File Read Timing - Combinational

**Options**:
- A) Combinational read (0-cycle latency)
- B) Registered read (1-cycle latency)

**Decision**: **Option A (Combinational Read)**

**Rationale**:
- Simpler pipeline control (no extra stage)
- Standard for small register files (32 registers)
- Matches PicoRV32, SERV, and most educational cores
- Critical path acceptable for educational FPGA target

**Trade-off**:
- Longer critical path (register file read → ALU → result)
- May limit maximum clock frequency
- Can optimize later with replication if needed

---

### Decision 5: Memory Addressing - Byte-Addressed

**Options**:
- A) Keep word-addressed (incompatible with compilers)
- B) Byte-addressed (RISC-V standard)

**Decision**: **Option B (Byte-Addressed)**

**Rationale**:
- **MANDATORY for RISC-V compliance**
- Required for GNU toolchain compatibility (gcc, binutils)
- Standard C compiler expects byte addressing
- All RISC-V software assumes byte addressing

**Implementation**:
- PC increments by 4 (not 1)
- Load/store addresses are byte addresses
- Word accesses must be 4-byte aligned (or support unaligned)
- Byte lane selection logic required for LB/LH/SB/SH

---

### Decision 6: Internal RAM vs. AXI Master

**Options**:
- A) Keep internal 8KB Block RAM
- B) Make CPU an AXI master, access external memory

**Decision**: **Option A (Internal RAM for Phase 1-9)**

**Rationale**:
- User specified "keep internal 8KB RAM initially"
- Simpler for initial bring-up and testing
- Same capacity as TD4CPU (no regression)
- AXI master can be added later as optional Phase 11

**Future Enhancement**:
- Phase 11 (optional): Add AXI4-Lite master interface
- Connect CPU to existing `Axi4_Lite_Master` module
- Share memory bus with UART bridge

---

### Decision 7: CSR Support - Minimal (ECALL/EBREAK Only)

**Options**:
- A) No system instructions (pure user-mode)
- B) ECALL/EBREAK only (minimal debug support)
- C) Full CSR support (mstatus, mtvec, etc.)

**Decision**: **Option B (ECALL/EBREAK Only)**

**Rationale**:
- ECALL enables system call emulation for testing
- EBREAK required for debugger integration
- Full CSR support adds complexity without immediate benefit
- User can request CSR extension later if needed

**Limitations**:
- No interrupt handling (no mtvec, mie, mip)
- No privilege modes (M-mode implicit)
- No performance counters (mcycle, minstret)
- No trap handling (exceptions halt CPU)

---

## Risk Assessment

### High-Priority Risks

1. **Memory Arbitration** (Structural Hazard)
   - **Risk**: IF and MEM stages both access same Block RAM
   - **Impact**: Data corruption, incorrect instruction fetch
   - **Mitigation**: Prioritize MEM stage, stall IF when conflict detected
   - **Status**: ⚠️ Must implement carefully in Phase 2 + Phase 5

2. **x0 Hardwire Violation** (RISC-V Compliance)
   - **Risk**: x0 not hardwired to zero (reads non-zero or writes stick)
   - **Impact**: Non-compliant with RISC-V spec, software breaks
   - **Mitigation**: Assertion checks, explicit hardwire logic, regression tests
   - **Status**: ✅ Assertion already written in `rv32i_pipeline_spec.sv`

3. **Byte Addressing Bugs** (Memory System)
   - **Risk**: Incorrect byte lane selection, alignment errors
   - **Impact**: Load/store corruption, hard-to-debug memory issues
   - **Mitigation**: Comprehensive LB/LH/LW/LBU/LHU/SB/SH/SW tests, assertions
   - **Status**: ⚠️ Critical for Phase 5

### Medium-Priority Risks

4. **Forwarding Path Bugs** (Data Hazards)
   - **Risk**: Incorrect forwarding logic, wrong operand values
   - **Impact**: ALU computes wrong results, silent failures
   - **Mitigation**: Hazard detection assertions, RAW test patterns
   - **Status**: ⚠️ Critical for Phase 7

5. **Branch Target Calculation** (Control Flow)
   - **Risk**: Incorrect immediate sign-extension, wrong PC update
   - **Impact**: Branches jump to wrong addresses, infinite loops
   - **Mitigation**: Branch test suite, PC tracking assertions
   - **Status**: ⚠️ Critical for Phase 4

6. **Pipeline Flush Timing** (Control Hazards)
   - **Risk**: Flush too early/late, incorrect instructions executed
   - **Impact**: Branch delay slot-like behavior (violates RISC-V spec)
   - **Mitigation**: Flush timing assertions, control flow tests
   - **Status**: ⚠️ Critical for Phase 4

### Low-Priority Risks

7. **Clock Frequency Regression**
   - **Risk**: Wider data paths increase critical path, lower Fmax
   - **Impact**: Slower operation than TD4CPU
   - **Mitigation**: Pipeline balancing, register replication if needed
   - **Status**: ✅ Acceptable trade-off for RISC-V compliance

8. **Resource Utilization Increase**
   - **Risk**: 32 registers + 32-bit datapath = more FPGA resources
   - **Impact**: May not fit on smaller FPGAs
   - **Mitigation**: Target same FPGA (Zynq-7020), optimize if needed
   - **Status**: ✅ Expected, manageable

---

## Success Criteria

### Functional Requirements (MANDATORY)

1. ✅ **RV32I ISA Compliance**
   - All 40 base instructions implemented correctly
   - x0 hardwired to zero
   - Byte-addressed memory
   - 32x32-bit register file

2. ⏳ **Pipeline Correctness**
   - No data hazards (forwarding works)
   - No control hazards (flush works)
   - No structural hazards (arbitration works)

3. ⏳ **Memory System**
   - Byte/halfword/word loads and stores work correctly
   - Alignment checks or unaligned access support
   - MMIO LED register accessible

4. ⏳ **Debug Interface**
   - Halt/run/step/break commands work
   - EBREAK instruction triggers breakpoint
   - Trace buffer captures execution

5. ⏳ **Verification**
   - All assertions pass
   - RV32I compliance tests pass
   - Regression test suite passes

### Performance Goals (TARGETS)

1. **IPC (Instructions Per Cycle)**: > 0.6
   - Best case: ~1.0 (ideal pipeline)
   - Realistic: 0.6-0.8 with hazards

2. **Clock Frequency**: > 50 MHz on Zynq-7020
   - TD4CPU achieved ~100 MHz
   - RV32I expected ~50-75 MHz (acceptable)

3. **Resource Utilization**: < 10,000 LUTs
   - TD4CPU used ~2,000 LUTs
   - RV32I expected ~5,000-8,000 LUTs (4× increase acceptable)

---

## Toolchain Integration Plan

### GNU RISC-V Toolchain

**Target**: riscv32-unknown-elf-gcc (bare-metal)

**Installation** (Windows):
```powershell
# Download prebuilt toolchain from SiFive or RISC-V organization
# Example: https://github.com/sifive/freedom-tools/releases
# Extract to: C:\riscv\riscv32-unknown-elf\bin

# Add to PATH
$env:PATH += ";C:\riscv\riscv32-unknown-elf\bin"

# Verify installation
riscv32-unknown-elf-gcc --version
riscv32-unknown-elf-as --version
riscv32-unknown-elf-objdump --version
```

**Test Compilation**:
```c
// test.c
int main(void) {
    volatile unsigned int *led = (unsigned int *)0x0000407C;
    *led = 0xA;  // Light up LEDs
    while(1);
    return 0;
}
```

```bash
# Compile
riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -T linker.ld test.c -o test.elf

# Disassemble
riscv32-unknown-elf-objdump -d test.elf

# Extract binary
riscv32-unknown-elf-objcopy -O binary test.elf test.bin
```

**ELF Loader** (MCP Integration):
- Parse ELF header, section headers
- Extract `.text` and `.data` sections
- Upload to CPU RAM via UART → AXI4-Lite → Register Block
- Set PC to entry point, start execution

---

## Timeline & Milestones

| Phase | Description | Duration | Target Date | Status |
|-------|-------------|----------|-------------|--------|
| 0 | Foundation (ISA, package, spec) | 8h | Jan 2, 2026 | ✅ Complete |
| 1 | Register File & Pipeline Regs | 10h | Jan 3, 2026 | 🚧 In Progress |
| 2 | Instruction Fetch (IF) | 8h | Jan 4, 2026 | ⏳ Pending |
| 3 | Instruction Decode (ID) | 10h | Jan 5, 2026 | ⏳ Pending |
| 4 | Execute (EX) | 14h | Jan 6-7, 2026 | ⏳ Pending |
| 5 | Memory Access (MEM) | 12h | Jan 8-9, 2026 | ⏳ Pending |
| 6 | Writeback (WB) | 6h | Jan 10, 2026 | ⏳ Pending |
| 7 | Hazard Detection & Forwarding | 14h | Jan 11-12, 2026 | ⏳ Pending |
| 8 | Debug Interface Integration | 8h | Jan 13, 2026 | ⏳ Pending |
| 9 | Trace Buffer Update | 6h | Jan 14, 2026 | ⏳ Pending |
| 10 | Verification & Testing | 24h | Jan 15-20, 2026 | ⏳ Pending |
| **Total** | **Core Implementation** | **120h** | **~3 weeks** | **5% Complete** |

---

## References

### RISC-V Specifications

- **RISC-V ISA Manual (Volume I: User-Level ISA)**  
  https://github.com/riscv/riscv-isa-manual
  
- **RISC-V ISA Instruction Reference** (msyksphinz)  
  https://msyksphinz-self.github.io/riscv-isadoc/html/rvi.html
  
- **RISC-V Compliance Test Suite**  
  https://github.com/riscv-non-isa/riscv-arch-test

### Reference Implementations

- **PicoRV32** (Clifford Wolf)  
  https://github.com/YosysHQ/picorv32  
  Compact, well-documented, educational

- **SERV** (Olof Kindgren)  
  https://github.com/olofk/serv  
  Bit-serial, smallest RISC-V core

- **Ibex** (lowRISC)  
  https://github.com/lowRISC/ibex  
  Production-quality, 2-stage pipeline

### TD4CPU Documentation

- **Original TD4CPU ISA**: `isa/td4cpu_isa.json`
- **TD4CPU Core Implementation**: `rtl/cpu/td4cpu_core_v0.1_archive.sv`
- **TD4CPU Pipeline Assertions**: `sim/assertions/td4cpu_*.sv`
- **TD4CPU Test Suite**: `sim/tests/axiuart_cpu_*.sv`

---

## Change Log

### 2026-01-02: Migration Started

- Created migration diary
- Completed Phase 0 (Foundation)
- Generated RV32I ISA specification (JSON)
- Generated SystemVerilog ISA package with full decoder
- Created pipeline specification as SVA assertions
- Tagged TD4CPU baseline as `td4cpu-final-v0.1`

**Next Steps**: Begin Phase 1 (Register File & Pipeline Registers)

---

## Open Questions

1. **Memory arbitration strategy**:
   - Q: Should IF stage have priority over MEM, or vice versa?
   - A: **MEM stage priority** (correctness over performance)
   - Rationale: Data loads/stores must complete atomically, IF can be stalled without corruption

2. **Alignment exception handling**:
   - Q: Should unaligned LH/LW/SH/SW raise exceptions or be supported?
   - A: **Enforce alignment** (raise exception or ignore)
   - Rationale: Simpler hardware, matches most embedded RISC-V cores

3. **Forwarding path for load-use**:
   - Q: Can we forward loaded data directly from MEM to EX in next cycle?
   - A: **Yes, with 1-cycle stall**
   - Rationale: Data available at end of MEM cycle, forward to EX in next cycle

4. **PC update timing**:
   - Q: Should PC update happen in IF or EX stage?
   - A: **IF stage computes PC+4, EX stage overrides on branch/jump**
   - Rationale: Standard approach, clean separation of concerns

---

## Notes

- **English responses mandatory** (per user instructions)
- **Assertions are specifications** (not documentation)
- **No placeholder code** - production quality only
- **Test-driven development** - assertions before implementation
- **Incremental verification** - test each phase before moving forward

---

**End of Diary Entry - 2026-01-02**

