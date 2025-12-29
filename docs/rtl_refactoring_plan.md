# RTL Refactoring Plan for Place & Route Optimization

## Current Issues Analysis

### 1. Module Complexity
| Module | Lines | Issues |
|--------|-------|--------|
| Uart_Axi4_Bridge.sv | 966 | Large state machine, deep combinational logic |
| Register_Block.sv | 924 | Many register cases, address decoding |
| td4cpu_core.sv | 922 | Deep nested conditions, large case statements |
| Frame_Parser.sv | 732 | Complex CRC validation logic |

### 2. Critical Path Problems

**td4cpu_core.sv:**
- Line 678-850: Large `case(insn_opcode)` with nested conditionals
- Line 215-270: Combinational always_comb with deep logic
- Line 392-866: Main FSM with 45+ if/case statements
- Memory address validation checks in critical path

**Register_Block.sv:**
- Line 193-732: Address decoding with many case entries
- Write data path has multiple conditional assignments
- Read data multiplexing is not pipelined

**Uart_Axi4_Bridge.sv:**
- Complex state machine with 12+ states
- Deep combinational logic chains
- Multiple nested if-else in critical paths

### 3. Timing Bottlenecks

1. **Address Decoding**: Non-registered address comparison
2. **Data Path Multiplexing**: Large combinational muxes
3. **ALU Operations**: Single-cycle execution
4. **Memory Access**: Unregistered address/data paths

## Optimization Strategy

### Phase 1: Pipeline Critical Paths (Priority: HIGH)

#### 1.1 CPU Core Decode Stage
```systemverilog
// Current: Single-cycle decode
case (insn_opcode)
  OP_LDI: ...
  OP_ADDI: ...
  OP_LD: ...
  // 8+ cases with nested logic
endcase

// Proposed: Split into 2-stage pipeline
// Stage 1: Opcode decode + address calculation
// Stage 2: Execution + writeback
```

**Benefits:**
- Reduces combinational path by ~50%
- Allows higher frequency operation
- Impact: +1 cycle latency (negligible for debug-oriented CPU)

#### 1.2 Register Block Address Decode
```systemverilog
// Current: Combinational address decode
always_comb begin
  case (axi_araddr)
    REG_CONTROL: ...
    REG_STATUS: ...
    // 30+ register cases
  endcase
end

// Proposed: Add pipeline register
logic [31:0] decoded_addr_stage1;
logic [31:0] read_data_stage2;

always_ff @(posedge clk) begin
  decoded_addr_stage1 <= axi_araddr; // Register address
  read_data_stage2 <= mux_output;    // Register data mux
end
```

**Benefits:**
- Breaks long address-to-data path
- Improves timing closure by 20-30%
- Cost: +1 AXI read latency cycle (acceptable)

### Phase 2: Simplify Combinational Logic (Priority: MEDIUM)

#### 2.1 Memory Address Validation
```systemverilog
// Current: Function called in critical path
function automatic logic is_ram_addr_valid(input logic [15:0] addr);
  return (addr < RAM_WORDS);
endfunction

// Used in: LD/ST execution, PC bounds check
if (is_ram_addr_valid(ld_effective_addr)) begin ...

// Proposed: Pre-compute during address calculation
logic [15:0] ld_effective_addr;
logic ld_addr_valid;

always_comb begin
  ld_effective_addr = regfile[ld_rB_idx] + ld_offset6;
  ld_addr_valid = (ld_effective_addr < RAM_WORDS);
end

// Then use registered valid signal
always_ff @(posedge clk) begin
  if (ld_addr_valid) ...
end
```

#### 2.2 MMIO Address Decode
```systemverilog
// Current: Comparisons in execution path
if (ld_effective_addr < MMIO_BASE) begin
  // RAM access
end else if (ld_effective_addr == MMIO_LED) begin
  // LED access
end

// Proposed: Decode flags during address calc
logic ld_is_ram, ld_is_led;

always_comb begin
  ld_effective_addr = regfile[ld_rB_idx] + ld_offset6;
  ld_is_ram = (ld_effective_addr < MMIO_BASE);
  ld_is_led = (ld_effective_addr == MMIO_LED);
end

// Simplified execution
always_ff @(posedge clk) begin
  if (ld_is_ram) ram[addr] <= data;
  else if (ld_is_led) led_reg <= data;
end
```

### Phase 3: Reduce Module Complexity (Priority: LOW)

#### 3.1 Split Large State Machines
```systemverilog
// Uart_Axi4_Bridge: 966 lines, 12+ states
// Proposed: Split into 3 sub-modules
// - Parser FSM (RX path)
// - Builder FSM (TX path)  
// - AXI Master FSM (bus interface)
```

#### 3.2 Factor Out Repeated Logic
```systemverilog
// Multiple modules have CRC calculation
// Proposal: Single parameterized CRC module
// Benefits: Area reduction, easier verification
```

### Phase 4: Synthesis Directives (Priority: HIGH)

#### 4.1 Critical Path Preservation
```systemverilog
// Add synthesis directives to prevent unwanted optimization
(* dont_touch = "true" *) logic critical_signal;
(* max_fanout = 32 *) logic high_fanout_signal;
```

#### 4.2 FSM Encoding
```systemverilog
// Force one-hot encoding for state machines
(* fsm_encoding = "one_hot" *) enum logic [11:0] {
  IDLE,
  DECODE,
  EXECUTE,
  // ...
} state;
```

## Implementation Priority

### Immediate (Pre-synthesis fixes):
1. ✅ Add pipeline stage to Register_Block address decode
2. ✅ Pre-compute address validation flags in CPU
3. ✅ Add synthesis directives for FSM encoding
4. ⚠️ Split LD/ST address calculation into separate cycle

### Short-term (1-2 weeks):
5. Split Uart_Axi4_Bridge into sub-modules
6. Pipeline Frame_Parser CRC validation
7. Add timing constraints (.xdc)

### Long-term (Future):
8. Add instruction cache (reduce memory access)
9. Optimize AXI4-Lite master burst handling
10. Consider dual-port RAM for CPU

## Estimated Impact

| Optimization | Timing Improvement | Area Impact | Effort |
|--------------|-------------------|-------------|--------|
| Register decode pipeline | +15-20% | +2% | Low |
| CPU address pre-decode | +10-15% | +1% | Low |
| FSM encoding directives | +5-10% | 0% | Trivial |
| Split large modules | +10-15% | -5% | Medium |
| **Total Estimated** | **+30-40%** | **-2%** | **Low-Medium** |

## Risk Assessment

**Low Risk:**
- Adding pipeline registers (functionality preserved)
- Synthesis directives (no RTL change)
- Pre-computation of flags (logic equivalence)

**Medium Risk:**
- Splitting state machines (requires re-verification)
- Changing instruction timing (may affect tests)

**Mitigation:**
- Run full regression after each change
- Maintain git branches for rollback
- Compare waveforms before/after

## Next Steps

1. Create `feature/rtl-optimization` branch
2. Implement Phase 1.1 (CPU decode pipeline)
3. Run regression tests
4. Measure timing improvement
5. Iterate with Phase 1.2 if needed

---

**Document created**: December 29, 2025  
**Status**: Planning phase
