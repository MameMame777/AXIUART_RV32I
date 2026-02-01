# Issue: VexRiscv Test Failures - Memory Loading Infrastructure Missing

**Status**: 🔴 **CRITICAL**  
**Date Created**: 2026-02-01  
**Assignee**: TBD  
**Labels**: `bug`, `verification`, `priority-high`, `stage-1-regression`

## Summary

VexRiscv verification tests fail because `load_memory_backdoor()` in `vexriscv_base_test.sv` is not implemented. Test programs (Intel HEX files) are never loaded into BRAM, causing CPU to execute uninitialized memory (0x00000000 = illegal instruction → HALTED state).

**Current Regression Results** (2026-02-01):
- **Total**: 10 tests
- **Passed**: 6 tests ✅
- **Failed**: 4 tests ❌

---

## Affected Tests

### ❌ Failed (4 tests)

1. **vexriscv_alu_test** - UVM_ERROR: 2
   - CPU HALTED状態で20サイクル停止
   - x30 = 0x80000094 (期待値: 0x80000098)
   - ALU命令未実行

2. **vexriscv_memory_access_test** - UVM_ERROR: 1
   - CPU HALTED状態で20サイクル停止
   - x11 = 0x00000000 (期待値: 0x12345678)
   - LW命令失敗

3. **vexriscv_wb_bypass_test** - UVM_ERROR: 1
   - x2=6 (正しい) but サイクル数=25 (異常、bypassWriteBackBuffer問題？)
   
4. **vexriscv_dbus_access_test** - UVM_ERROR: 5
   - CPU HALTED状態で20サイクル停止
   - BRAM[0x1000] = 0x00000013 (期待値: 0x000000FF)
   - バイト/ハーフワード/ワードアクセス未実行

### ✅ Passed (6 tests)

- vexriscv_regfile_test
- vexriscv_ibus_fetch_test
- vexriscv_pipeline_flow_test
- vexriscv_ex_bypass_test
- vexriscv_mem_bypass_test
- vexriscv_load_use_stall_test

**注意**: PASSしたテストは個別に`write_memory_backdoor()`でプログラムを書き込んでいるため成功している。

---

## Root Cause Analysis

### 1. Missing Implementation

