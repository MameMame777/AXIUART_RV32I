# New Test Creation Guide

## Quick Start (3 Minutes)

```bash
# 1. Copy template
cp sim/tests/.test_template.sv sim/tests/my_new_test.sv

# 2. Edit file and replace "MyTestName" with your test name
# 3. Implement run_test_sequence()

# 4. Add to package
echo '`include "my_new_test.sv"' >> sim/tests/axiuart_test_pkg.sv

# 5. Run test
.\scripts\run_test.ps1 my_new_test -Verbosity UVM_MEDIUM -Waves
```

---

## Detailed Instructions

### Step 1: Copy Template

The template file `.test_template.sv` contains all required boilerplate:

```bash
cd sim/tests
cp .test_template.sv axiuart_my_feature_test.sv
```

### Step 2: Rename Test Class

Open your new file and search/replace `MyTestName` with your actual class name:

```systemverilog
// BEFORE:
class MyTestName extends axiuart_cpu_test_base;
    `uvm_component_utils(MyTestName)
    function new(string name = "MyTestName", uvm_component parent = null);

// AFTER:
class axiuart_my_feature_test extends axiuart_cpu_test_base;
    `uvm_component_utils(axiuart_my_feature_test)
    function new(string name = "axiuart_my_feature_test", uvm_component parent = null);
```

**Naming Convention:**
- Prefix: `axiuart_`
- Middle: Feature description (e.g., `cpu_branch`, `alu_overflow`, `interrupt`)
- Suffix: `_test`
- Example: `axiuart_cpu_branch_cond_test`

### Step 3: Implement Test Logic

**DO:**
✅ Implement `run_test_sequence()` only
✅ Use helper methods from base class
✅ Add assertions with `assert_equal_*()` methods
✅ Log important steps with `uvm_info`

**DON'T:**
❌ Override `run_phase()` - let base class handle it
❌ Duplicate helper methods (write_reg, step_cpu, etc.)
❌ Manually manage objections
❌ Create sequences outside of helper methods

**Example Implementation:**

```systemverilog
virtual task run_test_sequence();
    bit [7:0] result;
    
    `uvm_info(get_type_name(), "=== Testing Branch Instruction ===", UVM_LOW)
    
    // Setup: Load registers
    write_insn(16'h0000, 16'h3105);  // LDI R1, 0x05
    write_insn(16'h0001, 16'h8100);  // BEQ R1, PC+0 (should not branch)
    write_insn(16'h0002, 16'hF000);  // SYS BRK
    
    reset_cpu();
    
    // Execute LDI
    step_cpu();
    read_trace_buffer(16'h0000, result);
    assert_equal_8(result, 8'h05, "R1 loaded with 0x05");
    
    // Execute BEQ (should not branch because R1 != 0)
    step_cpu();
    read_cpu_pc(pc);
    assert_equal_16(pc, 16'h0002, "PC advanced (no branch)");
    
    `uvm_info(get_type_name(), "=== Branch Test Complete ===", UVM_LOW)
endtask
```

### Step 4: Register in Test Package

Add your test to `sim/tests/axiuart_test_pkg.sv`:

```systemverilog
// Add after other test includes
`include "axiuart_my_feature_test.sv"
```

**Recommended Order:**
1. Base test
2. CPU test base
3. Simple tests (basic, reset, reg_rw)
4. CPU tests (sorted by complexity)
5. Your new test

### Step 5: Compile Test

```bash
python mcp_server/mcp_client.py --workspace . \
  --tool run_uvm_simulation \
  --test-name axiuart_my_feature_test \
  --mode compile \
  --verbosity UVM_LOW
```

**Check for:**
- ✅ No compilation errors
- ✅ Test registered in UVM factory
- ✅ All sequences found

### Step 6: Run Test

```bash
python mcp_server/mcp_client.py --workspace . \
  --tool run_uvm_simulation \
  --test-name axiuart_my_feature_test \
  --mode run \
  --verbosity UVM_MEDIUM \
  --waves
```

