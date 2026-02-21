# UVM + DSim で作る RISC-V 内蔵 UART-AXI4 ブリッジの検証環境

## はじめに

FPGA開発において「RTLを書いたあとの検証」は最も時間がかかる工程のひとつです。本記事では、UART経由でAXI4-Liteレジスタを読み書きできるブリッジIP（AXIUART）に、オープンソースのRISC-V CPU「VexRiscv」を統合したプロジェクトの検証環境構築についてまとめます。

主なトピック：
- **UVM 1.2** によるモジュラー検証環境の設計
- **Altair DSim** のコマンドライン実行とPowerShellによる自動化
- **AXIUART** ブリッジの設計・アーキテクチャ
- **Python** による実機制御ソフトウェア
- レジスタマップの **Single Source of Truth** 設計
- **SystemVerilog Assertions (SVA)** による非侵入的検証

---

## プロジェクト概要

```
AXIUART_RV32I/
├── rtl/          # SystemVerilog RTL (VexRiscv CPU + UART-AXI4ブリッジ)
├── sim/          # UVM検証環境
├── software/     # Python制御ドライバ
├── register_map/ # レジスタ定義 JSON (SSOT)
└── scripts/      # PowerShell実行スクリプト
```

**検証ステータス（2026年2月時点）：**

| コンポーネント | テスト内容 | 状態 |
|---|---|---|
| UARTプロトコル | 基本 + レジスタR/W | ✅ PASS |
| AXI4-Liteインタフェース | Write/Read シーケンス | ✅ PASS |
| VexRiscv RTL | フルパイプライン（レジスタファイル/ALU/メモリ/分岐） | ✅ PASS |
| ハザード検出 | EX/MEM/WBバイパス + load-useストール | ✅ PASS |
| 例外ハンドラ | EBREAK/ECALL + トラップハンドラ | ✅ PASS |
| デバッグ制御ブリッジ | ステップ/ブレークポイント/リセットパス | ✅ PASS |
| Stage 3 SVA | ハザード/パイプライン/バイパス/ジャンプ/FIFO | ✅ 実装済み |

---

## 1. AXIUART ブリッジのアーキテクチャ

### ハードウェア構成

```
PC (Python) ──UART(115200baud)──► AXIUART_Top ──AXI4-Lite──► レジスタブロック
                                      │                          (base: 0x1000)
                                      └──────────────────────► VexRiscv CPU
                                                                 ├── 8KB Block RAM
                                                                 ├── MMIO LED (0x407C)
                                                                 └── EBREAK検出
```

**UARTフレーム形式（CRC-8付き）：**

```
[SOF][CMD][ADDR(4byte)][DATA(4byte)][CRC]  ← Write
[SOF][CMD][ADDR(4byte)][CRC]               ← Read
[SOF][STATUS][CMD][ADDR][DATA][CRC]        ← Response
```

CRC-8によるエラー検出を標準装備しており、ノイズ環境でも安定した通信が可能です。

### VexRiscv CPU 統合

VexRiscvはSpinalHDLで生成されたRISC-V CPUです。本プロジェクトでは**生成済みの `VexRiscv.v` をそのまま使用**し、その周囲に UART デバッグ・制御インフラを SystemVerilog で追加実装しました。

**CPU コア（SpinalHDL 生成、変更なし）：**

- `rtl/cpu/VexRiscv.v` — SpinalHDL が出力したままの Verilog

**自作した統合・デバッグ回路（`rtl/vexriscvwrap/`）：**