**File**: [sim/uvm/sv/vexriscv_base_test.sv#L167-L176](../sim/uvm/sv/vexriscv_base_test.sv#L167-L176)

```systemverilog
virtual task load_memory_backdoor(string hex_path, bit translate_addr);
    // Placeholder for memory loading via backdoor
    // Actual implementation options:
    // 1. DPI call to Python hex loader
    // 2. SystemVerilog $readmemh with preprocessing
    // 3. UVM register backdoor write
    
    `uvm_warning(get_type_name(), 
        "load_memory_backdoor() is not implemented - override in derived test")
endtask
```

**Impact**: 
- Called by `load_hex_file()` task for all VexRiscv tests using HEX files
- Only emits warning, performs no actual memory loading
- Tests proceed with uninitialized BRAM (all zeros)
- CPU executes 0x00000000 (illegal instruction) → HALTED state

### 2. Architecture Evolution Context

**Historical Timeline**:

| Phase | Date | Method | Status |
|-------|------|--------|--------|
| **Phase 1** | ~2026-01 | Direct `write_memory_backdoor()` calls | ✅ Tests PASSED |
| **Phase 2** | 2026-02-01 | HEX file loader migration | ❌ Incomplete transition |
| **Planned** | Future | UART-based verification | 🔮 Design intent |

**From** [docs/issue18_fix_review.md](../docs/issue18_fix_review.md):
```
### Test Results

Regression Suite (Stage 1)

| Test | Result | Duration |
|------|--------|----------|
| vexriscv_memory_access_test | **PASS** | 14s |
| vexriscv_alu_test | **PASS** | 14s |
| vexriscv_dbus_access_test | **PASS** | DBus protocol verified |
```

これらのテストは以前PASSしていた（直接メモリ書き込み使用時）。

**From** [docs/vexriscv_test_plan.md](../docs/vexriscv_test_plan.md):
```markdown
4. **Observable Verification** - Test through UART debug interface, not direct RTL access
```

UART検証への移行は計画されているが、**未実装**。

### 3. Existing Infrastructure (Available but Unused)

**Working Components**:
- ✅ `tools/vexriscv_hex_loader.py` - Python Intel HEX parser (369 lines)
- ✅ `write_memory_backdoor()` - Direct BRAM write (L397-L415)
- ✅ `read_memory_backdoor()` - Direct BRAM read (L379-L395)
- ✅ Test programs: `.hex` files in `generated/asm/vexriscv/`

**Missing Link**: 
- SystemVerilog実装でIntel HEXファイルをパース
- `write_memory_backdoor()`を使ってBRAMに書き込み

---

## Proposed Solution

### Option A: Immediate Fix (SystemVerilog Implementation) ⭐ **RECOMMENDED**

**Approach**: `load_memory_backdoor()`をSystemVerilog `$readmemh`ライクな実装で完成

**利点**:
- ✅ 外部依存なし（純SystemVerilog）
- ✅ 高速シミュレーション（Python DPIオーバーヘッド不要）
- ✅ 既存HEXファイル形式と互換
- ✅ 最小コード変更（~50-80行）

**実装コード**:

```systemverilog
virtual task load_memory_backdoor(string hex_path, bit translate_addr);
    int fd;
    string line;
    bit [31:0] base_addr, offset_addr, data;
    int byte_count, record_type, checksum;
    bit [7:0] byte_data;
    logic [10:0] word_addr;
    int bytes_loaded = 0;
    
    `uvm_info(get_type_name(), 
        $sformatf("Loading hex file: %s (translate=%0d)", hex_path, translate_addr), 
        UVM_LOW)
    
    fd = $fopen(hex_path, "r");
    if (fd == 0) begin
        `uvm_fatal(get_type_name(), $sformatf("Cannot open hex file: %s", hex_path))
    end
    
    base_addr = 32'h0000_0000;  // Extended Linear Address base
    
    // Parse Intel HEX format line by line
    while (!$feof(fd)) begin
        void'($fgets(line, fd));
        
        // Skip empty lines or non-record lines
        if (line.len() < 11 || line[0] != ":") continue;
        
        // Parse record header: :BBAAAATTHHHH...CC
        // BB=byte_count (2 hex), AAAA=address (4 hex), TT=type (2 hex)
        void'($sscanf(line.substr(1,2), "%h", byte_count));
        void'($sscanf(line.substr(3,6), "%h", offset_addr));
        void'($sscanf(line.substr(7,8), "%h", record_type));
        
        case (record_type)
            8'h00: begin  // Data record
                // Process bytes in groups of 4 (little-endian word assembly)
                for (int i = 0; i < byte_count; i += 4) begin
                    data = 32'h0000_0000;
                    
                    // Assemble 4 bytes into 32-bit word (little-endian)
                    for (int j = 0; j < 4; j++) begin
                        if (i+j < byte_count) begin
                            string byte_str = line.substr(9 + (i+j)*2, 10 + (i+j)*2);
                            void'($sscanf(byte_str, "%h", byte_data));
                            data |= (byte_data << (j*8));
                        end
                    end
                    
                    // Calculate full address
                    bit [31:0] full_addr = base_addr + offset_addr + i;
                    
                    // Apply address translation if enabled
                    if (translate_addr) begin
                        full_addr = full_addr - 32'h8000_0000;
                    end
                    
                    // Validate address range (8KB BRAM = 0x0000-0x1FFF)
                    if (full_addr < 32'h0000_2000) begin
                        word_addr = full_addr[12:2];
                        
                        // Direct backdoor write to BRAM
                        $root.rv32i_tb_top.dut.vexriscv_inst.mem_crossbar.blockram_inst.mem[word_addr] = data;
                        
                        bytes_loaded += 4;
                        
                        `uvm_info(get_type_name(), 
                            $sformatf("Loaded: mem[%0d] = 0x%08X (from hex addr 0x%08X)", 
                                      word_addr, data, full_addr), 
                            UVM_HIGH)
                    end else begin
                        `uvm_warning(get_type_name(), 
                            $sformatf("Address 0x%08X out of range, skipping", full_addr))
                    end
                end
            end
            
            8'h01: begin  // EOF record
                `uvm_info(get_type_name(), "End of hex file reached", UVM_MEDIUM)
                break;
            end
            
            8'h04: begin  // Extended Linear Address (upper 16 bits)
                string addr_high_str = line.substr(9, 12);
                bit [15:0] addr_high;
                void'($sscanf(addr_high_str, "%h", addr_high));
                base_addr = {addr_high, 16'h0000};
                `uvm_info(get_type_name(), 
                    $sformatf("Extended address base: 0x%08X", base_addr), 
                    UVM_MEDIUM)
            end
            
            default: begin
                `uvm_warning(get_type_name(), 
                    $sformatf("Unsupported record type: 0x%02X, skipping", record_type))
            end
        endcase
    end
    
    $fclose(fd);
    
    `uvm_info(get_type_name(), 
        $sformatf("Hex file loaded successfully: %0d bytes written to BRAM", bytes_loaded), 
        UVM_LOW)
endtask
```

**検証手順**:

1. **Unit Test** (単一テスト実行):
   ```powershell
   .\scripts\run_test.ps1 vexriscv_alu_test -Verbosity UVM_HIGH
   ```
   - ログで "Loaded: mem[...]" メッセージを確認
   - CPU HALTEDエラーが消えることを確認
   - UVM_ERROR = 0 を確認

2. **Integration Test** (失敗していた4テスト):
   ```powershell
   .\scripts\run_regression.ps1 -Tests vexriscv_alu_test,vexriscv_memory_access_test,vexriscv_wb_bypass_test,vexriscv_dbus_access_test
   ```
   - 4/4 tests PASS を確認

3. **Full Regression** (全Stage 1テスト):
   ```powershell
   .\scripts\run_regression.ps1 -Stage 1
   ```
   - 10/10 tests PASS を確認

---

### Option B: Long-term Solution (UART-Based Verification) 🔮

**Approach**: UART debug interfaceを使ったプロトコルベースのメモリロード

**利点**:
- ✅ 設計意図に合致（test plan参照）
- ✅ より現実的（実際のデバッグワークフローを反映）
- ✅ Hardware-in-the-Loop テスト可能

**欠点**:
- ❌ 大規模開発（3-5日）
- ❌ UART agent実装必要
- ❌ 遅いシミュレーション（プロトコルオーバーヘッド）
- ❌ 複雑なデバッグパス

**推奨**: Stage 1テスト安定後のPhase 2で実施

---

## Implementation Plan

### Phase 1: Quick Fix (Option A) - **THIS ISSUE**

**Tasks**:

1. ✅ **Implement `load_memory_backdoor()` in vexriscv_base_test.sv**
   - Intel HEX parser (lines ~50-80)
   - Address translation support (0x80000000 → 0x00000000)
   - Error handling for file I/O
   - Support record types: 0x00 (data), 0x01 (EOF), 0x04 (extended address)
   
2. ✅ **Validate with failing tests**
   - vexriscv_alu_test: Verify ALU results correct
   - vexriscv_memory_access_test: Verify LW/SW operations
   - vexriscv_wb_bypass_test: Verify bypass timing
   - vexriscv_dbus_access_test: Verify byte/halfword accesses
   
3. ✅ **Run full Stage 1 regression**
   - Target: 10/10 tests PASS
   - Generate regression report
   - Update documentation

**Acceptance Criteria**:
- [ ] All 4 previously failing tests now PASS
- [ ] No new test failures introduced
- [ ] UVM_ERROR count = 0 for all Stage 1 tests
- [ ] Regression runtime < 2 minutes total
- [ ] Log files show "Hex file loaded successfully" messages

**Estimated Effort**: 2-3 hours (implementation + validation)

---

### Phase 2: UART Migration (Option B) - **FUTURE ISSUE**

**Scope**:
- UART-based memory loading protocol
- Debug register interface for CPU control
- Updated test base class architecture
- Migration guide for existing tests

**Priority**: Medium (after Stage 1 stabilization)

---

## Testing Strategy

### Before Fix (Current State)

```powershell
PS> .\scripts\run_regression.ps1 -Stage 1
Total: 10, Passed: 6, Failed: 4

Failed Tests:
- vexriscv_alu_test (UVM_ERROR: 2)
- vexriscv_memory_access_test (UVM_ERROR: 1)
- vexriscv_wb_bypass_test (UVM_ERROR: 1)
- vexriscv_dbus_access_test (UVM_ERROR: 5)
```

### After Fix (Target)

```powershell
PS> .\scripts\run_regression.ps1 -Stage 1
Total: 10, Passed: 10, Failed: 0

All tests PASS ✅
```

### Expected Test Results

| Test | Current | After Fix | Notes |
|------|---------|-----------|-------|
| vexriscv_regfile_test | ✅ PASS | ✅ PASS | Already working |
| vexriscv_alu_test | ❌ ERROR:2 | ✅ PASS | x30=0x80000098 ✓ |
| vexriscv_pipeline_flow_test | ✅ PASS | ✅ PASS | Already working |
| vexriscv_ibus_fetch_test | ✅ PASS | ✅ PASS | Already working |
| vexriscv_ex_bypass_test | ✅ PASS | ✅ PASS | Already working |
| vexriscv_mem_bypass_test | ✅ PASS | ✅ PASS | Already working |
| vexriscv_load_use_stall_test | ✅ PASS | ✅ PASS | Already working |
| vexriscv_wb_bypass_test | ❌ ERROR:1 | ✅ PASS | Cycle count correct |
| vexriscv_memory_access_test | ❌ ERROR:1 | ✅ PASS | x11=0x12345678 ✓ |
| vexriscv_dbus_access_test | ❌ ERROR:5 | ✅ PASS | Byte/halfword/word OK |

---

## Documentation Updates

**Required**:
1. [sim/uvm/sv/vexriscv_base_test.sv](../sim/uvm/sv/vexriscv_base_test.sv) - Implementation
2. [docs/vexriscv_test_quickstart.md](../docs/vexriscv_test_quickstart.md) - Updated usage
3. [docs/known_issues.md](../docs/known_issues.md) - Remove after fix
4. [sim/tests/NEW_TEST_GUIDE.md](../sim/tests/NEW_TEST_GUIDE.md) - Hex loading workflow

**Optional**:
- Add code comments explaining Intel HEX format
- Create `docs/intel_hex_format.md` reference guide

---

## Dependencies

**Required Files**:
- ✅ `tools/vexriscv_hex_loader.py` (exists, reference implementation)
- ✅ `generated/asm/vexriscv/*.hex` (test programs)
- ✅ `sim/uvm/sv/vexriscv_base_test.sv` (edit target)

**No External Dependencies**:
- Pure SystemVerilog implementation
- No DPI-C required
- No Python runtime during simulation

---

## Risks & Mitigation

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Intel HEX parsing bugs | High | Medium | Thorough unit testing with known-good hex files |
| Address alignment issues | High | Low | Validate word alignment (addr[1:0] == 2'b00) |
| File path resolution | Medium | Low | Use absolute paths in test configuration |
| Memory overflow | High | Low | Bounds checking in loader (8KB BRAM limit) |
| Endianness errors | High | Medium | Reference VexRiscv byte ordering specification |

---

## References

**Related Issues**:
- Issue #18 - DBus Store-Load Stale Data (fixed, revealed this gap)
- Issue #24 - LED UART Test Failure (related, different root cause)

**Documentation**:
- [docs/vexriscv_test_plan.md](../docs/vexriscv_test_plan.md) - Test architecture
- [docs/issue18_fix_review.md](../docs/issue18_fix_review.md) - Previous backdoor usage
- [docs/vexriscv_test_quickstart.md](../docs/vexriscv_test_quickstart.md) - Test execution guide

**Code Locations**:
- [sim/uvm/sv/vexriscv_base_test.sv#L167](../sim/uvm/sv/vexriscv_base_test.sv#L167) - Stub implementation
- [sim/uvm/sv/vexriscv_base_test.sv#L397](../sim/uvm/sv/vexriscv_base_test.sv#L397) - Working write_memory_backdoor()
- [tools/vexriscv_hex_loader.py](../tools/vexriscv_hex_loader.py) - Python reference

**Regression Logs**:
- `sim/exec/logs/vexriscv_alu_test_20260201_174445.log` - Example failure
- `sim/exec/logs/*_20260201_1746*.log` - Latest regression results

---

## Success Metrics

**Quantitative**:
- ✅ 10/10 Stage 1 tests PASS
- ✅ 0 UVM_ERROR across all tests
- ✅ Regression runtime < 2 minutes
- ✅ Code coverage >90% for hex loader

**Qualitative**:
- ✅ No test modifications required (base class fix only)
- ✅ Clear log messages for debugging
- ✅ Maintainable implementation (<100 lines)
- ✅ Reusable for future VexRiscv tests

---

**Created**: 2026-02-01  
**Last Updated**: 2026-02-01  
**Status**: 🔴 Open - Ready for implementation
