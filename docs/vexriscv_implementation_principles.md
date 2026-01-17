# VexRiscv Design Analysis for SystemVerilog Implementation

**Generated**: 2026-01-17  
**Source**: VexRiscv GenSmallOptimized (bypassWriteBackBuffer=true)  
**Purpose**: Complete understanding of VexRiscv architecture for SystemVerilog reimplementation

---

## 1. Pipeline Structure

### Stage Organization (4 Stages)

VexRiscv uses **4 pipeline stages** (not 5):

```
IBusInjection → DECODE → EXECUTE → MEMORY → WRITEBACK
     ↑
  (not a stage, 
   just instruction
   injection logic)
```

**Key Signals Per Stage**:
```systemverilog
// Each stage has arbitration bundle
decode_arbitration_isValid
decode_arbitration_haltItself
decode_arbitration_haltByOther
decode_arbitration_isStuck        // = haltItself || haltByOther
decode_arbitration_isMoving       // = !isStuck && !removeIt
decode_arbitration_isFiring       // = isValid && isMoving
decode_arbitration_removeIt       // Flush this instruction
decode_arbitration_flushIt        // External flush signal
decode_arbitration_flushNext      // Flush subsequent stages

// Same for execute, memory, writeBack stages
```

### Critical Finding: No FSM, Only Combinational Control

```scala
// From HazardSimplePlugin.scala L113-115
when(readStage.arbitration.isValid && (src0Hazard || src1Hazard)) {
  readStage.arbitration.haltByOther := True
}
```

**SystemVerilog Equivalent**:
```systemverilog
// Pure combinational logic - re-evaluated every cycle
assign decode_arbitration_haltByOther = 
    decode_arbitration_isValid && (src0_hazard || src1_hazard);
```

**No state machine**. No IDLE/DETECTED/WAIT_MEM/RELEASE states. Just check hazards **every cycle**.

---

## 2. HazardSimplePlugin - Core Bypass Logic

### 2.1 Write-Back Buffer (Critical for WB→ID Forwarding)

```scala
// HazardSimplePlugin.scala L67-72
val writeBackWrites = Flow(new Bundle {
  val address = Bits(5 bits)
  val data = Bits(32 bits)
})
writeBackWrites.valid := stages.last.output(REGFILE_WRITE_VALID) && stages.last.arbitration.isFiring
writeBackWrites.address := stages.last.output(INSTRUCTION)(rdRange)
writeBackWrites.data := stages.last.output(REGFILE_WRITE_DATA)
val writeBackBuffer = writeBackWrites.stage()  // ← 1-cycle delay register
```

**Generated RTL**:
```systemverilog
wire HazardSimplePlugin_writeBackWrites_valid;
wire [4:0] HazardSimplePlugin_writeBackWrites_payload_address;
wire [31:0] HazardSimplePlugin_writeBackWrites_payload_data;

reg HazardSimplePlugin_writeBackBuffer_valid;
reg [4:0] HazardSimplePlugin_writeBackBuffer_payload_address;
reg [31:0] HazardSimplePlugin_writeBackBuffer_payload_data;

always @(posedge clk) begin
  HazardSimplePlugin_writeBackBuffer_valid <= HazardSimplePlugin_writeBackWrites_valid;
  HazardSimplePlugin_writeBackBuffer_payload_address <= HazardSimplePlugin_writeBackWrites_payload_address;
  HazardSimplePlugin_writeBackBuffer_payload_data <= HazardSimplePlugin_writeBackWrites_payload_data;
end
```

**Purpose**: Holds the **previous cycle's writeback data**. This allows decode stage to forward from "WB-1" instead of "WB-0", eliminating the race condition where WB stage updates **after** decode reads.

### 2.2 Per-Stage Hazard Tracking Pattern

