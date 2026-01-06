# Assertion Modules - Debug Verification Infrastructure

## Overview

This directory contains **SystemVerilog Assertion (SVA) modules** for deep debugging and verification of the TD4CPU core. These assertions are **disabled by default** for performance and only loaded when explicitly requested.

## Quick Start - Enabling Assertions

### Command Line

```powershell
# Standard compilation (assertions OFF - fast)
python mcp_server/mcp_client.py --workspace . --tool run_uvm_simulation \
  --test-name axiuart_cpu_simple_mem_test --mode compile

# Debug mode (assertions ON - full checking)
python mcp_server/mcp_client.py --workspace . --tool run_uvm_simulation \
  --test-name axiuart_cpu_simple_mem_test --mode compile \
  --plusarg +define+ENABLE_ASSERTIONS
```

### Python API

```python
from mcp_server.dsim_fastmcp_server import run_uvm_simulation

# Enable assertions via parameter
result = await run_uvm_simulation(
    test_name="axiuart_cpu_simple_mem_test",
    mode="compile",
    enable_assertions=True  # Automatically adds +define+ENABLE_ASSERTIONS
)
```

## Performance Impact

| Configuration | Modules Compiled | td4cpu_core Complexity | Overhead |
|--------------|------------------|------------------------|----------|
| **Assertions OFF** (default) | 22 | 100 functions / 568 blocks | 0% (baseline) |
| **Assertions ON** (debug) | 28 (+6) | 119 functions / 615 blocks | +19% |

**Recommendation:** Keep assertions disabled during normal development. Enable only when:
- Investigating test failures
- Debugging timing issues
- Performing root cause analysis
- Validating critical RTL changes

## Assertion Modules

### 1. Branch Timing (`td4cpu_br_timing_assertions.sv`)

**Purpose:** Verifies branch instruction execution timing and PC tracking.

**Checks:**
- `fetch_pc` captures correct address (branch target vs sequential)
- `insn_fetched_pc` captures `fetch_pc` at instruction valid
- `br_insn_pc` captures `insn_fetched_pc` at branch decode
- Delay slot PC equals `BR_PC + 1` (MIPS/SPARC delay slot semantics)
- PC updates to `branch_target + 1` after branch completes
- Branch target fetch verification (actual vs expected address)
- PC sequence continuity (detects unexpected jumps)
- Sequential vs branch fetch source validation

**Example Failure:**
```
[AST_FAIL] Delay slot PC incorrect: fetch_pc(prev)=0x0005, expected=0x0004 (br_insn_pc=0x0003)
```

**Coverage:**
- Branch detection events
- Branch pending states
- PC update sequences
- Branch flow cross-coverage

### 2. Address Flow (`td4cpu_address_debug.sv`)

**Purpose:** Tracks address propagation from debug interface through RAM to CPU execution.

**Checks:**
- Debug write address → RAM write address matching
- Debug write data → RAM write data matching
- RAM read address matches PC during instruction fetch
- `insn_fetched_pc` captures `fetch_pc` correctly
- `insn_decoded_pc` matches `insn_fetched_pc` at decode
- RAM content verification (write → fetch consistency)

**Example Failure:**
```
[ADDR_DBG] Fetch address mismatch: ram_addr_next=0x0002, prev_pc=0x0001
[ADDR_DBG] RAM CONTENT MISMATCH at fetch_pc=0x0000: fetched=0x1234, expected=0x5678
```

**Debug Output:**
- Debug write requests with addresses and data
- RAM write operations
- RAM read cycles with address tracking
- Instruction validation with PC correlation
- RAM content tracking for first 16 addresses

### 3. Memory Read Path (`td4cpu_debug_read_monitor.sv`)

**Purpose:** Investigates debug memory read path failures (address pollution detection).

**Checks:**
- Debug read address propagates to `ram_addr_next` correctly
- No pollution from previous write operations
- `ram_addr_next` stability during multi-cycle reads
- Control signal correlation (read_req → ram_rd_en → mem_busy)

**Example Failure:**
```
[ASSERT] ram_addr_next polluted by previous write address: ram_addr_next=0x0010, prev_write=0x0010
[DBG_READ_MON] *** POLLUTION: ram_addr_next matches last_write_addr! ***
```

**State Tracking:**
- Captures requested address at read start
- Monitors address through all read phases
- Detects pollution sources (fetch, write, debug write)
- Validates data capture timing

