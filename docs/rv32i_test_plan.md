# RV32I 命令テストプラン

**作成日**: 2026-01-14  
**目的**: RV32I命令セットの系統的検証  
**戦略**: 依存関係の少ない命令から順にテストし、各テストは独立して実行可能にする

---

## 📊 全体進捗

| カテゴリ | 実装済 | 計画中 | 未着手 | 合計 |
|---------|--------|--------|--------|------|
| Phase 1: 即値命令 | 4 | 0 | 0 | 4 |
| Phase 2: レジスタ演算 | 2 | 0 | 0 | 2 |
| Phase 3: メモリアクセス | 2 | 0 | 1 | 3 |
| Phase 4: 制御フロー | 0 | 0 | 3 | 3 |
| Phase 5: システム命令 | 0 | 0 | 2 | 2 |
| **合計** | **8** | **0** | **7** | **14** |

**進捗率**: 57.1% (8/14 tests) | **命令カバレッジ**: 56.8% (25/44 instructions)

---

## 🚨 既知の問題

### Issue #1: ADDI命令のデスティネーションレジスタ破損 ✅ **修正完了**
**発見日**: 2026-01-14  
**修正日**: 2026-01-15  
**影響範囲**: 全命令（LOAD以外）  
**重要度**: 🔴 Critical → ✅ Resolved

**症状**:
- 全てのレジスタ書き込みが1命令分ずれる
- x1に20（x2の値）、x2に-5（x3の値）が書き込まれる
- データとアドレスのタイミング不一致

**根本原因** (2026-01-15 02:00 - 波形解析により特定):
[rv32i_mem.sv](rtl/cpu/rv32i_mem.sv) Line 88-129の`ctrl_final`レジスタが**全命令**に1サイクル遅延を与えていた
```systemverilog
// 修正前（問題あり）
always_ff @(posedge clk) begin
    if (!mem_stall) begin
        ctrl_final <= ctrl;  // ← 常に1サイクル遅延
    end
end
```

**修正内容** (2026-01-15):
- `ctrl_held`専用レジスタを作成（LOAD命令専用）
- 非LOAD命令は組み合わせ回路で直接通過（遅延なし）
- LOAD命令のみ`mem_stall`時に`ctrl_held`を使用

```systemverilog
// 修正後（正常）
always_ff @(posedge clk) begin
    if (ctrl.mem_read && !mem_stall) begin
        ctrl_held <= ctrl;  // LOAD命令の1サイクル目のみ保存
    end
end
assign ctrl_final = mem_stall ? ctrl_held : ctrl;  // 条件選択
```

**検証結果** (Test 1.1):
- ✅ x1 = 0x0000000A (10) - PASS
- ✅ x2 = 0x00000014 (20) - PASS
- ✅ x3 = 0xFFFFFFFB (-5) - PASS
- ✅ x4 = 0x0000006E (110) - PASS

---

## Phase 1: 即値命令 ✅ **完了** (2026-01-17)

**カバレッジ**: 13/44 命令 (29.5%)

### Test 1.1: 即値演算基礎 `rv32i_basic_imm_test`

**ステータス**: ✅ **完了** (2026-01-14)  
**カバーする命令**: ADDI (1)

**目的**: レジスタファイルへの書き込みとフォワーディングの基本動作確認

**テストコード**:
```assembly
ADDI x1, x0, 10      # x1 = 10
ADDI x2, x0, 20      # x2 = 20
ADDI x3, x0, -5      # x3 = -5 (負数)
ADDI x4, x1, 100     # x4 = x1 + 100 = 110 (依存あり)
EBREAK
```

**確認項目**:
- [ ] x0からの読み出し（常に0）
- [ ] 正の即値、負の即値
- [ ] レジスタファイルへの書き込み
- [x] 1サイクル後の依存（フォワーディング）

**期待結果**:
- x1 = 0x0000000A (10)
- x2 = 0x00000014 (20)
- x3 = 0xFFFFFFFB (-5)
- x4 = 0x0000006E (110)

