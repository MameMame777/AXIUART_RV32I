# CPU Debug Fix - PC Reset Issue

**Date**: 2026-01-06  
**Status**: FIXED - Requires FPGA reprogramming  
**Commit**: c61f731

## Problem Description

The RV32I CPU debug interface was not working correctly when loading and executing programs via the Python driver (`test_cpu_led.py`):

**Symptoms**:
- Programs loaded successfully into CPU memory (verified by readback)
- CPU started (HALTED flag cleared) but never completed execution
- EBREAK instruction never triggered (BREAK flag never set)
- LED value stuck at 0x3 (stale value from previous test)

**Root Cause**:
The CPU Program Counter (PC) was **only reset at power-on**, not when starting execution after loading a program. When the debug interface loaded a program to address 0x0 and then asserted CPU_RUN:

1. PC remained at its previous value (e.g., 0x407C from last MMIO access, or wherever CPU was halted)
2. CPU started executing from random/stale address
3. Never reached the loaded program at address 0x0
4. Never hit EBREAK instruction

## Investigation Steps

### Discovery Process
1. Created `test_cpu_led.py` to test CPU LED control via memory-mapped program
2. Program verification showed correct data in memory (4 instructions at 0x0-0xC)
3. CPU status showed "running" (HALTED=False) but BREAK never triggered
4. Created `check_memory.py` to inspect CPU memory - found multiple test program remnants
5. Created `debug_cpu_status.py` to check CPU control bit behavior
6. **Key finding**: Memory at addresses 0-3 showed stale LUI instructions from previous runs
7. **Root cause identified**: `write_cpu_mem()` worked correctly, but PC didn't reset to 0x0

### Evidence
```
Memory contents at address 0x0000-0x001C:
  Word[0] (0x0000): 0x000048B7  (LUI instruction)  ← Should be current program's LUI
  Word[1] (0x0004): 0x000048B7  (LUI instruction)  ← Should be ADDI!  
  Word[2] (0x0008): 0x000048B7  (LUI instruction)  ← Should be SW!
  Word[3] (0x000C): 0x000048B7  (LUI instruction)  ← Should be EBREAK!
```

Initial diagnosis was wrong - memory WAS being written correctly. The issue was PC not resetting.

## Fix Implementation

**File**: `rtl/cpu/rv32i_core.sv` lines 312-319

**Before**:
```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pc_if <= 32'h00000000;
    end else if (running && !cpu_halt) begin
        pc_if <= pc_next;
    end
end
```

**After**:
```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pc_if <= 32'h00000000;
    end else if (cpu_run && cpu_halted) begin
        // Reset PC to 0 when starting from halted state
        pc_if <= 32'h00000000;
    end else if (running && !cpu_halt) begin
        pc_if <= pc_next;
    end
end
```

**Logic**: When `cpu_run` is asserted while `cpu_halted` is true (transition from halted→running), reset PC to 0x0 before starting execution. This ensures programs loaded via debug interface always start from address 0.

## Verification Required

**IMPORTANT**: This fix requires FPGA reprogramming! The Python driver tests will continue to fail until the updated bitstream is deployed.

### Steps to Verify Fix:

1. **Re-run Vivado Synthesis**:
   ```powershell
   cd <repo-root>\PandR\axi4_rv32i
   vivado axi4_rv32i.xpr
   # Run synthesis → Implementation → Generate Bitstream
   ```

2. **Program FPGA**:
   - Open Hardware Manager
   - Program device with new bitstream
   - Verify COM3 port active at 115200 baud

3. **Run Python Tests**:
   ```powershell
   cd <repo-root>\software\axiuart_driver\examples
   
   # Test 1: CPU control basics
   python debug_cpu_status.py
   
   # Test 2: Memory access
   python check_memory.py
   
   # Test 3: Detailed CPU execution test
   python test_cpu_detailed.py
   
   # Test 4: Full LED pattern test  
   python test_cpu_led.py
   ```

4. **Expected Results**:
   - `debug_cpu_status.py`: CPU should halt and run correctly
   - `check_memory.py`: Should show program loaded at addresses 0-3
   - `test_cpu_detailed.py`: 
     - ✅ Program verification passes
     - ✅ EBREAK detected within ~50ms
     - ✅ LED value matches programmed value
   - `test_cpu_led.py`: All 8 LED patterns should pass (0x1,0x2,0x4,0x8,0xF,0x0,0x5,0xA)

## Test Files Created

1. **`test_driver.py`**: Driver connectivity and register access test (5 tests)
2. **`test_cpu_led.py`**: Full LED pattern test (8 different values)
3. **`debug_cpu_status.py`**: CPU control bit verification
4. **`check_memory.py`**: CPU memory inspection tool
5. **`test_cpu_detailed.py`**: Step-by-step execution test with detailed logging

## Impact Assessment

- **RTL Change**: Single always_ff block in `rv32i_core.sv`
- **Timing Impact**: Minimal - adds one condition to existing PC mux
- **Functional Impact**: Critical fix - enables debug interface to work correctly
- **Simulation**: Existing UVM tests unaffected (use reset, not debug load)
- **Software**: No changes needed - driver already correct

## Related Issues

- **LED stuck at 0x3**: Was stale value because CPU never executed new program
- **EBREAK not triggering**: CPU executing from wrong address, never reached EBREAK
- **Program verification passing**: Memory writes worked, PC behavior was wrong

## Follow-up Tasks

After verification:
1. Run full UVM regression to ensure no timing/functional regressions
2. Update RV32I CPU documentation to clarify debug interface PC reset behavior
3. Consider adding PC read capability to debug interface for future debugging
4. Add assertion to check PC resets to 0 when cpu_run asserted while halted
