# Hazard Detection Unit - 詳細設計

**モジュール名:** `rv32i_hazard`  
**ファイル:** `rtl/cpu/rv32i_hazard.sv`  
**バージョン:** 1.1  
**最終更新:** 2026年1月5日

---

## 設計意図

### なぜこの設計なのか

ハザードユニットは**パイプラインの正確性を保証する中枢**です：

1. **RAWハザード検出**: Read-After-Write依存関係を早期発見
2. **フォワーディング制御**: データを必要とするステージに即座に供給
3. **ストール生成**: ロード使用時の1サイクルペナルティを最小化
4. **フラッシュ制御**: 分岐/例外時の誤った命令を無効化

### 主要な設計判断

#### 判断1: フォワーディング制御をIDステージで事前計算 ✅

**理由**:
- EXステージのクリティカルパス短縮（フォワーディングMUX → ALU）
- IDステージは比較的余裕がある（レジスタ読み出し後）
- 1サイクル前に計算しても、フォワーディングソースは変わらない

**実装**:
```
IDステージ: RAW検出 → フォワーディング制御生成
    ↓ (ID/EXレジスタに格納)
EXステージ: フォワーディングMUX → ALU
```

**効果**:
- ✅ EXクリティカルパス: 約3ns短縮
- ✅ タイミング余裕: 125MHz → 150MHz可能
- ❌ IDステージ複雑度: わずかに増加（許容範囲）

#### 判断2: 3レベルフォワーディング（EX/MEM/WB） ✅

**優先順位**: EX > MEM > WB > ID（フォワーディングなし）

**理由**:
- **最新値優先**: EXステージにある最新結果を最優先
- **時間的近接性**: 近いステージほど新しいデータ
- **完全性**: すべてのRAWハザードをカバー

**実装**:
```systemverilog
if (raw_rs1_ex)        forward_rs1_sel = 2'b01;  // EX → EX
else if (raw_rs1_mem)  forward_rs1_sel = 2'b10;  // MEM → EX
else if (raw_rs1_wb)   forward_rs1_sel = 2'b11;  // WB → EX
else                   forward_rs1_sel = 2'b00;  // ID RF
```

#### 判断3: ロード使用時は1サイクルストール ✅

**なぜフォワーディングできないのか**:
- ロード命令はMEMステージでデータ取得（BRAM 1サイクルレイテンシ）
- EXステージではまだアドレス計算中、データなし
- EX/MEMレジスタにはアドレスのみ、ロードデータはMEM/WBレジスタに到達

**タイムライン**:
```
Cycle N:   LW x1, 0(x2)  [EX stage, address calc]
Cycle N+1: ADD x3, x1, x4 [ID stage, needs x1] → STALL
Cycle N+2: LW completes to MEM → Forward to ADD in EX
```

---

## ブロック図

