# Known Issues

## CPU MMIO LED - R0 Register Value Anomaly

**Status**: Identified, Low Priority  
**Date Found**: 2025-12-31  
**Affected Component**: td4cpu_core.sv - ST instruction execution  

### Symptom
After executing ST (store) instruction, the source register (rD) value is doubled when read back via debug interface.

**Example**:
```
Program: LDI R0, #10; ST R0, [R1+offset]; BRK
Expected: R0 = 10 (0x000A)
Actual:   R0 = 20 (0x0014)
```

**Pattern observed**:
- LED value 0 → R0 = 0 ✓ (correct)
- LED value 1 → R0 = 2 (2x)
- LED value 5 → R0 = 10 (2x)
- LED value 10 → R0 = 20 (2x)
- LED value 15 → R0 = 30 (2x)

### Impact
**Low** - LED MMIO write functionality is **NOT affected**. The value written to LED register (0x101F) is correct. Only post-execution register reads show doubled values.

**Hardware Test Results**: All 16 LED patterns (0x0-0xF) display correctly on physical LEDs ✓

### Likely Cause
ST instruction pipeline may be writing back rD register incorrectly, possibly:
1. Left-shifting rD value during address calculation
2. Writing back effective address instead of original rD
3. Double-write in pipeline stages

### Investigation Steps
1. Check td4cpu_core.sv ST execution logic (lines ~900-1100)
2. Look for register writeback in ST path
3. Compare with LD instruction (which likely works correctly)
4. Review pipeline signals: `insn_decoded_valid`, register write enables
5. Simulate with waveforms: ST R0, [R1+offset] single instruction

### Workaround
For hardware testing: Visual LED verification instead of R0 register read

### Priority
Low - Does not affect primary MMIO functionality. Can be debugged later with simulation.

---

## Other Issues
(None currently)
