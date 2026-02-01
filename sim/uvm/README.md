# AXIUART Simplified UVM Environment (UBUS Style)

## 概要

UBUSリファレンス実装を参考に、AXIUART UVM環境を大幅に簡素化しました。

## ディレクトリ構造

```
sim/
├── tests/                       # テスト定義 (新構造: 2024-12リファクタリング)
│   ├── axiuart_test_pkg.sv     # テストパッケージ
│   ├── axiuart_base_test.sv    # ベーステスト
│   ├── axiuart_basic_test.sv   # 基本テスト
│   ├── axiuart_reset_test.sv   # リセットテスト
│   └── axiuart_reg_rw_test.sv  # レジスタR/Wテスト
│
└── uvm/
    ├── sv/                      # すべてのUVMコンポーネント (UBUSスタイル)
    │   ├── axiuart_pkg.sv       # メインパッケージ (1ファイル)
    │   ├── uart_transaction.sv  # トランザクション
    │   ├── uart_monitor.sv      # UARTモニター
    │   ├── uart_driver.sv       # UARTドライバー
    │   ├── uart_sequencer.sv    # UARTシーケンサー
    │   ├── uart_agent.sv        # UARTエージェント
    │   ├── axi4_lite_monitor.sv # AXIモニター (観測のみ)
    │   ├── axiuart_scoreboard.sv# スコアボード
    │   └── axiuart_env.sv       # トップ環境
    │
    └── tb/                      # テストベンチ
        ├── axiuart_tb_top.sv    # トップモジュール
        └── dsim_config.f        # DSIMファイルリスト
```

## 主な簡素化ポイント

### 1. ファイル数の削減
- **旧環境**: 49個のSystemVerilogファイル (agents/, env/, scoreboard/, analysis/ などに分散)
- **新環境**: 14個のファイル (sv/, tb/, tests/ に整理)
  - UVMコンポーネント: 10個 (sv/)
  - テストベンチ: 1個 (tb/)
  - テスト定義: 4個 (tests/ - 2024-12リファクタリング)

### 2. 削除したコンポーネント

#### 重複スコアボード
- `uart_axi4_enhanced_scoreboard.sv` → 削除
- `uart_axi4_scoreboard.sv` → 統合
- `correlation_engine.sv` → 統合

#### 重複カバレッジ
- `uart_axi4_phase3_coverage.sv` → 削除
- `system_coverage.sv` → 削除  
- `axiuart_cov_pkg.sv` → 削除

#### 過剰な分離
- `uart_axi4_predictor.sv` → 削除
- `uart_axi4_error_detector.sv` → 削除
- `bridge_status_monitor.sv` → 削除
- `independent_verification_monitor.sv` → 削除

#### 設定クラス
- `uart_axi4_env_config.sv` → 削除 (シンプルなVIF設定のみ使用)

### 3. トランザクションの簡素化
- **旧**: 158行 (20個以上のフィールド、複雑な制約)
- **新**: 47行 (基本フィールドのみ)

### 4. モニターの簡素化
- **旧**: 890行 (RX/TXの複雑なステートマシン)
- **新**: 78行 (シンプルなフレーム収集)

### 5. ドライバーの簡素化
- **旧**: 351行 (baud rate動的変更、reset処理、複雑なフロー制御)
- **新**: 98行 (8N1フォーマットの基本送信)

### 6. 環境の簡素化
- **旧**: 191行 (複数のanalysisコンポーネント、複雑な接続)
- **新**: 68行 (Agent + Monitor + Scoreboardのみ)

## レジスタマップ管理 (2024-12追加)

### 自動生成レジスタパッケージの使用

UVMテストでは、`axiuart_reg_pkg.sv`（自動生成）のレジスタ定数を使用します。

**使用方法:**
```systemverilog
// sim/tests/axiuart_reg_rw_test.sv
import axiuart_reg_pkg::*;  // 生成されたパッケージをインポート

class axiuart_reg_rw_test extends axiuart_base_test;
  task main_phase(uvm_phase phase);
    // 生成された定数を使用（ハードコード禁止）
    uart_seq.write_then_read(REG_TEST_0, 32'h11111111);  // ✓ 正しい
    uart_seq.write_then_read(32'h1020, 32'h11111111);    // ✗ 避ける
  endtask
endclass
```

**利点:**
- RTL、UVM、Pythonで同一のレジスタアドレスを保証
- JSON編集→再生成で全レイヤーが自動的に更新
- アドレスミスマッチのリスクを排除

**コンパイル順序:**
```
dsim_config.f:
  rtl/register_block/axiuart_reg_pkg.sv  # 最初にコンパイル
  rtl/register_block/Register_Block.sv   # パッケージをインポート
  sim/tests/*.sv                          # テストでもインポート
```

**ソース:** `register_map/axiuart_registers.json` (Single Source of Truth)

## UVM標準パターンの実装 (2024-12更新)

### 1. Mailboxベースの応答メカニズム

**課題**: UARTのread操作では、コマンド送信後にデバイスからの応答を待つ必要がある。

**解決策**: SystemVerilogのmailboxを使用したDriver-Monitor間通信

```systemverilog
// データフロー:
Test Sequence
  ↓ read_reg(addr, data)
  ↓ get_response() を呼び出し
  ↓
Driver (送信 + 待機)
  ↓ UART送信
  ↓ mailbox.get(rsp) ← ★応答待機★
  ←─┐
     │
Monitor (別スレッド)
  ↓ UART受信
  ↓ mailbox.put(rsp) → Driverに通知
  └──┘
  ↓
Driver
  ↓ put_response(rsp) → Sequenceに返却
  ↓
Sequence
  ↓ 正しいデータ取得！
```