```scala
// HazardSimplePlugin.scala L39-64
def trackHazardWithStage(stage: Stage, bypassable: Boolean, runtimeBypassable: Stageable[Bool]): Unit = {
  val addr0Match = stage.input(INSTRUCTION)(rdRange) === readStage.input(INSTRUCTION)(rs1Range)
  val addr1Match = stage.input(INSTRUCTION)(rdRange) === readStage.input(INSTRUCTION)(rs2Range)
  
  when(stage.arbitration.isValid && stage.input(REGFILE_WRITE_VALID)) {
    if (bypassable) {
      when(runtimeBypassableValue) {
        when(addr0Match) {
          readStage.input(RS1) := stage.output(REGFILE_WRITE_DATA)  // ← DIRECT ASSIGNMENT
        }
        when(addr1Match) {
          readStage.input(RS2) := stage.output(REGFILE_WRITE_DATA)
        }
      }
    }
  }
  
  when(stage.arbitration.isValid && stage.input(REGFILE_WRITE_VALID)) {
    when(Bool(!bypassable) || !runtimeBypassableValue) {
      when(addr0Match) {
        src0Hazard := True  // ← Stall if not bypassable
      }
      when(addr1Match) {
        src1Hazard := True
      }
    }
  }
}
```

**Key Insight**: VexRiscv **directly assigns** forwarded data to `readStage.input(RS1)`. This is **SpinalHDL magic** that gets translated to muxes in Verilog. In SystemVerilog, we must implement explicit mux priority.

**Generated RTL for WB Bypass**:
```systemverilog
wire when_HazardSimplePlugin_l47;  // writeBackBuffer.valid && addr0Match
wire when_HazardSimplePlugin_l48;  // addr0Match (RS1)
wire when_HazardSimplePlugin_l51;  // addr1Match (RS2)

always @(*) begin
  decode_RS1 = RegFilePlugin_regFile[decode_INSTRUCTION[19:15]];  // Default: RF read
  decode_RS2 = RegFilePlugin_regFile[decode_INSTRUCTION[24:20]];
  
  // WB buffer bypass (lowest priority, checked first in SpinalHDL = last override in Verilog)
  if(when_HazardSimplePlugin_l47) begin  // WB buffer valid
    if(when_HazardSimplePlugin_l48) begin  // RS1 match
      decode_RS1 = HazardSimplePlugin_writeBackBuffer_payload_data;
    end
    if(when_HazardSimplePlugin_l51) begin  // RS2 match
      decode_RS2 = HazardSimplePlugin_writeBackBuffer_payload_data;
    end
  end
  
  // Execute bypass (higher priority, overrides WB buffer)
  if(when_HazardSimplePlugin_l45_2) begin  // Execute valid && REGFILE_WRITE_VALID
    if(execute_BYPASSABLE_EXECUTE_STAGE) begin
      if(when_HazardSimplePlugin_l48_2) begin  // RS1 match
        decode_RS1 = _zz_decode_RS1_1;  // Execute result
      end
      if(when_HazardSimplePlugin_l51_2) begin  // RS2 match
        decode_RS2 = _zz_decode_RS2_1;
      end
    end
  end
  
  // Memory bypass (highest priority, last override)
  if(when_HazardSimplePlugin_l45_1) begin  // Memory valid && REGFILE_WRITE_VALID
    if(memory_BYPASSABLE_MEMORY_STAGE) begin
      if(when_HazardSimplePlugin_l48_1) begin  // RS1 match
        decode_RS1 = _zz_decode_RS1;  // Memory result
      end
      if(when_HazardSimplePlugin_l51_1) begin  // RS2 match
        decode_RS2 = _zz_decode_RS2;
      end
    end
  end
end
```

**Bypass Priority** (last assignment wins):
1. WB Buffer (lowest)
2. Execute Stage
3. Memory Stage (highest)

### 2.3 Stall Generation Logic