| モジュール | 役割 |
|---|---|
| `vexriscv_wrapper.sv` | 全サブモジュールをまとめるトップラッパー |
| `vexriscv_debug_bridge.sv` | UART レジスタ命令 → VexRiscv DebugPlugin バス変換 |
| `vexriscv_control.sv` | Run/Halt/Step FSM（UART 経由の CPU 制御） |
| `vexriscv_ebreak_monitor.sv` | DBus を監視して EBREAK (0x00100073) を検出・自動 halt |
| `vexriscv_mem_crossbar.sv` | IBus/DBus メモリアービタ（デバッグポート優先） |
| `vexriscv_blockram.sv` | 8KB デュアルポート Block RAM + MMIO LED |
| `vexriscv_ibus_adapter.sv` / `vexriscv_dbus_adapter.sv` | IBus/DBus インタフェース変換 |
| `vexriscv_trace_probe.sv` | パイプライン実行トレース取得 |

**CPUスペック（VexRiscv GenSmallAndProductive 設定）：**

- ISA: RV32I + Zicsr（DebugPlugin 有効）
- パイプライン: 4ステージ（Fetch/Decode/Execute/Memory-WriteBack）
- 性能: ~0.82 DMIPS/MHz（Dhrystone）
- メモリ: 8KB デュアルポート Block RAM
- UART経由でプログラムロード・実行・halt が可能

---

## 2. レジスタマップの Single Source of Truth 設計

### 課題：アドレス不一致の防止

RTL・UVM・Pythonドライバでそれぞれハードコードされたアドレスは、メンテナンスのたびにズレが生じます。本プロジェクトではJSONを唯一の定義ファイルとし、全レイヤーのコードを自動生成します。

```
register_map/axiuart_registers.json   ← ここだけ編集する
            │
    gen_registers.py
            │
    ┌───────┴────────┬─────────────────┐
    ↓                ↓                 ↓
Python           SystemVerilog      Markdown
registers.py     axiuart_reg_pkg.sv REGISTER_MAP.md
```

### レジスタ定義の実例

CPU制御レジスタ（`CPU_MEM_CTRL`）を例に、どう管理されているかを見てみます。

**JSON定義（唯一の編集場所）：**

```json
{
  "name": "CPU_MEM_CTRL",
  "offset": "0x1234",
  "access": "RW",
  "description": "[3:0]=byte_enables, [4]=read_req(W1P), [5]=write_req(W1P),
                  [6]=busy(RO), [7]=cpu_run, [8]=cpu_halt,
                  [9]=cpu_halted(RO), [10]=cpu_break(RO)"
},
{
  "name": "DBG_BP0_ADDR",
  "offset": "0x1240",
  "access": "RW",
  "description": "Hardware breakpoint 0 address (PC value, halts CPU when matched)"
}
```

**生成された Python 定数（`registers.py`）：**

```python
# AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
REG_CPU_MEM_CTRL  = 0x2234  # RW - [7]=cpu_run, [8]=cpu_halt, [9]=cpu_halted(RO) ...
REG_DBG_BP0_ADDR  = 0x2240  # RW - Hardware breakpoint 0 address
REG_DBG_BP_CTRL   = 0x2250  # RW - [3:0]=bp_enable, [7:4]=bp_hit_flags(RO)
REG_DBG_RF_ADDR   = 0x2270  # RW - Register file read address [4:0]
REG_DBG_RF_DATA   = 0x2274  # RO - Register file read data
```

**生成された SystemVerilog パッケージ（`axiuart_reg_pkg.sv`）：**

```systemverilog
// AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
package axiuart_reg_pkg;
    parameter int BASE_ADDR         = 32'h00001000;
    parameter int REG_CPU_MEM_CTRL  = 32'h00002234;
    parameter int REG_DBG_BP0_ADDR  = 32'h00002240;
    parameter int REG_DBG_BP_CTRL   = 32'h00002250;
    parameter int REG_DBG_RF_ADDR   = 32'h00002270;
    parameter int REG_DBG_RF_DATA   = 32'h00002274;
endpackage
```

Python・SystemVerilog ともに同じアドレス `0x2234` が記述されており、ズレが発生する余地がありません。UVM テスト内でも `import axiuart_reg_pkg::*;` でそのままインポートして使用しています。

### レジスタマップの全体像（抜粋）

