# Write Back (WB) Stage - 詳細設計

**モジュール名:** `rv32i_wb`  
**ファイル:** `rtl/cpu/rv32i_wb.sv`  
**バージョン:** 1.1  
**最終更新:** 2026年1月5日  
**重要な修正**: WBフォワーディングタイミング修正（2026/1/5）

---

## 設計意図

WBステージは**結果をレジスタファイルに書き戻し、フォワーディング用データを提供**：

1. **結果マルチプレクサ**: ALU/Memory/PC+4/CSRから正しい値を選択
2. **レジスタ書き込み**: IDステージのレジスタファイルに書き戻し
3. **フォワーディング供給**: EXステージへの最新データ供給（**タイミング重要**）

### 主要な設計判断（重要な修正履歴）

#### 判断1: WBフォワーディングはレジスタ化必須 ✅

**問題（初期実装、2026/1/3）**:
```systemverilog
// rv32i_top.sv (旧実装)
.mem_forward_data(wb_result),  // 組み合わせ信号
.wb_forward_data(wb_result)    // 組み合わせ信号
```

**発覚した不具合**:
- `wb_result`はWBモジュールの`always_comb`で計算される組み合わせ信号
- EXステージでフォワーディング使用時（cycle N+1）、WBステージは既に次の命令に進行
- `wb_result`の値が変化してしまい、EXは間違ったデータをフォワーディング

**具体例**:
```
Cycle N:   ADDI x27, x0, 7   [WB] wb_result = 0x7 (組み合わせ)
Cycle N+1: SW x27, 0(x15)    [EX] x27が必要
           LUI x15, 0x4000   [WB] wb_result = 0x4000 (新しい命令)
           
EXのフォワーディングMUXは wb_result = 0x4000 を読む（誤り！）
正しくは 0x7 が必要
```

**修正実装（2026/1/5）**:
```systemverilog
// rv32i_top.sv (新実装)
logic [31:0] wb_result;       // 組み合わせ信号（WBモジュール出力）
logic [31:0] wb_result_fwd;   // レジスタ化されたフォワーディング専用信号

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

**タイミング図（修正後）**:
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
- ✅ cycle Nで計算された`wb_result`がcycle N+1で`wb_result_fwd`として安定利用
- ✅ クリティカルパス分割: `MEM/WB reg → WB mux`と`wb_result_fwd → EX mux`が別サイクル
- ✅ 命令レイテンシ増加なし（パイプライン深度は5のまま）
- ✅ タイミング違反解消（4-5 LUTレベルの組み合わせパス削減）

**設計哲学**:
パイプラインレジスタの値は**そのサイクルで確定した値**を保持。フォワーディングは「過去のサイクルで確定した結果」を使用するため、レジスタ化が必須。

---

## ブロック図

```
                ┌────────────────────────────────────────────┐
                │         rv32i_wb Module                    │
                │                                            │
 mem_wb_alu_res │  ┌──────────────────────────────────────┐  │
    [31:0] ─────┼─►│   Result Multiplexer (4-way)        │  │
 mem_wb_load───┼─►│                                      │  │
    [31:0]     │  │   rf_wdata_sel[1:0]:                │  │
 mem_wb_pc+4───┼─►│     00: ALU result                   │  │
    [31:0]     │  │     01: Load data                    │  │
 mem_wb_csr────┼─►│     10: PC+4 (JAL/JALR)             │  │
    [31:0]     │  │     11: CSR read data               │  │
                │  └──────────────┬───────────────────────┘  │
                │                 │ wb_result[31:0]          │
                │                 │ (combinational)          │
                │                 │                          │
                └─────────────────┼──────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────────┐
                    │ rv32i_top (Integration)    │
                    │                             │
                    │  always_ff:                 │
                    │    wb_result_fwd <= wb_result;
                    │                             │
                    │  wb_result_fwd[31:0]        │
                    │    (registered for          │
                    │     forwarding timing)      │
                    └──────┬──────────────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
         to ID RF    to EX fwd    to MEM fwd
       (rf_wdata)   (wb_forward)  (wb_forward)
```

---

## 機能詳細

### 3.1 結果マルチプレクサ

```systemverilog
logic [31:0] wb_result;

always_comb begin
    case (mem_wb_ctrl.rf_wdata_sel)
        2'b00: wb_result = mem_wb_alu_result;  // ALU演算結果
        2'b01: wb_result = mem_wb_load_data;   // ロードデータ
        2'b10: wb_result = mem_wb_pc + 32'd4;  // PC+4 (JAL/JALR)
        2'b11: wb_result = mem_wb_csr_rdata;   // CSR読み出しデータ
    endcase
end
```

### 3.2 レジスタファイル書き込み信号

```systemverilog
// IDステージのレジスタファイルへの書き込み
assign rf_wen   = mem_wb_ctrl.rf_wen && mem_wb_valid;
assign rf_waddr = mem_wb_rd_addr;
assign rf_wdata = wb_result;  // 組み合わせ信号（IDレジスタファイルへは即座に）
```

### 3.3 フォワーディング供給（rv32i_topで実装）

```systemverilog
// ファイル: rv32i_top.sv

// WBモジュールからの組み合わせ出力
logic [31:0] wb_result;

rv32i_wb u_wb (
    // ...
    .wb_result(wb_result)  // 組み合わせ信号出力
);

// フォワーディング専用レジスタ（重要な修正！）
logic [31:0] wb_result_fwd;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || soft_reset_active) begin
        wb_result_fwd <= 32'h0;
    end else begin
        wb_result_fwd <= wb_result;  // 1サイクル遅延、タイミング保証
    end
