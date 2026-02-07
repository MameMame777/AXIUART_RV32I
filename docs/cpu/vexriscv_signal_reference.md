# VexRiscv GenSmallOptimized - Signal Reference

**Version:** 1.0  
**Date:** 2026-02-07  
**Configuration:** GenSmallOptimized  
**Generated RTL:** `rtl/cpu/VexRiscv.v`

---

## Table of Contents

1. [Top-Level Port Signals](#top-level-port-signals)
2. [Internal Pipeline Signals](#internal-pipeline-signals)
3. [Arbitration Signals](#arbitration-signals)
4. [Control Signals](#control-signals)
5. [Debug Observation Points](#debug-observation-points)
6. [Signal Naming Conventions](#signal-naming-conventions)

---

## Top-Level Port Signals

### Module Declaration

```verilog
module VexRiscv (
  // Instruction Bus (IBus)
  output wire          iBus_cmd_valid,
  input  wire          iBus_cmd_ready,
  output wire [31:0]   iBus_cmd_payload_pc,
  input  wire          iBus_rsp_valid,
  input  wire          iBus_rsp_payload_error,
  input  wire [31:0]   iBus_rsp_payload_inst,
  
  // Data Bus (DBus)
  output wire          dBus_cmd_valid,
  input  wire          dBus_cmd_ready,
  output wire          dBus_cmd_payload_wr,
  output wire [3:0]    dBus_cmd_payload_mask,
  output wire [31:0]   dBus_cmd_payload_address,
  output wire [31:0]   dBus_cmd_payload_data,
  output wire [1:0]    dBus_cmd_payload_size,
  input  wire          dBus_rsp_ready,
  input  wire          dBus_rsp_error,
  input  wire [31:0]   dBus_rsp_data,
  
  // Interrupts
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
  input  wire          reset
);
```

---

### IBus Signals (Instruction Fetch)

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| `iBus_cmd_valid` | 1 | Output | Instruction fetch request valid |
| `iBus_cmd_ready` | 1 | Input | Memory controller ready to accept fetch |
| `iBus_cmd_payload_pc` | 32 | Output | Program counter (fetch address) |
| `iBus_rsp_valid` | 1 | Input | Instruction response valid |
| `iBus_rsp_payload_error` | 1 | Input | Fetch error (page fault, bus error) |
| `iBus_rsp_payload_inst` | 32 | Input | Fetched instruction word |

**Protocol:**
```
Handshake: cmd_valid && cmd_ready → Request accepted
Latency: Typically 1 cycle (BRAM), response on next cycle
Stall: If !iBus_cmd_ready, CPU stalls fetch (PC freezes)
```

**Example Fetch Sequence:**
```
Cycle 1: iBus_cmd_valid=1, iBus_cmd_payload_pc=0x80000000
         iBus_cmd_ready=1 → Accepted
Cycle 2: iBus_rsp_valid=1, iBus_rsp_payload_inst=0x00000013 (NOP)
         CPU injects instruction to decode stage
```

**Error Handling:**
- `iBus_rsp_payload_error=1` → Fetch access fault
- If `catchAccessFault=false` in config, error is ignored (GenSmallOptimized behavior)

---

### DBus Signals (Data Memory)

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| `dBus_cmd_valid` | 1 | Output | Load/store command valid |
| `dBus_cmd_ready` | 1 | Input | Memory controller ready |
| `dBus_cmd_payload_wr` | 1 | Output | 0=Read (load), 1=Write (store) |
| `dBus_cmd_payload_mask` | 4 | Output | Byte enable (bit per byte) |
| `dBus_cmd_payload_address` | 32 | Output | Memory address |
| `dBus_cmd_payload_data` | 32 | Output | Write data (for stores) |
| `dBus_cmd_payload_size` | 2 | Output | 0=Byte, 1=Halfword, 2=Word |
| `dBus_rsp_ready` | 1 | Input | Response ready (always 1 in GenSmallOptimized) |
| `dBus_rsp_error` | 1 | Input | Access error flag |
| `dBus_rsp_data` | 32 | Input | Read data (for loads) |

**Protocol:**
```
Handshake: cmd_valid && cmd_ready → Command accepted
Latency: 1 cycle (response next cycle)
Stall: If !dBus_cmd_ready, MEMORY stage stalls (backpressure to all stages)
```

**Byte Mask Encoding:**
```
mask[3:0] = 4'b0001 → Write byte 0 only (SB to address+0)
mask[3:0] = 4'b0011 → Write bytes 0-1 (SH to aligned address)
mask[3:0] = 4'b1111 → Write all bytes (SW)
```

**Example Load Sequence (LW):**
```
Cycle 1: dBus_cmd_valid=1, dBus_cmd_payload_wr=0
         dBus_cmd_payload_address=0x80001000
         dBus_cmd_ready=1 → Accepted
Cycle 2: dBus_rsp_ready=1, dBus_rsp_data=0xDEADBEEF
         CPU writes to destination register
```

**Example Store Sequence (SW):**
```
Cycle 1: dBus_cmd_valid=1, dBus_cmd_payload_wr=1
         dBus_cmd_payload_address=0x80001000
         dBus_cmd_payload_data=0x12345678
         dBus_cmd_payload_mask=4'b1111
         dBus_cmd_ready=1 → Accepted
Cycle 2: dBus_rsp_ready=1 (acknowledge, no data)
```

---

### Interrupt Signals

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| `timerInterrupt` | 1 | Input | Machine timer interrupt (MTI) |
| `externalInterrupt` | 1 | Input | Machine external interrupt (MEI) |
| `softwareInterrupt` | 1 | Input | Machine software interrupt (MSI) |

**Behavior:**
- Interrupts checked at instruction retirement (WRITEBACK stage)
- If MIE (Machine Interrupt Enable) set in MSTATUS → Take trap
- CsrPlugin handles trap entry: PC → MEPC, jump to MTVEC
- **GenSmallOptimized:** Interrupts are wired but basic handling (no nested interrupts)

**Priority:** External > Software > Timer (standard RISC-V priority)

---

### Debug Interface

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| `debug_bus_cmd_valid` | 1 | Input | Debug command valid |
| `debug_bus_cmd_ready` | 1 | Output | CPU ready to accept debug command |
| `debug_bus_cmd_payload_wr` | 1 | Input | 0=Read, 1=Write |
| `debug_bus_cmd_payload_address` | 8 | Input | Debug register address |
| `debug_bus_cmd_payload_data` | 32 | Input | Write data |
| `debug_bus_rsp_data` | 32 | Output | Read data |
| `debug_resetOut` | 1 | Output | Debug-triggered CPU reset |

**Debug Register Map (Typical):**
```
0x00: FLAGS     - Control flags (halt, step, reset request)
0x04: PC        - Current program counter
0x08: INSN      - Current instruction
0x10-0x4C: x0-x15 - Register file (first 16 regs)
```

**Usage in Testbench:**
```systemverilog
// Halt CPU
debug_bus_cmd_valid = 1;
debug_bus_cmd_payload_wr = 1;
debug_bus_cmd_payload_address = 8'h00;
debug_bus_cmd_payload_data = 32'h00000001;  // Halt flag

// Read PC
debug_bus_cmd_payload_wr = 0;
debug_bus_cmd_payload_address = 8'h04;
wait(debug_bus_cmd_ready);
pc_value = debug_bus_rsp_data;
```

---

## Internal Pipeline Signals

### Stage Valid Signals

| Signal | Description |
|--------|-------------|
| `decode_arbitration_isValid` | Valid instruction in DECODE stage |
| `execute_arbitration_isValid` | Valid instruction in EXECUTE stage |
| `memory_arbitration_isValid` | Valid instruction in MEMORY stage |
| `writeBack_arbitration_isValid` | Valid instruction in WRITEBACK stage |

**Meaning:** `isValid=1` indicates stage contains an instruction (not a bubble).

### Instruction Signals

| Signal | Width | Stage | Description |
|--------|-------|-------|-------------|
| `decode_INSTRUCTION` | 32 | DEC | Current decoded instruction |
| `execute_INSTRUCTION` | 32 | EX | Instruction in execute stage |
| `memory_INSTRUCTION` | 32 | MEM | Instruction in memory stage |
| `writeBack_INSTRUCTION` | 32 | WB | Instruction being retired |
| `decode_PC` | 32 | DEC | Program counter of instruction |
| `execute_PC` | 32 | EX | PC in execute |
| `memory_PC` | 32 | MEM | PC in memory |
| `writeBack_PC` | 32 | WB | PC being retired |

**Usage:** UVM tests monitor these to verify instruction flow:
```systemverilog
always @(posedge clk) begin
  if (writeBack_arbitration_isFiring) begin
    $display("Retired: PC=0x%08x INSN=0x%08x", writeBack_PC, writeBack_INSTRUCTION);
  end
end
```

### Register File Signals

| Signal | Width | Description |
|--------|-------|-------------|
| `decode_RS1` | 32 | RS1 value (after forwarding) |
| `decode_RS2` | 32 | RS2 value (after forwarding) |
| `decode_REGFILE_WRITE_VALID` | 1 | Instruction writes register |
| `execute_REGFILE_WRITE_VALID` | 1 | EX stage will write register |
| `memory_REGFILE_WRITE_VALID` | 1 | MEM stage will write register |
| `writeBack_REGFILE_WRITE_VALID` | 1 | WB stage writing register this cycle |
| `execute_REGFILE_WRITE_DATA` | 32 | Data being written in EX |
| `memory_REGFILE_WRITE_DATA` | 32 | Data being written in MEM |
| `writeBack_REGFILE_WRITE_DATA` | 32 | Data being written in WB |

**Register File Array:**
```verilog
reg [31:0] RegFilePlugin_regFile [0:31];

always @(posedge clk) begin
  if (writeBack_REGFILE_WRITE_VALID && (writeBack_rd != 5'b0)) begin
    RegFilePlugin_regFile[writeBack_rd] <= writeBack_REGFILE_WRITE_DATA;
  end
end
```

### Memory Signals (Internal)

| Signal | Width | Description |
|--------|-------|-------------|
| `execute_MEMORY_ENABLE` | 1 | Instruction is load/store |
| `execute_MEMORY_STORE` | 1 | Store (not load) |
| `memory_MEMORY_ENABLE` | 1 | MEM stage accessing memory |
| `memory_MEMORY_STORE` | 1 | MEM stage storing |
| `memory_MEMORY_ADDRESS_LOW` | 2 | Low address bits (for byte alignment) |
| `memory_MEMORY_READ_DATA` | 32 | Loaded data (from dBus) |
| `writeBack_MEMORY_ENABLE` | 1 | WB stage had memory access |
| `writeBack_MEMORY_READ_DATA` | 32 | Load data available in WB |

**Load Data Path:**
```
dBus_rsp_data → memory_MEMORY_READ_DATA → memory_to_writeBack_MEMORY_READ_DATA → 
writeBack_MEMORY_READ_DATA → writeBack_REGFILE_WRITE_DATA (if load)
```

---

## Arbitration Signals

### Per-Stage Arbitration Bundle

Each stage has 9 arbitration signals (example for DECODE):

| Signal | Type | Description |
|--------|------|-------------|
| `decode_arbitration_isValid` | Wire | Stage has valid instruction |
| `decode_arbitration_haltItself` | Wire | Stage stalls itself (e.g., waiting for memory) |
| `decode_arbitration_haltByOther` | Wire | Stalled by hazard unit |
| `decode_arbitration_isStuck` | Wire | Stage not advancing (= haltItself \|\| haltByOther \|\| isStuckByOthers) |
| `decode_arbitration_isStuckByOthers` | Wire | Later stage is stuck → backpressure |
| `decode_arbitration_isMoving` | Wire | Stage advancing this cycle (= !isStuck && !removeIt) |
| `decode_arbitration_isFiring` | Wire | Committing instruction (= isValid && isMoving) |
| `decode_arbitration_removeIt` | Reg | Kill this instruction (flush) |
| `decode_arbitration_flushIt` | Wire | Flush request from upstream |
| `decode_arbitration_flushNext` | Wire | Flush downstream stages |

**Computation Example:**
```verilog
// Stall propagation (backward)
assign decode_arbitration_isStuckByOthers = (
  execute_arbitration_isStuck || 
  memory_arbitration_isStuck || 
  writeBack_arbitration_isStuck
);

assign decode_arbitration_isStuck = (
  decode_arbitration_haltItself || 
  decode_arbitration_haltByOther || 
  decode_arbitration_isStuckByOthers
);

// Movement calculation
assign decode_arbitration_isMoving = (
  !decode_arbitration_isStuck && 
  !decode_arbitration_removeIt
);

assign decode_arbitration_isFiring = (
  decode_arbitration_isValid && 
  decode_arbitration_isMoving
);

// Flush propagation (forward)
assign decode_arbitration_flushNext = (
  BranchPlugin_jumpInterface_valid ||  // Branch taken
  CsrPlugin_jumpInterface_valid ||     // Exception
  // ... other flush sources
);

assign execute_arbitration_flushIt = decode_arbitration_flushNext;

always @(posedge clk) begin
  if (reset || execute_arbitration_flushIt) begin
    execute_arbitration_isValid <= 1'b0;
  end else if (!execute_arbitration_isStuck) begin
    execute_arbitration_isValid <= decode_arbitration_isValid;
  end
end
```

---

## Control Signals

### Decode Control Signals

Generated by DecoderSimplePlugin based on opcode:

| Signal | Width | Values | Description |
|--------|-------|--------|-------------|
| `decode_ALU_CTRL` | 2 | ADD_SUB(0), SLT_SLTU(1), BITWISE(2) | ALU operation |
| `decode_ALU_BITWISE_CTRL` | 2 | XOR(0), OR(1), AND(2) | Bitwise op type |
| `decode_SHIFT_CTRL` | 2 | DISABLE(0), SLL(1), SRL(2), SRA(3) | Shift operation |
| `decode_SRC1_CTRL` | 2 | RS(0), IMU(1), PC_INC(2), URS1(3) | Source 1 mux |
| `decode_SRC2_CTRL` | 2 | RS(0), IMI(1), IMS(2), PC(3) | Source 2 mux |
| `decode_BRANCH_CTRL` | 2 | INC(0), B(1), JAL(2), JALR(3) | Branch type |
| `decode_ENV_CTRL` | 2 | NONE(0), XRET(1), ECALL(2), EBREAK(3) | System instruction |
| `decode_IS_CSR` | 1 | - | Instruction is CSR access |
| `decode_MEMORY_ENABLE` | 1 | - | Load/store instruction |
| `decode_MEMORY_STORE` | 1 | - | Store (not load) |
| `decode_SRC_LESS_UNSIGNED` | 1 | - | Unsigned comparison (SLTU, BLTU) |
| `decode_SRC2_FORCE_ZERO` | 1 | - | Force RS2=0 (for LUI) |
| `decode_BYPASSABLE_EXECUTE_STAGE` | 1 | - | Can forward from EX |
| `decode_BYPASSABLE_MEMORY_STAGE` | 1 | - | Can forward from MEM |

**Example Decoder Output:**
```
ADDI x1, x2, 5:
  ALU_CTRL = ADD_SUB
  SRC1_CTRL = RS (x2)
  SRC2_CTRL = IMI (immediate I-type)
  REGFILE_WRITE_VALID = 1
  BYPASSABLE_EXECUTE_STAGE = 1
```

### Execute Stage Control

| Signal | Width | Description |
|--------|-------|-------------|
| `execute_ALU_CTRL` | 2 | ALU operation (propagated from decode) |
| `execute_ALU_BITWISE_CTRL` | 2 | Bitwise operation |
| `execute_SRC1` | 32 | ALU source 1 (after mux) |
| `execute_SRC2` | 32 | ALU source 2 (after mux) |
| `execute_SRC_ADD` | 32 | SRC1 + SRC2 (for address calc) |
| `execute_SRC_LESS` | 1 | SRC1 < SRC2 (comparison result) |
| `execute_BRANCH_DO` | 1 | Branch condition met |
| `execute_BRANCH_CALC` | 32 | Branch target address |
| `execute_DO_EBREAK` | 1 | EBREAK instruction executing |

---

## Debug Observation Points

### Key Signals for Testbench Monitoring

**Instruction Retirement:**
```verilog
wire instruction_retired = writeBack_arbitration_isFiring;
wire [31:0] retired_pc = writeBack_PC;
wire [31:0] retired_insn = writeBack_INSTRUCTION;
```

**Register Writes:**
```verilog
wire reg_write = writeBack_REGFILE_WRITE_VALID && writeBack_arbitration_isFiring;
wire [4:0] reg_write_addr = writeBack_INSTRUCTION[11:7];
wire [31:0] reg_write_data = writeBack_REGFILE_WRITE_DATA;
```

**Pipeline Stalls:**
```verilog
wire decode_stalled = decode_arbitration_isStuck;
wire execute_stalled = execute_arbitration_isStuck;
wire memory_stalled = memory_arbitration_isStuck;
```

**Hazard Detection:**
```verilog
wire hazard_detected = decode_arbitration_haltByOther;
wire load_use_stall = HazardSimplePlugin_src0Hazard || HazardSimplePlugin_src1Hazard;
```

**Branch Taken:**
```verilog
wire branch_taken = BranchPlugin_jumpInterface_valid;
wire [31:0] branch_target = BranchPlugin_jumpInterface_payload;
```

### UVM Monitor Example

```systemverilog
class vexriscv_monitor extends uvm_monitor;
  virtual rv32i_if vif;
  
  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      
      // Monitor instruction retirement
      if (vif.writeBack_arbitration_isFiring) begin
        `uvm_info("MON", $sformatf("Retired: PC=0x%08x INSN=0x%08x", 
                  vif.writeBack_PC, vif.writeBack_INSTRUCTION), UVM_MEDIUM)
      end
      
      // Monitor register writes
      if (vif.writeBack_REGFILE_WRITE_VALID && vif.writeBack_arbitration_isFiring) begin
        `uvm_info("MON", $sformatf("RF Write: x%0d = 0x%08x", 
                  vif.writeBack_INSTRUCTION[11:7], 
                  vif.writeBack_REGFILE_WRITE_DATA), UVM_HIGH)
      end
      
      // Monitor stalls
      if (vif.decode_arbitration_isStuck) begin
        `uvm_info("MON", "Decode stage stalled", UVM_HIGH)
      end
    end
  endtask
endclass
```

---

## Signal Naming Conventions

### SpinalHDL Generated Naming

**Stage Prefix:** `{stage}_{signal}` where stage is `decode`, `execute`, `memory`, or `writeBack`.

**Examples:**
- `decode_PC` - PC value in decode stage
- `execute_ALU_RESULT` - ALU output in execute stage
- `memory_MEMORY_READ_DATA` - Load data in memory stage

**Internal Signals:** Prefix with `_zz_` (SpinalHDL convention for intermediate wires):
```verilog
wire [31:0] _zz_decode_RS1;        // Intermediate value before forwarding
wire _zz_execute_IS_LOAD;         // Helper signal
```

**Plugin Signals:** Prefix with plugin name:
```verilog
wire HazardSimplePlugin_src0Hazard;
wire BranchPlugin_jumpInterface_valid;
wire CsrPlugin_privilege;
wire DebugPlugin_haltIt;
```

### Finding Signals in Generated Verilog

**Strategy:**
1. **Search by stage:** Ctrl+F for "decode_" to find all decode-stage signals
2. **Search by function:** Ctrl+F for "MEMORY" to find all memory-related signals
3. **Search by plugin:** Ctrl+F for "HazardSimplePlugin" to find hazard logic

**Common Patterns:**
```
{stage}_to_{next_stage}_{signal}  - Pipeline register
{stage}_arbitration_{signal}      - Arbitration bundle
{stage}_{CONTROL_NAME}            - Control signal (uppercase)
{plugin}_{signal}                 - Plugin-specific signal
_zz_{signal}                      - Intermediate wire
```

---

## Related Documentation

- **[Architecture Overview](vexriscv_architecture.md)** - Plugin configuration details
- **[Pipeline Operation](vexriscv_pipeline_operation.md)** - How signals interact across stages
- **[Build Guide](vexriscv_build_guide.md)** - Generating RTL from SpinalHDL
- **[Test Plan](vexriscv_test_plan.md)** - Verification coverage

---

**Document Version:** 1.0  
**Last Updated:** 2026-02-07  
**Author:** Generated from VexRiscv.v RTL analysis