```systemverilog
// Generated RTL
assign HazardSimplePlugin_src0Hazard = (
  // Check Execute stage
  (when_HazardSimplePlugin_l57_2 && (!execute_BYPASSABLE_EXECUTE_STAGE)) ||
  // Check Memory stage
  (when_HazardSimplePlugin_l57_1 && (!memory_BYPASSABLE_MEMORY_STAGE)) ||
  // Check WB stage
  when_HazardSimplePlugin_l57 ||
  // Check WB buffer
  (when_HazardSimplePlugin_l108 && when_HazardSimplePlugin_l113)
);

assign HazardSimplePlugin_src1Hazard = /* similar for RS2 */;

assign when_HazardSimplePlugin_l113 = (decode_arbitration_isValid && (HazardSimplePlugin_src0Hazard || HazardSimplePlugin_src1Hazard));

// Propagate stall to decode stage
assign decode_arbitration_haltByOther = /* ... */ || when_HazardSimplePlugin_l113;
```

**Key Point**: Stall only if:
- Stage has valid instruction
- Stage writes to register (`REGFILE_WRITE_VALID`)
- Address matches RS1/RS2
- Stage is **NOT bypassable** (or runtime bypass disabled)

---

## 3. DBusSimplePlugin - Memory Interface

### 3.1 Handshake Protocol

```scala
// DBusSimplePlugin.scala (simplified)
val dBus = master(DBusSimpleBus())  // cmd/rsp interface

val cmd = Stream(DBusCmd())
cmd.valid := memory_arbitration_isValid && memory_IS_DBUS_SHARING
cmd.payload.wr := memory_MEMORY_WR
cmd.payload.address := memory_INSTRUCTION[...]
cmd.payload.data := memory_MEMORY_STORE_DATA_RF

val rsp = Flow(DBusRsp())
when(!dBus.cmd.ready) {
  memory.arbitration.haltItself := True  // ← Stall MEM stage
}

val rspStage = rsp.stage()  // Optional pipeline register for load data
writeBack.insert(MEMORY_READ_DATA) := rspStage.data
```

**Generated RTL**:
```systemverilog
wire dBus_cmd_valid;
wire dBus_cmd_ready;  // From memory controller
wire dBus_cmd_payload_wr;
wire [31:0] dBus_cmd_payload_address;
wire [31:0] dBus_cmd_payload_data;
wire [3:0] dBus_cmd_payload_size;

wire dBus_rsp_ready;  // Always true
wire dBus_rsp_error;
wire [31:0] dBus_rsp_data;

assign memory_arbitration_haltItself = (
  /* ... */ ||
  (memory_arbitration_isValid && memory_MEMORY_ENABLE && (!dBus_cmd_ready))
);
```

**Key Finding**: No FSM. Just:
- Assert `dBus_cmd_valid` when MEM stage has load/store
- If `!dBus_cmd_ready`, assert `memory_arbitration_haltItself`
- This automatically stalls all prior stages via arbitration propagation

### 3.2 Load Data Forwarding

```systemverilog
// Load data arrives in MEM stage
assign _zz_decode_RS1 = /* ... other sources ... */ ? xxx :
                        (memory_MEMORY_READ_DATA);  // Can forward from MEM

// Or arrives in WB stage (if rspStage pipeline register used)
assign writeBack_MEMORY_READ_DATA = memory_to_writeBack_MEMORY_READ_DATA;
```

VexRiscv can forward load data from:
- **MEM stage** (if data arrives in time)
- **WB stage** (more common, 1-cycle after MEM)

---

## 4. IBusSimplePlugin - Instruction Fetch

### 4.1 Injection, Not a Stage

```scala
// IBusSimplePlugin.scala
val injector = new Area {
  val decodeInput = Stream(FetchRsp())
  decodeInput.valid := iBusRsp.valid && !iBusRsp.error
  decodeInput.payload.pc := iBusRsp.pc
  decodeInput.payload.instruction := iBusRsp.inst
  
  decode.insert(INSTRUCTION) := decodeInput.payload.instruction
  decode.insert(PC) := decodeInput.payload.pc
}

when(!decodeInput.ready) {
  // Stall fetch - no explicit "fetch stage arbitration"
  pcReg.increment := False
}
```