```
                   ┌─────────────────────────────────────────────┐
                   │       rv32i_hazard Module                   │
                   │                                             │
                   │  ┌───────────────────────────────────────┐ │
                   │  │    RAW Hazard Detection Logic        │ │
                   │  │                                       │ │
 id_rs1_addr[4:0]──┼─►│ RS1 Match Comparators:              │ │
 id_rs2_addr[4:0]──┼─►│  - id_rs1 vs ex_rd  → raw_rs1_ex    │ │
                   │  │  - id_rs1 vs mem_rd → raw_rs1_mem   │ │
 ex_rd_addr[4:0] ──┼─►│  - id_rs1 vs wb_rd  → raw_rs1_wb    │ │
 mem_rd_addr[4:0]──┼─►│  - id_rs2 vs ex_rd  → raw_rs2_ex    │ │
 wb_rd_addr[4:0] ──┼─►│  - id_rs2 vs mem_rd → raw_rs2_mem   │ │
                   │  │  - id_rs2 vs wb_rd  → raw_rs2_wb    │ │
 ex_rf_wen ────────┼─►│                                       │ │
 mem_rf_wen ───────┼─►│ Conditions:                           │ │
 wb_rf_wen ────────┼─►│  - addr != x0                         │ │
 ex_valid ─────────┼─►│  - write enable asserted              │ │
 mem_valid ────────┼─►│  - stage valid                        │ │
 wb_valid ─────────┼─►│                                       │ │
                   │  └────┬────────────────┬─────────────────┘ │
                   │       │ raw_rs1_*      │ raw_rs2_*         │
                   │       ▼                ▼                   │
                   │  ┌──────────────────────────────────────┐  │
                   │  │  Forwarding Control Logic            │  │
                   │  │  (Priority Encoder)                  │  │
                   │  │                                       │  │
                   │  │  RS1 Priority:                        │  │
                   │  │    if (raw_rs1_ex)   → 2'b01 (EX)    │  │
                   │  │    elif (raw_rs1_mem) → 2'b10 (MEM)  │  │
                   │  │    elif (raw_rs1_wb)  → 2'b11 (WB)   │  │
                   │  │    else              → 2'b00 (ID RF) │  │
                   │  │                                       │  │
                   │  │  RS2 Priority: (同様)                 │  │
                   │  └──────┬──────────────┬─────────────────┘  │
                   │         │              │                    │
                   │         ▼              ▼                    │
                   │   forward_rs1_sel  forward_rs2_sel         │
                   │      [1:0]            [1:0]                │
                   │         │              │                    │
                   │  ┌──────▼──────────────▼─────────────────┐ │
                   │  │  Load-Use Hazard Detection            │ │
 ex_is_load ───────┼─►│                                       │ │
 id_valid ─────────┼─►│  Conditions:                          │ │
                   │  │   - ex_valid && ex_is_load           │ │
                   │  │   - ex_rf_wen                         │ │
                   │  │   - (ex_rd == id_rs1 || ex_rd == id_rs2) │
                   │  │   - id_rs1/rs2 != x0                  │ │
                   │  └──────────────┬────────────────────────┘ │
                   │                 │ load_use_hazard          │
                   │                 ▼                          │
                   │  ┌──────────────────────────────────────┐  │
                   │  │     Stall Signal Generator           │  │
                   │  │                                       │  │
                   │  │  if_stall = load_use_hazard          │  │
                   │  │  id_stall = load_use_hazard          │  │
                   │  └──────┬──────────────┬─────────────────┘  │
                   │         │              │                    │
                   │         ▼              ▼                    │
                   │    if_stall       id_stall                 │
                   │                                             │
                   │  ┌──────────────────────────────────────┐  │
 branch_taken ─────┼─►│   Flush Signal Generator             │  │
 jump_req ─────────┼─►│                                       │  │
 trap_redirect ────┼─►│  if_flush = branch_taken | jump_req  │  │
 mret_req ─────────┼─►│              | trap_redirect | mret  │  │
                   │  │  id_flush = (同上)                    │  │
                   │  │  ex_flush = trap_redirect | mret     │  │
                   │  └──────┬───────┬───────┬────────────────┘  │
                   │         │       │       │                   │
                   └─────────┼───────┼───────┼───────────────────┘
                             ▼       ▼       ▼
                        if_flush id_flush ex_flush
```

---

## 機能詳細

### 3.1 RAWハザード検出

**検出条件**:

```systemverilog
// RS1がEXステージの書き込み先と一致
assign raw_rs1_ex = (id_rs1_addr != 5'b0) &&         // x0除外
                    (id_rs1_addr == ex_rd_addr) &&    // アドレス一致
                    ex_rf_wen &&                      // EXが書き込み
                    ex_valid;                         // EX命令有効

// RS1がMEMステージの書き込み先と一致
assign raw_rs1_mem = (id_rs1_addr != 5'b0) &&
                     (id_rs1_addr == mem_rd_addr) &&
                     mem_rf_wen &&
                     mem_valid;

// RS1がWBステージの書き込み先と一致
assign raw_rs1_wb = (id_rs1_addr != 5'b0) &&
                    (id_rs1_addr == wb_rd_addr) &&
                    wb_rf_wen &&
                    wb_valid;

// RS2も同様のロジック
assign raw_rs2_ex  = ...;
assign raw_rs2_mem = ...;
assign raw_rs2_wb  = ...;
```

**重要ルール**:
1. **x0除外**: x0は常に0、ハザードなし
2. **valid確認**: 無効命令（バブル）は無視
3. **書き込み確認**: `rf_wen`がアサートされている命令のみ

---

### 3.2 フォワーディング制御

**優先順位エンコーダ**:

```systemverilog
// RS1フォワーディング選択
always_comb begin
    if (raw_rs1_ex)
        forward_rs1_sel = 2'b01;      // EX/MEMレジスタから
    else if (raw_rs1_mem)
        forward_rs1_sel = 2'b10;      // MEM/WBレジスタから
    else if (raw_rs1_wb)
        forward_rs1_sel = 2'b11;      // WB結果から
    else
        forward_rs1_sel = 2'b00;      // IDレジスタファイル
end

// RS2フォワーディング選択（同様）
always_comb begin
    if (raw_rs2_ex)
        forward_rs2_sel = 2'b01;
    else if (raw_rs2_mem)
        forward_rs2_sel = 2'b10;
    else if (raw_rs2_wb)
        forward_rs2_sel = 2'b11;
    else
        forward_rs2_sel = 2'b00;
end
```

**フォワーディングパス**:

```
EXステージのフォワーディングMUX:

RS1データソース選択 (forward_rs1_sel):
  2'b00: id_ex_rs1_data (IDレジスタファイル読み出し)
  2'b01: ex_mem_alu_result (EX/MEMレジスタ、最新）
  2'b10: mem_wb_result (MEM/WBレジスタ)
  2'b11: wb_result_fwd (WBフォワーディング専用レジスタ)

RS2データソース選択 (forward_rs2_sel):
  (同様)
```

---

### 3.3 ロード使用ハザード検出

**検出ロジック**:

```systemverilog
logic load_use_hazard;

assign load_use_hazard = ex_valid &&          // EX命令有効
                         ex_is_load &&         // EXがロード命令
                         ex_rf_wen &&          // EXが書き込み
                         ((ex_rd_addr == id_rs1_addr && id_rs1_addr != 5'b0) ||
                          (ex_rd_addr == id_rs2_addr && id_rs2_addr != 5'b0));
```

**ストール生成**:

```systemverilog
assign if_stall = load_use_hazard;
assign id_stall = load_use_hazard;
```

**タイムライン例**:

```
Cycle:   0      1      2      3      4
         
IF:    LW x1  ADD x3  ADD x3  SUB x5  ...
ID:    ...    LW x1   ADD x3  ADD x3  SUB x5
EX:    ...    ...     LW x1   BUBBLE  ADD x3
MEM:   ...    ...     ...     LW x1   BUBBLE
WB:    ...    ...     ...     ...     LW x1

Hazard:        -      STALL   FWD MEM -
```

**ストール理由**:
- Cycle 1: `ADD x3, x1, x4`がIDにある、`LW x1`がEXにある
- EXステージのロードはまだデータ未取得（アドレス計算中）
- Cycle 2: ストール、`LW`がMEMに進みデータ取得
- Cycle 3: MEMからフォワーディング可能、`ADD`がEXに進む

---

### 3.4 制御ハザード処理

**フラッシュ信号生成**:

```systemverilog
// 分岐/ジャンプ時: IFとIDをフラッシュ
assign if_flush = branch_taken | jump_req | trap_redirect | mret_req;
assign id_flush = branch_taken | jump_req | trap_redirect | mret_req;

// 例外時のみEXもフラッシュ
assign ex_flush = trap_redirect | mret_req;
```

**フラッシュタイミング**:

```
分岐Takenの場合:
Cycle N:   BEQ in EX, branch_taken=1
Cycle N+1: if_flush=1, id_flush=1 → IF/IDステージバブル化
Cycle N+2: 正しいターゲット命令がIFに到達

例外トラップの場合:
Cycle N:   Exception detected in MEM
Cycle N+1: trap_redirect=1, if_flush=1, id_flush=1, ex_flush=1
           IF/ID/EXすべてバブル化
Cycle N+2: トラップハンドラ命令がIFに到達
```

---

## 実装ガイド

### 4.1 RAWハザード検出実装

```systemverilog
// ファイル: rv32i_hazard.sv

// EXステージとのマッチ
logic raw_rs1_ex, raw_rs2_ex;

assign raw_rs1_ex = (id_rs1_addr != 5'b0) &&
                    (id_rs1_addr == ex_rd_addr) &&
                    ex_rf_wen && ex_valid;

assign raw_rs2_ex = (id_rs2_addr != 5'b0) &&
                    (id_rs2_addr == ex_rd_addr) &&
                    ex_rf_wen && ex_valid;

// MEMステージとのマッチ
logic raw_rs1_mem, raw_rs2_mem;

assign raw_rs1_mem = (id_rs1_addr != 5'b0) &&
                     (id_rs1_addr == mem_rd_addr) &&
                     mem_rf_wen && mem_valid;

assign raw_rs2_mem = (id_rs2_addr != 5'b0) &&
                     (id_rs2_addr == mem_rd_addr) &&
                     mem_rf_wen && mem_valid;

// WBステージとのマッチ
logic raw_rs1_wb, raw_rs2_wb;

assign raw_rs1_wb = (id_rs1_addr != 5'b0) &&
                    (id_rs1_addr == wb_rd_addr) &&
                    wb_rf_wen && wb_valid;

assign raw_rs2_wb = (id_rs2_addr != 5'b0) &&
                    (id_rs2_addr == wb_rd_addr) &&
                    wb_rf_wen && wb_valid;
```