### 4. RAM Read Investigation (`td4cpu_ram_read_investigation.sv`)

**Purpose:** Systematic investigation of RAM read control conflicts.

**Focus Areas:**
- **Assignment conflicts** between run handler (line 715) and debug read handler (line 753)
- Simultaneous run/debug operations detection
- Address propagation pollution analysis
- Control signal handshake verification

**Checks:**
- `ram_rd_en` must be set within 1 cycle of debug read request
- No simultaneous run and debug read operations
- Address propagation correctness (`ram_addr_next` == requested address)
- Read enable stability (stays high for required duration)
- Complete read sequence timing (request → data valid within 3 cycles)

**Example Failure:**
```
[RAM_READ_INVEST] ASSIGNMENT CONFLICT: Both line 715 and 753 executing in same cycle!
[ASSERT_RAM_READ] ram_rd_en=0 after debug read request (CRITICAL BUG)
```

**FSM States:**
- IDLE → READ_REQUESTED → READ_CYCLE1_EXPECT_RD_EN → READ_CYCLE2_WAIT_DATA → READ_COMPLETE
- Tracks timestamps for latency analysis
- Identifies conflict sources and pollution vectors

**Coverage:**
- Read request scenarios
- `ram_rd_en` enable/disable states
- Halted vs running state combinations
- Successful vs failed read cross-coverage

### 5. RAM Read Enable Timing (`td4cpu_ram_rd_en_timing.sv`)

**Purpose:** Deep dive into `ram_rd_en` signal timing and multi-cycle read protocol.

**RAM Read Timing Specification:**
```
Cycle N:   Debug read request
           → ram_rd_en <= 1, mem_busy_q <= 1, ram_addr_next <= addr

Cycle N+1: RAM access (ram_rd_en held)
           → RAM outputs data to ram_rd_data

Cycle N+2: Data capture
           → dbg_mem_rdata <= ram_rd_data, mem_data_valid <= 1, ram_rd_en <= 0

Cycle N+3: Complete
           → mem_busy_q <= 0
```

**Checks:**
- `ram_rd_en` set within 1 cycle of request
- `ram_rd_en` held for at least 1 cycle (prevents early clear)
- Complete sequence timing (request → data valid in 2-3 cycles)

**Example Failure:**
```
[RAM_RD_EN_TIMING] ✗ CRITICAL: ram_rd_en cleared TOO EARLY
[RAM_RD_EN_TIMING] It was 1 last cycle but now 0
[RAM_RD_EN_TIMING] This prevents data capture!
```

**Detailed Logging:**
- Cycle-by-cycle state machine progression
- Expected vs actual timing comparison
- Latency measurements (request → data valid)
- Error detection with remediation hints

**Coverage:**
- State transitions (IDLE → REQUEST → WAIT_RD_EN → RAM_ACCESS → DATA_CAPTURE → COMPLETE)
- Error state detection
- `ram_rd_en` value tracking (0 → 1 → 0 transitions)

### 6. Debug Memory Specification (`td4cpu_debug_mem_spec.sv`)

**Purpose:** Formal specification enforcement for debug memory interface protocol.

**Protocol Verification:**
- Debug read/write handshake timing
- Error signal propagation
- Busy flag behavior
- Address/data capture correctness

**Checks:**
- Request → response latency bounds
- Mutual exclusion (no simultaneous read/write)
- Error conditions properly flagged
- Data valid assertions align with protocol

**Example Failure:**
```
[DBG_MEM_SPEC] Protocol violation: read_req and write_req both active
[DBG_MEM_SPEC] mem_data_valid asserted without mem_busy_q active
```

### 7. Bind Declarations (`bind_debug_spec.sv`)

**Purpose:** Connects assertion modules to DUT internals using SystemVerilog `bind`.

**Architecture:**
```systemverilog
bind td4cpu_core td4cpu_debug_mem_spec spec_checker (
    .clk(clk),
    .rst(rst),
    // ... internal signal connections
);
```

**Advantages:**
- **Non-intrusive:** No DUT modification required
- **Modular:** Assertions live in separate modules
- **Configurable:** Easy to enable/disable entire assertion suites
- **Hierarchical access:** Can probe internal CPU signals

## Architecture and Design Principles

### Separation of Concerns

```
rtl/cpu/td4cpu_core.sv          ← Production RTL (never modified for assertions)
          ↑
          | bind (external connection)
          |
sim/assertions/*.sv              ← Debug assertion modules (only loaded when enabled)
```