end

// EXステージへのフォワーディング接続
rv32i_ex u_ex (
    // ...
    .wb_forward_data(wb_result_fwd)  // レジスタ化済みデータ
);

// MEMステージへのフォワーディング接続
rv32i_mem u_mem (
    // ...
    .mem_forward_data(wb_result_fwd)  // レジスタ化済みデータ
);
```

---

## 実装ガイド

### 4.1 WBモジュール実装（組み合わせロジック）

```systemverilog
// ファイル: rv32i_wb.sv

module rv32i_wb (
    // 入力
    input  logic [31:0] mem_wb_alu_result,
    input  logic [31:0] mem_wb_load_data,
    input  logic [31:0] mem_wb_pc,
    input  logic [31:0] mem_wb_csr_rdata,
    input  ctrl_signals_t mem_wb_ctrl,
    input  logic        mem_wb_valid,
    
    // 出力（組み合わせ）
    output logic [31:0] wb_result,
    output logic        rf_wen,
    output logic [4:0]  rf_waddr
);

// 結果MUX（組み合わせロジック）
always_comb begin
    case (mem_wb_ctrl.rf_wdata_sel)
        2'b00: wb_result = mem_wb_alu_result;
        2'b01: wb_result = mem_wb_load_data;
        2'b10: wb_result = mem_wb_pc + 32'd4;
        2'b11: wb_result = mem_wb_csr_rdata;
    endcase
end

// レジスタ書き込み制御
assign rf_wen   = mem_wb_ctrl.rf_wen && mem_wb_valid;
assign rf_waddr = mem_wb_rd_addr;

endmodule
```

### 4.2 統合レベル実装（rv32i_top）

```systemverilog
// ファイル: rv32i_top.sv

// WBモジュールインスタンス
logic [31:0] wb_result;  // 組み合わせ信号

rv32i_wb u_wb (
    .clk(clk),
    .rst_n(rst_n),
    .mem_wb_alu_result(mem_wb_alu_result),
    .mem_wb_load_data(mem_wb_load_data),
    .mem_wb_pc(mem_wb_pc),
    .mem_wb_csr_rdata(mem_wb_csr_rdata),
    .mem_wb_ctrl(mem_wb_ctrl),
    .mem_wb_valid(mem_wb_valid),
    .wb_result(wb_result),              // 組み合わせ出力
    .rf_wen(rf_wen),
    .rf_waddr(rf_waddr)
);

// フォワーディング専用レジスタ（重要！）
logic [31:0] wb_result_fwd;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || soft_reset_active) begin
        wb_result_fwd <= 32'h0;
    end else begin
        wb_result_fwd <= wb_result;  // レジスタ化
    end
end

// IDレジスタファイル書き込み（組み合わせwb_resultを使用）
assign id_rf_wdata = wb_result;  // 即座に書き込み

// EX/MEMフォワーディング（レジスタ化wb_result_fwdを使用）
assign ex_wb_forward_data = wb_result_fwd;
assign mem_wb_forward_data = wb_result_fwd;
```

---

## デバッグガイド

### 5.1 フォワーディングタイミング確認

```systemverilog
`ifdef DEBUG_WB_FORWARDING
always @(posedge clk) begin
    $display("[WB_DEBUG] wb_result (comb)=0x%08X, wb_result_fwd (reg)=0x%08X",
             wb_result, wb_result_fwd);
    if (wb_result != wb_result_fwd)
        $display("[WB_DEBUG] *** Forwarding timing mismatch detected! ***");
end
`endif
```

### 5.2 レジスタ書き込み確認

```systemverilog
always @(posedge clk) begin
    if (rf_wen)
        $display("[WB_DEBUG] Write x%0d <= 0x%08X (sel=%b)",
                 rf_waddr, wb_result, mem_wb_ctrl.rf_wdata_sel);
end
```

---

## 検証ポイント

### 6.1 アサーション

#### **SPEC-WB-1: フォワーディング値安定性**
```systemverilog
property wb_forwarding_stable;
    logic [31:0] captured_fwd;
    @(posedge clk) disable iff (!rst_n)
    (1'b1, captured_fwd = wb_result_fwd)
    |=> (wb_result_fwd == captured_fwd || $changed(wb_result));
endproperty

assert_wb_fwd_stable: assert property (wb_forwarding_stable)
    else $error("[WB_SPEC] wb_result_fwd changed unexpectedly");
```

#### **SPEC-WB-2: x0書き込み防止**
```systemverilog
property no_write_to_x0;
    @(posedge clk) disable iff (!rst_n)
    (rf_wen && rf_waddr == 5'b0) |-> 1'b0;  // x0書き込みは常に偽
endproperty

assert_no_x0_write: assert property (no_write_to_x0)
    else $error("[WB_SPEC] Attempted write to x0");
```

---

## 関連ドキュメント

- **[00_overview.md](00_overview.md)** - WBフォワーディングタイミング修正の全体説明
- **[02_id_stage.md](02_id_stage.md)** - レジスタファイル書き込み先
- **[03_hazard_unit.md](03_hazard_unit.md)** - WBフォワーディング制御
- **[04_ex_stage.md](04_ex_stage.md)** - WBフォワーディングデータ使用
- **[08_integration.md](08_integration.md)** - rv32i_topでの統合実装

---

**このドキュメントの目的**: 
WBステージの**結果選択**、**レジスタ書き込み**、**フォワーディングタイミング修正**を理解し、正確に実装できる知識を提供します。特に**wb_result_fwdのレジスタ化が必須**であることを強調します。