**Generated RTL**:
```systemverilog
wire IBusSimplePlugin_fetchPc_output_valid;
wire IBusSimplePlugin_fetchPc_output_ready;
wire [31:0] IBusSimplePlugin_fetchPc_output_payload;

assign IBusSimplePlugin_fetchPc_output_ready = (
  (!IBusSimplePlugin_injector_decodeInput_valid) || 
  IBusSimplePlugin_injector_decodeInput_ready
);

assign decode_arbitration_isValid = IBusSimplePlugin_injector_decodeInput_valid;
```

**Key Point**: Fetch is **not a pipeline stage** with arbitration. It's a **stream producer** that injects into decode stage.

---

## 5. Arbitration Framework

### 5.1 Halt Propagation (Backward)

```systemverilog
// Generated pattern
assign decode_arbitration_isStuckByOthers = (
  execute_arbitration_isStuck || 
  memory_arbitration_isStuck || 
  writeBack_arbitration_isStuck
);

assign decode_arbitration_isStuck = (
  decode_arbitration_haltItself || 
  decode_arbitration_isStuckByOthers
);

assign execute_arbitration_isStuckByOthers = (
  memory_arbitration_isStuck || 
  writeBack_arbitration_isStuck
);
// ... and so on
```

**Logic**: If any later stage stalls, all earlier stages must stall.

### 5.2 Flush Propagation (Forward)

```systemverilog
assign decode_arbitration_flushNext = (
  decode_arbitration_isFlushed ||  // Flush from earlier stage
  BranchPlugin_jumpInterface_valid  // Branch/jump taken
);

assign execute_arbitration_flushIt = decode_arbitration_flushNext;

always @(posedge clk) begin
  if(decode_arbitration_flushNext) begin
    execute_arbitration_isValid <= 1'b0;  // Kill next stage
  end
end
```

**Logic**: Flush propagates forward, killing instructions in flight.

---

## 6. SystemVerilog Implementation Strategy

### 6.1 Data Structures

```systemverilog
// Pipeline register struct (keep current structure)
typedef struct packed {
    logic [31:0] pc;
    logic [31:0] instruction;
    logic [4:0]  rd_addr;
    logic        rf_wen;
    // ... control signals
} decode_execute_reg_t;

// Arbitration signals per stage
typedef struct {
    logic isValid;
    logic haltItself;
    logic haltByOther;
    logic isStuck;
    logic isMoving;
    logic isFiring;
    logic removeIt;
    logic flushIt;
    logic flushNext;
} stage_arbitration_t;
```

### 6.2 Hazard Detection Module