| アドレス | レジスタ名 | Access | 説明 |
| --- | --- | --- | --- |
| `0x1000` | CONTROL | RW | ブリッジ制御 |
| `0x1004` | STATUS | RO | ブリッジ状態 |
| `0x101C` | VERSION | RO | ハードウェアバージョン |
| `0x2228` | CPU_MEM_ADDR | RW | CPUメモリアクセスアドレス |
| `0x2234` | CPU_MEM_CTRL | RW | CPU制御（run/halt/step）＋ビット定義 |
| `0x2240`–`0x224C` | DBG_BP0–3_ADDR | RW | ハードウェアブレークポイント（4点） |
| `0x2250` | DBG_BP_CTRL | RW | BP有効化 / ヒットフラグ |
| `0x2260`–`0x226C` | PERF_CYCLE/INSN/STALL/FLUSH | RO | パフォーマンスカウンタ |
| `0x2270` / `0x2274` | DBG_RF_ADDR / DBG_RF_DATA | RW/RO | レジスタファイル直接読み出し |
| `0x2280`–`0x22A0` | TRACE_READ_ADDR / TRACE_DATA_* | RW/RO | 64エントリ実行トレースバッファ |

ブレークポイント4点・パフォーマンスカウンタ・レジスタファイル読み出し・実行トレースバッファなど、UART経由で使えるデバッグ機能がこのレジスタマップひとつで管理されています。

### 再生成コマンド

```bash
python software/axiuart_driver/tools/gen_registers.py \
  --in register_map/axiuart_registers.json
```

JSONを1箇所修正するだけで、RTL・UVM・Pythonドライバすべてのアドレス定数が更新されます。アドレスのバリデーション（アライメント・重複チェック）も自動実行されます。

---

## 3. UVM 検証環境

### コンポーネント階層

```
uvm_test_top
└── env (axiuart_env)
    ├── uart_agt (uart_agent)
    │   ├── driver    ← UART フレームをピンレベルで駆動
    │   ├── monitor   ← TX ラインを観測してトランザクション復元
    │   └── sequencer ← シーケンスの実行管理
    └── scoreboard    ← Write → Read ライトバック検証
```

### テストスイート

**Stage 1（基礎テスト）：**

| テスト名 | 検証内容 |
|---|---|
| `vexriscv_smoke_test` | NOP プログラム実行・PC進行確認 |
| `vexriscv_regfile_test` | レジスタファイル R/W 正確性 |
| `vexriscv_alu_test` | ADD/SUB/AND/OR/XOR/SLT/シフト網羅 |
| `vexriscv_pipeline_flow_test` | ハザード・フォワーディング |
| `vexriscv_memory_access_test` | ロード/ストア・MMIO LEDアクセス |

**デバッグ制御テスト：**

| テスト名 | 検証内容 |
|---|---|
| `vexriscv_control_test` | Run/Halt/Step 制御レジスタパス |
| `vexriscv_debug_bridge_test` | デバッグブリッジ FSM |
| `rv32i_ebreak_simple_test` | EBREAK トラップ → halt フロー |
| `rv32i_exception_handler_test` | EBREAK/ECALL + CSR トラップハンドラ |

### シーケンスの実装例

```systemverilog
// レジスタ書き込みシーケンス
class uart_write_sequence extends uvm_sequence#(uart_transaction);
    `uvm_object_utils(uart_write_sequence)
    rand bit [31:0] addr;
    rand bit [31:0] data;

    task body();
        uart_transaction req = uart_transaction::type_id::create("req");
        start_item(req);
        assert(req.randomize() with {
            cmd == CMD_WRITE;
            addr == local::addr;
            data == local::data;
        });
        finish_item(req);
    endtask
endclass
```

---

## 4. Altair DSim のコマンドライン実行

### なぜ DSim を選んだか

Altair DSim（旧 Metrics DSim）は SystemVerilog + UVM 1.2 をフルサポートする商用シミュレータです。Windows / Linux 両対応で、ライセンスが比較的入手しやすいため採用しました。

### PowerShell スクリプトによる自動化

```powershell
# 単体テスト実行
.\scripts\run_test.ps1 vexriscv_regfile_test -Verbosity UVM_LOW

