# 簡素化UVM環境 - 実行状況と対応策

## 作成日
2025-12-07

## 現状サマリー

### ✅ 完了事項
1. **UBUS参照に基づく簡素化環境構築**
   - 14ファイル構成（既存49ファイルから71%削減）
   - ディレクトリ: `sim/uvm/`
   - パッケージ: `axiuart_pkg.sv` (UBUS単一パッケージパターン)
   - テスト: `axiuart_basic_test` (Reset + Write sequences)

2. **構造的問題の修正**
   - ❌ `include "axiuart_pkg.sv"` → ✅ `import axiuart_pkg::*`
   - ❌ テストクラスがパッケージ外 → ✅ パッケージに統合
   - ❌ 設定ファイルで二重定義 → ✅ 整理完了

3. **環境設定スクリプト作成**
   - `setup_simplified_env.ps1` - PowerShell環境初期化
   - `run_simplified_test.py` - Python実行ラッパー（環境変数設定込み）
   - `simplified_config.py` - MCP設定拡張

### ✅ 過去の問題 (すべて解決済み)

#### **DSIM実行時クラッシュ (Exit Code: 0xC0000135)** ✅ 解決済み

**原因:** subprocess環境変数PATHが未継承

**解決策:** 環境変数明示的設定

#### **UART Monitor無限ループ** ✅ 解決済み

**原因:** 同期待ちロジックでの即リターン

**解決策:** do-while ループに変更、ログレベル調整

## 次のアクション（優先順位順）

### 1. 最小限テストベンチでの検証 [HIGH]
```systemverilog
// minimal_tb.sv - RTL不要の最小テスト
`timescale 1ns/1ps
import uvm_pkg::*;

module minimal_tb;
    initial begin
        run_test();
    end
endmodule
```

**目的:** DSIM起動自体が問題かどうか切り分け

**手順:**
```powershell
cd E:\Nautilus\workspace\fpgawork\AXIUART_\sim\uvm_simplified\tb
dsim -uvm 1.2 -timescale 1ns/1ps minimal_tb.sv -top minimal_tb -work work
```

### 2. 既存環境との差分比較 [HIGH]
- `sim/uvm/config/dsim_config.f` (旧環境・削除済み) vs `sim/uvm/tb/dsim_config.f`
- 特に`+define`、`+incdir`の順序と内容
- インターフェースファイルの指定方法

### 3. パッケージコンパイルの分離 [MEDIUM]
簡素化版を2段階コンパイルに変更:
```powershell
# Step 1: パッケージのみコンパイル
dsim -uvm 1.2 -work work -f pkg_only.f -genimage pkg_image

# Step 2: トップモジュール追加
dsim -uvm 1.2 -work work -image pkg_image -f tb_only.f -top axiuart_tb_top
```

### 4. MCPサーバー統合 [LOW]
現時点では既存環境が安定動作しているため、簡素化版のMCP統合は後回し。
まず手動実行での成功を優先。

## 既存環境の活用方針

**重要:** 簡素化版が完全動作するまで、既存環境 (`sim/uvm/`) を維持・使用する。

### 既存環境での作業継続
```powershell
# コンパイルのみ
python mcp_server/mcp_client.py --workspace "e:\Nautilus\workspace\fpgawork\AXIUART_" \
    --tool compile_design_only --test-name uart_axi4_basic_test --verbosity UVM_LOW

# フルシミュレーション
python mcp_server/mcp_client.py --workspace "e:\Nautilus\workspace\fpgawork\AXIUART_" \
    --tool run_uvm_simulation_batch --test-name uart_axi4_basic_test \
    --verbosity UVM_MEDIUM --waves
```

## ファイル構成

### 簡素化環境 (`sim/uvm_simplified/`)
```
sim/uvm_simplified/
├── sv/                          # UVMコンポーネント
│   ├── axiuart_pkg.sv          # メインパッケージ（全include統合）
│   ├── uart_transaction.sv
│   ├── uart_monitor.sv
│   ├── uart_driver.sv
│   ├── uart_sequencer.sv
│   ├── uart_agent.sv
│   ├── axi4_lite_monitor.sv
│   ├── axiuart_scoreboard.sv
│   └── axiuart_env.sv
├── tb/                          # テストベンチ
│   ├── axiuart_basic_test.sv   # テストクラス（パッケージに統合済み）
│   ├── axiuart_tb_top.sv       # トップモジュール
│   └── dsim_config.f           # DSIM設定ファイル
├── setup_simplified_env.ps1    # 環境初期化スクリプト
└── launch_test.py              # テストランチャー（暫定）
```

### 設定ファイル (`mcp_server/`)
```
mcp_server/
├── simplified_config.py        # 簡素化版設定
├── run_simplified_test.py      # 簡素化版実行スクリプト
└── client_api.py               # 既存MCP API（環境変数設定含む）
```

## デバッグコマンド集

### 環境確認
```powershell
# 環境変数表示
$env:DSIM_HOME
$env:PATH -split ';' | Select-String 'DSim'

# DSIM実行確認
& "C:\Program Files\Altair\DSim\2025.1\bin\dsim.exe" -version
```

### 設定ファイル検証
```powershell
cd E:\Nautilus\workspace\fpgawork\AXIUART_\sim\uvm_simplified\tb

# 全パス存在確認
Get-Content dsim_config.f | ForEach-Object {
    if ($_ -match '^\.\./') {
        $path = Join-Path (Get-Location) $_
        Write-Host "$_ -> $(Test-Path $path)"
    }
}
```

### 手動コンパイル試行
```powershell
# 環境セットアップ
.\setup_simplified_env.ps1

# DSIM実行（詳細出力）
dsim -uvm 1.2 -timescale 1ns/1ps -f dsim_config.f -top axiuart_tb_top \
    +UVM_TESTNAME=axiuart_basic_test -work work -genimage image \
    -l debug.log -verbose
```

## 参考資料

- UBUS参照実装: `reference/Accellera/uvm/distrib/examples/integrated/ubus/`
- 既存動作環境: `sim/uvm/` (49ファイル、複雑な構成だが動作確認済み)
- DSIM 2025.1 ドキュメント: `C:\Program Files\Altair\DSim\2025.1\doc\`

## 結論

簡素化版UVM環境は**構造的には正しく構築済み**ですが、DSIM実行時にクラッシュする問題が未解決です。

**推奨対応:**
1. ✅ 既存環境で開発継続（安定動作中）
2. 🔍 最小限テストベンチでDSIM動作確認
3. 🔍 設定ファイル差分の詳細比較
4. ⏳ 簡素化版の完全動作確認後にMCP統合

**破棄しない:** 既存複雑環境は簡素化版が完全動作するまで保持。
