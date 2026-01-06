# Pipeline Integration - 詳細設計

**ドキュメント名:** パイプライン統合設計  
**バージョン:** 1.1  
**最終更新:** 2026年1月5日

---

## 設計意図

このドキュメントは**5ステージパイプラインの統合と相互作用**を説明します：

1. **パイプラインレジスタ**: ステージ間のデータ伝播
2. **制御フロー**: ストール/フラッシュの伝播
3. **データフォワーディング**: 3レベルフォワーディングパス
4. **タイミング解析**: クリティカルパスと最適化
5. **クロック単位実行例**: 具体的な命令シーケンス

---

## パイプラインレジスタ構成

### 1. IF/IDレジスタ

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        if_id_valid <= 1'b0;
        if_id_pc    <= 32'h0;
        if_id_insn  <= 32'h0000_0013;  // NOP
    end else if (if_flush) begin
        if_id_valid <= 1'b0;
    end else if (!if_stall) begin
        if_id_valid <= 1'b1;
        if_id_pc    <= pc_reg;
        if_id_insn  <= insn_ram_rdata;
    end
end
```

### 2. ID/EXレジスタ

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        id_ex_valid      <= 1'b0;
        id_ex_pc         <= 32'h0;
        id_ex_rs1_data   <= 32'h0;
        id_ex_rs2_data   <= 32'h0;
        id_ex_imm        <= 32'h0;
        id_ex_ctrl       <= '0;
        id_ex_forward_rs1 <= 2'b00;
        id_ex_forward_rs2 <= 2'b00;
    end else if (id_flush) begin
        id_ex_valid <= 1'b0;
    end else if (!id_stall) begin
        id_ex_valid      <= if_id_valid;
        id_ex_pc         <= if_id_pc;
        id_ex_rs1_data   <= rs1_data;
        id_ex_rs2_data   <= rs2_data;
        id_ex_imm        <= imm;
        id_ex_ctrl       <= ctrl;
        id_ex_forward_rs1 <= forward_rs1_sel;
        id_ex_forward_rs2 <= forward_rs2_sel;
    end
end
```

### 3. EX/MEMレジスタ

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ex_mem_valid      <= 1'b0;
        ex_mem_alu_result <= 32'h0;
        ex_mem_rs2_data   <= 32'h0;
        ex_mem_ctrl       <= '0;
    end else if (ex_flush) begin
        ex_mem_valid <= 1'b0;
    end else begin
        ex_mem_valid      <= id_ex_valid;
        ex_mem_alu_result <= alu_result;
        ex_mem_rs2_data   <= rs2_forward;  // ストアデータ
        ex_mem_ctrl       <= id_ex_ctrl;
    end
end
```

### 4. MEM/WBレジスタ

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem_wb_valid      <= 1'b0;
        mem_wb_alu_result <= 32'h0;
        mem_wb_load_data  <= 32'h0;
        mem_wb_ctrl       <= '0;
    end else begin
        mem_wb_valid      <= ex_mem_valid;
        mem_wb_alu_result <= ex_mem_alu_result;
        mem_wb_load_data  <= aligned_load_data;
        mem_wb_ctrl       <= ex_mem_ctrl;
    end
end
```

---

## クロック単位実行例

### 例1: 通常実行（ハザードなし）

```
命令シーケンス:
  0x0000: ADDI x1, x0, 10   # x1 = 10
  0x0004: ADDI x2, x0, 20   # x2 = 20
  0x0008: ADD  x3, x1, x2   # x3 = 30 (フォワーディング不要)
  0x000C: SW   x3, 0(x0)    # メモリ[0] = 30

Cycle 0: IF=ADDI_x1
Cycle 1: IF=ADDI_x2, ID=ADDI_x1
Cycle 2: IF=ADD_x3,  ID=ADDI_x2, EX=ADDI_x1
Cycle 3: IF=SW_x3,   ID=ADD_x3,  EX=ADDI_x2, MEM=ADDI_x1
Cycle 4: IF=next,    ID=SW_x3,   EX=ADD_x3,  MEM=ADDI_x2, WB=ADDI_x1
Cycle 5:             IF=next,    ID=next,    EX=SW_x3,    MEM=ADD_x3,  WB=ADDI_x2
```