**Expected Output:**
```
UVM_INFO @ 0: reporter [RNTST] Running test axiuart_my_feature_test...
UVM_INFO @ 0: uvm_test_top [axiuart_my_feature_test] ╔══════════════════════╗
UVM_INFO @ 0: uvm_test_top [axiuart_my_feature_test] ║ axiuart_my_feature_test ║
UVM_INFO @ 0: uvm_test_top [axiuart_my_feature_test] ╚══════════════════════╝
UVM_INFO @ XXX: uvm_test_top [axiuart_my_feature_test] ✓ Environment validation passed
UVM_INFO @ XXX: uvm_test_top [axiuart_my_feature_test] Waiting for clock stabilization...
UVM_INFO @ XXX: uvm_test_top [axiuart_my_feature_test] Clock stable
UVM_INFO @ XXX: uvm_test_top [axiuart_my_feature_test] Executing reset sequence...
...
```

### Step 7: Debug with Waveforms

Waveforms are automatically generated in:
```
sim/exec/wave/axiuart_my_feature_test_YYYYMMDD_HHMMSS.mxd
```

Open with DSIM viewer:
```bash
dvviewer sim/exec/wave/axiuart_my_feature_test_*.mxd
```

---

## Common Pitfalls & Solutions

### 🚫 HANG #1: Test Never Starts

**Symptom:**
```
UVM_INFO @ 0: reporter [RNTST] Running test my_test...
[No further output - hangs forever]
```

**Cause:** Sequencer is null (agent created with `UVM_PASSIVE`)

**Solution:** The new base class automatically detects this with `validate_test_environment()`:
```
UVM_FATAL: Sequencer is NULL!
  Likely cause: Agent is_active != UVM_ACTIVE
  Check: uvm_config_db settings for 'is_active'
```

**Prevention:** Don't override agent configuration unless needed.

---

### 🚫 HANG #2: Stuck at Clock Stabilization

**Symptom:**
```
UVM_INFO: Waiting for clock stabilization...
[Hangs here forever]
```

**Cause:** Clock not running in testbench

**Solution:** The new base class has 100µs timeout:
```
UVM_FATAL: Clock stabilization timeout - clock not running or stuck?
```

**Prevention:** Verify testbench has clock generation:
```systemverilog
initial begin
    clk = 0;
    forever #4 clk = ~clk;  // 125MHz
end
```

---

### 🚫 HANG #3: Reset Sequence Timeout

**Symptom:**
```
UVM_INFO: Executing reset sequence...
[Hangs for ~10 seconds, then:]
UVM_FATAL: Reset sequence timeout!
```

**Cause:** UART communication failure (baudrate mismatch, driver not running)

**Solution:** Check logs for driver startup:
```
UVM_INFO: [uart_driver] Starting driver run_phase
```

**Prevention:** 
- Ensure baud rate matches (default: 115200)
- Verify driver is created (agent must be UVM_ACTIVE)

---

### 🚫 ERROR: Missing Sequence

**Symptom:**
```
UVM_FATAL: Factory did not return a component of type 'uart_reset_sequence'
```

**Cause:** Sequence not included in package

**Solution:** Check `sim/sv/axiuart_pkg.sv` includes:
```systemverilog
`include "uart_reset_sequence.sv"
`include "uart_reg_sequences.sv"
```

---

### 🚫 ERROR: Duplicate Test Name

**Symptom:**
```
UVM_WARNING: [TPRGED] Type name 'axiuart_my_test' already registered
```

**Cause:** Two tests with same class name

**Solution:** 
1. Check for duplicate includes in axiuart_test_pkg.sv
2. Ensure test file name matches class name
3. Remove old backup files from sim/tests/

---

### 🚫 ERROR: Trace Buffer Returns 0xFF

**Symptom:**
```
UVM_ERROR: ✗ R0 value: expected 0x05, got 0xff
```

**Cause:** Instruction didn't execute or trace buffer not updated