**実装箇所:**
- `sim/uvm/sv/uart_driver.sv` - mailbox初期化、応答待機
- `sim/uvm/sv/uart_monitor.sv` - 応答検出、mailbox送信
- `sim/uvm/sv/uart_agent.sv` - mailbox参照の接続
- `sim/uvm/sv/uart_reg_sequences.sv` - get_response()実装

**効果:**
- タイミング依存の問題を完全に解決
- 全テストで自動的に正しい応答を取得
- ハードコードされた遅延（#2us, #3us等）が不要に

### 2. UBUS参考ポイント

1. **1パッケージファイル**: すべてのコンポーネントを`axiuart_pkg.sv`に集約
2. **シンプルな階層**: Agent → Driver/Monitor/Sequencer → Env
3. **VIF設定**: `uvm_config_db`でVirtual Interfaceを渡すだけ
4. **スコアボード**: FIFOベースの単純な比較
5. **テスト**: Sequence→Agent→Driverの明確なフロー
6. **応答メカニズム**: Mailbox + get_response()パターン

## テスト構造の改善 (2024-12リファクタリング)

### 旧構造の問題点
- 単一ファイル(`axiuart_test_lib.sv`)に全テストクラスが混在
- 新規テスト追加時にファイルが肥大化
- 並行開発でコンフリクトリスクが高い

### 新構造 (sim/tests/)
- **1テスト = 1ファイル** の明確な責任分離
- `axiuart_test_pkg.sv`で統合管理
- 拡張性・保守性・並行開発性が大幅向上

## 既存環境との比較

| 項目 | 旧環境 | 新環境 (UBUS Style + 2024-12改善) |
|------|--------|----------------------------------|
| ファイル数 | 49個 | 14個 (UVM:10 + TB:1 + Tests:4) |
| 総行数 | ~5000行 | ~800行 |
| ディレクトリ数 | 10個 | 3個 (sv/, tb/, tests/) |
| テスト構造 | 単一ファイル | 個別ファイル (拡張性向上) |
| スコアボード | 3個 | 1個 |
| カバレッジ | 3個 | 0個 (必要に応じて追加) |
| 設定クラス | 複雑 | なし (VIFのみ) |

## 使用方法

### PowerShell スクリプト経由での実行（推奨）
```powershell
# 標準ワークフロー
.\scripts\run_test.ps1 axiuart_basic_test -Verbosity UVM_MEDIUM

# CPU検証テスト
.\scripts\run_test.ps1 axiuart_cpu_mem_simple_rw_test -Verbosity UVM_MEDIUM
```

### 直接コンパイル・実行
```bash
# コンパイル
dsim -work work \
     +incdir+sv \
     sv/axiuart_pkg.sv \
     tb/axiuart_tb_top.sv \
     tb/axiuart_basic_test.sv
```

### 実行
```bash
dsim -work work \
     +UVM_TESTNAME=axiuart_basic_test \
     tb_top
```

## CPU検証のアプローチ (2024-12追加)

### 直接階層アクセスを採用した理由

CPU検証では、UVMインターフェース層を使用せず、**直接階層アクセス**を採用しています。

```systemverilog
// 例: axiuart_cpu_logic_test.sv
task read_trace_buffer_direct(input int index, output bit [31:0] data);
    data = axiuart_tb_top.dut.cpu_inst.trace_buffer[index[7:0]];
endtask
```

**採用理由:**
1. **検証対象が内部状態**: トレースバッファは外部インターフェースではなく、CPU内部のデバッグ機能
2. **UVMオーバーヘッド回避**: インターフェース/モニター/予測器レイヤーは不要
3. **高速実行**: 17テストが約200秒で完了（UART経由では900秒以上）
4. **シンプルさ**: テストコードが明確で保守しやすい
5. **プロダクション実績**: 17/17 ALU演算テスト成功（2025-12-27検証済）

**削除したUVMコンポーネント:**
- `cpu_trace_monitor.sv` - 不要なモニタークラス
- `cpu_trace_predictor.sv` - 不要な予測器クラス  
- `td4cpu_trace_if.sv` - 不要なインターフェース定義

**適用ガイドライン:**
- 外部インターフェース（UART, AXI）→ UVM標準アプローチ
- 内部デバッグ機能（トレースバッファ）→ 直接階層アクセス

### トレースバッファ仕様
- **容量**: 256エントリ
- **フォーマット**: `{instruction[31:16], result[15:0]}`
- **トリガー**: ALU writeback または flag update
- **アクセス**: `dut.cpu_inst.trace_buffer[index]`
- **ポインタ**: `dut.cpu_inst.trace_write_ptr`

## 今後の拡張

必要に応じて以下を追加:
1. **カバレッジ**: UBUSの`ubus_example_scoreboard.sv`を参考
2. **複数シーケンス**: `seq_lib`パターン
3. **設定**: 必要最小限のconfigクラス

## 削除対象の旧環境ファイル

以下のディレクトリは削除推奨:
- `sim/uvm/analysis/`
- `sim/uvm/components/`
- `sim/uvm/scoreboard/` (重複スコアボード)
- `sim/uvm/env/` (重複ファイル)

保持推奨:
- `rtl/interfaces/uart_if.sv` (interface定義)
- `rtl/interfaces/axi4_lite_if.sv` (interface定義)

## 参考文献
- UBUSリファレンス: `reference/Accellera/uvm/distrib/examples/integrated/ubus`
- UVM Cookbook: Simple agent pattern
