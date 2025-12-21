# UVM Test Timing Guide

## Test Execution Time Reference

This document provides estimated execution times and recommended timeout settings for each UVM test.

### Quick Reference Table

| Test Name | Operations | Estimated Time | Recommended Timeout | Verbosity | Notes |
|-----------|-----------|----------------|---------------------|-----------|-------|
| `axiuart_basic_test` | ~10 | < 1s | 180s | UVM_LOW | Basic register R/W validation |
| `axiuart_reset_test` | ~5 | < 1s | 180s | UVM_LOW | Reset sequence verification |
| `axiuart_reg_rw_test` | ~20 | < 5s | 180s | UVM_LOW | Register access pattern test |
| `axiuart_cpu_debug_test` | ~50 | < 10s | 300s | UVM_MEDIUM | CPU debug register access |
| `axiuart_cpu_simple_mem_test` | 7 | ~46ms | 180s | UVM_LOW | Simple CPU memory verification ✅ |
| `axiuart_cpu_memory_test` | 640 | ~32min | 1200-2400s | UVM_LOW/MEDIUM | March C- memory test ⚠️ |

### Detailed Information

#### axiuart_cpu_simple_mem_test
- **Purpose**: Basic CPU memory access validation
- **Operations**: 7 write/read pairs
- **Measured Time**: 46ms @ 115200 baud
- **Status**: ✅ Validated (7/7 matches)
- **Command**:
  ```powershell
  python mcp_server/mcp_client.py --workspace . --tool run_uvm_simulation \
    --test-name axiuart_cpu_simple_mem_test --mode run --verbosity UVM_LOW --timeout 180
  ```

#### axiuart_cpu_memory_test
- **Purpose**: Comprehensive March C- memory algorithm test
- **Operations**: 640 (6 phases × 64 addresses × multiple patterns)
  - Phase 0: ⇕ (w0) - 64 writes
  - Phase 1: ⇑ (r0,w1) - 128 operations  
  - Phase 2: ⇑ (r1,w0) - 128 operations
  - Phase 3: ⇓ (r0,w1) - 128 operations
  - Phase 4: ⇓ (r1,w0) - 128 operations
  - Phase 5: ⇕ (r0) - 64 reads
- **Measured Time**: ~32 minutes (1,910,432,150 ps sim time)
- **Status**: ✅ Validated (319/319 matches, 0 mismatches)
- **Recommended Verbosity**: UVM_LOW for production, UVM_DEBUG for detailed analysis
- **Command**:
  ```powershell
  # Standard execution
  python mcp_server/mcp_client.py --workspace . --tool run_uvm_simulation \
    --test-name axiuart_cpu_memory_test --mode run --verbosity UVM_LOW --timeout 1200
  
  # Debug execution with waveforms
  python mcp_server/mcp_client.py --workspace . --tool run_uvm_simulation \
    --test-name axiuart_cpu_memory_test --mode run --verbosity UVM_DEBUG --waves --timeout 2400
  ```

### Timeout Calculation Guidelines

**Basic Formula**:
```
Timeout = (Operations × Transaction_Time × Safety_Margin) + Overhead
```

**Parameters**:
- **Transaction_Time**: ~313μs per UART transaction @ 115200 baud
- **Safety_Margin**: 2-3× recommended for UVM overhead
- **Overhead**: ~30s for elaboration, initialization, and cleanup

**Example Calculation** (cpu_memory_test):
```
Operations:     640
Transaction:    313μs × 2 (write+read) = 626μs
Base Time:      640 × 626μs ≈ 400ms
With UVM:       400ms × 300 (actual overhead) ≈ 32min
Recommended:    1200s (20min) to 2400s (40min)
```

### UART Timing Constraints

At 115200 baud with 8N1 format:
- **Bit Time**: ~8.68μs
- **Frame Time**: ~86.8μs (10 bits: 1 start + 8 data + 1 stop)
- **Multi-byte Frame**: Variable (header + payload + CRC)
- **Register Write**: ~313μs average (includes frame overhead)
- **Register Read**: ~313μs average (request + response)

### Verbosity Impact

| Verbosity | Log Size | Performance Impact | Use Case |
|-----------|----------|-------------------|----------|
| UVM_NONE | Minimal | None | Production/Regression |
| UVM_LOW | Small | < 5% | Standard verification |
| UVM_MEDIUM | Medium | ~10% | Debug specific issues |
| UVM_HIGH | Large | ~20% | Detailed transaction trace |
| UVM_DEBUG | Very Large | ~30% | Full UVM phase tracing |

### Recommendations

#### For Quick Validation
- Use **UVM_LOW** verbosity
- Set timeout to **180s** for simple tests
- Disable waveform dumping unless debugging

#### For Comprehensive Testing
- Use **UVM_MEDIUM** verbosity
- Set timeout to **1200s+** for memory tests
- Enable waves with `--waves` flag

#### For Debug/Analysis
- Use **UVM_DEBUG** verbosity
- Set timeout to **2400s** (40 min)
- Always enable waveforms
- Use `+UVM_PHASE_TRACE` for phase debugging

### CI/CD Integration

Recommended timeout settings for automated testing:

```yaml
fast_tests:
  timeout: 300s  # 5 minutes
  tests:
    - axiuart_basic_test
    - axiuart_reset_test
    - axiuart_reg_rw_test
    - axiuart_cpu_simple_mem_test

medium_tests:
  timeout: 600s  # 10 minutes  
  tests:
    - axiuart_cpu_debug_test

slow_tests:
  timeout: 2400s  # 40 minutes
  tests:
    - axiuart_cpu_memory_test
```

### Historical Data

| Date | Test | Time | Result | Notes |
|------|------|------|--------|-------|
| 2024-12-21 | axiuart_cpu_simple_mem_test | 46ms | PASS | 7/7 matches |
| 2024-12-21 | axiuart_cpu_memory_test | 32m02s | PASS | 319/319 matches, March C- algorithm |

### Troubleshooting

**Test timeout exceeded:**
1. Check if DSIM license is available
2. Verify no previous DSIM processes are hung
3. Increase timeout by 2× and retry
4. Check logs for infinite loops or deadlocks

**Unexpectedly slow execution:**
1. Verify UART baud rate settings (should be 115200)
2. Check for excessive UVM_DEBUG messages
3. Disable unnecessary waveform dumping
4. Review test sequence delays (ns vs μs)

### Update History

- **2024-12-21**: Initial version with cpu_simple_mem_test and cpu_memory_test timing data