```systemverilog
module rv32i_hazard_plugin (
    input  logic clk, rst,
    
    // Decode stage inputs
    input  logic [31:0] decode_insn,
    input  logic        decode_valid,
    input  logic        decode_rs1_use, decode_rs2_use,
    
    // Execute stage
    input  logic [31:0] execute_insn,
    input  logic        execute_valid,
    input  logic        execute_rf_wen,
    input  logic [31:0] execute_result,
    input  logic        execute_bypassable,
    
    // Memory stage
    input  logic [31:0] memory_insn,
    input  logic        memory_valid,
    input  logic        memory_rf_wen,
    input  logic [31:0] memory_result,
    input  logic        memory_bypassable,
    
    // WriteBack stage
    input  logic [31:0] wb_insn,
    input  logic        wb_valid,
    input  logic        wb_rf_wen,
    input  logic [31:0] wb_result,
    
    // Outputs
    output logic [31:0] decode_rs1_data,  // Forwarded data
    output logic [31:0] decode_rs2_data,
    output logic        decode_stall      // Hazard detected
);

    // WB buffer registers
    logic wb_buffer_valid;
    logic [4:0] wb_buffer_rd;
    logic [31:0] wb_buffer_data;
    
    always_ff @(posedge clk) begin
        wb_buffer_valid <= wb_valid && wb_rf_wen && (wb_insn[11:7] != 5'b0);
        wb_buffer_rd <= wb_insn[11:7];
        wb_buffer_data <= wb_result;
    end
    
    // Extract register addresses
    wire [4:0] decode_rs1 = decode_insn[19:15];
    wire [4:0] decode_rs2 = decode_insn[24:20];
    wire [4:0] execute_rd = execute_insn[11:7];
    wire [4:0] memory_rd = memory_insn[11:7];
    wire [4:0] wb_rd = wb_insn[11:7];
    
    // Bypass logic (cascade from lowest to highest priority)
    always_comb begin
        decode_rs1_data = rf_read_rs1;  // Default from register file
        decode_rs2_data = rf_read_rs2;
        
        // WB buffer bypass (lowest priority)
        if (wb_buffer_valid && wb_buffer_rd == decode_rs1) 
            decode_rs1_data = wb_buffer_data;
        if (wb_buffer_valid && wb_buffer_rd == decode_rs2) 
            decode_rs2_data = wb_buffer_data;
            
        // Execute bypass
        if (execute_valid && execute_rf_wen && execute_bypassable && execute_rd == decode_rs1)
            decode_rs1_data = execute_result;
        if (execute_valid && execute_rf_wen && execute_bypassable && execute_rd == decode_rs2)
            decode_rs2_data = execute_result;
            
        // Memory bypass (highest priority)
        if (memory_valid && memory_rf_wen && memory_bypassable && memory_rd == decode_rs1)
            decode_rs1_data = memory_result;
        if (memory_valid && memory_rf_wen && memory_bypassable && memory_rd == decode_rs2)
            decode_rs2_data = memory_result;
    end
    
    // Stall logic - NO FSM
    logic rs1_hazard, rs2_hazard;
    always_comb begin
        rs1_hazard = 1'b0;
        rs2_hazard = 1'b0;
        
        if (decode_valid && decode_rs1_use && decode_rs1 != 5'b0) begin
            // Check execute stage
            if (execute_valid && execute_rf_wen && !execute_bypassable && execute_rd == decode_rs1)
                rs1_hazard = 1'b1;
            // Check memory stage
            if (memory_valid && memory_rf_wen && !memory_bypassable && memory_rd == decode_rs1)
                rs1_hazard = 1'b1;
            // Check WB stage (never bypassable in VexRiscv GenSmall)
            if (wb_valid && wb_rf_wen && wb_rd == decode_rs1)
                rs1_hazard = 1'b1;
        end
        
        // Similar for RS2...
    end
    
    assign decode_stall = rs1_hazard || rs2_hazard;
endmodule
```

---

## 7. Critical Design Rules

### ✓ DO:
1. **Use combinational hazard detection** - re-check every cycle, no FSM
2. **Implement WB buffer** - eliminates WB→ID race
3. **Cascade bypass muxes** - lowest priority first, highest priority last
4. **Use per-stage arbitration** - `isValid`, `haltItself`, `haltByOther`, `isStuck`
5. **Propagate stalls backward** - if MEM stalls, all prior stages stall
6. **Keep explicit pipeline registers** - don't try to auto-generate like SpinalHDL

### ✗ DON'T:
1. **Don't use FSMs for hazard/stall** - source of race conditions
2. **Don't pre-compute bypass controls in ID** - must be dynamic
3. **Don't use output registration in MEM** - breaks control/data association
4. **Don't separate hazard detection from bypass** - keep them together
5. **Don't forget x0 special case** - register 0 always reads as 0, never forward/stall

---

## 8. Next Steps

1. ✓ VexRiscv.v generated and analyzed
2. ✓ SpinalHDL source understood
3. → Implement `rv32i_hazard_plugin.sv` following VexRiscv pattern
4. → Implement `rv32i_dbus_plugin.sv` with cmd/rsp handshake
5. → Implement `rv32i_ibus_plugin.sv` with injection logic
6. → Integrate into `rv32i_core.sv` with arbitration framework
7. → Verify against UVM testbench

---

**END OF ANALYSIS**