### Loading Mechanism

1. **Main Config** (`sim/uvm/tb/dsim_config.f`):
   - Contains only production RTL files
   - No assertion modules (clean separation)

2. **Assertion Config** (`sim/uvm/tb/dsim_assertions.f`):
   - Lists all assertion module files
   - Only included when `+define+ENABLE_ASSERTIONS` detected

3. **MCP Server Logic** (`mcp_server/dsim_uvm_server.py`):
   ```python
   # Automatic detection
   enable_assertions = any("+define+ENABLE_ASSERTIONS" in arg for arg in plusargs)
   if enable_assertions:
       cmd.extend(["-f", "dsim_assertions.f"])  # Conditional include
   ```

### Observer-Only Principle

**All assertion modules follow the "Observer-Only" design:**

✅ **Allowed:**
- `assert property` with `disable iff`
- SVA temporal operators (`|->`, `|=>`, `##`, `$stable`, `$rose`, `$fell`)
- `$error`, `$warning`, `$display` for diagnostics
- Signal monitoring and tracking
- Coverage collection

❌ **Forbidden:**
- `always`, `initial`, `fork`, tasks, functions (behavioral code)
- Signal assignments that affect DUT
- Procedural stimulus generation
- `assume` (for formal verification tools only)
- `$fatal` (would terminate simulation)

**Why?**  
Assertions must **never** influence DUT behavior. They are diagnostic instruments, not functional logic.

## Implementation Guidelines for New Assertions

### 1. Use the Template

```systemverilog
`timescale 1ns / 1ps

module <design>_<feature>_assertions (
    input logic clk,
    input logic rst,  // Active-high reset
    
    // Observed signals (input only)
    input logic        signal_a,
    input logic [15:0] signal_b
);

    // Assertion: <brief description>
    property p_<feature>_check;
        @(posedge clk) disable iff (rst)
        <temporal_expression> |-> <consequent>;
    endproperty
    
    assert property (p_<feature>_check) else
        $error("[<MODULE>] <clear error message>");
    
    // Optional: Coverage
    covergroup cg_<feature> @(posedge clk);
        cp_signal_a: coverpoint signal_a;
    endgroup
    
    cg_<feature> cg_inst = new();

endmodule

