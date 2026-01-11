# Instruction Fetch (IF) Stage - 詳細設計

**モジュール名:** `rv32i_if`  
**ファイル:** `rtl/cpu/rv32i_if.sv`  
**バージョン:** 1.1  
**最終更新:** 2026年1月5日  
**アサーションモジュール:** `sim/assertions/rv32i_if_timing_spec.sv`

---

## 目次

1. [設計意図](#設計意図)
2. [モジュール概要](#モジュール概要)
3. [ブロック図](#ブロック図)
4. [インターフェース信号](#インターフェース信号)
5. [機能詳細](#機能詳細)
6. [タイミング図](#タイミング図)
7. [実装ガイド](#実装ガイド)
8. [検証ポイント](#検証ポイント)
9. [デバッグガイド](#デバッグガイド)

---

## 設計意図

### なぜこの設計なのか

IFステージは**パイプラインの入り口**であり、以下の要求を満たす必要があります：

1. **毎サイクル命令供給**: IDステージが飢えないよう、連続してフェッチ
2. **即座な制御フロー変更**: 分岐/ジャンプ/例外時の素早いリダイレクト
3. **デバッグ支援**: ブレークポイントによるプログラム停止機能
4. **ハザード対応**: ロード使用時のPC凍結、ミスプレディクション時のフラッシュ

### 主要な設計判断

#### 判断1: PC更新の優先順位（Priority Encoder方式）

**選択肢**:
- A: 全ての制御信号をmutually exclusiveと仮定し、単純なmuxで実装
- B: 優先順位エンコーダで明示的に順序を定義 ✅採用

**理由**:
- 例外とブランチが同時に発生する可能性（例: 分岐命令でアドレス例外）
- trap_redirect > mret_req > branch_taken > sequential の優先順位を明確化
- 将来の拡張（割り込み追加など）でも優先順位が自明

**実装**:
```systemverilog
always_comb begin
    if (trap_redirect)          // 最優先: 例外処理
        pc_next = trap_vector;
    else if (mret_req)          // 次優先: 例外復帰
        pc_next = mret_pc;
    else if (branch_taken)      // 次優先: 分岐・ジャンプ
        pc_next = branch_target;
    else
        pc_next = pc_reg + 4;   // デフォルト: 連続実行
end
```

#### 判断2: ブレークポイントは組み合わせ回路

**選択肢**:
- A: ブレークポイント判定をレジスタ化（1サイクル遅延）
- B: 組み合わせ回路で即座に判定 ✅採用

**理由**:
- デバッグ時は性能より即応性が重要
- PC比較は単純な等価比較（クリティカルパスにならない）
- `cpu_break`フラグをトップレベルのステートマシンで即座に検出可能

**トレードオフ**:
- ✅ 1サイクル早く検出、ブレークポイント直後の命令を実行しない
- ❌ 4つの32ビット比較器がわずかに遅延を追加（約0.5ns @ 125MHz）

#### 判断3: RAMアドレスはワードアドレッシング

**理由**:
- RV32I命令は4バイト固定 → 常にワード境界
- `pc_reg[12:2]`を使用してRAMアドレス生成（11ビット）
- `pc_reg[1:0]`は常に`2'b00`（アライメント保証）

**メモリマップ**:
```
PC[31:0]         pc_reg[12:2]    Block RAM
0x0000_0000  →     0x000    →    ram[0]
0x0000_0004  →     0x001    →    ram[1]
0x0000_0008  →     0x002    →    ram[2]
...
0x0000_1FFC  →     0x7FF    →    ram[2047] (最後のワード)
0x0000_2000以上は未定義（範囲外）
```

---

## モジュール概要

### CPUリセットと初期化シーケンス

CPUの起動時の動作を理解することは、デバッグとシステム設計において重要です。

#### ハードウェアリセット (rst / rst_n)

**注意**: ドキュメントでは`rst_n`（アクティブロー）を使用していますが、RTL実装では`rst`（アクティブハイ）を使用する場合があります。両者は同じ物理リセット信号を指します。

**リセット時の初期状態** (サイクル0):
```
Pipeline Registers:  すべて0にクリア（valid=0）
PC:                  0x0000_0000（リセットベクタ）
CSR Registers:
  mtvec:            0x0000_1000（デフォルトトラップハンドラアドレス）
  mepc:             0x0000_0000
  mcause:           0x0000_0000
  mtval:            0x0000_0000
Register File:
  x0 (zero):        0x0000_0000（硬配線、常時）
  x1-x31:           0x0000_0000（クリア）
Debug Interface:
  dbg_bp_enable:    4'b0000（全ブレークポイント無効）
  dbg_cpu_halted:   1'b1（CPU停止状態）
```

**リセット解除後の動作** (サイクル1以降):
```
Cycle 1:
  IF:   PC=0x0000_0000から命令フェッチ開始
        insn_ram_addr = 0x000
  ID:   Bubble (valid=0, NOP)
  EX:   Bubble (valid=0, NOP)
  MEM:  Bubble (valid=0, NOP)
  WB:   Bubble (valid=0, NOP)

Cycle 2:
  IF:   PC=0x0000_0004の命令をフェッチ
  ID:   0x0000_0000番地の命令をデコード
  EX:   Bubble
  MEM:  Bubble
  WB:   Bubble

Cycle 3:
  IF:   PC=0x0000_0008の命令をフェッチ
  ID:   0x0000_0004番地の命令をデコード
  EX:   0x0000_0000番地の命令を実行
  MEM:  Bubble
  WB:   Bubble

...（パイプラインが徐々に埋まる）

Cycle 6:
  WB:   0x0000_0000番地の命令が完了（最初の命令がWBステージに到達）
```

**典型的なブートコード**:
```assembly
# リセットベクタ (0x0000_0000番地)
_start:
    # スタックポインタ初期化
    lui  sp, 0x2        # sp = 0x0000_2000（RAM範囲外から開始）
    
    # グローバルポインタ初期化（オプション）
    lui  gp, 0x1        # gp = 0x0000_1000
    addi gp, gp, 0x800  # gp = 0x0000_1800（中央値）
    
    # BSS領域をゼロクリア（オプション）
    # ... (省略)
    
    # main関数へジャンプ
    jal  ra, main       # main()を呼び出し
    
    # main()から戻った場合の処理
_end:
    j    _end           # 無限ループ（CPUを停止）
```

#### ソフトウェアリセット (dbg_soft_reset)

デバッグインターフェース経由でCPUを再起動できます。ハードウェアリセットと同じ効果を持ちますが、外部ピンを操作する必要がありません。

**トリガー方法**:
```python
# Python example using AXIUARTDriver
driver.write_register(REG_DBG_CTRL, 0x0001)  # soft_reset bit = 1
```

**タイミング**:
```
Cycle N:   dbg_soft_reset=1 を検出
Cycle N+1: soft_reset_active=1
           - パイプライン全体をフラッシュ（バブル注入）
           - PC = 0x0000_0000
           - CSRs = 初期値
Cycle N+2: soft_reset_active=0
           - 通常実行再開（0x0000_0000番地から）
```

**使用例**:
1. 新しいプログラムをRAMにロード
2. ソフトウェアリセットをトリガー
3. CPUが0x0000_0000から実行開始

#### デバッグ制御実行フロー

デバッグインターフェースを使用したプログラム実行の標準手順：

**ステップ1: プログラムロード**（CPU停止状態）
```python
# RAMにプログラムを書き込み
for addr in range(0x0000, 0x1FFF, 4):
    driver.write_cpu_mem(addr, instruction[addr//4])
```

**ステップ2: ブレークポイント設定**（オプション）
```python
# ブレークポイント0を0x0000_0010に設定
driver.write_register(REG_DBG_BP0_ADDR, 0x00000010)
driver.write_register(REG_DBG_BP_CTRL, 0x00000001)  # Enable BP0
```

**ステップ3: CPU実行開始**
```python
# dbg_cpu_run = 1（W1P: Write-One-Pulse）
driver.write_register(REG_DBG_CTRL, 0x0100)
```
```
Cycle M:   dbg_cpu_run=1を検出
Cycle M+1: dbg_cpu_halted=0（実行開始）
           IF: PC=0x0000_0000から命令フェッチ開始
```

**ステップ4: 実行状態監視**
```python
# CPU状態をポーリング
while True:
    status = driver.read_register(REG_CPU_STATUS)
    if status & CPU_HALTED:
        # CPU停止（ブレークポイントヒットまたは完了）
        bp_hit = (status >> 16) & 0xF  # bp_hit[3:0]
        if bp_hit:
            print(f"Breakpoint {bp_hit} hit")
        break
```

**ステップ5: レジスタ確認**
```python
# 全レジスタを読み出し
for i in range(32):
    value = driver.read_cpu_register(i)
    abi_name = ["zero", "ra", "sp", ...][i]  # ABI名参照
    print(f"x{i} ({abi_name}) = 0x{value:08X}")
```

**ステップ6: シングルステップ実行**（オプション）
```python
# 1命令ずつ実行
for step in range(10):
    driver.write_register(REG_DBG_CTRL, 0x0200)  # dbg_cpu_step=1
    time.sleep(0.001)  # 処理待ち
    pc = driver.read_register(REG_DBG_PC)
    insn = driver.read_cpu_mem(pc)
    print(f"Step {step}: PC=0x{pc:08X}, Insn=0x{insn:08X}")
```

**ステップ7: 実行再開**
```python
# ブレークポイント後に実行を継続
driver.write_register(REG_DBG_BP_CTRL, 0x00000000)  # Clear BP
driver.write_register(REG_DBG_CTRL, 0x0100)         # Run
```

#### 注意事項

**スタックオーバーフロー**:
- RAM範囲: 0x0000 - 0x1FFF
- スタック初期値: 0x2000（範囲外）
- スタックは下方向に成長（sp デクリメント）
- 深いネストでRAM下限（0x0000）に到達する可能性
- **対策**: ソフトウェアでスタックポインタ監視（例外機構は未実装）

**RAM書き込みタイミング**:
- デバッグアクセスはMEMステージとPort Bを共有
- CPU実行中のRAM書き込みは競合の可能性
- **推奨**: CPU停止状態（dbg_cpu_halted=1）でRAMをロード

**ブレークポイント制約**:
- 最大4個まで同時設定可能
- PCと比較（命令実行前に検出）
- ヒット時は即座にCPU停止（`dbg_cpu_halted=1`）

---

### 責務

IFステージは以下の5つの主要責務を持ちます：

1. **PC管理**: 32ビットプログラムカウンタの保持と更新
2. **命令フェッチ**: Block RAM Port AからのROM読み出し
3. **PCリダイレクト**: 分岐/ジャンプ/例外時のターゲットアドレス設定
4. **ブレークポイント検出**: 4つのハードウェアブレークポイントとの比較
5. **パイプライン制御**: ストール（凍結）とフラッシュ（バブル注入）への対応

### 入出力概要

- **入力**: クロック、リセット、制御信号（stall/flush/branch/trap）、RAM読み出しデータ
- **出力**: RAMアドレス、IF/IDレジスタ（pc, insn, valid）、デバッグフラグ

---

## ブロック図

```
                      ┌───────────────────────────────────────────────┐
                      │           rv32i_if Module                     │
                      │                                               │
                      │  ┌──────────┐                                 │
                      │  │PC Register│                                │
                      │  │  32-bit   │                                │
                      │  │    FF     │                                │
                      │  └─────┬─────┘                                │
                      │        │ pc_reg[31:0]                         │
                      │        ├─────────────────┐                    │
                      │        │                 │                    │
                      │        ▼                 ▼                    │
                      │  ┌──────────┐      ┌──────────┐              │
                      │  │ PC + 4   │      │Breakpoint│              │
                      │  │  Adder   │      │Comparator│              │
                      │  └────┬─────┘      │   x 4    │              │
                      │       │            └─────┬────┘              │
                      │       │                  │ dbg_bp_hit[3:0]   │
                      │       ▼                  ▼                    │
 trap_redirect ───────┼─────►┌──────────────────────┐                │
 trap_vector[31:0] ───┼─────►│   PC Source MUX      │                │
 mret_req ────────────┼─────►│   (4-way priority)   │                │
 mret_pc[31:0] ───────┼─────►│                      │                │
 branch_taken ────────┼─────►│  Priority:           │                │
 branch_target[31:0] ─┼─────►│  1. trap_redirect    │                │
                      │      │  2. mret_req         │                │
                      │      │  3. branch_taken     │                │
                      │      │  4. pc + 4           │                │
                      │      └──────────┬───────────┘                │
                      │                 │ pc_next[31:0]              │
                      │                 │                            │
                      │                 ▼                            │
 if_stall ────────────┼────────►  PC Enable Logic                    │
                      │          (freeze when stalled)               │
                      │                 │                            │
                      │                 └────────► pc_reg update     │
                      │                                               │
                      │         ┌─────────────────────────┐          │
                      │         │ Valid Control Logic     │          │
 if_flush ────────────┼────────►│ (bubble on flush)       │          │
                      │         └───────────┬─────────────┘          │
                      │                     │                        │
                      │         ┌───────────▼─────────────┐          │
                      │         │  IF/ID Pipeline Reg     │          │
                      │         │                         │          │
 pc_reg ──────────────┼────────►│  if_id_pc[31:0]         │──────────┼──► to ID stage
 insn_ram_rdata[31:0]─┼────────►│  if_id_insn[31:0]       │──────────┼──► to ID stage
                      │         │  if_id_valid            │──────────┼──► to ID stage
                      │         └─────────────────────────┘          │
                      │                                               │
                      │  pc_reg[12:2]                                │
                      │       │                                       │
                      └───────┼───────────────────────────────────────┘
                              │
                              ▼
                        insn_ram_addr[10:0] ───► to Block RAM Port A
                        
                        insn_ram_rdata[31:0] ◄─── from Block RAM Port A
```

---

## インターフェース信号

### 入力信号

| 信号名 | ビット幅 | ソース | 説明 |
|--------|----------|--------|------|
| `clk` | 1 | System | システムクロック（正エッジトリガ） |
| `rst_n` | 1 | System | 非同期アクティブローリセット |
| **制御入力** ||||
| `if_stall` | 1 | rv32i_hazard | IFステージストール（PCとIF/IDレジスタを凍結） |
| `if_flush` | 1 | rv32i_hazard | IFステージフラッシュ（バブル注入、valid=0） |
| **PCリダイレクト** ||||
| `branch_taken` | 1 | rv32i_ex | 分岐/ジャンプ条件成立（EXステージ） |
| `branch_target[31:0]` | 32 | rv32i_ex | 分岐/ジャンプターゲットPC |
| `trap_redirect` | 1 | rv32i_csr | 例外トラップ発生 |
| `trap_vector[31:0]` | 32 | rv32i_csr | トラップハンドラPC（mtpecから） |
| `mret_req` | 1 | rv32i_mem | MRET命令（MEMステージ） |
| `mret_pc[31:0]` | 32 | rv32i_csr | 復帰PC（mepcから） |
| **メモリインターフェース** ||||
| `insn_ram_rdata[31:0]` | 32 | Block RAM | Port Aから読み出した命令データ |
| **デバッグインターフェース** ||||
| `dbg_bp_enable[3:0]` | 4 | Debug I/F | ブレークポイント有効フラグ |
| `dbg_bp_addr[i][31:0]` | 32×4 | Debug I/F | ブレークポイントアドレス（4個） |
| `running` | 1 | Top Level | CPU動作中フラグ（HALTED時=0） |

### 出力信号

| 信号名 | ビット幅 | 宛先 | 説明 |
|--------|----------|------|------|
| **メモリインターフェース** ||||
| `insn_ram_addr[10:0]` | 11 | Block RAM | Port Aワードアドレス（pc[12:2]） |
| **デバッグインターフェース** ||||
| `dbg_bp_hit[3:0]` | 4 | Debug I/F | ブレークポイントヒットフラグ |
| `cpu_break` | 1 | Top Level | EBREAKまたはBP検出（CPUハルト要求） |
| **IF/IDパイプラインレジスタ** ||||
| `if_id_valid` | 1 | rv32i_id | 命令有効フラグ（フラッシュ時=0） |
| `if_id_pc[31:0]` | 32 | rv32i_id | フェッチした命令のPC |
| `if_id_insn[31:0]` | 32 | rv32i_id | フェッチした命令ワード |

---

## 機能詳細

### 5.1 PC更新ロジック

**優先順位エンコーディング方式**:

```systemverilog
// PC次値の決定（組み合わせロジック）
always_comb begin
    if (trap_redirect)
        pc_next = trap_vector;          // 優先度1: 例外トラップ
    else if (mret_req)
        pc_next = mret_pc;              // 優先度2: MRET復帰
    else if (branch_taken)
        pc_next = branch_target;        // 優先度3: 分岐/ジャンプ
    else
        pc_next = pc_reg + 4;           // 優先度4: 連続実行（デフォルト）
end

// PCレジスタ更新（同期ロジック）
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        pc_reg <= 32'h0000_0000;        // リセットベクタ
    else if (!if_stall)
        pc_reg <= pc_next;              // ストール時以外は更新
    // else: 現在値を保持（ストール時）
end
```

**重要ポイント**:
- リセットベクタは`0x0000_0000`（Block RAMの先頭）
- `if_stall`がアサートされるとPC凍結（ロード使用ハザード時など）
- PCは常に4バイト境界（命令ワードサイズ）

**優先順位の根拠**:
1. **例外**: 最高優先。ハードウェア例外は即座に処理必須
2. **MRET**: 例外復帰。例外ハンドラ完了時の復帰
3. **分岐/ジャンプ**: 通常の制御フロー変更
4. **連続実行**: デフォルト動作

---

### 5.2 命令RAMアドレス生成

```systemverilog
// バイトアドレスからワードアドレスへの変換
assign insn_ram_addr = pc_reg[12:2];  // ビット[12:2]を抽出して11ビットワードアドレス

// 有効アドレス範囲: 0x000 - 0x7FF（2048ワード = 8KB）
```

**アドレスマッピング**:
```
PCバイトアドレス    ワードアドレス    Block RAM位置
0x0000_0000   →     0x000      →    ram[0]
0x0000_0004   →     0x001      →    ram[1]
0x0000_0008   →     0x002      →    ram[2]
...
0x0000_1FFC   →     0x7FF      →    ram[2047]（最終ワード）
```

**アドレス範囲外アクセス**:
- `pc >= 0x2000`の場合、`pc[12:2]`は11ビットに収まり、自然にラップアラウンド
- 範囲外アクセスは未定義動作（例外検出はMEMステージで実装可能）

---

### 5.3 ハードウェアブレークポイント検出

```systemverilog
// ブレークポイントヒット検出（組み合わせロジック）
generate
    for (genvar i = 0; i < 4; i++) begin : gen_bp_detect
        assign dbg_bp_hit[i] = dbg_bp_enable[i] &&      // 有効かつ
                               (pc_reg == dbg_bp_addr[i]) &&  // PC一致かつ
                               running;                       // CPU動作中
    end
endgenerate

// CPUブレークフラグ（任意のBPヒットでハルト要求）
assign cpu_break = |dbg_bp_hit;  // ORリダクション
```

**動作**:
- **ブレークポイントヒット**: `dbg_bp_hit[i]`がアサートされる条件：
  1. ブレークポイント有効（`dbg_bp_enable[i] = 1`）
  2. PCがBPアドレスと一致（`pc_reg == dbg_bp_addr[i]`）
  3. CPU動作中（`running = 1`、既にハルト済みでない）
- **ハルトトリガ**: `cpu_break`フラグによりCPUステートマシンがHALTED状態に遷移
- **優先度**: 毎サイクルチェック、次クロックエッジでハルト適用

**複数BP同時ヒット**:
- 複数のBPが同時にヒットした場合、`dbg_bp_hit`の複数ビットがアサート
- `cpu_break`は単一フラグなので、どのBPがトリガしたかは`dbg_bp_hit`ベクタで識別

---

### 5.4 Valid信号制御

```systemverilog
// IF/IDパイプラインレジスタvalid ロジック
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        if_id_valid <= 1'b0;            // リセット時: 無効
    else if (if_flush)
        if_id_valid <= 1'b0;            // フラッシュ: バブル注入（無効命令）
    else if (!if_stall)
        if_id_valid <= 1'b1;            // 通常動作: 有効命令伝播
    // else: 前の値を保持（ストール時）
end
```

**バブル注入シナリオ**:
1. **リセット**: 最初のフェッチまで全命令無効
2. **フラッシュ（if_flush）**: 分岐ミスプレディクション、例外リダイレクト時
3. **ストール（if_stall）**: validビット保持（命令をIDステージに再提示）

**validビットの意味**:
- `valid = 1`: 正常な命令、後続ステージで実行すべき
- `valid = 0`: バブル（NOP相当）、後続ステージはスキップ

---

### 5.5 IF/IDパイプラインレジスタ

```systemverilog
// パイプラインレジスタ更新
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        if_id_pc   <= 32'h0;
        if_id_insn <= 32'h0000_0013;    // NOP（ADDI x0, x0, 0）
    end else if (!if_stall) begin
        if_id_pc   <= pc_reg;
        if_id_insn <= insn_ram_rdata;
    end
    // else: 前の値を保持（ストール時）
end
```

**リセット値**:
- `if_id_insn = 0x0000_0013`（NOP命令）
  - IDステージで誤ったデコードを防ぐため、無害な命令で初期化

**ストール時動作**:
- PCと命令を保持、IDステージに同じ命令を再提示
- Load-use hazard時にIDステージが再デコード・再評価可能

---

## タイミング図

### 6.1 通常連続実行

```
Clock    : _/‾\_/‾\_/‾\_/‾\_/‾\_
           
Cycle    :   0    1    2    3    4
           
pc_reg   : 0x00| 0x04| 0x08| 0x0C| 0x10
           
if_stall : __________________________
if_flush : __________________________
           
insn_ram_: 0x00| 0x01| 0x02| 0x03| 0x04
addr     :     |     |     |     |
           
insn_ram_: ????| I_0 | I_1 | I_2 | I_3
rdata    :     |(0x0)|(0x4)|(0x8)|(0xC)
           
if_id_pc : 0x00| 0x00| 0x04| 0x08| 0x0C
           
if_id_   : NOP | I_0 | I_1 | I_2 | I_3
insn     :(rst)|     |     |     |
           
if_id_   :  0  |  1  |  1  |  1  |  1
valid    :     |     |     |     |
```

**説明**: 
- PCは毎サイクル+4ずつインクリメント
- 命令は順次フェッチされ、IF/IDレジスタに格納
- Cycle 0はリセット後の初期状態（NOP）

---

### 6.2 分岐Taken（パイプラインフラッシュ）

```
Clock    : _/‾\_/‾\_/‾\_/‾\_/‾\_
           
Cycle    :   0    1    2    3    4
           
pc_reg   : 0x00| 0x04| 0x08|0x100|0x104
                            \____/
                          branch_target
           
branch_  : ______________/‾‾‾‾\________
taken    :               (cyc 2)
           
branch_  : xxxxxxxxxxxx|0x100|xxxxxxxxx
target   :             |     |
           
if_flush : _______________/‾‾‾‾\______
           :               (cyc 3)
           
if_id_pc : 0x00| 0x04| 0x08| 0x08|0x100
                             \___/
                            flushed
           
if_id_   : I_0 | I_1 | I_2 | I_2 |I_TGT
insn     :     |     |     |(flsh)|
           
if_id_   :  1  |  1  |  1  |  0  |  1
valid    :     |     |     |BUBBL|
```

**説明**:
1. Cycle 2で`branch_taken`検出
2. Cycle 3でPCが`branch_target`（0x100）にリダイレクト
3. Cycle 3でIFステージフラッシュ（バブル注入）
4. Cycle 4で正しいターゲット命令フェッチ

**分岐ペナルティ**: 2サイクル（検出1 + フラッシュ1）

---

### 6.3 Load-Useストール

```
Clock    : _/‾\_/‾\_/‾\_/‾\_/‾\_
           
Cycle    :   0    1    2    3    4
           
pc_reg   : 0x00| 0x04| 0x04| 0x04| 0x08
                      \____/\____/
                      stalled stalled
           
if_stall : _______/‾‾‾‾‾‾‾‾‾‾‾‾\_____
           :       (cycle 1-2)
           
insn_ram_: 0x00| 0x01| 0x01| 0x01| 0x02
addr     :     |     |(hold)|(hold)|
           
if_id_pc : 0x00| 0x00| 0x04| 0x04| 0x04
                      \____/\____/
                      repeated repeated
           
if_id_   : NOP | I_0 | I_1 | I_1 | I_1
insn     :(rst)|     |(hold)|(hold)|
           
if_id_   :  0  |  1  |  1  |  1  |  1
valid    :     |     |(hold)|(hold)|
```

**説明**:
1. Cycle 1-2でIFステージストール（IDステージでload-use hazard検出）
2. PCは0x04で凍結
3. IF/IDレジスタ出力は保持（命令I_1をIDステージに再提示）
4. Cycle 3でストール解除、PCが再開

**ストール目的**: IDステージが依存関係を解決するまでIFを待機

---

### 6.4 ハードウェアブレークポイントヒット

```
Clock    : _/‾\_/‾\_/‾\_/‾\_/‾\_
           
Cycle    :   0    1    2    3    4
           
pc_reg   : 0x00| 0x04| 0x08| 0x08| 0x08
                             \____/\____/
                             frozen frozen
           
dbg_bp_  : ______________/‾‾‾‾‾‾‾‾‾‾‾‾‾
hit[0]   :               (BP hit)
           
cpu_     : ______________/‾‾‾‾‾‾‾‾‾‾‾‾‾
break    :               (triggers halt)
           
running  :  1  |  1  |  1  |  0  |  0
           :     |     |     |HALT |HALT
           
if_id_   : I_0 | I_1 | I_2 | I_2 | I_2
insn     :     |     |     |(frzn)|(frzn)
```

**説明**:
1. Cycle 2でPCがブレークポイントアドレス（0x08）到達
2. `dbg_bp_hit[0]`がアサート
3. `cpu_break`フラグによりCPUステートマシンがHALT遷移
4. Cycle 3以降、PCとパイプライン凍結

**用途**: デバッグ時の特定アドレスでの停止、レジスタ/メモリ検査

---

### 6.5 例外トラップリダイレクト

```
Clock    : _/‾\_/‾\_/‾\_/‾\_/‾\_
           
Cycle    :   0    1    2    3    4
           
pc_reg   : 0x00| 0x04| 0x08|0x1000|0x1004
                             \____/
                           trap_vector
           
trap_    : ______________/‾‾‾‾\________
redirect :               (cyc 2)
           
trap_    : xxxxxxxxxxxx|0x1000|xxxxxxx
vector   :             |      |
           
if_flush : _______________/‾‾‾‾\______
           :               (cyc 3)
           
if_id_pc : 0x00| 0x04| 0x08| 0x08|0x1000
                             \___/
                            flushed
           
if_id_   : I_0 | I_1 | I_2 | I_2 |TRAP
insn     :     |     |     |(flsh)|HDL
           
if_id_   :  1  |  1  |  1  |  0  |  1
valid    :     |     |     |BUBBL|
```

**説明**:
1. Cycle 1でMEMステージで例外検出
2. Cycle 2で`trap_redirect`アサート
3. Cycle 3でPCが`trap_vector`（0x1000）にリダイレクト
4. Cycle 3でIFステージフラッシュ
5. Cycle 4でトラップハンドラ命令フェッチ

**例外種類**: アドレスミスアライメント、不正命令、EBREAK、外部割り込み（将来）

---

## 実装ガイド

### 7.1 コーディング例: PC更新ロジック

**ステップ1: 組み合わせロジックでpc_next決定**

```systemverilog
// ファイル: rv32i_if.sv
logic [31:0] pc_reg;       // 現在のPC（レジスタ）
logic [31:0] pc_next;      // 次のPC（組み合わせ）

always_comb begin
    // 優先順位エンコーダ方式
    if (trap_redirect)
        pc_next = trap_vector;
    else if (mret_req)
        pc_next = mret_pc;
    else if (branch_taken)
        pc_next = branch_target;
    else
        pc_next = pc_reg + 32'd4;  // 明示的に32ビット幅の4を加算
end
```

**ステップ2: 同期ロジックでPC更新**

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pc_reg <= 32'h0000_0000;    // リセットベクタ
    end else if (!if_stall) begin
        pc_reg <= pc_next;          // ストール時以外は更新
    end
    // else: pc_reg保持（ストール時）
end
```

**注意事項**:
- `pc_reg + 4`は32ビット加算器を生成（約1ns遅延 @ 125MHz）
- ストール時に`pc_next`の計算は継続されるが、レジスタ更新されない

---

### 7.2 コーディング例: ブレークポイント検出

```systemverilog
// パラメータ定義
localparam NUM_BREAKPOINTS = 4;

// 入力ポート
input logic [NUM_BREAKPOINTS-1:0] dbg_bp_enable;
input logic [31:0] dbg_bp_addr [NUM_BREAKPOINTS];
input logic running;

// 出力ポート
output logic [NUM_BREAKPOINTS-1:0] dbg_bp_hit;
output logic cpu_break;

// ブレークポイントヒット検出（組み合わせロジック）
generate
    for (genvar i = 0; i < NUM_BREAKPOINTS; i++) begin : gen_bp_detect
        always_comb begin
            dbg_bp_hit[i] = dbg_bp_enable[i] && 
                            (pc_reg == dbg_bp_addr[i]) && 
                            running;
        end
    end
endgenerate

// CPUブレークフラグ（ORリダクション）
assign cpu_break = |dbg_bp_hit;
```

**実装上の注意**:
- `generate`ブロックで4つの比較器を生成
- 各比較器は独立（パラレル動作、遅延は1つと同じ）
- `cpu_break`はトップレベルのステートマシンに接続

---

### 7.3 コーディング例: IF/IDパイプラインレジスタ

```systemverilog
// パイプラインレジスタ定義
logic        if_id_valid;
logic [31:0] if_id_pc;
logic [31:0] if_id_insn;

// Valid信号制御
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        if_id_valid <= 1'b0;
    else if (if_flush)
        if_id_valid <= 1'b0;        // バブル注入
    else if (!if_stall)
        if_id_valid <= 1'b1;        // 通常伝播
    // else: 保持（ストール時）
end

// PCと命令のレジスタ化
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        if_id_pc   <= 32'h0;
        if_id_insn <= 32'h0000_0013;    // NOP
    end else if (!if_stall) begin
        if_id_pc   <= pc_reg;
        if_id_insn <= insn_ram_rdata;
    end
    // else: 保持（ストール時）
end
```

**設計ポイント**:
- **3つの独立した信号**: valid, pc, insn
- **ストール時**: 3つとも保持（IDステージに同じ命令再提示）
- **フラッシュ時**: validのみクリア、pc/insnは保持（デバッグ時に確認可能）

---

### 7.4 RAMアドレス生成

```systemverilog
// Block RAM Port Aアドレス出力
assign insn_ram_addr = pc_reg[12:2];

// Block RAM読み出しレイテンシ: 1サイクル
// Cycle N: pc_reg更新 → insn_ram_addr出力
// Cycle N+1: insn_ram_rdata有効 → if_id_insn格納
```

**タイミング考慮**:
- RAMは1サイクル読み出し（BRAMの特性）
- `insn_ram_rdata`はCycle N+1で有効
- IF/IDレジスタも同じサイクルで更新 → 同期

---

## 検証ポイント

### 8.1 アサーションチェックリスト

以下のプロパティは`rv32i_if_timing_spec.sv`で検証されます：

#### **SPEC-IF-1: PC連続インクリメント**
```systemverilog
// ストール・フラッシュ・リダイレクトがない場合、PCは+4
property pc_increments_sequentially;
    @(posedge clk) disable iff (!rst_n)
    (!if_stall && !if_flush && !branch_taken && !trap_redirect && !mret_req)
    |=> (pc_reg == $past(pc_reg) + 4);
endproperty

assert_pc_sequential: assert property (pc_increments_sequentially)
    else $error("[IF_SPEC] PC did not increment sequentially");
```

#### **SPEC-IF-2: 分岐リダイレクト**
```systemverilog
// branch_taken時にbranch_targetへジャンプ
property pc_redirects_on_branch;
    logic [31:0] expected_target;
    @(posedge clk) disable iff (!rst_n)
    (branch_taken, expected_target = branch_target)
    |=> (pc_reg == expected_target);
endproperty

assert_pc_branch: assert property (pc_redirects_on_branch)
    else $error("[IF_SPEC] PC did not redirect to branch_target");
```

#### **SPEC-IF-3: トラップベクタリダイレクト**
```systemverilog
// trap_redirect時にtrap_vectorへジャンプ
property pc_redirects_on_trap;
    logic [31:0] expected_vector;
    @(posedge clk) disable iff (!rst_n)
    (trap_redirect, expected_vector = trap_vector)
    |=> (pc_reg == expected_vector);
endproperty

assert_pc_trap: assert property (pc_redirects_on_trap)
    else $error("[IF_SPEC] PC did not redirect to trap_vector");
```

#### **SPEC-IF-4: PCストール動作**
```systemverilog
// if_stall時にPC凍結
property pc_freezes_on_stall;
    logic [31:0] stalled_pc;
    @(posedge clk) disable iff (!rst_n)
    (if_stall, stalled_pc = pc_reg)
    |=> (pc_reg == stalled_pc);
endproperty

assert_pc_stall: assert property (pc_freezes_on_stall)
    else $error("[IF_SPEC] PC changed during stall");
```

#### **SPEC-IF-5: ブレークポイントヒット検出**
```systemverilog
generate
    for (genvar i = 0; i < 4; i++) begin : gen_bp_assertions
        property bp_hit_detected;
            @(posedge clk) disable iff (!rst_n)
            (dbg_bp_enable[i] && (pc_reg == dbg_bp_addr[i]) && running)
            |-> (dbg_bp_hit[i] == 1'b1);
        endproperty
        
        assert_bp_hit: assert property (bp_hit_detected)
            else $error("[IF_SPEC] Breakpoint %0d not detected at PC=0x%08X", i, pc_reg);
    end
endgenerate
```

#### **SPEC-IF-6: Validビットフラッシュ**
```systemverilog
// if_flush時にvalidクリア
property valid_cleared_on_flush;
    @(posedge clk) disable iff (!rst_n)
    if_flush |=> (if_id_valid == 1'b0);
endproperty

assert_valid_flush: assert property (valid_cleared_on_flush)
    else $error("[IF_SPEC] Valid not cleared on flush");
```

#### **SPEC-IF-7: RAMアドレス正確性**
```systemverilog
// RAMアドレスがPCワードアドレスと一致
property ram_addr_matches_pc;
    @(posedge clk) disable iff (!rst_n)
    (insn_ram_addr == pc_reg[12:2]);
endproperty

assert_ram_addr: assert property (ram_addr_matches_pc)
    else $error("[IF_SPEC] RAM address mismatch: expected 0x%03X, got 0x%03X", pc_reg[12:2], insn_ram_addr);
```

---

### 8.2 カバレッジ目標

#### **PCリダイレクトカバレッジ**:
- [ ] 連続実行（ベースライン）
- [ ] 分岐taken
- [ ] ジャンプ（JAL/JALR）
- [ ] トラップリダイレクト
- [ ] MRET復帰

#### **ストール/フラッシュカバレッジ**:
- [ ] 通常動作（ストールなし、フラッシュなし）
- [ ] ストールのみ
- [ ] フラッシュのみ
- [ ] ストール+フラッシュ同時

#### **ブレークポイントカバレッジ**:
- [ ] 各ブレークポイント[3:0]が個別にヒット
- [ ] 複数ブレークポイント同時ヒット
- [ ] ストール中にブレークポイントヒット
- [ ] ブレークポイント無効時に誤検出なし

#### **エッジケース**:
- [ ] PCラップアラウンド（0x1FFC → 0x0000）
- [ ] 高速ストール/フラッシュトグル
- [ ] ストール中のリダイレクト

---

## デバッグガイド

### 9.1 よくある問題と対処法

#### **問題1: PCが更新されない**

**症状**: `pc_reg`が同じ値で停止

**原因候補**:
1. `if_stall`が常時アサート → ハザードユニットをチェック
2. `cpu_break`がアサートされCPUハルト → `dbg_bp_hit`を確認
3. クロックが供給されていない → 波形確認

**デバッグステップ**:
```systemverilog
// アサーションでストール原因を特定
assert property (@(posedge clk) if_stall |-> ##[1:10] !if_stall)
    else $warning("[IF_DEBUG] Prolonged stall detected");
```

#### **問題2: 分岐ターゲットが誤る**

**症状**: `branch_taken`後、PCが意図しないアドレスへジャンプ

**原因候補**:
1. `branch_target`の計算ミス（EXステージ） → EXステージをデバッグ
2. 優先順位エンコーダのバグ → `trap_redirect`や`mret_req`が同時にアサート

**デバッグステップ**:
```systemverilog
// ブランチ時のPC遷移をトレース
always @(posedge clk) begin
    if (branch_taken)
        $display("[IF_DEBUG] Branch: PC=0x%08X → Target=0x%08X", pc_reg, branch_target);
end
```

#### **問題3: ブレークポイントが検出されない**

**症状**: PCがBPアドレスを通過してもCPU停止しない

**原因候補**:
1. `dbg_bp_enable[i]`が設定されていない
2. `running`フラグが0（CPUが既にハルト状態）
3. アドレス比較ミス → `dbg_bp_addr[i]`の値を確認

**デバッグステップ**:
```systemverilog
// BP条件を詳細表示
generate
    for (genvar i = 0; i < 4; i++) begin
        always @(posedge clk) begin
            if (pc_reg == dbg_bp_addr[i])
                $display("[IF_DEBUG] BP[%0d]: PC=0x%08X, Enable=%b, Running=%b, Hit=%b", 
                         i, pc_reg, dbg_bp_enable[i], running, dbg_bp_hit[i]);
        end
    end
endgenerate
```

#### **問題4: バブル注入後もvalid=1のまま**

**症状**: `if_flush`後も`if_id_valid`がクリアされない

**原因候補**:
1. `if_flush`信号が届いていない → ハザードユニットの出力確認
2. `if_stall`が同時にアサート → ストールが優先されvalidが保持

**修正方法**:
```systemverilog
// フラッシュを優先する場合はロジック変更
if (!rst_n || if_flush)
    if_id_valid <= 1'b0;
else if (!if_stall)
    if_id_valid <= 1'b1;
```

---

### 9.2 デバッグ用表示文

```systemverilog
// デバッグモード（シミュレーション専用）
`ifdef DEBUG_IF_STAGE
always @(posedge clk) begin
    $display("================== IF Stage Debug ==================");
    $display("  PC: 0x%08X → 0x%08X", pc_reg, pc_next);
    $display("  RAM Addr: 0x%03X, Data: 0x%08X", insn_ram_addr, insn_ram_rdata);
    $display("  Control: stall=%b, flush=%b", if_stall, if_flush);
    $display("  Redirect: branch=%b(0x%08X), trap=%b(0x%08X), mret=%b(0x%08X)",
             branch_taken, branch_target, trap_redirect, trap_vector, mret_req, mret_pc);
    $display("  IF/ID: valid=%b, pc=0x%08X, insn=0x%08X", if_id_valid, if_id_pc, if_id_insn);
    $display("  Breakpoint: hit=%b, cpu_break=%b", dbg_bp_hit, cpu_break);
    $display("====================================================");
end
`endif
```

**使用方法**: コンパイル時に`+define+DEBUG_IF_STAGE`を追加

---

### 9.3 波形確認ポイント

**必須信号**:
1. `clk`, `rst_n`
2. `pc_reg[31:0]`, `pc_next[31:0]`
3. `if_stall`, `if_flush`
4. `branch_taken`, `branch_target[31:0]`
5. `insn_ram_addr[10:0]`, `insn_ram_rdata[31:0]`
6. `if_id_valid`, `if_id_pc[31:0]`, `if_id_insn[31:0]`

**確認手順**:
1. PCが+4ずつ連続的に更新されているか
2. 分岐時にPC遷移が正しいか
3. ストール時にPCが凍結しているか
4. フラッシュ時にvalidが0になっているか
5. RAMアドレスがPC[12:2]と一致しているか

---

## 関連ドキュメント

- **[00_overview.md](00_overview.md)** - CPU全体アーキテクチャ
- **[02_id_stage.md](02_id_stage.md)** - IDステージ（命令デコード）
- **[03_hazard_unit.md](03_hazard_unit.md)** - ハザードユニット（ストール/フラッシュ生成）
- **[04_ex_stage.md](04_ex_stage.md)** - EXステージ（分岐判定）
- **[07_csr_module.md](07_csr_module.md)** - CSRモジュール（トラップベクタ）

---

**このドキュメントの目的**: 
IFステージの**設計意図**、**実装方法**、**デバッグ手法**を理解し、コードレベルで正確に実装・検証できる知識を提供します。
