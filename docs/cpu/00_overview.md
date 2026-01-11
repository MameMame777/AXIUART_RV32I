# RV32I CPU Core - アーキテクチャ概要

**バージョン:** 1.1  
**最終更新:** 2026年1月5日  
**アーキテクチャ:** RISC-V RV32I Base Integer Instruction Set  
**プロジェクト:** TD4UART - RV32I CPU統合

---

## 目次

1. [設計コンセプト](#設計コンセプト)
2. [アーキテクチャ仕様](#アーキテクチャ仕様)
3. [パイプライン構造](#パイプライン構造)
4. [モジュール階層](#モジュール階層)
5. [主要設計決定](#主要設計決定)
6. [実装状況](#実装状況)

---

## 設計コンセプト

### 設計思想

このRV32I CPUコアは、**FPGA実装を前提とした教育的かつ実用的なRISC-Vプロセッサ**として設計されています。以下の原則に基づいています：

1. **完全性**: RV32I仕様を完全に実装（40命令すべて）
2. **明確性**: パイプラインステージごとにモジュール分割、各責務を明確化
3. **検証可能性**: 各モジュールに対応するSVAベースのアサーションモジュール
4. **デバッグ性**: トレースバッファ、外部メモリアクセス、ブレークポイント機能
5. **拡張性**: MMIOインターフェース、CSRモジュール化による将来の拡張対応

### 設計目標

- **性能**: 125MHz動作（Zynq-7000ターゲット）、単一サイクル算術演算
- **資源効率**: 1500 LUT以下、1 BRAMブロック、1000 FF以下
- **タイミング**: クリティカルパスは5ns以下（200MHz理論値）
- **正確性**: ハザード完全検出、フォワーディング、ストール/フラッシュ制御

---

## アーキテクチャ仕様

### コア構成

```
┌─────────────────────────────────────────────────────────────────┐
│                        RV32I CPU Core                           │
│                       (rv32i_core.sv)                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  │
│  │   IF   │→ │   ID   │→ │   EX   │→ │  MEM   │→ │   WB   │  │
│  │ Stage  │  │ Stage  │  │ Stage  │  │ Stage  │  │ Stage  │  │
│  └────────┘  └────────┘  └────────┘  └────────┘  └────────┘  │
│       ↑          ↓            ↓           ↓           ↓        │
│       │      ┌────────┐   ┌────────┐  ┌────────┐  ┌────────┐ │
│       │      │Register│   │  ALU   │  │Block   │  │Forward │ │
│       │      │  File  │   │Shifter │  │  RAM   │  │Control │ │
│       │      │32×32bit│   │Branch  │  │Port B  │  │        │ │
│       │      └────────┘   └────────┘  └────────┘  └────────┘ │
│       │                                                        │
│       │      ┌───────────────────────────────────┐            │
│       └──────┤     Hazard Detection Unit        │            │
│              │  (Forwarding/Stall/Flush Logic)  │            │
│              └───────────────────────────────────┘            │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │                    CSR Module                             │ │
│  │  (mtvec, mepc, mcause, mtval + Exception Handling)       │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │            Debug & Trace Interface                        │ │
│  │  - Breakpoint registers (4 points)                       │ │
│  │  - Instruction trace buffer (64 entries)                 │ │
│  │  - External RAM access (Port B arbitration)              │ │
│  └──────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘

                          ↓ Port A (IF)    ↓ Port B (MEM/Debug)
                    ┌────────────────────────────────┐
                    │   Block RAM (8KB, Dual-Port)  │
                    │      2048 words × 32 bits      │
                    └────────────────────────────────┘
```

---

## メモリマップ

このCPUは32ビットアドレス空間を持ちますが、実装されているのは8KBのBlock RAMとわずかなMMIOレジスタのみです。

### 物理メモリレイアウト

| Address Range | Size | Type | Description | Access |
|--------------|------|------|-------------|--------|
| **0x0000_0000 - 0x0000_1FFF** | 8KB | Block RAM | 統合命令/データメモリ | RW + Execute |
| 0x0000_2000 - 0x0000_3FFF | - | Reserved | 未実装（将来拡張用） | - |
| **0x0000_4000 - 0x0000_4FFF** | 4KB | MMIO | Memory-Mapped I/O領域 | Varies |
| **0x0000_407C** | 4B | MMIO | LED制御レジスタ [3:0] | Write-Only |
| 0x0000_5000 - 0xFFFF_FFFF | - | Unmapped | 未定義（アクセス例外） | Exception |

### RAM構成 (0x0000 - 0x1FFF)

**Block RAM仕様**:
- **容量**: 2048 words × 32 bits = 8KB
- **ポート構成**: Dual-Port BRAM
  - **Port A**: IFステージ専用（命令フェッチ、読み取り専用）
  - **Port B**: MEMステージ/デバッグアクセス（データ読み書き）
- **アドレッシング**: バイトアドレス可能、ワード境界必須
- **初期化**: デバッグインターフェース経由でロード

**アドレス変換**:
```
Byte Address (PC)  →  Word Address (RAM)  →  Physical Array
0x0000_0000       →      0x000           →    ram[0]
0x0000_0004       →      0x001           →    ram[1]
0x0000_0008       →      0x002           →    ram[2]
...
0x0000_1FFC       →      0x7FF           →    ram[2047]
0x0000_2000以上は未定義（範囲外アクセス）
```

**使用例** (メモリレイアウト):
```
0x0000_0000: ┌─────────────────┐
             │ .text (Code)    │ ← プログラムコード (_start, main, etc.)
0x0000_0800: ├─────────────────┤
             │ .rodata         │ ← 読み取り専用データ（文字列、定数テーブル）
0x0000_0C00: ├─────────────────┤
             │ .data           │ ← 初期化済みグローバル変数
0x0000_1000: ├─────────────────┤
             │ .bss            │ ← 未初期化グローバル変数
0x0000_1800: ├─────────────────┤
             │ Heap (未実装)   │ ← 動的メモリ確保領域（将来用）
0x0000_1C00: ├─────────────────┤
             │ Stack (grows ↓) │ ← スタック領域（sp初期値=0x2000）
0x0000_2000: └─────────────────┘ (範囲外)
```

### MMIO ペリフェラル

#### LED制御レジスタ (0x0000_407C)

**レジスタ構成**:
```
Bits [31:4]: Reserved (書き込み無視、読み出し時0)
Bits [3:0]:  LED出力ビット (1=点灯, 0=消灯)
Access: Write-Only (読み出し時は常に0を返す)
```

**使用例**:
```assembly
# LEDを0b1010パターンで点灯
lui  x15, 0x4        # x15 = 0x0000_4000
addi x16, x15, 0x7C  # x16 = 0x0000_407C (LEDアドレス)
addi x17, zero, 0xA  # x17 = 0b1010
sw   x17, 0(x16)     # LEDレジスタに書き込み
```

#### 新しいMMIOペリフェラルの追加方法

1. **アドレス選定**: `0x4000-0x4FFF`範囲内で未使用アドレスを選択
2. **MEMステージ修正**: `rtl/cpu/rv32i_mem.sv`のアドレスデコーダを更新
   ```systemverilog
   // 例: UARTレジスタを0x4080に追加
   wire is_uart = (mem_alu_result == 32'h0000_4080);
   ```
3. **トップレベル統合**: `rtl/cpu/rv32i_top.sv`でペリフェラルモジュールを接続
4. **ドキュメント更新**: このテーブルに新しいペリフェラルを追記

---

### 主要パラメータ

| パラメータ | 値 | 説明 |
|-----------|-----|------|
| **ISA** | RV32I v2.1 | 基本整数命令セット（40命令） |
| **データ幅** | 32 bit | レジスタ、データバス幅 |
| **アドレス幅** | 32 bit | バイトアドレッシング |
| **レジスタ数** | 32 | x0-x31（x0は常に0、[ABI名称は09_software_abi.md参照](09_software_abi.md)） |
| **内蔵RAM** | 8 KB | 2048 words（デュアルポートBRAM） |
| **パイプラインステージ** | 5 | IF/ID/EX/MEM/WB |
| **フォワーディングパス** | 3 | EX→EX, MEM→EX, WB→EX |
| **CSRレジスタ** | 4 | mtvec, mepc, mcause, mtval |

### 物理特性

- **FPGA リソース**: 
  - LUT: ~1500 (Zynq-7020の1%未満)
  - FF: ~1000 (Zynq-7020の1%未満)
  - BRAM: 1 block (36Kb)
  - DSP: 0 (算術演算はLUTで実装)

- **動作周波数**:
  - 設計目標: 125 MHz
  - 実測値: 150 MHz以上可能（post-implementation）
  - クリティカルパス: ALU → ブランチ判定 → PC MUX

- **レイテンシ**:
  - 連続命令: 1サイクル/命令（CPI = 1.0理想値）
  - ブランチ分岐時: 2サイクル（ストール1 + フラッシュ1）
  - ロード使用依存: 1サイクルストール
  - 実効CPI: 1.1~1.3（ベンチマーク依存）

---

## パイプライン構造

### 5ステージパイプライン概要

| Stage | Name | Operations | Key Registers | Critical Decisions |
|-------|------|------------|---------------|-------------------|
| **IF** | Instruction Fetch | - PC管理<br>- RAMアドレス計算 (PC[12:2])<br>- 命令読み出し<br>- ブレークポイント検出 | **if_id_reg**:<br>- pc<br>- insn<br>- valid<br>- bp_hit[3:0] | - PCソース選択（例外 > MRET > 分岐 > PC+4）<br>- ストール/フラッシュ制御 |
| **ID** | Instruction Decode | - 命令デコード<br>- レジスタファイル読み出し<br>- 即値生成 (I/S/B/U/J)<br>- 制御信号生成 | **id_ex_reg**:<br>- rs1_data, rs2_data<br>- rs1_addr, rs2_addr<br>- imm<br>- 制御信号群 | - レジスタx0ハードワイヤー処理<br>- 不正命令検出 |
| **EX** | Execute | - ALU演算<br>- 分岐条件評価<br>- ジャンプターゲット計算<br>- フォワーディングMUX | **ex_mem_reg**:<br>- alu_result<br>- branch_taken<br>- mem制御信号 | - フォワーディングパス選択（EX/MEM/WB）<br>- RAWハザード解決 |
| **MEM** | Memory Access | - RAM読み書き<br>- MMIOアドレスデコード<br>- ロード整列<br>- 例外検出 | **mem_wb_reg**:<br>- mem_rdata<br>- alu_result<br>- 例外情報 | - MMIO vs RAM選択<br>- アドレスミスアライン検出<br>- 例外トリガ |
| **WB** | Write Back | - 結果ソース選択<br>- レジスタファイル書き込み<br>- WBフォワーディング | **wb_result_fwd**:<br>- 書き込みデータ | - メモリ vs ALU結果選択<br>- x0への書き込み防止 |

**パイプラインレジスタ命名規則**: `{source}_{dest}_reg` (例: `if_id_reg`, `id_ex_reg`)

**データフロー例** (連続命令):
```
Clock:     t0      t1      t2      t3      t4      t5
           │       │       │       │       │       │
ADDI x1:   IF  →  ID  →  EX  →  MEM →  WB  
ADD  x2:          IF  →  ID  →  EX  →  MEM →  WB
SW   x3:                 IF  →  ID  →  EX  →  MEM →  WB
LW   x4:                        IF  →  ID  →  EX  →  MEM →  WB
BEQ:                                   IF  →  ID  →  EX  →  MEM

理想CPI = 1.0 (1命令/サイクル)
```

**ハザード時の動作**:
```
# Load-Use Hazard (1サイクルストール)
Clock:     t0      t1      t2      t3      t4      t5      t6
LW  x1:    IF  →  ID  →  EX  →  MEM →  WB
ADD x2:           IF  →  ID  → [STALL] → EX  →  MEM →  WB
                              (Bubble)
実効CPI = 2.0 (この2命令で)

# Branch Misprediction (2サイクルペナルティ)
Clock:     t0      t1      t2      t3      t4
BEQ:       IF  →  ID  →  EX (判定) →  MEM →  WB
Target+4:         IF  →  ID (Flush) → [Bubble]
Target+8:                IF (Flush) → [Bubble]
Correct:                             IF  →  ID  →  EX
分岐ペナルティ = 2サイクル
```
Insn3:                   IF  →  ID  →  EX  →  MEM →  WB
Insn4:                          IF  →  ID  →  EX  →  MEM
Insn5:                                 IF  →  ID  →  EX
```

### ステージ詳細

| ステージ | 略称 | 主要機能 | クリティカルパス要素 |
|----------|------|----------|----------------------|
| **Instruction Fetch** | IF | PC管理、命令フェッチ、ブレークポイント検出 | PC加算器 → MUX |
| **Instruction Decode** | ID | 命令デコード、レジスタ読み出し、即値生成 | レジスタファイル読み出し |
| **Execute** | EX | ALU演算、分岐判定、ジャンプ計算 | ALU → ブランチコンパレータ |
| **Memory Access** | MEM | ロード/ストア、MMIOデコード、例外検出 | BRAM read → アライメント |
| **Write Back** | WB | 結果選択、レジスタ書き込み、CSR書き込み | 結果MUX → レジスタファイル |

### パイプラインレジスタ

各ステージ間にパイプラインレジスタが配置され、以下の情報を伝播します：

1. **IF/ID Register**:
   - `pc[31:0]`: プログラムカウンタ
   - `insn[31:0]`: フェッチした命令
   - `valid`: 命令有効フラグ

2. **ID/EX Register**:
   - 上記 + `rs1_data[31:0]`, `rs2_data[31:0]`: レジスタ値
   - `imm[31:0]`: 即値
   - `ctrl`: 制御信号束（ALU操作、メモリ操作、分岐条件など）
   - `forward_rs1[1:0]`, `forward_rs2[1:0]`: フォワーディング制御

3. **EX/MEM Register**:
   - 上記 + `alu_result[31:0]`: ALU演算結果
   - `rs2_data[31:0]`: ストアデータ（フォワーディング後）

4. **MEM/WB Register**:
   - 上記 + `mem_data[31:0]`: ロードデータ

---

## モジュール階層

### トップダウン構成

```
rv32i_core (トップレベル)
├── rv32i_top (パイプライン統合)
│   ├── rv32i_if (Instruction Fetch)
│   ├── rv32i_id (Instruction Decode)
│   │   └── regfile [32x32] (レジスタファイル)
│   ├── rv32i_hazard (ハザード検出・制御)
│   ├── rv32i_ex (Execute)
│   │   ├── ALU
│   │   ├── Branch Comparator
│   │   └── Forwarding Multiplexers
│   ├── rv32i_mem (Memory Access)
│   │   ├── Load/Store Aligner
│   │   ├── MMIO Decoder
│   │   └── Exception Detector
│   ├── rv32i_wb (Write Back)
│   │   └── Result Multiplexer
│   └── rv32i_csr (Control & Status Registers)
│       ├── Exception Handler
│       └── CSR Register Bank
├── block_ram_dual (Dual-Port BRAM, 8KB)
│   ├── Port A (IF read-only)
│   └── Port B (MEM read/write, Debug read/write)
└── rv32i_trace_buffer (命令トレース, 64エントリ)
```

### モジュールファイル対応

| モジュール | ファイル | 行数 | 主要責務 |
|-----------|---------|------|----------|
| `rv32i_core` | rv32i_core.sv | ~400 | トップレベル統合、RAM/Debug I/F |
| `rv32i_top` | rv32i_top.sv | ~700 | パイプライン統合、フォワーディング接続 |
| `rv32i_if` | rv32i_if.sv | ~250 | PC制御、命令フェッチ、ブレークポイント |
| `rv32i_id` | rv32i_id.sv | ~400 | デコード、レジスタファイル、即値生成 |
| `rv32i_hazard` | rv32i_hazard.sv | ~300 | RAWハザード、ロード使用、ストール/フラッシュ |
| `rv32i_ex` | rv32i_ex.sv | ~350 | ALU、分岐判定、フォワーディングMUX |
| `rv32i_mem` | rv32i_mem.sv | ~400 | ロード/ストア、MMIO、例外検出 |
| `rv32i_wb` | rv32i_wb.sv | ~200 | 結果選択、レジスタ/CSR書き込み |
| `rv32i_csr` | rv32i_csr.sv | ~300 | CSRレジスタ、例外処理、MRET |
| `rv32i_trace_buffer` | rv32i_trace_buffer.sv | ~150 | 命令履歴記録（デバッグ用） |

---

## 主要設計決定

### 1. デュアルポートBRAM構成

**決定**: Port AをIF専用（読み出しのみ）、Port BをMEM/Debug共用

**理由**:
- IFは毎サイクル命令フェッチ → 専用ポート必要
- MEMはロード/ストア時のみアクセス → 共有可能
- Debug accessはCPU halt時のみ → 競合しない

**トレードオフ**:
- ✅ ハーバードアーキテクチャで命令/データ同時アクセス可能
- ✅ シングルサイクルロード実現
- ❌ 命令RAM、データRAMの分離不可（統一アドレス空間）

### 2. フォワーディングタイミング設計（重要な修正履歴）

**初期実装（2026年1月3日）**:
```systemverilog
// rv32i_top.sv (旧実装)
.mem_forward_data(wb_result),  // 組み合わせ回路
.wb_forward_data(wb_result)    // 組み合わせ回路
```

**問題点**:
- `wb_result`はWBステージの`always_comb`ブロックで計算される組み合わせ信号
- EXステージで必要なタイミング（cycle N+1）には、WBステージが次の命令に進んでおり、`wb_result`の値が変化してしまう
- 例: cycle Nで`ADDI x27, x0, 7`がWB → `wb_result = 0x7`
  - cycle N+1で`SW x27, 0(x15)`がEX、WBステージは次の`LUI x15, 0x4000`に進行
  - EXのフォワーディングMUXは`wb_result = 0x4000`（LUIの結果）を読んでしまう
  - 結果: 不正な値がフォワーディングされる

**修正実装（2026年1月5日）**:
```systemverilog
// rv32i_top.sv (新実装)
logic [31:0] wb_result;       // 組み合わせ信号
logic [31:0] wb_result_fwd;   // レジスタ化されたフォワーディング用信号

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || soft_reset_active) begin
        wb_result_fwd <= 32'h0;
    end else begin
        wb_result_fwd <= wb_result;  // cycle Nの結果をcycle N+1で使用可能に
    end
end

// フォワーディング接続
.mem_forward_data(wb_result_fwd),  // レジスタ化済み
.wb_forward_data(wb_result_fwd)    // レジスタ化済み
```

**タイミング図**:
```
Cycle N:                    Cycle N+1:
 ┌──────────┐                ┌──────────┐
 │ MEM/WB   │                │ MEM/WB   │  
 │  Reg     │                │  Reg     │
 └─────┬────┘                └─────┬────┘
       │                           │
       ▼ combinational             ▼ combinational
  ┌─────────┐                 ┌─────────┐
  │WB  Mux  │                 │WB  Mux  │
  │(4-way)  │                 │(4-way)  │
  └────┬────┘                 └────┬────┘
       │ wb_result=0x7              │ wb_result=0x4000
       │                            │
       ▼ registered                 │
  ┌─────────┐                      │
  │wb_result│                      │
  │  _fwd   │◄─────────────────────┘
  │  FF     │  (holds 0x7 from cycle N)
  └────┬────┘
       │
       ▼ to EX forwarding mux
   (stable value)
```

**効果**:
- ✅ cycle Nで計算された`wb_result`がcycle N+1で`wb_result_fwd`として安定して利用可能
- ✅ クリティカルパスを分割: `MEM/WB reg → WB mux`と`wb_result_fwd → EX mux`が別サイクル
- ✅ 命令レイテンシは増加しない（パイプライン深度は5のまま）
- ✅ タイミング違反を解消（4-5 LUTレベルの組み合わせパスを削減）

**設計哲学**:
パイプラインレジスタの値は**そのサイクルで確定した値**を保持する。フォワーディングは「過去のサイクルで確定した結果」を使用するため、レジスタ化が必須。

### 3. ハザード検出の事前計算

**決定**: フォワーディング制御をIDステージで事前計算し、ID/EXレジスタに格納

**理由**:
- EXステージでフォワーディング判定するとクリティカルパス延長
- IDステージは比較的余裕がある（レジスタ読み出し後）
- 1サイクル前に判定しても、フォワーディングソースは変わらない

**実装**:
```systemverilog
// rv32i_hazard.sv
// IDステージで計算
assign id_rs1_match_ex  = (id_rs1_addr == ex_rd_addr) && ex_rf_wen && ex_valid;
assign id_rs1_match_mem = (id_rs1_addr == mem_rd_addr) && mem_rf_wen && mem_valid;
assign id_rs1_match_wb  = (id_rs1_addr == wb_rd_addr) && wb_rf_wen && wb_valid;

// 優先順位: EX > MEM > WB
assign forward_rs1_sel = id_rs1_match_ex  ? 2'b01 :
                        id_rs1_match_mem ? 2'b10 :
                        id_rs1_match_wb  ? 2'b11 : 2'b00;

// ID/EXレジスタに格納
id_ex_reg.forward_rs1 <= forward_rs1_sel;
```

**メリット**:
- ✅ EXステージのクリティカルパスを短縮
- ✅ フォワーディングMUXがシンプルなcase文で実装可能
- ✅ タイミング解析が容易

### 4. ロード使用ストール戦略

**決定**: 1サイクルストール + MEMステージフォワーディング

**シナリオ**:
```assembly
LW   x1, 0(x2)   # cycle 0: IF, cycle 1: ID, cycle 2: EX, cycle 3: MEM (データ取得), cycle 4: WB
ADD  x3, x1, x4  # cycle 1: IF, cycle 2: ID → STALL, cycle 3: ID (retry), cycle 4: EX (MEMフォワーディング)
```

**理由**:
- BRAMは1サイクル読み出しレイテンシ → MEMステージでデータ確定
- EXステージでデータ必要 → 1サイクル不足 → ストール必須
- MEMステージ結果をEXにフォワーディングすることで、WBステージ到達を待つ必要がない

**実装**:
```systemverilog
// rv32i_hazard.sv
assign load_use_hazard_rs1 = id_rs1_match_ex && ex_is_load;
assign load_use_hazard_rs2 = id_rs2_match_ex && ex_is_load;
assign load_use_stall = (load_use_hazard_rs1 || load_use_hazard_rs2) && id_valid;

assign if_stall = load_use_stall;
assign id_stall = load_use_stall;
```

### 5. 分岐ペナルティ最小化

**決定**: EXステージで分岐判定 + 2サイクルペナルティ（ストール1 + フラッシュ1）

**タイムライン**:
```
Cycle:   0       1       2       3       4
BEQ:     IF  →  ID  →  EX  (判定) →  MEM →  WB
         │       │       │
Target:  │       IF  →  ID (フラッシュ) →  bubble
Next:    │              IF  (正しいターゲット) →  ID  →  EX
```

**理由**:
- IFステージで分岐予測なし（シンプル設計優先）
- IDステージでレジスタ読み出し完了 → EXで比較可能
- 分岐ターゲット計算もEXステージ（ALU利用）

**最適化の余地**:
- 将来的に静的分岐予測（backward taken, forward not-taken）を追加可能
- BTB（Branch Target Buffer）追加で0サイクルペナルティ実現可能（リソース増加）

---

## 実装状況

### 完了機能

- [x] RV32I基本命令セット（40命令すべて）
- [x] 5ステージパイプライン
- [x] 完全なハザード検出・フォワーディング
- [x] ロード使用ストール
- [x] 分岐/ジャンプ制御
- [x] CSRレジスタ（Machine Mode基本4種）
- [x] 例外処理（トラップ、MRET）
- [x] MMIOサポート（LEDレジスタ at 0x407C）
- [x] デバッグインターフェース（外部RAMアクセス）
- [x] ブレークポイント機能（4ポイント）
- [x] 命令トレースバッファ（64エントリ）
- [x] UVM検証環境
- [x] WBフォワーディングタイミング修正（2026/1/5）

### テスト済み

- [x] 算術演算命令（ADD, SUB, AND, OR, XOR, SLT, SLTU）
- [x] 即値演算命令（ADDI, ANDI, ORI, XORI, SLTI, SLTIU）
- [x] シフト命令（SLL, SRL, SRA, SLLI, SRLI, SRAI）
- [x] ロード/ストア命令（LB, LH, LW, LBU, LHU, SB, SH, SW）
- [x] 分岐命令（BEQ, BNE, BLT, BGE, BLTU, BGEU）
- [x] ジャンプ命令（JAL, JALR）
- [x] 上位即値命令（LUI, AUIPC）
- [x] システム命令（EBREAK, MRET, CSRRW, CSRRS, CSRRC）
- [x] ハザードテスト（RAW, load-use, WB forwarding）
- [x] 例外/トラップシーケンス

### 未実装・将来拡張

- [ ] 割り込み処理（外部割り込み、タイマー割り込み）
- [ ] 追加CSR（misa, mhartid, mstatus拡張）
- [ ] デバッグモジュール（JTAG/RISC-V Debug Spec）
- [ ] 性能カウンタ（mcycle, minstret）
- [ ] 分岐予測機構
- [ ] キャッシュ（I-cache, D-cache）
- [ ] MMU/仮想メモリ
- [ ] 乗除算命令（M拡張）
- [ ] アトミック命令（A拡張）
- [ ] 圧縮命令（C拡張）

---

## 次のドキュメント

各パイプラインステージの詳細設計については、以下のドキュメントを参照してください：

- [01_if_stage.md](01_if_stage.md) - Instruction Fetch Stage詳細
- [02_id_stage.md](02_id_stage.md) - Instruction Decode Stage詳細
- [03_hazard_unit.md](03_hazard_unit.md) - Hazard Detection Unit詳細
- [04_ex_stage.md](04_ex_stage.md) - Execute Stage詳細
- [05_mem_stage.md](05_mem_stage.md) - Memory Access Stage詳細
- [06_wb_stage.md](06_wb_stage.md) - Write Back Stage詳細
- [07_csr_module.md](07_csr_module.md) - CSR Module詳細
- [08_integration.md](08_integration.md) - Pipeline Integration詳細

---

**このドキュメントの目的**: 
このドキュメントを読むことで、RV32I CPUコアの全体像、設計思想、主要な実装判断を理解し、個別のモジュール設計ドキュメントに進む準備ができます。
