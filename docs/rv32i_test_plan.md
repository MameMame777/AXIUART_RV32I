# RV32I 命令テストプラン

**作成日**: 2026-01-14  
**目的**: RV32I命令セットの系統的検証  
**戦略**: 依存関係の少ない命令から順にテストし、各テストは独立して実行可能にする

---

## 📊 全体進捗

| カテゴリ | 実装済 | 計画中 | 未着手 | 合計 |
|---------|--------|--------|--------|------|
| Phase 1: 基本命令 | 1 | 1 | 0 | 2 |
| Phase 2: レジスタ演算 | 0 | 3 | 0 | 3 |
| Phase 3: メモリアクセス | 1 | 1 | 1 | 3 |
| Phase 4: 制御フロー | 0 | 0 | 3 | 3 |
| Phase 5: システム命令 | 0 | 0 | 2 | 2 |
| **合計** | **2** | **5** | **6** | **13** |

**進捗率**: 15.4% (2/13)

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

## Phase 1: 基本命令（レジスタライトバック確認）

### Test 1.1: 即値演算基礎 `rv32i_basic_imm_test`

**ステータス**: ✅ **実装完了** - 2026-01-14  
**作成日**: 2026-01-14  

**目的**: レジスタファイルへの書き込みとフォワーディングの基本動作確認

**カバーする命令**: ADDI, EBREAK

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

**ステータス**: 🟡 未着手  

**目的**: LUI/AUIPCの動作確認

**カバーする命令**: LUI, AUIPC, ADDI, EBREAK

**依存関係**: Test 1.1 ✅

---

## Phase 2: レジスタ間演算

### Test 2.1: 算術論理演算 `rv32i_alu_basic_test`
**ステータス**: 🟡 未着手  
**依存関係**: Test 1.1

### Test 2.2: 比較命令 `rv32i_compare_test`
**ステータス**: 🟡 未着手  
**依存関係**: Test 1.1

### Test 2.3: シフト命令 `rv32i_shift_test`
**ステータス**: 🟡 未着手  
**依存関係**: Test 1.2

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

**合計**: 3/44 命令 (6.8%)

### 算術演算 (0/13)
- [ ] ADD, SUB, ADDI 🔴
- [ ] SLT, SLTU, SLTI, SLTIU
- [ ] AND, OR, XOR, ANDI, ORI, XORI

### シフト演算 (0/6)
- [ ] SLL, SRL, SRA, SLLI, SRLI, SRAI

### メモリ (3/8)
- [x] SW, SH, SB ✅
- [ ] LW, LH, LHU, LB, LBU

### 分岐 (0/6)
- [ ] BEQ, BNE, BLT, BGE, BLTU, BGEU

### ジャンプ (0/2)
- [ ] JAL, JALR

### 上位即値 (0/2)
- [ ] LUI, AUIPC

### システム (0/7)
- [ ] ECALL, EBREAK, CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI

---

## 📅 実装スケジュール

### Week 1 (2026-01-14 ~ 2026-01-20) - Critical Path
- [ ] Issue #1 修正
- [ ] Test 1.1 実装・実行
- [ ] Test 1.2 実装・実行
- [ ] Test 3.2 実装・実行

### Week 2-4
Phase 2-5の順次実装

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