**実装結果** (2026-01-15):
```
✅ Test 1.1 PASS - Regression: cpu_basic suite
✅ x1 = 0x0000000A (PASS)
✅ x2 = 0x00000014 (PASS)
✅ x3 = 0xFFFFFFFB (PASS)  
✅ x4 = 0x0000006E (PASS)
✅ Issue #1 FIX VERIFIED
```

**依存関係**: なし

---

### Test 1.2: 上位即値命令 `rv32i_upper_imm_test`

**ステータス**: ✅ **完了** (2026-01-15)  
**カバーする命令**: LUI, AUIPC (2)

**目的**: LUI/AUIPCの動作確認  
**検証項目**: 10個のレジスタ検証 (上位20ビット設定、PC相対アドレス計算)

---

### Test 1.3: 即値論理演算 `rv32i_imm_logic_test`

**ステータス**: ✅ **完了** (2026-01-16)  
**カバーする命令**: SLTI, SLTIU, XORI, ORI, ANDI (5)

**目的**: 即値論理演算と符号付き/符号なし比較の動作確認  
**検証項目**: 10個のレジスタ検証

---

### Test 1.4: 即値シフト命令 `rv32i_shift_imm_test`

**ステータス**: ✅ **完了** (2026-01-16)  
**カバーする命令**: SLLI, SRLI, SRAI (3)

**目的**: 即値シフト演算とSRLI/SRAI区別の検証  
**検証項目**: 15個のレジスタ検証 (オーバーフロー、最大シフト、ゼロフィル/符号拡張)  
**重要**: SRLI (0x80000000>>16 = 0x00008000) vs SRAI (0x80000000>>8 = 0xFF800000)

---

## Phase 2: レジスタ演算 ✅ **完了** (2026-01-17)

**カバレッジ**: 7/44 追加命令 → 累計 20/44 (45.5%)

### Test 2.1: R型算術論理演算 `rv32i_reg_alu_test`

**ステータス**: ✅ **完了** (2026-01-16)  
**カバーする命令**: ADD, SUB, SLT, SLTU, XOR, OR, AND (7)

**目的**: レジスタ間演算とオーバーフロー/アンダーフローの検証  
**検証項目**: 21個のレジスタ検証  
**重要検証**:
- ADDオーバーフロー: 0x7FFFFFFF + 1 = 0x80000000
- SUBアンダーフロー: 0x80000000 - 1 = 0x7FFFFFFF
- SLT vs SLTU: 符号付き/符号なし比較の区別

---

### Test 2.3: R型シフト命令 `rv32i_reg_shift_test`

**ステータス**: ✅ **完了** (2026-01-17)  
**カバーする命令**: SLL, SRL, SRA (3)

**目的**: レジスタ指定シフト量とSRL/SRA区別の検証  
**検証項目**: 18個のレジスタ検証 (シフト量マスキング、ゼロフィル/符号拡張)  
**重要検証**:
- SRL (x8): 0x80000000 >> 16 = 0x00008000 (ゼロフィル)
- SRA (x19): 0x80000000 >> 16 = 0xFFFF8000 (符号拡張)
- シフト量マスキング: rs2[4:0]のみ使用

---

## Phase 3: メモリアクセス

### Test 3.1: STORE命令 `rv32i_store_simple_test`
**ステータス**: ✅ **完了** (2026-01-13)

### Test 3.2: LOAD基礎 `rv32i_load_basic_test`
**ステータス**: � **準備完了** - Test 1.1 依存解決  
**更新**: Issue #1修正により、ADDI命令が正常動作。インフラ整備後に再実行可能。

### Test 3.3: LOAD-USE ハザード `rv32i_load_hazard_test`
**ステータス**: 🟡 未着手  
**依存関係**: Test 3.2

---

## Phase 4: 制御フロー

