# Instruction Decode (ID) Stage - 詳細設計

**モジュール名:** `rv32i_id`  
**ファイル:** `rtl/cpu/rv32i_id.sv`  
**バージョン:** 1.1  
**最終更新:** 2026年1月5日  
**アサーションモジュール:** `sim/assertions/rv32i_id_timing_spec.sv`

---

## 目次

1. [設計意図](#設計意図)
2. [モジュール概要](#モジュール概要)
3. [ブロック図](#ブロック図)
4. [機能詳細](#機能詳細)
5. [実装ガイド](#実装ガイド)
6. [検証ポイント](#検証ポイント)
7. [デバッグガイド](#デバッグガイド)

---

## 設計意図

### なぜこの設計なのか

IDステージは**命令の意味を解釈し、実行準備を整える**役割を持ちます：

1. **デコード効率**: 40命令すべてを組み合わせ回路で高速デコード
2. **ゼロレイテンシレジスタ読み出し**: 組み合わせ読み出しでクリティカルパス短縮
3. **ハザード検出支援**: レジスタアドレスを事前にハザードユニットへ提供
4. **即値生成の集約**: 5種類のフォーマット（I/S/B/U/J）を統一的に処理

### 主要な設計判断

#### 判断1: レジスタファイルは組み合わせ読み出し

**選択肢**:
- A: 同期読み出し（1サイクル遅延、EXステージでデータ確定）
- B: 組み合わせ読み出し（ゼロレイテンシ） ✅採用

**理由**:
- IDステージでデータが即座に確定 → ハザード検出が早期化
- EXステージのクリティカルパスに読み出し遅延が含まれない
- フォワーディングロジックがIDステージで事前計算可能

**トレードオフ**:
- ✅ 性能向上（1サイクル短縮相当）
- ✅ ハザード検出精度向上
- ❌ レジスタファイルの組み合わせ出力でタイミング制約厳しい（約2ns @ 125MHz）

**実装**:
```systemverilog
// 組み合わせ読み出し
assign rs1_data = (rs1 == 5'b0) ? 32'h0 : regfile[rs1];
assign rs2_data = (rs2 == 5'b0) ? 32'h0 : regfile[rs2];
```

#### 判断2: x0ハードワイヤードを論理レベルで実装

**選択肢**:
- A: regfile[0]を物理的に削除（31個のレジスタ）
- B: regfile[0]は存在するが、読み出し時に0を返す ✅採用

**理由**:
- コード簡潔性: インデックス計算不要
- デバッグ容易性: x0への書き込み試行を観察可能
- 合成ツールが最適化: 使用されないregfile[0]は削除される

**実装**:
```systemverilog
// x0は常に0を返す
assign rs1_data = (rs1 == 5'b0) ? 32'h0 : regfile[rs1];

// x0への書き込みは無視
if (rf_wen && rf_waddr != 5'b0) begin
    regfile[rf_waddr] <= rf_wdata;
end
```

#### 判断3: 即値生成は単一always_combブロック

**理由**:
- すべての即値フォーマット（I/S/B/U/J）を統一的に扱う
- opcodeベースのcase文で明確な制御フロー
- 符号拡張ルールを一箇所で管理

**5種類の即値フォーマット**:
```
I-type (12-bit): [31:20] → 符号拡張
S-type (12-bit): [31:25][11:7] → 符号拡張
B-type (13-bit): [31][7][30:25][11:8][0] → 符号拡張、LSB=0
U-type (20-bit): [31:12][11:0=0] → 符号拡張なし
J-type (21-bit): [31][19:12][20][30:21][0] → 符号拡張、LSB=0
```

---

## モジュール概要

### 責務

1. **命令デコード**: opcode、funct3、funct7、レジスタアドレス抽出
2. **レジスタファイル管理**: 32×32ビットレジスタ、組み合わせ読み出し、同期書き込み
3. **即値生成**: 符号拡張された32ビット即値生成（5フォーマット対応）
4. **制御信号生成**: 後続ステージ用の制御信号デコード
5. **CSR読み出し開始**: CSRアドレス抽出、CSRモジュールへ読み出し要求
6. **ハザード情報提供**: rs1/rs2/rdアドレスをハザードユニットへ

---

## ブロック図

```
                   ┌────────────────────────────────────────────────┐
                   │           rv32i_id Module                      │
                   │                                                │
                   │  ┌──────────────────────────────────────────┐ │
if_id_insn[31:0] ──┼─►│     Instruction Decoder               │ │
                   │  │  (opcode, funct3, funct7 extractor)   │ │
                   │  └────┬──────────┬───────────┬────────────┘ │
                   │       │          │           │               │
                   │       ▼          ▼           ▼               │
                   │  ┌────────┐ ┌────────┐ ┌────────────┐       │
                   │  │rs1[4:0]│ │rs2[4:0]│ │rd[4:0]     │       │
                   │  │rs1_addr│ │rs2_addr│ │rd_addr     │       │
                   │  └────┬───┘ └────┬───┘ └────┬───────┘       │
                   │       │          │           │               │
                   │       ▼          ▼           │               │
                   │  ┌─────────────────────┐    │               │
                   │  │  Register File      │    │               │
                   │  │   32x32-bit         │    │               │
                   │  │  (combinational     │    │               │
                   │  │   read, sync write) │    │               │
                   │  │                     │    │               │
rf_wen ────────────┼─►│ write_enable        │    │               │
rf_waddr[4:0] ─────┼─►│ write_addr          │    │               │
rf_wdata[31:0] ────┼─►│ write_data          │    │               │
                   │  │                     │    │               │
                   │  │  regfile[1:31]      │    │               │
                   │  │  (x0 = hardwired 0) │    │               │
                   │  └──────┬─────┬────────┘    │               │
                   │         │     │              │               │
                   │         ▼     ▼              ▼               │
                   │    rs1_data rs2_data    to hazard unit      │
                   │     [31:0]  [31:0]      (id_rs1_addr,       │
                   │         │     │          id_rs2_addr,       │
                   │         │     │          id_rd_addr)        │
                   │         │     │                             │
                   │  ┌──────▼─────▼──────────────────────────┐  │
                   │  │      Immediate Generator              │  │
if_id_insn[31:0] ──┼─►│  (I/S/B/U/J format decoder)          │  │
                   │  │  - Sign extension logic               │  │
                   │  │  - Format-specific bit selection      │  │
                   │  └──────────────┬────────────────────────┘  │
                   │                 │ imm[31:0]                 │
                   │                 │                           │
                   │  ┌──────────────▼────────────────────────┐  │
if_id_insn[31:0] ──┼─►│   Control Signal Generator           │  │
                   │  │   (opcode/funct3/funct7 → ctrl)      │  │
                   │  │                                       │  │
                   │  │  Generates:                           │  │
                   │  │  - alu_op, alu_src1/2_sel            │  │
                   │  │  - mem_read/write, mem_size          │  │
                   │  │  - rf_wen, rf_wdata_sel              │  │
                   │  │  - is_branch/jal/jalr                │  │
                   │  │  - is_csr/ebreak/ecall/mret          │  │
                   │  │  - is_illegal                         │  │
                   │  └──────────────┬────────────────────────┘  │
                   │                 │ ctrl (struct)             │
                   │                 │                           │
                   │  ┌──────────────▼────────────────────────┐  │
if_id_insn[31:0] ──┼─►│   CSR Address Extractor              │  │
                   │  │   (bits [31:20] for CSR ops)         │  │
                   │  └──────────────┬────────────────────────┘  │
                   │                 │ csr_raddr[11:0]           │
                   │                 ▼                           │
                   │            to rv32i_csr                     │
                   │                 │                           │
csr_rdata[31:0] ───┼─────────────────┘ (from rv32i_csr)         │
                   │                 │                           │
                   │  ┌──────────────▼────────────────────────┐  │
                   │  │     ID/EX Pipeline Register           │  │
id_stall ──────────┼─►│  (posedge clk, hold when stalled)    │  │
id_flush ──────────┼─►│  (clear valid when flushed)          │  │
                   │  │                                       │  │
                   │  │  Contents:                            │  │
                   │  │  - id_ex_valid                        │  │
                   │  │  - id_ex_pc[31:0]                     │  │
                   │  │  - id_ex_insn[31:0]                   │  │
                   │  │  - id_ex_rs1_data[31:0]               │  │
                   │  │  - id_ex_rs2_data[31:0]               │  │
                   │  │  - id_ex_imm[31:0]                    │  │
                   │  │  - id_ex_csr_rdata[31:0]              │  │
                   │  │  - id_ex_ctrl (struct)                │  │
                   │  └───────────────────────────────────────┘  │
                   │                 │                           │
                   └─────────────────┼───────────────────────────┘
                                     ▼
                               to EX stage
```

---

## 機能詳細

### 4.1 命令デコーダ

**ビットフィールド抽出**:

```systemverilog
logic [6:0]  opcode;
logic [4:0]  rd, rs1, rs2;
logic [2:0]  funct3;
logic [6:0]  funct7;
logic [11:0] imm_i, csr_addr;

assign opcode   = if_id_insn[6:0];
assign rd       = if_id_insn[11:7];
assign funct3   = if_id_insn[14:12];
assign rs1      = if_id_insn[19:15];
assign rs2      = if_id_insn[24:20];
assign funct7   = if_id_insn[31:25];
assign imm_i    = if_id_insn[31:20];
assign csr_addr = if_id_insn[31:20];
```

**Opcode分類**:

| Opcode | 命令タイプ | フォーマット | 例 |
|--------|-----------|-------------|-----|
| `0110011` | R-type算術 | R | ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU |
| `0010011` | I-type算術 | I | ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, SLTI, SLTIU |
| `0000011` | ロード | I | LB, LH, LW, LBU, LHU |
| `0100011` | ストア | S | SB, SH, SW |
| `1100011` | 分岐 | B | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| `1101111` | JAL | J | JAL |
| `1100111` | JALR | I | JALR |
| `0110111` | LUI | U | LUI |
| `0010111` | AUIPC | U | AUIPC |
| `1110011` | システム | I | ECALL, EBREAK, MRET, CSRRW, CSRRS, CSRRC |

---

### 4.2 レジスタファイル

**アーキテクチャ**:
- **32個のレジスタ**: x0-x31（各32ビット）
- **x0固定**: 常に0x00000000を返す（RISC-V仕様）
- **読み出しポート**: 2つの組み合わせ読み出しポート（rs1, rs2）
- **書き込みポート**: 1つの同期書き込みポート（posedge clk）

**実装**:

```systemverilog
// レジスタファイルストレージ（31個、x0はハードワイヤード）
logic [31:0] regfile [1:31];

// 組み合わせ読み出し（x0は0を返す）
assign rs1_data = (rs1 == 5'b0) ? 32'h0 : regfile[rs1];
assign rs2_data = (rs2 == 5'b0) ? 32'h0 : regfile[rs2];

// 同期書き込み（x0への書き込みは無視）
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // オプション: レジスタを0で初期化
        for (int i = 1; i < 32; i++) begin
            regfile[i] <= 32'h0;
        end
    end else if (rf_wen && rf_waddr != 5'b0) begin
        regfile[rf_waddr] <= rf_wdata;
    end
end
```

**重要な動作**:
- **x0読み出し**: 常に0、書き込み試行に関係なく
- **組み合わせ読み出し**: アドレスからデータまでゼロレイテンシ
- **書き込みタイミング**: `rf_wen`アサート後、次サイクルでデータ利用可能
- **Read-during-write**: 古い値を読む（書き込みはクロックエッジで発生）

---

### 4.3 即値生成

**RV32I即値フォーマット**:

```
I-type (12ビット):
  31           20 19  15 14  12 11   7 6     0
  [   imm[11:0]  ][ rs1 ][funct3][ rd ][opcode]
  
  imm = { {20{insn[31]}}, insn[31:20] }  // 符号拡張

S-type (12ビット):
  31        25 24  20 19  15 14  12 11   7 6     0
  [imm[11:5]][ rs2 ][ rs1 ][funct3][imm[4:0]][opcode]
  
  imm = { {20{insn[31]}}, insn[31:25], insn[11:7] }

B-type (13ビット、LSB=0):
  31 30    25 24  20 19  15 14  12 11  8 7 6     0
  [12][10:5][ rs2 ][ rs1 ][funct3][4:1][11][opcode]
  
  imm = { {19{insn[31]}}, insn[31], insn[7], 
          insn[30:25], insn[11:8], 1'b0 }

U-type (20ビット):
  31                    12 11   7 6     0
  [      imm[31:12]      ][ rd ][opcode]
  
  imm = { insn[31:12], 12'h0 }  // 符号拡張なし

J-type (21ビット、LSB=0):
  31 30      21 20 19       12 11   7 6     0
  [20][10:1]  [11][19:12]    [ rd ][opcode]
  
  imm = { {11{insn[31]}}, insn[31], insn[19:12],
          insn[20], insn[30:21], 1'b0 }
```

**実装**:

```systemverilog
logic [31:0] imm;

always_comb begin
    case (opcode)
        // I-type: ADDI, SLTI, SLTIU, ANDI, ORI, XORI, loads, JALR
        7'b0010011, 7'b0000011, 7'b1100111: begin
            imm = {{20{if_id_insn[31]}}, if_id_insn[31:20]};
        end
        
        // S-type: SB, SH, SW
        7'b0100011: begin
            imm = {{20{if_id_insn[31]}}, if_id_insn[31:25], if_id_insn[11:7]};
        end
        
        // B-type: BEQ, BNE, BLT, BGE, BLTU, BGEU
        7'b1100011: begin
            imm = {{19{if_id_insn[31]}}, if_id_insn[31], if_id_insn[7], 
                   if_id_insn[30:25], if_id_insn[11:8], 1'b0};
        end
        
        // U-type: LUI, AUIPC
        7'b0110111, 7'b0010111: begin
            imm = {if_id_insn[31:12], 12'h0};
        end
        
        // J-type: JAL
        7'b1101111: begin
            imm = {{11{if_id_insn[31]}}, if_id_insn[31], if_id_insn[19:12],
                   if_id_insn[20], if_id_insn[30:21], 1'b0};
        end
        
        // デフォルト: 0（R-typeや無効命令）
        default: imm = 32'h0;
    endcase
end
```

**符号拡張ルール**:
- **I/S/B/J-type**: MSB（符号ビット）を複製して上位ビット埋める
- **U-type**: 符号拡張なし（20ビット値を12ビット左シフト）
- **分岐/ジャンプオフセット**: 常に偶数（LSB = 0）

---

### 4.4 制御信号生成

**制御信号構造体**:

```systemverilog
typedef struct packed {
    logic [3:0]  alu_op;        // ALU演算
    logic        alu_src1_sel;  // 0=rs1, 1=PC
    logic        alu_src2_sel;  // 0=rs2, 1=imm
    logic        is_branch;
    logic        is_jal;
    logic        is_jalr;
    logic        mem_read;
    logic        mem_write;
    logic [2:0]  mem_size;      // 000=byte, 001=half, 010=word
    logic        mem_unsigned;
    logic        rf_wen;
    logic [1:0]  rf_wdata_sel;  // 00=ALU, 01=mem, 10=PC+4, 11=CSR
    logic        is_csr;
    logic [1:0]  csr_op;
    logic        is_ebreak;
    logic        is_ecall;
    logic        is_mret;
    logic        is_illegal;
} ctrl_signals_t;
```

**主要命令の制御信号例**:

| 命令 | alu_op | alu_src1 | alu_src2 | rf_wen | rf_wdata_sel | mem_read | mem_write |
|------|--------|----------|----------|--------|--------------|----------|-----------|
| ADD  | 0000 (ADD) | 0 (rs1) | 0 (rs2) | 1 | 00 (ALU) | 0 | 0 |
| ADDI | 0000 (ADD) | 0 (rs1) | 1 (imm) | 1 | 00 (ALU) | 0 | 0 |
| LW   | 0000 (ADD) | 0 (rs1) | 1 (imm) | 1 | 01 (mem) | 1 | 0 |
| SW   | 0000 (ADD) | 0 (rs1) | 1 (imm) | 0 | xx | 0 | 1 |
| BEQ  | xxxx | 0 (rs1) | 0 (rs2) | 0 | xx | 0 | 0 |
| JAL  | xxxx | x | x | 1 | 10 (PC+4) | 0 | 0 |
| LUI  | 1010 (PASS_B) | x | 1 (imm) | 1 | 00 (ALU) | 0 | 0 |

---

### 4.5 ID/EXパイプラインレジスタ

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        id_ex_valid     <= 1'b0;
        id_ex_pc        <= 32'h0;
        id_ex_insn      <= 32'h0000_0013;    // NOP
        id_ex_rs1_data  <= 32'h0;
        id_ex_rs2_data  <= 32'h0;
        id_ex_imm       <= 32'h0;
        id_ex_csr_rdata <= 32'h0;
        id_ex_ctrl      <= '0;
    end else if (id_flush) begin
        id_ex_valid <= 1'b0;                  // バブル注入
        // 他のフィールドはdon't-care（invalidなので）
    end else if (!id_stall) begin
        id_ex_valid     <= if_id_valid;
        id_ex_pc        <= if_id_pc;
        id_ex_insn      <= if_id_insn;
        id_ex_rs1_data  <= rs1_data;
        id_ex_rs2_data  <= rs2_data;
        id_ex_imm       <= imm;
        id_ex_csr_rdata <= csr_rdata;
        id_ex_ctrl      <= ctrl;
    end
    // else: 前の値を保持（ストール時）
end
```

---

## 実装ガイド

### 5.1 レジスタファイル実装

**ステップ1: ストレージ宣言**

```systemverilog
// ファイル: rv32i_id.sv
logic [31:0] regfile [1:31];  // x1-x31のみ（x0はハードワイヤード）
```

**ステップ2: 組み合わせ読み出し**

```systemverilog
// rs1読み出し
assign rs1_data = (rs1 == 5'b0) ? 32'h0000_0000 : regfile[rs1];

// rs2読み出し
assign rs2_data = (rs2 == 5'b0) ? 32'h0000_0000 : regfile[rs2];
```

**ステップ3: 同期書き込み**

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // リセット時: すべてのレジスタを0初期化（オプション）
        for (int i = 1; i < 32; i++) begin
            regfile[i] <= 32'h0;
        end
    end else if (rf_wen && rf_waddr != 5'b0) begin
        regfile[rf_waddr] <= rf_wdata;
    end
end
```

**注意点**:
- `regfile[0]`は宣言されていない → 合成ツールが最適化
- x0への書き込み試行は`rf_waddr != 5'b0`で防止
- 組み合わせ読み出しは約2ns遅延（32-bit MUX × 32）

---

### 5.2 即値生成実装

```systemverilog
logic [31:0] imm;

always_comb begin
    case (opcode)
        7'b0010011, 7'b0000011, 7'b1100111: begin  // I-type
            imm = {{20{if_id_insn[31]}}, if_id_insn[31:20]};
        end
        
        7'b0100011: begin  // S-type
            imm = {{20{if_id_insn[31]}}, if_id_insn[31:25], if_id_insn[11:7]};
        end
        
        7'b1100011: begin  // B-type
            imm = {{19{if_id_insn[31]}}, if_id_insn[31], if_id_insn[7], 
                   if_id_insn[30:25], if_id_insn[11:8], 1'b0};
        end
        
        7'b0110111, 7'b0010111: begin  // U-type
            imm = {if_id_insn[31:12], 12'h0};
        end
        
        7'b1101111: begin  // J-type
            imm = {{11{if_id_insn[31]}}, if_id_insn[31], if_id_insn[19:12],
                   if_id_insn[20], if_id_insn[30:21], 1'b0};
        end
        
        default: imm = 32'h0;
    endcase
end
```

**デバッグヒント**: 即値の符号拡張が正しいか確認
```systemverilog
// I-type: imm_i = 12'hFFF (-1)
// 期待値: imm = 32'hFFFFFFFF
assert (opcode == 7'b0010011 && if_id_insn[31:20] == 12'hFFF)
    |-> (imm == 32'hFFFFFFFF);
```

---

### 5.3 制御信号生成実装

**基本構造**:

```systemverilog
ctrl_signals_t ctrl;

always_comb begin
    // デフォルト: すべて0（NOP動作）
    ctrl = '0;
    
    case (opcode)
        7'b0110011: begin  // R-type ALU
            ctrl.alu_src1_sel = 1'b0;
            ctrl.alu_src2_sel = 1'b0;
            ctrl.rf_wen = 1'b1;
            ctrl.rf_wdata_sel = 2'b00;
            
            case (funct3)
                3'b000: ctrl.alu_op = (funct7[5]) ? 4'b0001 : 4'b0000;
                3'b001: ctrl.alu_op = 4'b0010;  // SLL
                // ... その他のfunct3
            endcase
        end
        
        // ... その他のopcode
        
        default: ctrl.is_illegal = 1'b1;
    endcase
end
```

**不正命令検出**:
- 無効なopcode
- 無効なfunct3/funct7組み合わせ
- 予約済み命令エンコーディング

---

## 検証ポイント

### 6.1 アサーションチェックリスト

#### **SPEC-ID-1: x0常に0を読む**
```systemverilog
property x0_reads_zero_rs1;
    @(posedge clk) disable iff (!rst_n)
    (rs1 == 5'b0) |-> (rs1_data == 32'h0);
endproperty

assert_x0_rs1: assert property (x0_reads_zero_rs1)
    else $error("[ID_SPEC] x0 did not read zero for rs1");
```

#### **SPEC-ID-2: レジスタ書き込み可視性**
```systemverilog
property register_write_visible;
    logic [4:0] addr;
    logic [31:0] data;
    @(posedge clk) disable iff (!rst_n)
    (rf_wen && rf_waddr != 5'b0, addr = rf_waddr, data = rf_wdata)
    ##1 (rs1 == addr)
    |-> (rs1_data == data);
endproperty

assert_rf_write: assert property (register_write_visible)
    else $error("[ID_SPEC] Register write not visible");
```

#### **SPEC-ID-3: 即値符号拡張（I-type）**
```systemverilog
property i_type_imm_sext;
    @(posedge clk) disable iff (!rst_n)
    (opcode == 7'b0010011)
    |-> (imm == {{20{if_id_insn[31]}}, if_id_insn[31:20]});
endproperty

assert_i_imm: assert property (i_type_imm_sext)
    else $error("[ID_SPEC] I-type immediate sign-extension incorrect");
```

#### **SPEC-ID-4: ADD制御信号正確性**
```systemverilog
property add_control_signals;
    @(posedge clk) disable iff (!rst_n)
    (opcode == 7'b0110011 && funct3 == 3'b000 && funct7 == 7'b0000000)
    |-> (ctrl.alu_op == 4'b0000 && ctrl.rf_wen && 
         !ctrl.mem_read && !ctrl.mem_write);
endproperty

assert_add_ctrl: assert property (add_control_signals)
    else $error("[ID_SPEC] ADD control signals incorrect");
```

---

### 6.2 カバレッジ目標

**命令カバレッジ**: 40命令すべて最低1回デコード  
**レジスタカバレッジ**: x0-x31すべて読み書き  
**即値フォーマット**: I/S/B/U/J各フォーマット  
**エッジケース**:
- x0への書き込み試行
- x0をrs1/rs2/rdとして使用
- 最大正/負即値（符号拡張境界）
- すべてのfunct3/funct7組み合わせ

---

## デバッグガイド

### 7.1 よくある問題

#### **問題1: x0が0以外を返す**

**原因**:
- 組み合わせ読み出しロジックのバグ
- x0書き込み防止の失敗

**対処**:
```systemverilog
// x0読み出しを強制的に0に
assign rs1_data = (rs1 == 5'b0) ? 32'h0 : regfile[rs1];

// x0書き込みを無視
if (rf_wen && rf_waddr != 5'b0) begin
    regfile[rf_waddr] <= rf_wdata;
end
```

#### **問題2: 即値符号拡張エラー**

**症状**: 負の即値が正になる、またはその逆

**原因**: ビット選択ミス、符号ビット位置間違い

**デバッグ**:
```systemverilog
// I-type負即値テスト
// if_id_insn = 32'hFFF00093  // ADDI x1, x0, -1
// 期待: imm = 32'hFFFFFFFF
always @(posedge clk) begin
    if (opcode == 7'b0010011 && if_id_insn[31:20] == 12'hFFF)
        $display("[ID_DEBUG] I-type imm: expected 0xFFFFFFFF, got 0x%08X", imm);
end
```

#### **問題3: レジスタ書き込みが反映されない**

**原因**:
- `rf_wen`が正しくアサートされていない
- `rf_waddr`が間違っている
- クロックタイミング問題

**確認**:
```systemverilog
// WBステージからの書き込みをトレース
always @(posedge clk) begin
    if (rf_wen)
        $display("[ID_DEBUG] Write: x%0d <= 0x%08X", rf_waddr, rf_wdata);
end

// 次サイクルで読み出し確認
always @(posedge clk) begin
    if (rs1 != 5'b0)
        $display("[ID_DEBUG] Read: x%0d = 0x%08X", rs1, rs1_data);
end
```

---

### 7.2 波形確認ポイント

**必須信号**:
1. `if_id_insn[31:0]` - フェッチした命令
2. `opcode[6:0]`, `funct3[2:0]`, `funct7[6:0]`
3. `rs1[4:0]`, `rs2[4:0]`, `rd[4:0]`
4. `rs1_data[31:0]`, `rs2_data[31:0]`
5. `imm[31:0]`
6. `ctrl` (構造体全フィールド)
7. `id_ex_valid`, `id_ex_rs1_data`, `id_ex_rs2_data`

**確認手順**:
1. 命令ビットフィールドが正しく抽出されているか
2. レジスタ読み出しが正しいアドレスからデータ取得しているか
3. 即値生成が符号拡張含めて正確か
4. 制御信号が命令に対応しているか
5. ID/EXレジスタが正しく更新されているか

---

## 関連ドキュメント

- **[00_overview.md](00_overview.md)** - CPU全体アーキテクチャ
- **[01_if_stage.md](01_if_stage.md)** - IFステージ（命令フェッチ）
- **[03_hazard_unit.md](03_hazard_unit.md)** - ハザードユニット（レジスタアドレス受信）
- **[04_ex_stage.md](04_ex_stage.md)** - EXステージ（デコード済み制御信号使用）
- **[07_csr_module.md](07_csr_module.md)** - CSRモジュール（CSR読み出し）

---

**このドキュメントの目的**: 
IDステージの**デコードロジック**、**レジスタファイル動作**、**即値生成**を理解し、正確に実装・デバッグできる知識を提供します。
