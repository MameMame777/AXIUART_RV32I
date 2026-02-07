# Plan: Issue #49 - regression_tests.json "full" スイートの更新

- **Issue**: #49
- **Priority**: P1-Critical
- **Date**: 2026-02-07
- **Estimated effort**: 2-3 hours

## 背景

`sim/regression_tests.json` の "full" スイートが実態と乖離している。
"full" には10テスト（うち1つはゴースト）しか含まれていないが、プロジェクトには37のアクティブテストファイルが存在する。

## 調査結果

### 発見された問題

| # | 問題 | 深刻度 |
|---|------|--------|
| 1 | `rv32i_load_use_stall_test` が "full" に登録されているが、対応する `.sv` ファイルが存在しない（ゴーストテスト）。`vexriscv_load_use_stall_test` の誤記と推測 | High |
| 2 | `run_regression.ps1` が `regression_tests.json` を一切読み込んでいない。ハードコードの `$Stage1Tests` のみ使用。`-Suite` パラメータも存在しない | Critical |
| 3 | スクリプトの `$Stage1Tests`（10テスト、`vexriscv_alu_test` 含む）と JSON の `vexriscv_stage1`（9テスト、`vexriscv_alu_test` なし）が不一致 | Medium |
| 4 | `documentation.active_test_count` が 10 のまま（実際は 37） | Medium |
| 5 | `test_categories` が全テストをカバーしていない（VexRiscv、LED、Store 系が未登録） | Medium |

### アクティブテスト一覧（37テスト）

**AXIUART (4):**
- `axiuart_reset_test`
- `axiuart_basic_test`
- `axiuart_reg_rw_test`
- `axiuart_cpu_simple_mem_test`

**RV32I (21):**
- `rv32i_basic_test`, `rv32i_basic_imm_test`, `rv32i_upper_imm_test`
- `rv32i_imm_logic_test`, `rv32i_shift_imm_test`
- `rv32i_reg_alu_test`, `rv32i_reg_shift_test`
- `rv32i_load_simple_test`, `rv32i_store_simple_test`
- `rv32i_debug_load_test`, `rv32i_ebreak_simple_test`
- `rv32i_breakpoint_test`, `rv32i_bp_vs_ebreak_test`
- `rv32i_wb_forward_timing_test`, `rv32i_comprehensive_test`
- `rv32i_exception_handler_test`, `rv32i_perfcount_test`
- `rv32i_minimal_led_test`, `rv32i_led_mmio_simple_test`
- `rv32i_led_complex_pattern_test`, `rv32i_led_fast_pattern_test`

**VexRiscv (12):**
- `vexriscv_regfile_test`, `vexriscv_alu_test`, `vexriscv_pipeline_flow_test`
- `vexriscv_ibus_fetch_test`, `vexriscv_memory_access_test`
- `vexriscv_ex_bypass_test`, `vexriscv_mem_bypass_test`, `vexriscv_wb_bypass_test`
- `vexriscv_load_use_stall_test`, `vexriscv_dbus_access_test`
- `vexriscv_smoke_test`, `vexriscv_led_uart_test`

**除外（TD4 アーカイブ）:**
- `axiuart_cpu_memory_test`, `axiuart_cpu_debug_test`, `axiuart_cpu_mmio_led_test`, `axiuart_cpu_br_test`

## 実装方針

### Step 1: `sim/regression_tests.json` 更新

- "full" スイートを37テスト全てで再構成
- ゴーストテスト `rv32i_load_use_stall_test` を削除
- `test_categories` を全テストカバーに拡大
- `documentation` セクションのメタデータを実数に更新
- テスト順序: AXIUART → RV32I (Phase順) → VexRiscv
- `vexriscv_stage1` スイートは現行の9テストを維持（Stage 1 定義に沿った構成のため）

### Step 2: `scripts/run_regression.ps1` に `-Suite` パラメータ追加

- `param()` に `[string]$Suite = ""` を追加
- テスト選択優先順位:
  1. `-Tests NAME[]` → そのまま実行（既存動作）
  2. `-Suite NAME` → `regression_tests.json` を読み込み、該当スイートのテスト名を抽出
  3. `-Stage N` → `regression_tests.json` の対応スイートにマップ（Stage 1 → `vexriscv_stage1`）
  4. 引数なし → デフォルトで `vexriscv_stage1`（既存動作維持）
- ハードコードの `$Stage1Tests` を削除し、JSON を Single Source of Truth 化
- `disabled: true` のスイートはエラーメッセージで拒否
- ヘルプ出力に `-Suite` オプションと利用可能スイート一覧を追加

### Step 3: `.vscode/tasks.json` 更新

- `DSIM: Run Suite Regression` タスクを追加
- `suiteName` 入力を追加（`smoke`, `full`, `vexriscv_stage1` 等）
- `testName` の選択肢を全37テストに拡大

### Step 4: 検証

- `run_regression.ps1 -Suite full` が37テスト全てを実行すること
- `run_regression.ps1 -Stage 1` が既存動作（VexRiscv Stage 1）を維持すること
- `run_regression.ps1 -Suite td4_archive` がエラーになること
- JSON 内の全テスト名に対応する `.sv` ファイルが存在すること

## 影響範囲

| ファイル | 変更内容 |
|----------|----------|
| `sim/regression_tests.json` | "full" スイート更新、test_categories 拡大、documentation 更新 |
| `scripts/run_regression.ps1` | `-Suite` パラメータ追加、ハードコード削除、JSON 読み込み |
| `.vscode/tasks.json` | 新タスク追加、testName 選択肢拡大 |

## リスク

- `run_regression.ps1` のテスト選択ロジック変更は既存ワークフロー（`-Stage 1`）に影響するため、後方互換性を確保する
- `ConvertFrom-Json` による JSON パースが PowerShell 5.x で動作することを確認（プロジェクトは PowerShell 5.x+ 前提）