// Bind to DUT
bind <dut_module> <design>_<feature>_assertions u_<feature>_assertions (
    .clk(clk),
    .rst(rst),
    .signal_a(signal_a),
    .signal_b(signal_b)
);
```

### 2. Follow the One-Intent-One-Assertion Rule

❌ **Bad:** One assertion checking multiple behaviors
```systemverilog
assert property (
    req |-> ##1 ack && (data == expected) && (state == IDLE)
);
```

✅ **Good:** Separate assertions per intent
```systemverilog
assert property (req |-> ##1 ack);
assert property (req && ##1 ack |-> (data == expected));
assert property (req && ##1 ack |-> (state == IDLE));
```

### 3. Use Descriptive Error Messages

❌ **Bad:** Vague error
```systemverilog
$error("Assertion failed");
```

✅ **Good:** Actionable error with context
```systemverilog
$error("[ADDR_DBG] Fetch address mismatch: ram_addr_next=%0h, expected_pc=%0h at time %0t",
       ram_addr_next, expected_pc, $time);
```

### 4. Add to Configuration File

After creating a new assertion module:

1. Add to `sim/uvm/tb/dsim_assertions.f`:
   ```
   ../../assertions/my_new_assertions.sv
   ```

2. Test compilation:
   ```powershell
   # Test with assertions enabled
   python mcp_server/mcp_client.py --workspace . --tool run_uvm_simulation \
     --test-name axiuart_cpu_simple_mem_test --mode compile \
     --plusarg +define+ENABLE_ASSERTIONS
   
   # Verify module count increased (should be 29 now)
   ```

## Debugging with Assertions

### Workflow

1. **Test Fails** → Run without assertions first (fast iteration)
2. **Reproduce** → Narrow down failing scenario
3. **Enable Assertions** → Recompile with `+define+ENABLE_ASSERTIONS`
4. **Analyze** → Review assertion failures in simulation log
5. **Fix** → Apply RTL fix based on assertion diagnostics
6. **Verify** → Run with assertions enabled to confirm fix
7. **Regression** → Run final test without assertions (performance)

### Reading Assertion Output

**Typical assertion failure:**
```
@5942428000 [ADDR_DBG] @5942428000 DEBUG WRITE REQUEST: addr=0x0000, data=0x1234
@8074100000 [DBG_READ_MON] @8074100000 READ REQUEST: dbg_mem_addr=0x0000
@8074108000 [RAM_RD_EN_TIMING] @8074108000 CYCLE N (post-clock): Checking immediate effects
=E:[$error call] td4cpu_ram_rd_en_timing.sv:165
[RAM_RD_EN_TIMING] ✗ CRITICAL: ram_rd_en cleared TOO EARLY

SVA Summary: 33 assertions, 229,199,058 evaluations, 13,890,807 nonvacuous passes
```

**How to interpret:**
- **Timestamp** (`@5942428000`): Simulation time in picoseconds
- **Module Tag** (`[RAM_RD_EN_TIMING]`): Which assertion module detected the issue
- **Error Location** (`td4cpu_ram_rd_en_timing.sv:165`): Source file and line
- **Diagnostic Message**: What went wrong and why it matters
- **SVA Summary**: Statistics (33 checks active, 229M evaluations, 13M passes)

### Common Issues and Resolutions

**Issue:** Assertion fails only with assertions enabled  
**Cause:** Compilation differences (more functions/blocks compiled)  
**Solution:** This is expected. Assertions reveal bugs masked by optimization.

**Issue:** Massive assertion spam  
**Cause:** Fundamental protocol violation repeating every cycle  
**Solution:** Fix the first failure (often cascades disappear)

**Issue:** Assertion fails in unrelated code  
**Cause:** Side effects from timing changes  
**Solution:** Use waveforms + assertion timestamps to correlate

## File Reference

| File | Purpose | Lines | Complexity |
|------|---------|-------|------------|
| `td4cpu_br_timing_assertions.sv` | Branch PC tracking | ~400 | High |
| `td4cpu_address_debug.sv` | Address flow debug | ~300 | Medium |
| `td4cpu_debug_read_monitor.sv` | Read path analysis | ~250 | Medium |
| `td4cpu_ram_read_investigation.sv` | Conflict detection | ~500 | High |
| `td4cpu_ram_rd_en_timing.sv` | Timing verification | ~350 | High |
| `td4cpu_debug_mem_spec.sv` | Protocol compliance | ~400 | Medium |
| `bind_debug_spec.sv` | Bind declarations | ~30 | Low |
| `forCopilot-assertions.md` | AI generation rules | Documentation | N/A |

## Integration with CI/CD

### Nightly Builds (Assertions ON)

```yaml
# .github/workflows/nightly-verification.yml
- name: Full Verification with Assertions
  run: |
    python mcp_server/mcp_client.py --workspace . \
      --tool run_uvm_simulation \
      --test-name axiuart_cpu_memory_test \
      --mode run \
      --verbosity UVM_HIGH \
      --plusarg +define+ENABLE_ASSERTIONS
```

### PR Checks (Assertions OFF - Fast)

```yaml
# .github/workflows/pr-checks.yml
- name: Quick Smoke Test
  run: |
    python mcp_server/mcp_client.py --workspace . \
      --tool run_uvm_simulation \
      --test-name axiuart_cpu_simple_mem_test \
      --mode compile \
      --verbosity UVM_LOW
    # No --plusarg needed (assertions disabled by default)
```

## Maintenance

### When to Update Assertions

- **New RTL features:** Add corresponding assertion coverage
- **Bug fixes:** Add assertions to prevent regression
- **Protocol changes:** Update specification checkers
- **Performance issues:** Profile and optimize expensive properties

### Deprecation Policy

Assertion modules should be removed when:
1. The checked feature is removed from RTL
2. The assertion has not fired in 6+ months (dead code)
3. The assertion causes excessive false positives

Document removal in commit message for future reference.

## References

- **Assertion Guidelines:** `forCopilot-assertions.md` (AI generation rules)
- **ISA Specification:** `docs/ISA.md` (branch delay slot semantics)
- **MCP Server API:** `mcp_server/README.md` (enable_assertions parameter)
- **Simulation Guide:** `sim/README.md` (usage examples)

## Questions?

For assertion-related issues:
1. Check simulation logs under `sim/exec/logs/`
2. Review assertion module source code (detailed comments)
3. Run with `+UVM_VERBOSITY=UVM_HIGH` for detailed traces
4. Compare waveforms with assertion timestamps for correlation

Assertions are tools to accelerate debugging, not replace it. Use them strategically when standard debugging methods are insufficient.