### 例2: EXフォワーディング（RAWハザード）

```
命令シーケンス:
  0x0000: ADDI x1, x0, 5    # x1 = 5
  0x0004: ADD  x2, x1, x1   # x2 = 10 (x1をEXからフォワード)

Cycle 0: IF=ADDI_x1
Cycle 1: IF=ADD_x2, ID=ADDI_x1
         Hazard: id_rs1=x1, id_rs2=x1, ex_rd=x1 → forward_rs1/2_sel=2'b01
Cycle 2: IF=next,   ID=ADD_x2 (forward_rs1/2=2'b01 registered), EX=ADDI_x1
         EX: rs1_forward = ex_mem_alu_result (ADDI結果=5)
             rs2_forward = ex_mem_alu_result (ADDI結果=5)
             alu_result = 5 + 5 = 10 ✓
```

### 例3: ロード使用ストール

```
命令シーケンス:
  0x0000: LW   x1, 0(x0)    # x1 = mem[0]
  0x0004: ADD  x2, x1, x1   # x2 = x1 + x1

Cycle 0: IF=LW_x1
Cycle 1: IF=ADD_x2, ID=LW_x1
         Hazard: load-use detected (ex_is_load=1, ex_rd=x1, id_rs1/2=x1)
         → if_stall=1, id_stall=1
Cycle 2: IF=ADD_x2 (stalled), ID=ADD_x2 (stalled), EX=LW_x1
         Load data not yet available
Cycle 3: IF=ADD_x2, ID=ADD_x2 (retry, forward_rs1/2=2'b10 for MEM fwd), EX=bubble, MEM=LW_x1
         MEM: load data available
Cycle 4: IF=next, ID=next, EX=ADD_x2, MEM=bubble, WB=LW_x1
         EX: rs1_forward = mem_wb_result (LWのロードデータ)
             rs2_forward = mem_wb_result
             alu_result = load_data + load_data ✓
```

### 例4: 分岐Taken（フラッシュ）

```
命令シーケンス:
  0x0000: BEQ  x1, x2, target  # target=0x0100
  0x0004: ADD  x3, x1, x2      # 実行されない（フラッシュ）
  ...
  0x0100: SUB  x4, x5, x6      # 分岐ターゲット

Cycle 0: IF=BEQ
Cycle 1: IF=ADD (wrong path), ID=BEQ
Cycle 2: IF=next, ID=ADD (wrong path), EX=BEQ
         EX: branch_condition=1 → branch_taken=1
Cycle 3: IF=SUB (0x0100), ID=bubble (if_flush=1), EX=bubble (id_flush=1), MEM=BEQ
         IF/IDフラッシュ、正しいターゲットフェッチ開始
Cycle 4: IF=next, ID=SUB, EX=bubble, MEM=bubble, WB=BEQ
         分岐ペナルティ: 2サイクル
```

### 例5: WBフォワーディング（タイミング修正後）

```
命令シーケンス:
  0x0000: ADDI x27, x0, 7      # x27 = 7
  0x0004: LUI  x15, 0x4000     # x15 = 0x4000000
  0x0008: SW   x27, 0(x15)     # mem[0x4000000] = 7

Cycle N:   WB=ADDI_x27, wb_result=0x7 (combinational)
           wb_result_fwd=0x7 (registered, from cycle N-1)
Cycle N+1: WB=LUI_x15, wb_result=0x4000000 (combinational)
           wb_result_fwd=0x7 (registered, holds ADDI result)
           EX=SW_x27, needs x27
           EX: forward_rs2_sel=2'b11 (WB forward)
               rs2_forward = wb_result_fwd = 0x7 ✓ (正しい値)
           ❌ 修正前: rs2_forward = wb_result = 0x4000000 (誤り)
```