---

### 4.2 フォワーディング制御実装

```systemverilog
logic [1:0] forward_rs1_sel, forward_rs2_sel;

// RS1フォワーディング
always_comb begin
    casez ({raw_rs1_ex, raw_rs1_mem, raw_rs1_wb})
        3'b1??:  forward_rs1_sel = 2'b01;  // EX優先
        3'b01?:  forward_rs1_sel = 2'b10;  // MEM次優先
        3'b001:  forward_rs1_sel = 2'b11;  // WB最後
        default: forward_rs1_sel = 2'b00;  // フォワーディングなし
    endcase
end

// RS2フォワーディング（同様）
always_comb begin
    casez ({raw_rs2_ex, raw_rs2_mem, raw_rs2_wb})
        3'b1??:  forward_rs2_sel = 2'b01;
        3'b01?:  forward_rs2_sel = 2'b10;
        3'b001:  forward_rs2_sel = 2'b11;
        default: forward_rs2_sel = 2'b00;
    endcase
end
```

---

### 4.3 ロード使用ストール実装

```systemverilog
logic load_use_stall;

// ロード使用ハザード検出
assign load_use_stall = ex_valid && ex_is_load && ex_rf_wen &&
                        ((ex_rd_addr == id_rs1_addr && id_rs1_addr != 5'b0) ||
                         (ex_rd_addr == id_rs2_addr && id_rs2_addr != 5'b0));

// ストール信号生成
assign if_stall = load_use_stall;
assign id_stall = load_use_stall;
```

---

## 検証ポイント

### 5.1 アサーション

#### **SPEC-HAZARD-1: EX優先フォワーディング**
```systemverilog
property ex_forwarding_priority;
    @(posedge clk) disable iff (!rst_n)
    (raw_rs1_ex) |-> (forward_rs1_sel == 2'b01);
endproperty

assert_ex_fwd: assert property (ex_forwarding_priority)
    else $error("[HAZARD] EX forwarding priority violated");
```

#### **SPEC-HAZARD-2: ロード使用ストール**
```systemverilog
property load_use_stalls;
    @(posedge clk) disable iff (!rst_n)
    (ex_valid && ex_is_load && ex_rf_wen &&
     (ex_rd_addr == id_rs1_addr || ex_rd_addr == id_rs2_addr) &&
     id_rs1_addr != 5'b0)
    |-> (if_stall && id_stall);
endproperty

assert_load_stall: assert property (load_use_stalls)
    else $error("[HAZARD] Load-use stall not generated");
```

---

## デバッグガイド

### 6.1 フォワーディング不具合

**症状**: レジスタ値が古い

**確認**:
```systemverilog
always @(posedge clk) begin
    if (raw_rs1_ex)
        $display("[HAZARD_DEBUG] RS1 EX fwd: id_rs1=%0d, ex_rd=%0d, sel=%b",
                 id_rs1_addr, ex_rd_addr, forward_rs1_sel);
end
```

### 6.2 ロード使用ストール失敗

**症状**: ロード直後の使用で誤った値

**確認**:
```systemverilog
always @(posedge clk) begin
    if (ex_is_load && ex_rf_wen)
        $display("[HAZARD_DEBUG] Load rd=%0d, ID rs1=%0d, rs2=%0d, stall=%b",
                 ex_rd_addr, id_rs1_addr, id_rs2_addr, if_stall);
end
```

---

## 関連ドキュメント

- **[00_overview.md](00_overview.md)** - WBフォワーディングタイミング修正
- **[02_id_stage.md](02_id_stage.md)** - レジスタアドレス提供
- **[04_ex_stage.md](04_ex_stage.md)** - フォワーディングMUX
- **[06_wb_stage.md](06_wb_stage.md)** - wb_result_fwd生成

---

**このドキュメントの目的**: 
ハザード検出とフォワーディング制御の**設計意図**、**優先順位**、**タイミング**を理解し、正確に実装できる知識を提供します。
