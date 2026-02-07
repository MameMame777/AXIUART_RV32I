# VexRiscv GenSmallOptimized - Pipeline Operation

**Version:** 1.0  
**Date:** 2026-02-07  
**Configuration:** GenSmallOptimized  
**Pipeline Stages:** 4 (DECODE → EXECUTE → MEMORY → WRITEBACK)

---

## Table of Contents

1. [Pipeline Overview](#pipeline-overview)
2. [Arbitration Framework](#arbitration-framework)
3. [Stage-by-Stage Operation](#stage-by-stage-operation)
4. [Hazard Detection & Forwarding](#hazard-detection--forwarding)
5. [Control Flow Changes](#control-flow-changes)
6. [Example Execution Traces](#example-execution-traces)

---

## Pipeline Overview

### Four-Stage Architecture

VexRiscv GenSmallOptimized uses a **4-stage pipeline** with IBus injection feeding the decode stage:

```
┌───────────────┐
│ IBus Injection│  ← Not a pipeline stage, just instruction stream
│  (Fetch FSM)  │
└───────┬───────┘
        │ iBus_rsp_valid + instruction
        ▼
┌───────────────┐
│ DECODE Stage  │  - Instruction decode
│               │  - Register file read
│               │  - Hazard detection
└───────┬───────┘
        │ decode_to_execute pipeline register
        ▼
┌───────────────┐
│ EXECUTE Stage │  - ALU operations
│               │  - Branch resolution
│               │  - Address calculation
└───────┬───────┘
        │ execute_to_memory pipeline register
        ▼
┌───────────────┐
│ MEMORY Stage  │  - Data memory access (DBus)
│               │  - Load data arrival
└───────┬───────┘
        │ memory_to_writeBack pipeline register
        ▼
┌───────────────┐
│ WRITEBACK St. │  - Register file write
│               │  - Instruction commit
└───────────────┘
```

### Pipeline Registers

**Three pipeline register slices:**

```systemverilog
// Decode → Execute
reg [31:0] decode_to_execute_PC;
reg [31:0] decode_to_execute_INSTRUCTION;
reg [31:0] decode_to_execute_RS1;
reg [31:0] decode_to_execute_RS2;
reg [1:0]  decode_to_execute_ALU_CTRL;
reg [1:0]  decode_to_execute_SHIFT_CTRL;
// ... ~20 control signals

// Execute → Memory
reg [31:0] execute_to_memory_PC;
reg [31:0] execute_to_memory_REGFILE_WRITE_DATA;
reg [31:0] execute_to_memory_MEMORY_ADDRESS;
// ... ~15 signals

// Memory → WriteBack
reg [31:0] memory_to_writeBack_PC;
reg [31:0] memory_to_writeBack_REGFILE_WRITE_DATA;
reg [31:0] memory_to_writeBack_MEMORY_READ_DATA;
// ... ~10 signals
```

**Update Logic:**
```systemverilog
always @(posedge clk) begin
  if (decode_arbitration_isFiring) begin
    // Only advance if stage is not stalled and not flushed
    decode_to_execute_PC <= decode_PC;
    // ...
  end
end
```

---

## Arbitration Framework

### Arbitration Signals (Per Stage)

Each of the 4 stages has an **arbitration bundle**:

```systemverilog
// Example: DECODE stage arbitration
wire decode_arbitration_isValid;           // Valid instruction in this stage
wire decode_arbitration_haltItself;        // Stage wants to stall
wire decode_arbitration_haltByOther;       // Stalled by hazard/downstream
wire decode_arbitration_isStuck;           // haltItself || haltByOther
wire decode_arbitration_isStuckByOthers;   // Any later stage stalled
wire decode_arbitration_isMoving;          // !isStuck && !removeIt
wire decode_arbitration_isFiring;          // isValid && isMoving
wire decode_arbitration_removeIt;          // Flush this instruction
wire decode_arbitration_flushIt;           // Flush from upstream
wire decode_arbitration_flushNext;         // Flush downstream stages
```

### Arbitration Signal Definitions

| Signal | Meaning | Set By | Effect |
|--------|---------|--------|--------|
| `isValid` | Instruction present in stage | Pipeline control | Stage has work to do |
| `haltItself` | Stage cannot proceed | Stage logic (e.g., DBus !ready) | Blocks pipeline advancement |
| `haltByOther` | Stage blocked by hazard | Hazard unit | Blocks pipeline advancement |
| `isStuck` | Stage not advancing | Computed | Pipeline register holds value |
| `isStuckByOthers` | Downstream stage stuck | Computed | Propagates backpressure |
| `isMoving` | Stage advancing this cycle | Computed | Pipeline register updates |
| `isFiring` | Executing + advancing | Computed | Commits side effects |
| `removeIt` | Kill this instruction | Flush logic | Bubble in pipeline |
| `flushIt` | External flush request | Branch/exception | Clear stage |
| `flushNext` | Flush downstream | Branch/exception | Clear later stages |

### Stall Propagation (Backward)

When a stage stalls, all **earlier stages** must stall:

```systemverilog
// Compute "stuck by others" (later stages blocking me)
assign decode_arbitration_isStuckByOthers = (
  execute_arbitration_isStuck || 
  memory_arbitration_isStuck || 
  writeBack_arbitration_isStuck
);

assign execute_arbitration_isStuckByOthers = (
  memory_arbitration_isStuck || 
  writeBack_arbitration_isStuck
);

assign memory_arbitration_isStuckByOthers = (
  writeBack_arbitration_isStuck
);

assign writeBack_arbitration_isStuckByOthers = 1'b0;  // Last stage

// Compute final "stuck" status
assign decode_arbitration_isStuck = (
  decode_arbitration_haltItself || 
  decode_arbitration_haltByOther || 
  decode_arbitration_isStuckByOthers
);
```

**Example:** If MEMORY stage stalls (waiting for DBus), then DECODE and EXECUTE also stall (even if they want to advance).

### Flush Propagation (Forward)

When a branch is taken, **later stages** are flushed:

```systemverilog
// Branch resolves in EXECUTE stage
assign BranchPlugin_jumpInterface_valid = (
  execute_arbitration_isFiring && 
  execute_BRANCH_DO  // Branch taken
);

// Flush next stage
assign decode_arbitration_flushNext = (
  BranchPlugin_jumpInterface_valid ||
  // ... other flush sources
);

// Propagate flush to execute stage
assign execute_arbitration_flushIt = decode_arbitration_flushNext;

// Clear stage on flush
always @(posedge clk) begin
  if (execute_arbitration_flushIt) begin
    execute_arbitration_isValid <= 1'b0;
  end else if (!execute_arbitration_isStuck) begin
    execute_arbitration_isValid <= decode_arbitration_isValid;
  end
end
```

**Example:** Branch taken in EXECUTE → Flush EXECUTE (branch shadow instruction) → Flush MEMORY/WB if present.

---

## Stage-by-Stage Operation

### Stage 0: IBus Injection (Pseudo-Stage)

**Purpose:** Fetch instructions from memory and inject into decode stage.

**Key Signals:**
```systemverilog
wire [31:0] IBusSimplePlugin_fetchPc_pc;              // Current fetch PC
wire        IBusSimplePlugin_fetchPc_output_valid;    // Fetch request
wire        IBusSimplePlugin_fetchPc_output_ready;    // Decode can accept
wire        iBus_cmd_valid;                           // Memory command
wire        iBus_rsp_valid;                           // Memory response
wire [31:0] iBus_rsp_payload_inst;                    // Fetched instruction
```

**Operation:**
1. **PC Update:** On each cycle (unless stalled), increment PC or take jump target
2. **Fetch Request:** Assert `iBus_cmd_valid`, send PC to memory
3. **Receive Response:** When `iBus_rsp_valid`, instruction is ready
4. **Inject to Decode:** If decode accepts (`output_ready`), move instruction to decode stage

**PC Update Priority:**
```systemverilog
always @(*) begin
  if (BranchPlugin_jumpInterface_valid)
    pc_next = BranchPlugin_jumpInterface_payload;  // Branch/jump
  else if (CsrPlugin_jumpInterface_valid)
    pc_next = CsrPlugin_jumpInterface_payload;     // Exception/MRET
  else if (!IBusSimplePlugin_fetchPc_output_ready)
    pc_next = pc_reg;                              // Stall
  else
    pc_next = pc_reg + 4;                          // Sequential
end
```

**Stall Conditions:**
- Decode stage busy (`!output_ready`)
- Branch taken (1-cycle bubble while fetching new PC)

---

### Stage 1: DECODE

**Purpose:** Decode instruction, read register file, detect hazards.

**Key Operations:**

1. **Instruction Decoder:**
   ```systemverilog
   wire [6:0] opcode = decode_INSTRUCTION[6:0];
   wire [2:0] funct3 = decode_INSTRUCTION[14:12];
   wire [6:0] funct7 = decode_INSTRUCTION[31:25];
   
   // Generate control signals
   assign decode_IS_ALU = (opcode == 7'b0110011);  // R-type
   assign decode_IS_LOAD = (opcode == 7'b0000011); // I-type load
   // ... 40 instruction types
   ```

2. **Register File Read:**
   ```systemverilog
   wire [4:0] rs1_addr = decode_INSTRUCTION[19:15];
   wire [4:0] rs2_addr = decode_INSTRUCTION[24:20];
   
   wire [31:0] rf_rs1_data = RegFilePlugin_regFile[rs1_addr];
   wire [31:0] rf_rs2_data = RegFilePlugin_regFile[rs2_addr];
   
   // Forwarding mux (see Hazard Detection section)
   wire [31:0] decode_RS1 = /* forwarded or RF data */;
   wire [31:0] decode_RS2 = /* forwarded or RF data */;
   ```

3. **Hazard Detection:**
   ```systemverilog
   // Check if EX/MEM/WB stages have conflicting writes
   wire hazard_detected = (
     (execute_REGFILE_WRITE_VALID && (execute_rd == rs1_addr)) ||
     (memory_REGFILE_WRITE_VALID && (memory_rd == rs1_addr))
     // ... similar for rs2
   );
   
   assign decode_arbitration_haltByOther = hazard_detected && !can_forward;
   ```

**Output to EXECUTE:**
- Decoded control signals (ALU_CTRL, SHIFT_CTRL, etc.)
- Source operands (RS1, RS2 or forwarded values)
- Immediate values (sign-extended)

---

### Stage 2: EXECUTE

**Purpose:** Perform computation (ALU, shifter, branch resolution).

**Key Operations:**

1. **ALU Operations:**
   ```systemverilog
   wire [31:0] execute_SRC1 = /* from SrcPlugin based on SRC1_CTRL */;
   wire [31:0] execute_SRC2 = /* from SrcPlugin based on SRC2_CTRL */;
   
   wire [31:0] execute_ALU_RESULT = (execute_ALU_CTRL == ADD_SUB) ? (SRC1 + SRC2) :
                                     (execute_ALU_CTRL == SLT_SLTU) ? {{31{1'b0}}, SRC1 < SRC2} :
                                     (execute_ALU_CTRL == BITWISE) ? execute_ALU_BITWISE_RESULT :
                                     32'h0;
   ```

2. **Branch Resolution:**
   ```systemverilog
   wire execute_BRANCH_COND_RESULT = (execute_BRANCH_CTRL == BranchCtrlEnum_B) ? (
     (funct3 == 3'b000) ? (RS1 == RS2) :  // BEQ
     (funct3 == 3'b001) ? (RS1 != RS2) :  // BNE
     // ... 6 branch types
   ) : 1'b0;
   
   assign execute_BRANCH_DO = execute_BRANCH_COND_RESULT;
   assign execute_BRANCH_CALC = execute_PC + execute_IMM;  // Branch target
   ```

3. **Memory Address Calculation:**
   ```systemverilog
   wire [31:0] execute_MEMORY_ADDRESS = execute_RS1 + execute_IMM;  // Load/store address
   ```

**Output to MEMORY:**
- ALU result (or branch target if taken)
- Memory address (for loads/stores)
- Store data (RS2 for SW/SH/SB)

**Side Effects:**
- Branch taken → Flush decode stage (bubble)
- Exception detected → Trigger CSR exception logic

---

### Stage 3: MEMORY

**Purpose:** Access data memory (loads/stores).

**Key Operations:**

1. **Memory Request:**
   ```systemverilog
   assign dBus_cmd_valid = (
     memory_arbitration_isValid && 
     memory_MEMORY_ENABLE  // Instruction is LW/LH/LB/SW/SH/SB
   );
   
   assign dBus_cmd_payload_wr = memory_MEMORY_STORE;
   assign dBus_cmd_payload_address = memory_MEMORY_ADDRESS;
   assign dBus_cmd_payload_data = memory_RS2;  // Store data
   ```

2. **Stall on Busy:**
   ```systemverilog
   assign memory_arbitration_haltItself = (
     memory_MEMORY_ENABLE && !dBus_cmd_ready
   );
   ```

3. **Load Data Capture:**
   ```systemverilog
   wire [31:0] memory_MEMORY_READ_DATA = dBus_rsp_data;
   
   // Sign/zero extend based on LB/LH/LW
   wire [31:0] memory_LOAD_RESULT = (load_type == BYTE) ? {{24{data[7]}}, data[7:0]} :
                                     (load_type == HALF) ? {{16{data[15]}}, data[15:0]} :
                                     data;
   ```

**Output to WRITEBACK:**
- ALU result (for ALU instructions)
- Load data (for LW/LH/LB)
- Destination register address

**Stall Scenarios:**
- Memory not ready (`dBus_cmd_ready=0`)
- Multi-cycle shifts still executing (LightShifterPlugin)

---

### Stage 4: WRITEBACK

**Purpose:** Commit instruction results to register file.

**Key Operations:**

1. **Register File Write:**
   ```systemverilog
   assign writeBack_REGFILE_WRITE_VALID = (
     writeBack_arbitration_isFiring && 
     writeBack_INSTRUCTION[11:7] != 5'b0  // rd != x0
   );
   
   wire [4:0] writeBack_rd = writeBack_INSTRUCTION[11:7];
   wire [31:0] writeBack_REGFILE_WRITE_DATA = (
     writeBack_MEMORY_ENABLE ? writeBack_MEMORY_READ_DATA : writeBack_ALU_RESULT
   );
   
   always @(posedge clk) begin
     if (writeBack_REGFILE_WRITE_VALID) begin
       RegFilePlugin_regFile[writeBack_rd] <= writeBack_REGFILE_WRITE_DATA;
     end
   end
   ```

2. **WriteBack Buffer Update (CRITICAL):**
   ```systemverilog
   // HazardSimplePlugin writeBackBuffer
   always @(posedge clk) begin
     HazardSimplePlugin_writeBackBuffer_valid <= writeBack_REGFILE_WRITE_VALID;
     HazardSimplePlugin_writeBackBuffer_payload_address <= writeBack_rd;
     HazardSimplePlugin_writeBackBuffer_payload_data <= writeBack_REGFILE_WRITE_DATA;
   end
   ```

**No Stalls:** WriteBack stage never stalls (always accepts from MEMORY).

**Instruction Commit:** Only `isFiring` instructions commit (not flushed/invalid).

---

## Hazard Detection & Forwarding

### RAW Hazard Types

VexRiscv detects **Read-After-Write (RAW)** hazards:

```
Instruction 1:  ADD  x1, x2, x3  [writes x1 in WB]
Instruction 2:  SUB  x4, x1, x5  [reads x1 in DECODE, needs forwarding]
```

### Forwarding Paths

**Three forwarding sources** (priority: EX > MEM > WBBuffer):

```systemverilog
always @(*) begin
  // Default: Register file read
  decode_RS1 = RegFilePlugin_regFile[rs1_addr];
  
  // Forward from WB buffer (lowest priority, oldest data)
  if (writeBackBuffer_valid && (writeBackBuffer_addr == rs1_addr)) begin
    decode_RS1 = writeBackBuffer_data;
  end
  
  // Forward from EXECUTE stage (bypasses WB buffer)
  if (execute_REGFILE_WRITE_VALID && execute_BYPASSABLE_EXECUTE_STAGE && 
      (execute_rd == rs1_addr)) begin
    decode_RS1 = execute_REGFILE_WRITE_DATA;
  end
  
  // Forward from MEMORY stage (highest priority, newest data)
  if (memory_REGFILE_WRITE_VALID && memory_BYPASSABLE_MEMORY_STAGE && 
      (memory_rd == rs1_addr)) begin
    decode_RS1 = memory_REGFILE_WRITE_DATA;
  end
end
```

**Bypass Priority Justification:**
- **MEMORY > EXECUTE:** Later stage has newer data (if both match, use memory)
- **EXECUTE > WBBuffer:** Realtime EX result newer than buffered WB
- **WBBuffer > RF:** Buffered WB data from previous cycle newer than RF

### Load-Use Stall

**Unavoidable 1-cycle stall** when load result is immediately used:

```assembly
LW   x1, 0(x2)      # Cycle 1: EXECUTE (address calc)
                     # Cycle 2: MEMORY (data arrives end of cycle)
ADDI x3, x1, 1      # Cycle 2: DECODE (needs x1, but data not ready)
                     # → STALL x1
                     # Cycle 3: DECODE (now x1 forwarded from MEM stage)
```

**Detection Logic:**
```systemverilog
wire load_use_hazard = (
  execute_MEMORY_ENABLE &&       // Execute stage has load
  !execute_MEMORY_STORE &&       // It's a read (not write)
  decode_RS1_USE && (execute_rd == decode_rs1_addr)
);

assign decode_arbitration_haltByOther = load_use_hazard || /* other hazards */;
```

**Why Can't Forward?** Load data arrives at **end** of MEMORY stage (BRAM latency). DECODE needs data at **beginning** of cycle for EXECUTE to use.

---

## Control Flow Changes

### Branch Instructions

**Branch Resolution Timeline:**
```
Cycle 1: BEQ in DECODE
Cycle 2: BEQ in EXECUTE → Compare RS1==RS2 → Branch taken/not-taken
         If taken: Flush DECODE (shadow instruction), update PC
Cycle 3: Fetch from branch target
```

**Penalty:** 1-2 cycles (1 bubble if taken, 0 if not taken).

### Jump Instructions

**JAL (Unconditional Jump):**
```
Cycle 1: JAL in DECODE → Target known immediately
Cycle 2: JAL in EXECUTE → Flush DECODE, update PC, write return address to rd
Cycle 3: Fetch from jump target
```

**JALR (Indirect Jump):**
```
Cycle 1: JALR in DECODE → Read RS1
Cycle 2: JALR in EXECUTE → Compute RS1+imm → Flush DECODE, update PC
Cycle 3: Fetch from computed target
```

### Exceptions (EBREAK, ECALL)

**Exception Handling:**
```
Cycle 1: ECALL in DECODE
Cycle 2: ECALL in EXECUTE → Trigger CsrPlugin exception
         - MEPC ← current PC
         - MCAUSE ← 11 (ECALL code)
         - PC ← MTVEC (0x80000000)
         - Flush all stages
Cycle 3: Fetch from MTVEC (trap handler)
```

**MRET (Return from Exception):**
```
Cycle 1: MRET in DECODE
Cycle 2: MRET in EXECUTE → Read MEPC
         - PC ← MEPC
         - Flush all stages
Cycle 3: Fetch from MEPC (resume execution)
```

---

## Example Execution Traces

### Example 1: Simple ALU Sequence (No Hazards)

```assembly
ADDI x1, x0, 5     # x1 = 5
ADDI x2, x0, 3     # x2 = 3
ADD  x3, x1, x2    # x3 = x1 + x2 = 8
EBREAK
```

**Cycle-by-Cycle:**

| Cycle | DECODE | EXECUTE | MEMORY | WRITEBACK |
|-------|--------|---------|--------|-----------|
| 1 | ADDI x1,x0,5 | - | - | - |
| 2 | ADDI x2,x0,3 | ADDI x1 | - | - |
| 3 | ADD x3,x1,x2 | ADDI x2 | ADDI x1 | - |
| 4 | EBREAK | ADD x3 | ADDI x2 | ADDI x1 (x1=5) |
| 5 | (flushed) | EBREAK | ADD x3 | ADDI x2 (x2=3) |
| 6 | - | (exception) | EBREAK | ADD x3 (x3=8) |

**Notes:**
- No stalls (x1, x2 ready when ADD needs them)
- EBREAK flushes decode stage (cycle 5)
- Total: 6 cycles for 4 instructions

### Example 2: EX-to-EX Forwarding

```assembly
ADDI x1, x0, 5     # x1 = 5
ADD  x2, x1, x1    # x2 = x1 + x1 (needs x1 from previous EXECUTE)
EBREAK
```

**Cycle-by-Cycle:**

| Cycle | DECODE | EXECUTE | MEMORY | WRITEBACK | Hazard Action |
|-------|--------|---------|--------|-----------|---------------|
| 1 | ADDI x1,x0,5 | - | - | - | - |
| 2 | ADD x2,x1,x1 | ADDI x1 | - | - | Forward x1 from EX |
| 3 | EBREAK | ADD x2 | ADDI x1 | - | - |
| 4 | (flushed) | EBREAK | ADD x2 | ADDI x1 | - |

**Notes:**
- No stall! ADDI x1 result available in EXECUTE stage
- Forwarding path: `execute_REGFILE_WRITE_DATA → decode_RS1`
- Total: 4 cycles for 3 instructions

### Example 3: Load-Use Stall

```assembly
LW   x1, 0(x2)     # Load x1 from memory
ADDI x3, x1, 1     # Use x1 immediately (STALL)
EBREAK
```

**Cycle-by-Cycle:**

| Cycle | DECODE | EXECUTE | MEMORY | WRITEBACK | Hazard Action |
|-------|--------|---------|--------|-----------|---------------|
| 1 | LW x1,0(x2) | - | - | - | - |
| 2 | ADDI x3,x1,1 | LW x1 | - | - | **STALL (x1 not ready)** |
| 3 | (stalled) | (stalled) | LW x1 (data arrives) | - | - |
| 4 | ADDI x3,x1,1 | (bubble) | (bubble) | LW x1 | Forward x1 from WB |
| 5 | EBREAK | ADDI x3 | (bubble) | (bubble) | - |
| 6 | (flushed) | EBREAK | ADDI x3 | (bubble) | - |

**Notes:**
- **1-cycle stall** in cycle 2 (load-use hazard)
- Cycle 3: Data arrives in MEMORY stage (too late for cycle 2)
- Cycle 4: Forward from WRITEBACK to DECODE
- Total: 6 cycles for 3 instructions (1 cycle penalty)

### Example 4: Branch Misprediction

```assembly
0x80000000: ADDI x1, x0, 5
0x80000004: BEQ  x1, x0, target    # Not taken (x1 != 0)
0x80000008: ADDI x2, x0, 1         # Shadow instruction (executed)
0x8000000C: EBREAK
```

**Cycle-by-Cycle:**

| Cycle | DECODE | EXECUTE | MEMORY | WRITEBACK | PC |
|-------|--------|---------|--------|-----------|-----|
| 1 | ADDI x1,x0,5 | - | - | - | 0x80000000 |
| 2 | BEQ x1,x0,... | ADDI x1 | - | - | 0x80000004 |
| 3 | ADDI x2,x0,1 | BEQ (not taken) | ADDI x1 | - | 0x80000008 |
| 4 | EBREAK | ADDI x2 | (bubble) | ADDI x1 | 0x8000000C |
| 5 | (flushed) | EBREAK | ADDI x2 | (bubble) | 0x80000010 |

**Notes:**
- No flush! Branch not taken → Continue sequential
- Shadow instruction (ADDI x2) executes normally
- Total: 5 cycles for 4 instructions (no penalty)

---

## Performance Analysis

### IPC (Instructions Per Cycle)

**Ideal Case (No Hazards, No Branches):**
```
IPC = 1.0 (one instruction completes every cycle after pipeline fill)
```

**Realistic Case (With Hazards):**
```
Load-use hazard: ~10% of instructions → 0.1 stall/instruction
Branches: ~15% of instructions, 50% taken → 0.075 stall/instruction
IPC ≈ 1 / (1 + 0.1 + 0.075) = 0.85
```

### Critical Path

**Estimated Critical Path Components (GenSmallOptimized):**

1. **Register File Read:** 1.0ns (BRAM read)
2. **Hazard Detection + Forwarding Mux:** 1.5ns (4-input mux cascade)
3. **ALU Operation:** 2.0ns (32-bit adder)
4. **Setup to next register:** 0.5ns

**Total:** ~5.0ns → **200MHz theoretical maximum**

**Actual Target:** 125MHz (gives 3ns margin for routing, jitter)

---

## Related Documentation

- **[Architecture Overview](vexriscv_architecture.md)** - Plugin configuration and design rationale
- **[Signal Reference](vexriscv_signal_reference.md)** - Detailed signal descriptions
- **[Build Guide](vexriscv_build_guide.md)** - RTL generation process
- **[Test Plan](vexriscv_test_plan.md)** - Verification test cases

---

**Document Version:** 1.0  
**Last Updated:** 2026-02-07  
**Author:** Generated from project analysis and VexRiscv RTL inspection