# 波形付き実行（MXD形式）
.\scripts\run_test.ps1 vexriscv_regfile_test -Verbosity UVM_LOW -Waves

# Stage 1 リグレッション
.\scripts\run_regression.ps1 -Stage 1 -Verbosity UVM_LOW

# 特定のテストスイートのみ実行
.\scripts\run_regression.ps1 -Suite vexriscv_debug_control -Verbosity UVM_LOW
```

### run_test.ps1 の中身

スクリプトの核心部分は、DSimに渡す引数の組み立てと結果のパースです。

```powershell
param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$TestName,
    [switch]$Waves,
    [ValidateSet("UVM_LOW", "UVM_MEDIUM", "UVM_HIGH", "UVM_DEBUG")]
    [string]$Verbosity = "UVM_LOW",
    [int]$Seed = 1,
    [switch]$CompileOnly,
    [switch]$RunOnly,
    [int]$CleanupDays = 7,   # N日より古いログを自動削除
    [int]$KeepRecent  = 5    # テストごとに直近N件のログを保持
)
```

**テストルーティング：** テスト名のプレフィックスで使用するコンフィグファイルとトップモジュールを自動切り替えします。

```powershell
# RV32I / VexRiscv テストは専用コンフィグを使用
if ($TestName -match '^(rv32i_|vexriscv_)') {
    $ConfigFile = "dsim_config_rv32i.f"
    $TopModule  = "rv32i_tb_top"
}
# ユニットテストは別トップモジュール
elseif ($unitTestRouting.ContainsKey($TestName)) {
    $ConfigFile = $unitTestRouting[$TestName].ConfigFile
    $TopModule  = $unitTestRouting[$TestName].TopModule
    $IsUvmTest  = $unitTestRouting[$TestName].IsUvmTest
}
```

**DSimへの引数組み立て：**

```powershell
$args = @(
    "-timescale", "1ns/1ps",
    "-f",         $ConfigFile,       # ファイルリスト (.f)
    "-top",       $TopModule,
    "-sv_seed",   $Seed,
    "-l",         $logFile           # ログ出力先
)

if ($IsUvmTest) {
    $args += @(
        "-uvm",             "1.2",
        "+UVM_TESTNAME=$TestName",
        "+UVM_VERBOSITY=$Verbosity",
        "+UVM_PHASE_TRACE",       # フェーズトレース有効
        "+UVM_OBJECTION_TRACE"    # Objectionトレース有効
    )
}

if ($Waves) {
    $args += @("-waves", $waveFile)   # MXD形式の波形出力
}
```

**結果判定：** ログを走査して UVM_ERROR / UVM_FATAL カウントを拾い、JSONにも保存します。

```powershell
foreach ($line in $logContent) {
    if ($line -match "^\s*UVM_ERROR\s*:\s*(\d+)") { $uvmErrors = [int]$Matches[1] }
    if ($line -match "^\s*UVM_FATAL\s*:\s*(\d+)") { $uvmFatals = [int]$Matches[1] }
}

# テスト結果を JSON で保存（CI連携用）
$resultJson = @{
    test_name = $TestName
    status    = if ($testPass) { "success" } else { "failure" }
    exit_code = $resultCode
    log_file  = $logFile
    wave_file = if ($Waves) { $waveFile } else { "" }
    timestamp = $timestamp
} | ConvertTo-Json