---

## タイミング解析

### クリティカルパス

**最長パス（修正後）**:
```
IF Stage: PC加算器 (1ns) + MUX (0.5ns) = 1.5ns
ID Stage: レジスタファイル読み出し (2ns) + ハザード検出 (1ns) = 3ns
EX Stage: フォワーディングMUX (1ns) + ALU (3ns) = 4ns ← 最長
MEM Stage: BRAM読み出し (1.5ns) + アライメント (1ns) = 2.5ns
WB Stage: 結果MUX (0.5ns) = 0.5ns
```

**合計**: 約4ns @ EXステージ → 250MHz理論値（実装目標: 125MHz）

### フォワーディングタイミング最適化

**修正前**:
```
クリティカルパス: MEM/WB reg → WB mux → wb_result → EX fwd mux → ALU
                   (1ns)      (0.5ns)   (wire)     (1ns)      (3ns) = 5.5ns
```

**修正後**:
```
Cycle N:   MEM/WB reg → WB mux → wb_result
                       (1ns)    (0.5ns)    = 1.5ns
           wb_result_fwd register update
                       
Cycle N+1: wb_result_fwd → EX fwd mux → ALU
                (wire)     (1ns)      (3ns) = 4ns
```

**効果**: クリティカルパス1.5ns短縮、サイクル分割により並列性向上

---

## 制御フロー統合

### ストール伝播

```systemverilog
// ハザードユニット出力
assign if_stall = load_use_hazard;
assign id_stall = load_use_hazard;

// IFステージ
if (!if_stall) pc_reg <= pc_next;

// IDステージ
if (!id_stall) id_ex_reg <= {if_id_valid, if_id_pc, ...};
```

### フラッシュ伝播

```systemverilog
// ハザードユニット出力
assign if_flush = branch_taken | trap_redirect;
assign id_flush = branch_taken | trap_redirect;
assign ex_flush = trap_redirect;  // 例外時のみEXフラッシュ

// IFステージ
if (if_flush) if_id_valid <= 1'b0;

// IDステージ
if (id_flush) id_ex_valid <= 1'b0;

// EXステージ
if (ex_flush) ex_mem_valid <= 1'b0;
```

---

## デバッグガイド

### パイプライン可視化

```systemverilog
`ifdef DEBUG_PIPELINE
always @(posedge clk) begin
    $display("==================================================");
    $display("Cycle %0d:", $time / 10);
    $display("  IF : PC=0x%08X, insn=0x%08X, valid=%b", 
             pc_reg, if_id_insn, if_id_valid);
    $display("  ID : PC=0x%08X, insn=0x%08X, valid=%b", 
             if_id_pc, if_id_insn, if_id_valid);
    $display("  EX : PC=0x%08X, alu=0x%08X, valid=%b", 
             id_ex_pc, alu_result, id_ex_valid);
    $display("  MEM: PC=0x%08X, addr=0x%08X, valid=%b", 
             ex_mem_pc, ex_mem_alu_result, ex_mem_valid);
    $display("  WB : PC=0x%08X, result=0x%08X, valid=%b", 
             mem_wb_pc, wb_result, mem_wb_valid);
    $display("  Hazard: stall=%b%b, flush=%b%b%b, fwd_rs1=%b, fwd_rs2=%b",
             if_stall, id_stall, if_flush, id_flush, ex_flush,
             id_ex_forward_rs1, id_ex_forward_rs2);
    $display("==================================================");
end
`endif
```

---

## 関連ドキュメント

- **[00_overview.md](00_overview.md)** - 全体アーキテクチャとWB修正
- **[01_if_stage.md](01_if_stage.md) - [07_csr_module.md](07_csr_module.md)** - 各ステージ詳細

---

**このドキュメントの目的**: 
パイプライン統合の**データフロー**、**制御フロー**、**タイミング**を理解し、正確なシステム動作を検証できる知識を提供します。
