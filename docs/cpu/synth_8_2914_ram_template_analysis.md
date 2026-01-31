# Analysis of Vivado Synthesis Error [Synth 8-2914] "Unsupported RAM template"

## Error Message

```
[Synth 8-2914] Unsupported RAM template ["rtl/cpu/vexriscv_blockram.sv":93]
```

## Location

- **File**: `rtl/cpu/vexriscv_blockram.sv:93`
- **Line 93**: `logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];`

## Root Cause Analysis

The Vivado [Synth 8-2914] error "Unsupported RAM template" occurs because the current implementation combines several features that **cannot be mapped to Xilinx RAMB36E1 primitives**.

### Issue 1: True Dual-Port with Read-First Mode + Byte Enables

The design attempts to use:
- **True dual-port** (both Port A and Port B can read AND write)
- **Read-First mode** (read old data before writing)
- **Byte-granular write enables** with separate `if` conditions

Xilinx Block RAMs have limited mode combinations:

| Mode | Port A | Port B | Notes |
|------|--------|--------|-------|
| TDP | R/W | R/W | Same address space, limited mode combinations |
| SDP | Write-only | Read-only | Different ports have different roles |

The pattern in lines 119-122 and 143-146:

```systemverilog
if (a_we[0]) mem[a_addr][7:0]   <= a_wdata[7:0];
if (a_we[1]) mem[a_addr][15:8]  <= a_wdata[15:8];
if (a_we[2]) mem[a_addr][23:16] <= a_wdata[23:16];
if (a_we[3]) mem[a_addr][31:24] <= a_wdata[31:24];
```

**This doesn't map to RAMB36E1's WE pins** because it's written as separate conditional statements.

### Issue 2: Reset Affecting Data Output

Lines 108 and 132:

```systemverilog
if (rst) begin
    a_rdata <= 32'h0000_0013;  // Return NOP (no-operation instruction) on reset
end
```

**Block RAMs don't have reset on data output ports.** This forces synthesis to add external logic that breaks inference.

### Issue 3: MMIO Logic Interleaved with BRAM Access

Lines 110-123:

```systemverilog
if (a_is_mmio) begin
    a_rdata <= led_reg_rdata;
end else begin
    a_rdata <= mem[a_addr];
    // writes...
end
```

The conditional selecting between MMIO and BRAM read **inside the same sequential block** interferes with inference.

### Issue 4: Initial Block for Memory Initialization

Lines 96-100:

```systemverilog
initial begin
    for (int i = 0; i < (1<<ADDR_WIDTH); i++) begin
        mem[i] = 32'h0000_0013;
    end
end
```

While Vivado supports `initial` for BRAM initialization, the combination with other issues may cause problems.

---

## Recommended Fixes

### Option A: Restructure for Valid RAMB36E1 Inference (Recommended)

This option maintains the current interface while making minimal changes for proper inference.

**Changes required:**

1. **Remove reset from data outputs** - Use an external output register with reset
2. **Move MMIO decode outside BRAM block** - Separate MMIO mux after BRAM read
3. **Use standard byte-enable pattern**:

```systemverilog
// Standard byte-enable pattern Vivado recognizes
always_ff @(posedge clk) begin
    if (a_en && !a_is_mmio) begin
        a_rdata <= mem[a_addr];  // Read-first
        for (int i = 0; i < 4; i++) begin
            // i*8 +: 8 is indexed part-select syntax: extracts 8 bits starting at position i*8
            if (a_we[i]) mem[a_addr][i*8 +: 8] <= a_wdata[i*8 +: 8];
        end
    end
end
```

### Option B: Use Simple Dual-Port Instead (Lower Complexity)

If Port A is primarily for instruction fetch (read-only) and Port B for data (read/write):

- Make Port A read-only
- Make Port B read/write
- This maps cleanly to SDP BRAM

### Option C: Explicit RAMB36E1 Instantiation (Most Reliable)

Instantiate `RAMB36E1` primitive directly:

```systemverilog
RAMB36E1 #(
    .READ_WIDTH_A(36),
    .WRITE_WIDTH_A(36),
    .READ_WIDTH_B(36),
    .WRITE_WIDTH_B(36),
    .WRITE_MODE_A("READ_FIRST"),
    .WRITE_MODE_B("READ_FIRST"),
    // ...
) bram_inst (
    .CLKARDCLK(clk),
    .CLKBWRCLK(clk),
    // ...
);
```

---

## Recommended Action

**Option A is recommended** because it maintains the current interface while making minimal changes for proper inference.

The key changes would be:

1. Remove `rst` from affecting `a_rdata`/`b_rdata` outputs
2. Add output registers after BRAM that handle reset
3. Move MMIO muxing to output stage (combinational)
4. Use loop-based byte-enable pattern instead of separate `if` statements

This will require changes to the instantiation in `vexriscv_wrapper.sv` to account for the changed reset behavior.

---

## References

- [Xilinx UG901](https://docs.amd.com/r/en-US/ug901-vivado-synthesis/RAM-HDL-Coding-Techniques) "Vivado Design Suite User Guide: Synthesis" - Chapter 4: RAM HDL Coding Techniques (specifically "Block RAM Read/Write Synchronization Modes")
- [Xilinx UG473](https://docs.amd.com/v/u/en-US/ug473_7Series_Memory_Resources) "7 Series FPGAs Memory Resources User Guide" - Chapter 1: Block RAM Resources (RAMB36E1 primitive specifications)