$resultJson | Out-File -FilePath $jsonFile -Encoding UTF8
```

ログとJSONは `sim/exec/logs/` にタイムスタンプ付きで蓄積されます。`-CleanupDays` / `-KeepRecent` オプションで古いファイルを自動削除できるため、長期運用でもディスクを圧迫しません。

### リグレッション定義（JSON管理）

```json
{
  "stage1": {
    "description": "Foundation tests",
    "tests": [
      "vexriscv_smoke_test",
      "vexriscv_regfile_test",
      "vexriscv_alu_test",
      "vexriscv_pipeline_flow_test",
      "vexriscv_memory_access_test"
    ]
  },
  "vexriscv_debug_control": {
    "description": "Debug/control bridge tests",
    "tests": [
      "vexriscv_control_test",
      "vexriscv_debug_bridge_test",
      "rv32i_ebreak_simple_test",
      "rv32i_exception_handler_test"
    ]
  }
}
```

テストスイートの定義をJSONで管理することで、CIへの統合や新テストの追加が容易になります。

### アサーション制御（パフォーマンス vs デバッグ）

```powershell
# 通常開発（高速）
.\scripts\run_test.ps1 <test> -Verbosity UVM_LOW

# デバッグモード（SVAアサーション有効）
.\scripts\run_test.ps1 <test> -Verbosity UVM_LOW -Plusargs "+define+ENABLE_ASSERTIONS"
```

| モード | コンパイルモジュール数 | オーバーヘッド |
|---|---|---|
| アサーション無効 | 22モジュール | なし |
| アサーション有効 | 28モジュール（+6） | +19% |

---

## 5. Stage 3 SVA アサーションモジュール

UVMに加えて、RTLに非侵入的（bind文使用）なSystemVerilog Assertions (SVA) モジュールを実装しました。

```
sim/assertions/spec/
├── vexriscv_hazard_plugin_spec.sv       # RAWハザード・バイパス優先度・load-useストール
├── vexriscv_pipeline_arbitration_spec.sv # Decode/EX/MEM/WB アービトレーションフラグ
├── vexriscv_regfile_bypass_spec.sv      # EX/MEM/WB フォワーディング正確性
├── vexriscv_jump_arbitration_spec.sv    # ジャンプ/分岐 taken vs PC補正
└── vexriscv_stream_fifo_spec.sv         # IBus/DBus ストリームFIFO ハンドシェイク
```

`bind` 文によりRTLコードを一切変更せずにアサーションを追加できます：

```systemverilog
// bind ファイルの例
bind vexriscv_hazard_simple vexriscv_hazard_plugin_spec u_hazard_spec (.*);
```

これにより、RTLのコードレビューを経ずにアサーションを後から追加・変更できます。

---

## 6. Python 制御ソフトウェア

### ドライバアーキテクチャ

```
Application Layer (led_control.py, example_basic.py)
        │
AXIUARTDriver クラス (高レベルAPI)
        │
Protocol Layer (FrameBuilder / FrameParser / CRC-8)
        │
pySerial
        │
UART Hardware → FPGA AXIUART Bridge
```

### 使い方

```python
from axiuart_driver import AXIUARTDriver
from axiuart_driver.examples.led_control import LEDController

# 基本的なレジスタアクセス
with AXIUARTDriver('COM3') as driver:
    driver.write_reg32(0x1020, 0xDEADBEEF)
    value = driver.read_reg32(0x1020)
    print(f"Read back: 0x{value:08X}")

# LEDアニメーション（FPGA実機）
with LEDController('COM3') as led:
    led.set_led(0xF)            # 全LED点灯
    led.pattern_knight_rider()  # ナイトライダー風アニメ
    led.pattern_binary_count()  # 2進数カウントアップ