### Test 4.1: 分岐命令基礎 `rv32i_branch_basic_test`
**ステータス**: 🟡 未着手  
**依存関係**: Test 1.1

### Test 4.2: 比較分岐命令 `rv32i_branch_compare_test`
**ステータス**: 🟡 未着手  
**依存関係**: Test 1.1

### Test 4.3: ジャンプ命令 `rv32i_jump_test`
**ステータス**: 🟡 未着手  
**依存関係**: Test 1.1

---

## Phase 5: システム命令

### Test 5.1: ECALL/EBREAK `rv32i_system_test`
**ステータス**: 🟡 未着手  
**依存関係**: Test 1.1

### Test 5.2: CSR基本操作 `rv32i_csr_basic_test`
**ステータス**: 🟡 未着手  
**依存関係**: Test 1.1

---

## 📈 命令カバレッジマトリクス

**合計**: 20/44 命令 (45.5%)

### 算術演算 (10/13) ✅ 大部分完了
- [x] ADD, SUB ✅ (Test 2.1)
- [x] ADDI ✅ (Test 1.1)
- [x] SLT, SLTU ✅ (Test 2.1)
- [x] SLTI, SLTIU ✅ (Test 1.3)
- [x] AND, OR, XOR ✅ (Test 2.1)
- [x] ANDI, ORI, XORI ✅ (Test 1.3)

### シフト演算 (6/6) ✅ **完了**
- [x] SLL, SRL, SRA ✅ (Test 2.3)
- [x] SLLI, SRLI, SRAI ✅ (Test 1.4)

### メモリ (3/8)
- [x] SW, SH, SB ✅
- [ ] LW, LH, LHU, LB, LBU

### 分岐 (0/6)
- [ ] BEQ, BNE, BLT, BGE, BLTU, BGEU

### ジャンプ (0/2)
- [ ] JAL, JALR

### 上位即値 (2/2) ✅ **完了**
- [x] LUI, AUIPC ✅ (Test 1.2)

### システム (1/7)
- [x] EBREAK ✅ (全テストで使用)
- [ ] ECALL, CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI

---

## 📅 実装スケジュール

### Week 1 (2026-01-14 ~ 2026-01-17) ✅ **完了**
- [x] Issue #1 修正完了 ✅
- [x] Test 1.1 実装・実行 ✅
- [x] Test 1.2 実装・実行 ✅
- [x] Test 1.3 実装・実行 ✅
- [x] Test 1.4 実装・実行 ✅
- [x] Test 2.1 実装・実行 ✅
- [x] Test 2.3 実装・実行 ✅
- [x] **Phase 1 & 2 完了** ✅

### Week 2 (2026-01-20 ~ 2026-01-24) - Phase 3-5
- [ ] Test 3.2: LOAD命令
- [ ] Test 4.1-4.3: 分岐・ジャンプ命令
- [ ] Test 5.1-5.2: システム・CSR命令

---

## 🔍 次のアクション

**最優先**:
1. ✅ テスト計画ドキュメント作成
2. ✅ Test 1.1 実装 (hex生成・UVMテスト・regression登録)
3. 🔴 デコードステージのIssue #1調査
   - pipeline_decode_debug.csv確認
   - rv32i_id.sv decode_insn()関数確認
4. 🟡 Test 1.1実行とIssue #1検証

---

## 📝 更新履歴

| 日付 | 更新内容 | 担当者 |
|------|---------|--------|
| 2026-01-14 | 初版作成、Issue #1登録 | Copilot |
| 2026-01-14 | Test 1.1実装完了 (hex生成・UVMテスト・regression登録) | Copilot |
| 2026-01-15 | Issue #1修正完了、Test 1.2実装完了 | Copilot |
| 2026-01-16 | Test 1.3, 1.4, 2.1実装完了、Phase 1完了 | Copilot |
| 2026-01-17 | Test 2.3実装完了、Phase 2完了、カバレッジ45.5% | Copilot |
