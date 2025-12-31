# CPU Memory-Mapped IO Design (Feature: cpu-mmio-led)

## Overview
Implement LD/ST instructions in TD4CPU to enable direct memory-mapped IO access, specifically for LED control at address 0x101F.

## Design Decisions

### 1. Address Space Partitioning
```
0x0000 - 0x0FFF  : Internal RAM (4096 words, 16-bit)
0x1000 - 0x1FFF  : Memory-Mapped IO space
  0x101F         : LED register (4-bit, write-only from CPU perspective)
  0x1200+        : CPU debug registers (remain UART-accessible only)
```

### 2. LD/ST Instruction Implementation

**Instruction Format (M-format):**
```
[15:12] opcode (3=LD, 4=ST)
[11:9]  rD  - data register
[8:6]   rB  - base register
[5:0]   off6 - signed 6-bit offset
```

**Address Calculation:**
```systemverilog
effective_addr = regfile[rB] + sign_extend(off6)
```

**LD Operation:**
```
1. Calculate address
2. Check address space (RAM vs MMIO)
3. Read from RAM or MMIO
4. Write result to rD
```

**ST Operation:**
```
1. Calculate address
2. Check address space (RAM vs MMIO)
3. Write rD value to RAM or MMIO
```

### 3. MMIO Implementation Strategy: Simple Decode in CPU

**Choice: Direct LED register in td4cpu_core.sv**
- Add 4-bit `led_out` output port to td4cpu_core
- Add internal LED register: `logic [3:0] led_reg`
- ST to 0x1044 writes to `led_reg`
- LD from 0x1044 reads back `led_reg`
- No AXI/bus interface needed (simplest approach)

**Advantages:**
- Minimal complexity
- Fast single-cycle MMIO access
- Educational: demonstrates basic MMIO concept
- No need to modify Register_Block significantly

**Disadvantages:**
- Not scalable to many MMIO devices
- LED control no longer accessible via UART (acceptable tradeoff)

### 4. Register_Block Changes

**Remove REG_TEST_LED from UART/AXI interface:**
- Delete from register map JSON (0x1044 entry)
- Remove from Register_Block.sv read/write cases
- Remove LED output port from Register_Block
- Update AXIUART_Top to connect CPU's led_out directly to top-level LED pins

**Regenerate register map:**
```bash
python software/axiuart_driver/tools/gen_registers.py \
  --in register_map/axiuart_registers.json
```

### 5. Top-Level Wiring

**AXIUART_Top.sv changes:**
```systemverilog
// Remove:
// .test_led(test_led_internal)  // from Register_Block

// Add to td4cpu_core instantiation:
, .led_out(led)  // Direct connection to top-level LED pins
```

### 6. Execution Pipeline for LD/ST

Current CPU pipeline:
```
Cycle 0: FETCH (if running && !halted)
Cycle 1: DECODE + EXECUTE
  - R_ALU: Launch pipeline stage 1
  - SYS (BRK): Halt immediately
  - LD/ST: NEW - Execute address calc + memory access
```

**LD/ST Execution (single-cycle for simplicity):**
```systemverilog
OP_LD: begin
    logic [15:0] addr;
    addr = regfile[rB] + {{10{off6[5]}}, off6};
    if (addr < 16'h1000) begin
        // RAM access
        regfile[rD] <= ram[addr];
    end else if (addr == 16'h1044) begin
        // LED register read
        regfile[rD] <= {12'h000, led_reg};
    end else begin
        // Invalid MMIO address - treat as NOP or error
        regfile[rD] <= 16'h0000;
    end
end

OP_ST: begin
    logic [15:0] addr;
    addr = regfile[rB] + {{10{off6[5]}}, off6};
    if (addr < 16'h1000) begin
        // RAM access
        ram[addr] <= regfile[rD];
    end else if (addr == 16'h1044) begin
        // LED register write
        led_reg <= regfile[rD][3:0];
    end
    // else: invalid MMIO - ignore
end
```

### 7. ISA Documentation Updates

**Example Programs:**

**Example 1: LED binary counter**
```assembly
; Initialize R0 as counter
    LDI R0, #0          ; R0 = 0

loop:
    ST  R0, R1, #0x44   ; MEM[R1 + 0x44] = R0, where R1=0x1000
    ADDI R0, #1         ; R0++
    BR  loop            ; Repeat
```

**Example 2: LED pattern**
```assembly
    LDI R1, #0x1000     ; R1 = MMIO base
    LDI R0, #0xA        ; R0 = 0b1010
    ST  R0, R1, #0x44   ; LED = 0b1010
```

### 8. Test Plan

**UVM Tests:**
1. `axiuart_cpu_ld_ram_test.sv` - Test LD from RAM
2. `axiuart_cpu_st_ram_test.sv` - Test ST to RAM
3. `axiuart_cpu_ld_st_mmio_led_test.sv` - Test LD/ST to LED register
4. Update `axiuart_cpu_logic_test.sv` - Add LD/ST test cases

**Verification Approach:**
- Load program into RAM using debug interface
- Execute with RUN command
- Check LED output directly from top-level (DUT.led)
- Read back LED register using LD instruction
- Verify trace buffer shows correct ST execution

### 9. Migration Path

**Phase 1: LD/ST to RAM only**
- Implement LD/ST for addresses < 0x1000
- Test with RAM read/write patterns

**Phase 2: Add LED MMIO**
- Add led_reg and address decoder for 0x1044
- Test LED write/readback

**Phase 3: Remove old UART LED control**
- Remove REG_TEST_LED from register map
- Update documentation

**Phase 4: Python driver update (post-HW)**
- Document that LED control now requires CPU program execution
- Provide example assembly snippets

## Implementation Checklist
- [ ] Add LD/ST opcodes to td4cpu_core.sv
- [ ] Add led_reg and led_out to td4cpu_core
- [ ] Remove REG_TEST_LED from register_map/axiuart_registers.json
- [ ] Regenerate registers.py and axiuart_reg_pkg.sv
- [ ] Update Register_Block.sv (remove test_led logic)
- [ ] Update AXIUART_Top.sv wiring
- [ ] Create UVM tests
- [ ] Update docs/specification_plan.md
- [ ] Update README.md
- [ ] Update ISA documentation

## Timeline
Estimated: 4-6 hours for full implementation + testing