```

### FPGA実機への持ち込み（bring-up）

```bash
# UARTでFPGAにLEDブリンクプログラムを書き込んで実行
python software/rv32i/led_blink.py --port COM3
```

このスクリプトは：
1. UART経由でRV32IバイナリをブロックRAMに書き込み
2. CPUを実行開始（run コマンド送信）
3. EBREAK検出で自動停止

という一連のフローを実行します。シミュレーションで検証した動作が、そのまま実機でも動くことを確認するためのbring-upツールです。

---

## 7. ハマりどころと解決策

### バグ #8：スコアボードのRO(Read-Only)レジスタ検証

UVMスコアボードがRO属性のレジスタにWrite → Read-back検証をかけてしまい、常にミスマッチになる問題。レジスタJSONにRO属性を定義し、スコアボード側で除外するよう修正しました。

### Issue #55：デバッグブリッジのFSMパス

Step実行 / ブレークポイント / リセット のレジスタパスをUVMで検証する際、タイミングの調整が必要でした。`vexriscv_debug_bridge_test` で専用シーケンスを実装して解決。

### Issue #75：EBREAK/ECALL の CSR エンコーディング

EBREAK命令のトラップ時にCSR（mstatus/mepc/mcause）の値が仕様と一致しない問題。CSR実装を仕様書（RISC-V Privileged ISA Specification）と照合して修正しました。

---

## 8. 実際の UVM ログを読む

### コンパイル〜エラボレーション

DSimは Analyze → Elaborate → Optimize → Build の順に処理します。

```
Analyzing...
Elaborating...
  Top-level modules:
    $unit
    rv32i_tb_top
  Found 24 unique specialization(s) of 24 design element(s).
=W:[MissingTimescale]: ...（uvm_pkg にタイムスケール指定がないため出る定番警告）
Optimizing...
Building models...
  [4/24] module rv32i_tb_top: 650 functions, 3105 basic blocks
  [7/24] package uvm_pkg: 6 submodules, 3947 functions, 42162 basic blocks
Linking image.so...
```

`=W:` は Warning、`=E:` は Error、`=F:` は Fatal、`=T:` は終了ステータスです。UVM の Warning（uvm_callback.svh 由来の IneffectiveDynamicCast）は UVM 1.2 の既知の無害な警告で、実害はありません。

### UVM フェーズトレース（`+UVM_PHASE_TRACE`）

`+UVM_PHASE_TRACE` を有効にすると、各フェーズの開始・終了が記録されます。

```
UVM_INFO @ 0: reporter [RNTST] Running test vexriscv_regfile_test...
UVM_INFO @ 0: reporter [PH/TRC/STRT] Phase 'common.build'      Starting phase
UVM_INFO @ 0: reporter [PH/TRC/DONE] Phase 'common.build'      Completed phase
UVM_INFO @ 0: reporter [PH/TRC/STRT] Phase 'common.connect'    Starting phase
UVM_INFO @ 0: reporter [PH/TRC/DONE] Phase 'common.connect'    Completed phase
...
UVM_INFO @ 0: reporter [PH/TRC/SKIP] Phase 'uvm.uvm_sched.reset' No objections raised, skipping phase
...
UVM_INFO @ 0: run [OBJTN_TRC] Object uvm_test_top raised 1 objection(s): count=1  total=1
```

`[PH/TRC/SKIP]` は objection を raise したコンポーネントが誰もいないフェーズをスキップしたことを示します。reset / configure / main / shutdown の各サブフェーズがスキップされているのは、このプロジェクトでは `run_phase` に直接ロジックを書いているためです。

### vexriscv_regfile_test のログ抜粋

CPU をロードして run → halt し、レジスタファイルを読み取って検証するまでの流れが追えます。

```text
[124000] BRAM[0] = 0x00100093 (expected 0x00100093)   ← メモリロード確認
[124000] BRAM[1] = 0x00100113 (expected 0x00100113)
[140000] [BASE_TEST] Setting cpu_mem_ctrl_reg[7]=1 (CPU RUN)   ← run パルス
[148000] [BASE_TEST] Clearing cpu_mem_ctrl_reg[7]=0 (RUN pulse complete)
[252000] [PIPELINE] Cycle 12: WriteBack wb_valid=1, wb_firing=1, reg_write=1
[252000] [DEBUG] Write x1 = 0x00000001               ← x1 に書き込み確認
[284000] [DEBUG] Write x2 = 0x00000001
[316000] [DEBUG] Write x3 = 0x00000003
[404000] [BASE_TEST] Setting cpu_mem_ctrl_reg[8]=1 (CPU HALT)  ← halt パルス
[DEBUG] RegFile[0] = 0x00000000  (x0 はゼロ固定)
[DEBUG] RegFile[1] = 0x00000001
[DEBUG] RegFile[2] = 0x00000001
[DEBUG] RegFile[3] = 0x00000003