**Solution:**
1. Check step_cpu() completed without timeout
2. Verify instruction was written correctly
3. Add delay after step_cpu(): `#100ns;`
4. Check CPU wasn't in MMIO wait state

---

## Helper Method Reference

### Instruction Management

```systemverilog
write_insn(16'h0000, 16'h3005);  // Write: LDI R0, 0x05 at PC=0
```

### CPU Control

```systemverilog
reset_cpu();      // Reset CPU (leaves halted in step mode)
halt_cpu();       // Halt running CPU
run_cpu();        // Start CPU from PC
step_cpu();       // Execute one instruction
set_cpu_pc(pc);   // Set program counter
```

### Register Access

```systemverilog
bit [15:0] data;
write_cpu_reg(0, 16'h1234);      // R0 = 0x1234
read_cpu_reg(1, data);            // Read R1
read_cpu_flags(flags);            // Read [N,Z,C,V]
```

### Memory Access

```systemverilog
bit [15:0] data;
write_ram_direct(16'h0100, 16'h42);  // RAM[0x100] = 0x42
read_ram_direct(16'h0100, data);     // Read RAM[0x100]
```

### Trace Buffer

```systemverilog
bit [7:0] trace_data;
read_trace_buffer(16'h0000, trace_data);  // Read trace for PC=0
```

### Assertions

```systemverilog
assert_equal_8(actual, expected, "Test description");
assert_equal_16(actual, expected, "Test description");
assert_equal_4(flags, 4'b0010, "Zero flag set");
```

---

## Test Configuration

Override in constructor if needed:

```systemverilog
function new(string name = "my_test", uvm_component parent = null);
    super.new(name, parent);
    
    this.reset_cycles = 300;            // Longer reset (default: 200)
    this.step_timeout_cycles = 100;     // More patient step (default: 50)
    this.enable_debug_logging = 1;      // Verbose helper logs (default: 0)
endfunction
```

---

## Test Organization

### Single Feature Tests (Recommended)

**GOOD:**
```systemverilog
// axiuart_cpu_ldi_test.sv - Test ONLY LDI instruction
// axiuart_cpu_branch_eq_test.sv - Test ONLY BEQ instruction
// axiuart_cpu_alu_add_test.sv - Test ONLY ADD instruction
```

**Benefits:**
- Fast execution
- Easy debugging
- Clear failure localization
- Reusable in regression suites

### Multi-Feature Tests (Use Sparingly)

```systemverilog
// axiuart_cpu_comprehensive_test.sv - Test ALL instructions
```

**When to use:**
- Integration testing
- End-to-end scenarios
- Regression suite final validation

---

## Debugging Tips

### 1. Enable Verbose Logging

```bash
--verbosity UVM_HIGH
```

### 2. Add Debug Messages

```systemverilog
`uvm_info(get_type_name(), 
    $sformatf("PC=0x%04x, R0=0x%04x", pc, r0), UVM_MEDIUM)
```

### 3. Use Trace Buffer

The trace buffer captures execution history:
```systemverilog
for (int i = 0; i < 10; i++) begin
    read_trace_buffer(i, data);
    `uvm_info("TRACE", $sformatf("PC[%0d] = 0x%02x", i, data), UVM_LOW)
end
```

### 4. Check Register State

```systemverilog
for (int i = 0; i < 8; i++) begin
    read_cpu_reg(i, data);
    `uvm_info("REGS", $sformatf("R%0d = 0x%04x", i, data), UVM_LOW)
end
```

### 5. Inspect Waveforms

Critical signals to monitor:
- `cpu.insn_valid` - Instruction fetch
- `cpu.state` - CPU FSM state
- `cpu.mem_op_executing` - Memory operation flag
- `cpu.halt` - Halt state
- `uart_if.tx/rx` - UART communication

---

## Integration with Regression Suite

### Add to Smoke Suite

Edit `sim/regression_tests.json`:

```json
{
  "suites": {
    "smoke": {
      "tests": [
        "axiuart_basic_test",
        "axiuart_reset_test",
        "axiuart_my_feature_test"  // Add your test
      ],
      "timeout": 120
    }
  }
}
```

### Run Regression

```bash
# Smoke suite (fast validation)
python mcp_server/run_regression.py --suite smoke

