# VexRiscv GenSmallOptimized - Architecture Overview

**Version:** 1.0  
**Date:** 2026-02-07  
**Configuration:** GenSmallOptimized  
**ISA:** RV32I Base Integer Instruction Set  
**Generator:** SpinalHDL v1.13.0

---

## Table of Contents

1. [Introduction](#introduction)
2. [Plugin-Based Design Philosophy](#plugin-based-design-philosophy)
3. [GenSmallOptimized Configuration](#gensmalloptimized-configuration)
4. [Memory Architecture](#memory-architecture)
5. [Top-Level Interfaces](#top-level-interfaces)
6. [Key Design Decisions](#key-design-decisions)

---

## Introduction

### What is VexRiscv?

VexRiscv is a **highly configurable RISC-V CPU core generator** written in [SpinalHDL](https://spinalhdl.github.io/SpinalDoc-RTD/), a Scala-based hardware description language. Unlike traditional fixed-architecture CPUs, VexRiscv uses a **plugin architecture** where different functional units (fetch, decode, execute, memory, hazard detection, etc.) are composed at generation time.

### Why VexRiscv?

**Advantages:**
- **Configurability:** Select exactly the features you need (no unused hardware)
- **ISA Compliance:** Proven RISC-V compliance (passes official compliance tests)
- **Well-Tested:** Used in production systems (Murax SoC, Linux-capable variants)
- **FPGA-Optimized:** Efficient synthesis for Xilinx/Altera FPGAs
- **Active Community:** Maintained by Charles Papon, extensive examples

**Trade-offs:**
- **Generated Code:** Verilog output is machine-generated (less human-readable)
- **Scala Learning Curve:** Modifications require SpinalHDL knowledge
- **Build Complexity:** Requires JDK, sbt (Scala Build Tool)

### This Project's Choice: GenSmallOptimized

We use a **custom GenSmallOptimized configuration** optimized for:
- **Minimal area** (~1500 LUTs on Zynq-7020)
- **125MHz target frequency**
- **Critical hazard fixes** (`bypassWriteBackBuffer=true`)
- **Debug support** (2 hardware breakpoints, shared reset domain)

---

## Plugin-Based Design Philosophy

### SpinalHDL Plugin Architecture

VexRiscv is built from composable **plugins**, each implementing a CPU subsystem:

```scala
val config = VexRiscvConfig(
  plugins = List(
    new IBusSimplePlugin(...),      // Instruction fetch
    new DecoderSimplePlugin(...),   // Instruction decode
    new RegFilePlugin(...),         // Register file
    new IntAluPlugin,               // Integer ALU
    new SrcPlugin(...),             // Operand sourcing
    new LightShifterPlugin,         // Barrel shifter
    new HazardSimplePlugin(...),    // Hazard detection & forwarding
    new BranchPlugin(...),          // Branch resolution
    new DBusSimplePlugin(...),      // Data memory interface
    new CsrPlugin(...),             // Control & Status Registers
    new DebugPlugin(...),           // Debug interface
    new YamlPlugin(...)             // Documentation generator
  )
)
```

### Plugin Interaction Model

Plugins communicate through:
1. **Pipeline Stages:** Data flows through DECODE → EXECUTE → MEMORY → WRITEBACK
2. **Stage Insertions:** Plugins insert control signals into stages (e.g., `execute.insert(ALU_CTRL)`)
3. **Arbitration Framework:** Each stage has `isValid`, `isStuck`, `isFiring` signals
4. **Signal Ports:** Explicit interfaces (IBus, DBus, Debug, Interrupts)

**Key Insight:** Plugins are **composable but not optional** once selected. The configuration determines which plugins are instantiated, but they cannot be runtime-disabled.

---

## GenSmallOptimized Configuration

### Configuration File Location

- **Project-specific config:** `vexriscv_reference/config/GenSmallOptimized.scala`
- **Copied to VexRiscv source:** `vexriscv_reference/source/src/main/scala/vexriscv/demo/GenSmallOptimized.scala` (during build)
- **Generated RTL:** `vexriscv_reference/generated/VexRiscv.v`
- **Deployed RTL:** `rtl/cpu/VexRiscv.v`

### Plugin Configuration Details

#### 1. IBusSimplePlugin (Instruction Fetch)

```scala
new IBusSimplePlugin(
  resetVector = 0x80000000l,           // Reset PC address
  cmdForkOnSecondStage = false,        // No 2-stage fetch
  cmdForkPersistence = false,          // No fetch buffer
  prediction = NONE,                   // No branch prediction
  catchAccessFault = false,            // No fetch exceptions
  compressedGen = false                // No RV32C support
)
```

**Purpose:** Fetch instructions from memory via a simple handshake protocol (cmd/rsp).

**Trade-offs:**
- ✅ Minimal area (no branch predictor, no fetch buffer)
- ✅ Simple protocol (easy memory controller integration)
- ❌ No instruction prefetch (1 fetch per cycle max)
- ❌ No branch prediction (all branches mispredict)

**Reset Vector:** `0x80000000` is the RISC-V standard reset address. Our BRAM is mapped here in the memory controller.

#### 2. DecoderSimplePlugin (Instruction Decode)

```scala
new DecoderSimplePlugin(
  catchIllegalInstruction = false      // No illegal instruction trap
)
```

**Purpose:** Decode 32-bit instructions into control signals (ALU_CTRL, RS1_USE, etc.).

**Trade-off:** No illegal instruction detection saves ~100 LUTs but removes error handling.

#### 3. RegFilePlugin (Register File)

```scala
new RegFilePlugin(
  regFileReadyKind = plugin.SYNC,      // Synchronous reads
  zeroBoot = false                     // x0 hardwired to 0 (no init)
)
```

**Purpose:** 32×32-bit general-purpose register file (x0-x31).

**Key Detail:** `SYNC` reads mean register read data is available 1 cycle after address. VexRiscv handles this via hazard detection.

#### 4. IntAluPlugin (Integer ALU)

```scala
new IntAluPlugin
```

**Purpose:** ADD, SUB, SLT, SLTU operations. No configuration options (always included).

#### 5. SrcPlugin (Source Operand Selection)

```scala
new SrcPlugin(
  separatedAddSub = false,             // Combined ADD/SUB unit
  executeInsertion = true              // Insert SRC_ADD into EXECUTE stage
)
```

**Purpose:** Mux RS1/RS2/immediate values into ALU inputs.

**Trade-off:** `separatedAddSub=false` reuses ALU for address calculation (saves area, may limit frequency).

#### 6. LightShifterPlugin (Barrel Shifter)

```scala
new LightShifterPlugin
```

**Purpose:** SLL, SRL, SRA shift operations. "Light" version uses iterative shifting (multi-cycle) to save area.

**Performance:** Shifts take 1-32 cycles depending on shift amount (not single-cycle like full barrel shifter).

#### 7. HazardSimplePlugin (🔥 CRITICAL)

```scala
new HazardSimplePlugin(
  bypassExecute = true,                // EX→EX forwarding
  bypassMemory = true,                 // MEM→EX forwarding
  bypassWriteBack = true,              // WB→EX forwarding
  bypassWriteBackBuffer = true         // ⚠️ KEY FIX
)
```

**Purpose:** Detect data hazards (RAW) and forward results to avoid stalls.

**Critical Fix:** `bypassWriteBackBuffer=true` solves a timing race:
- **Problem:** WB stage writes register **same cycle** decode stage reads
- **Without fix:** Decode gets stale data → test failures
- **With fix:** 1-cycle buffer holds WB data for next decode cycle

**Forwarding Priority:** EX > MEM > WB Buffer > WB > Register File (last assignment wins in Verilog mux cascade)

**Stall Conditions:**
- Load-use hazard (LOAD followed by use of loaded register)
- Non-bypassable instructions (currently none in GenSmallOptimized)

#### 8. BranchPlugin (Branch Resolution)

```scala
new BranchPlugin(
  earlyBranch = false,                 // Resolve branches in EXECUTE stage
  catchAddressMisaligned = false       // No misalignment exceptions
)
```

**Purpose:** Handle JAL, JALR, BEQ, BNE, BLT, BGE, BLTU, BGEU.

**Performance:** All branches flush 1-2 instructions (no prediction).

#### 9. DBusSimplePlugin (Data Memory Interface)

```scala
new DBusSimplePlugin(
  catchAddressMisaligned = false,      // No alignment checks
  catchAccessFault = false             // No access exceptions
)
```

**Purpose:** Load/store interface (LW, LH, LB, SW, SH, SB) via handshake protocol.

**Protocol:** Valid/ready handshake, 1-cycle response latency.

#### 10. CsrPlugin (Control & Status Registers)

```scala
new CsrPlugin(
  CsrPluginConfig(
    catchIllegalAccess = false,
    mvendorid = null,                  // No vendor ID
    marchid = null, mimpid = null, mhartid = null,
    misaExtensionsInit = 0,
    misaAccess = CsrAccess.NONE,       // MISA read-only (not writable)
    mtvecAccess = CsrAccess.NONE,      // MTVEC constant (0x80000000)
    mtvecInit = 0x80000000l,           // Trap vector base
    mepcAccess = CsrAccess.READ_WRITE, // Exception PC
    mscratchGen = false,               // No MSCRATCH
    mcauseAccess = CsrAccess.READ_ONLY,// Exception cause
    mbadaddrAccess = CsrAccess.NONE,   // No MTVAL
    mcycleAccess = CsrAccess.READ_ONLY,// Cycle counter
    minstretAccess = CsrAccess.READ_ONLY,// Instruction counter
    ecallGen = true,                   // ECALL support
    ebreakGen = true,                  // EBREAK support
    wfiGenAsWait = false,
    wfiGenAsNop = true,                // WFI = NOP
    ucycleAccess = CsrAccess.READ_ONLY // User mode cycle counter
  )
)
```

**Purpose:** Machine-mode CSRs for exception handling and performance counters.

**Key CSRs:**
- **MTVEC:** Trap vector base (fixed at 0x80000000)
- **MEPC:** Stores PC of faulting instruction
- **MCAUSE:** Exception code (EBREAK=3, ECALL=11)
- **MCYCLE/MINSTRET:** Performance counters

#### 11. DebugPlugin (Hardware Debug)

```scala
new DebugPlugin(
  debugClockDomain = ClockDomain.current, // Shared reset domain
  hardwareBreakpointCount = 2             // 2 breakpoints
)
```

**Purpose:** External debug interface (JTAG-style register access).

**Interfaces:**
- `debug_bus_cmd`: Command interface (read/write CPU registers, memory)
- `debug_bus_rsp`: Response data
- `debug_resetOut`: Debug-initiated reset

**Usage:** Test infrastructure uses this for backdoor memory loading and PC inspection.

#### 12. YamlPlugin (Documentation Generator)

```scala
new YamlPlugin(s"$outputDir/cpu.yaml")
```

**Purpose:** Generate machine-readable CPU configuration (ISA, features, memory map).

**Note:** Sometimes generates empty `{}` (SpinalHDL quirk), but RTL is valid.

---

## Memory Architecture

### Address Map

| Address Range | Size | Type | Purpose | Access |
|--------------|------|------|---------|--------|
| **0x8000_0000 - 0x8000_1FFF** | 8KB | Block RAM | Instruction + Data | RWX |
| 0x8000_2000 - 0x8FFF_FFFF | - | Reserved | Future expansion | - |
| 0x0000_4000 - 0x0000_4FFF | 4KB | MMIO | UART, LED registers | RW |

### Reset Behavior

**Reset Vector:** PC initializes to `0x80000000` (configured in IBusSimplePlugin).

**Post-Reset Sequence:**
1. Fetch instruction from 0x80000000 (BRAM word 0)
2. Register file undefined (except x0=0)
3. CSRs initialized to reset values (MTVEC=0x80000000, MEPC=0, etc.)

### Memory Access Patterns

**Instruction Fetch (IBus):**
- Always word-aligned (PC[1:0] ignored)
- Single outstanding request
- 1-cycle latency (BRAM read)

**Data Access (DBus):**
- Supports byte/halfword/word (LB, LH, LW, SB, SH, SW)
- Misaligned accesses **NOT detected** (wraps within word)
- 1-cycle latency (BRAM read/write)

---

## Top-Level Interfaces

### Module Ports (VexRiscv.v)

```verilog
module VexRiscv (
  // Instruction Bus (IBus) - Fetch Interface
  output wire          iBus_cmd_valid,
  input  wire          iBus_cmd_ready,
  output wire [31:0]   iBus_cmd_payload_pc,
  input  wire          iBus_rsp_valid,
  input  wire          iBus_rsp_payload_error,
  input  wire [31:0]   iBus_rsp_payload_inst,
  
  // Data Bus (DBus) - Load/Store Interface
  output wire          dBus_cmd_valid,
  input  wire          dBus_cmd_ready,
  output wire          dBus_cmd_payload_wr,        // 0=read, 1=write
  output wire [3:0]    dBus_cmd_payload_mask,      // Byte enable
  output wire [31:0]   dBus_cmd_payload_address,
  output wire [31:0]   dBus_cmd_payload_data,      // Write data
  output wire [1:0]    dBus_cmd_payload_size,      // 0=byte, 1=half, 2=word
  input  wire          dBus_rsp_ready,
  input  wire          dBus_rsp_error,
  input  wire [31:0]   dBus_rsp_data,              // Read data
  
  // Interrupts (Machine Mode)
  input  wire          timerInterrupt,
  input  wire          externalInterrupt,
  input  wire          softwareInterrupt,
  
  // Debug Interface
  input  wire          debug_bus_cmd_valid,
  output reg           debug_bus_cmd_ready,
  input  wire          debug_bus_cmd_payload_wr,
  input  wire [7:0]    debug_bus_cmd_payload_address,
  input  wire [31:0]   debug_bus_cmd_payload_data,
  output reg  [31:0]   debug_bus_rsp_data,
  output wire          debug_resetOut,
  
  // Clock & Reset
  input  wire          clk,
  input  wire          reset                       // Active high, synchronous
);
```

### Interface Protocols

#### IBus Protocol (Instruction Fetch)

**Command Phase:**
```
Cycle N:   iBus_cmd_valid=1, iBus_cmd_payload_pc=0x80000000
           Wait for iBus_cmd_ready=1
Cycle N+1: (If ready) Command accepted, move to next fetch
```

**Response Phase:**
```
Cycle N+1: iBus_rsp_valid=1, iBus_rsp_payload_inst=0x12345678
           CPU accepts instruction (no backpressure)
```

**Error Handling:** `iBus_rsp_payload_error` causes fetch exception (if enabled).

#### DBus Protocol (Load/Store)

**Write Transaction:**
```
Cycle N:   dBus_cmd_valid=1
           dBus_cmd_payload_wr=1
           dBus_cmd_payload_address=0x80001000
           dBus_cmd_payload_data=0xDEADBEEF
           dBus_cmd_payload_mask=4'b1111 (word write)
           Wait for dBus_cmd_ready=1
Cycle N+1: dBus_rsp_ready=1 (acknowledge)
```

**Read Transaction:**
```
Cycle N:   dBus_cmd_valid=1
           dBus_cmd_payload_wr=0
           dBus_cmd_payload_address=0x80001000
Cycle N+1: dBus_rsp_ready=1
           dBus_rsp_data=0x12345678
```

**Stall Behavior:** If `dBus_cmd_ready=0`, CPU's MEMORY stage stalls (automatic backpressure).

---

## Key Design Decisions

### 1. Why 4 Stages Instead of 5?

**VexRiscv Stages:** DECODE → EXECUTE → MEMORY → WRITEBACK (no separate FETCH stage)

**Rationale:**
- **Fetch is not a stage:** IBusSimplePlugin is a *stream producer* that injects into decode
- **Simplicity:** Fewer arbitration signals, simpler control logic
- **Area:** One less pipeline register set (~150 FFs saved)

**Trade-off:** Fetch stalls affect decode directly (no buffering).

### 2. Why `bypassWriteBackBuffer=true` is Critical

**Problem Without Buffer:**
```
Cycle N:   WB stage writes x1=5 to register file
           Decode stage reads x1 → gets OLD value (race)
Cycle N+1: x1 now has correct value, but too late
```

**Solution With Buffer:**
```
Cycle N:   WB stage writes x1=5 to register file AND buffer
Cycle N+1: Decode reads x1 from register file OR buffer
           Buffer has priority → gets CORRECT value
```

**Implementation:** 1-cycle delay register holds `{valid, address, data}` from WB stage.

### 3. Why No Branch Prediction?

**Area vs. Performance Trade-off:**
- **Full branch predictor:** ~500 LUTs (2-bit counters, BTB)
- **Benefit:** 50-80% branch prediction accuracy (1 less stall per correct prediction)
- **GenSmallOptimized choice:** Every branch/jump flushes 1-2 instructions (**fixed penalty**)

**Rationale:** For small embedded workloads (UART communication, LED control), branch frequency is low enough that area savings outweigh performance loss.

### 4. Why Shared Reset Domain for Debug?

**Alternative:** Separate `debugClockDomain` with independent reset

**Problem:** Cross-domain synchronization complexity, metastability risks

**GenSmallOptimized Choice:** `debugClockDomain = ClockDomain.current`
- ✅ Debug reset tied to CPU reset (simpler synchronization)
- ✅ No clock domain crossing (no FIFO/synchronizers)
- ❌ Cannot debug through CPU reset (must re-halt after reset)

**Usage:** Acceptable for testbench debugging (not production JTAG).

---

## Related Documentation

- **[Pipeline Operation](vexriscv_pipeline_operation.md)** - Detailed 4-stage pipeline flow
- **[Signal Reference](vexriscv_signal_reference.md)** - Internal signal descriptions
- **[Build Guide](vexriscv_build_guide.md)** - SpinalHDL → Verilog generation process
- **[Test Plan](vexriscv_test_plan.md)** - Verification strategy and test cases

---

## References

1. **VexRiscv GitHub:** https://github.com/SpinalHDL/VexRiscv
2. **SpinalHDL Documentation:** https://spinalhdl.github.io/SpinalDoc-RTD/
3. **RISC-V ISA Spec:** https://riscv.org/technical/specifications/
4. **Project Config:** `vexriscv_reference/config/GenSmallOptimized.scala`
5. **Generated RTL:** `rtl/cpu/VexRiscv.v`

---

**Document Version:** 1.0  
**Last Updated:** 2026-02-07  
**Author:** Generated from project analysis