UVM_INFO @ 420000: [vexriscv_regfile_test] PASS: x0 = 0x00000000 (hardwired zero verified)
UVM_INFO @ 420000: [vexriscv_regfile_test] PASS: x1 = 0x00000001
UVM_INFO @ 420000: [vexriscv_regfile_test] PASS: x2 = 0x00000001
UVM_INFO @ 420000: [vexriscv_regfile_test] PASS: x3 = 0x00000003
UVM_INFO @ 420000: [vexriscv_regfile_test]
============================================================
  TEST PASSED
  Register File Verification Complete
============================================================
```

### vexriscv_alu_test のログ抜粋（IBus フェッチトレース）

ALU テストでは IBus の命令フェッチ過程がリアルタイムで見えます。

```text
[164000] [FETCH_VERIFY] FIRST INSTRUCTION FETCH  PC = 0x80000000
[180000] [FETCH_VERIFY] BRAM READ: addr=0x000 data=0x01000093  ← ADDI x1, x0, 1
[196000] [FETCH_VERIFY] IBus RSP: INST=0x01000093
[212000] [FETCH_VERIFY] BRAM READ: addr=0x001 data=0x00800113  ← ADDI x2, x0, 8
...
[1268000] [FETCH_VERIFY] *** EBREAK DETECTED *** PC=80000084   ← 自動 halt
```

最後に UVM Report Summary が出力されます。

```text
--- UVM Report Summary ---
** Report counts by severity
UVM_INFO    :  106
UVM_WARNING :    0
UVM_ERROR   :    0    ← 0 であることがパスの条件
UVM_FATAL   :    0

SVA Summary: 15 assertions, 6315 evaluations, 108 nonvacuous passes, 1 failure
```

`SVA Summary` はアサーション有効時に追加されます。`nonvacuous passes` は「実際に条件が成立して pass した回数」、`failure` はアサーション違反の件数です。PowerShell スクリプトは `UVM_ERROR: 0` と `UVM_FATAL: 0` かつ exit code 0 でのみ PASS と判定します。

---

## まとめ

| 技術 | 採用理由 |
|---|---|
| **UVM 1.2** | 再利用可能・モジュラーな検証環境。シーケンスライブラリで複雑なシナリオを組み合わせ可能 |
| **Altair DSim** | Windows対応・UVM完全サポート・コマンドライン自動化が容易 |
| **SVA（bind文）** | RTL無変更でアサーション追加。開発後期のデバッグにも対応 |
| **JSON SSOT** | RTL/UVM/Pythonのアドレス不一致を根絶。メンテナンスコスト大幅削減 |
| **Python Driver** | 実機との境界を薄く保つ。シミュレーションで検証した同じシーケンスが実機でも動く |

UVMの学習コストは高いですが、一度整備すると新しいテストケースの追加が格段に楽になります。特にスコアボードによる自動照合と、PowerShellによるリグレッション自動化の組み合わせは、毎回手動でログを確認する手間を大幅に削減できました。

---

## 参考資料

- [VexRiscv GitHub](https://github.com/SpinalHDL/VexRiscv)
- [Altair DSim](https://www.altair.com/dsim/)
- [UVM 1.2 User Guide (Accellera)](https://www.accellera.org/downloads/standards/uvm)
- [RISC-V Privileged ISA Specification](https://riscv.org/specifications/)

---

*このプロジェクトのソースコードは GitHub で公開しています。*

<!-- タグ候補: FPGA, SystemVerilog, UVM, RISC-V, VexRiscv, AXI4, UART, Python, DSim, 検証 -->