# Full suite
python mcp_server/run_regression.py --suite full --format html
```

---

## Best Practices

### ✅ DO

1. **Use descriptive test names** - `axiuart_cpu_branch_forward_test` not `test1`
2. **Test one feature** - Focused tests are easier to debug
3. **Add assertions** - Use `assert_equal_*()` liberally
4. **Log key steps** - Use `uvm_info` for important events
5. **Check waveforms** - Always run with `--waves` during development
6. **Add to regression** - Every test should be in a regression suite

### ❌ DON'T

1. **Don't override run_phase()** - Use `run_test_sequence()` instead
2. **Don't duplicate helpers** - Use base class methods
3. **Don't ignore errors** - Every assert should be meaningful
4. **Don't skip documentation** - Add comments explaining test purpose
5. **Don't commit broken tests** - Verify before pushing

---

## Need Help?

1. **Check existing tests** - Look at `axiuart_cpu_basic_inst_test.sv` for examples
2. **Read base class** - `axiuart_cpu_test_base.sv` shows all available methods
3. **Check logs** - MCP generates detailed logs in `sim/exec/logs/`
4. **Review waveforms** - Often shows issues not visible in logs
5. **Run simpler test first** - Validate environment with `axiuart_basic_test`

---

## Appendix: Complete Example

**File: `sim/tests/axiuart_cpu_shift_test.sv`**

```systemverilog
`timescale 1ns / 1ps

import uvm_pkg::*;
import td4cpu_isa_pkg::*;
import axiuart_reg_pkg::*;

class axiuart_cpu_shift_test extends axiuart_cpu_test_base;
    
    `uvm_component_utils(axiuart_cpu_shift_test)
    
    function new(string name = "axiuart_cpu_shift_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual task run_test_sequence();
        bit [7:0] result;
        
        `uvm_info(get_type_name(), "=== Testing Shift Operations ===", UVM_LOW)
        
        // Test SHL (Shift Left)
        write_insn(16'h0000, 16'h3101);  // LDI R1, 0x01
        write_insn(16'h0001, 16'h7100);  // SHL R1
        write_insn(16'h0002, 16'hF000);  // SYS BRK
        
        reset_cpu();
        step_cpu();  // Execute LDI
        step_cpu();  // Execute SHL
        
        read_trace_buffer(16'h0001, result);
        assert_equal_8(result, 8'h02, "SHL: 0x01 << 1 = 0x02");
        
        // Test SHR (Shift Right)
        write_insn(16'h0000, 16'h3204);  // LDI R2, 0x04
        write_insn(16'h0001, 16'h7210);  // SHR R2
        write_insn(16'h0002, 16'hF000);  // SYS BRK
        
        reset_cpu();
        step_cpu();  // Execute LDI
        step_cpu();  // Execute SHR
        
        read_trace_buffer(16'h0001, result);
        assert_equal_8(result, 8'h02, "SHR: 0x04 >> 1 = 0x02");
        
        `uvm_info(get_type_name(), "=== Shift Test Complete ===", UVM_LOW)
    endtask
    
endclass
```

**Add to package:**
```systemverilog
// sim/tests/axiuart_test_pkg.sv
`include "axiuart_cpu_shift_test.sv"
```

**Run:**
```bash
python mcp_server/mcp_client.py --workspace . \
  --tool run_uvm_simulation \
  --test-name axiuart_cpu_shift_test \
  --mode compile --verbosity UVM_LOW

python mcp_server/mcp_client.py --workspace . \
  --tool run_uvm_simulation \
  --test-name axiuart_cpu_shift_test \
  --mode run --verbosity UVM_MEDIUM --waves
```

---

**Last Updated:** December 31, 2025  
**Version:** 1.0  
**Maintainer:** TD4UART Project
