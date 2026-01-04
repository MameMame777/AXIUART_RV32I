# Execute (EX) Stage - 詳細設計

**モジュール名:** `rv32i_ex`  
**ファイル:** `rtl/cpu/rv32i_ex.sv`  
**バージョン:** 1.1  
**最終更新:** 2026年1月5日

---

## 設計意図

### なぜこの設計なのか

EXステージは**実際の演算実行と制御フロー決定**を担当：

1. **ALU演算**: 算術・論理・シフト演算を1サイクルで完了
2. **分岐判定**: 分岐条件評価とターゲットアドレス計算
3. **フォワーディングMUX**: 3ソース（EX/MEM/WB）からの最新データ選択
4. **ジャンプ計算**: JAL/JALRのターゲットPC生成

### 主要な設計判断

#### 判断1: フォワーディングMUXをALU前に配置 ✅

**構成**:
```
フォワーディングMUX → ALU/Branch Comparator → EX/MEMレジスタ
```

**理由**:
- フォワーディング制御はIDステージで事前計算済み（ID/EXレジスタに格納）
- EXステージのクリティカルパス: MUX → ALU（約4ns @ 125MHz）
- ALU後にMUX配置すると遅延増加

**効果**:
- ✅ タイミング最適化
- ✅ クリーンなデータフロー

#### 判断2: 分岐評価はEXステージ ✅

**理由**:
- IDステージでレジスタ読み出し完了
- EXステージでフォワーディング後の最新値で比較
- IFステージ予測なし（シンプル設計優先）

**ペナルティ**: 2サイクル（ストール1 + フラッシュ1）

---

## ブロック図

```
                ┌──────────────────────────────────────────┐
                │          rv32i_ex Module                 │
                │                                          │
 id_ex_rs1_data │  ┌────────────────────────────────────┐  │
     [31:0]  ───┼─►│  RS1 Forwarding Multiplexer       │  │
 forward_rs1_sel│  │  (4-way select)                   │  │
     [1:0]   ───┼─►│                                    │  │
 ex_mem_result  │  │  00: ID stage (id_ex_rs1_data)    │  │
     [31:0]  ───┼─►│  01: EX/MEM reg (ex_mem_result)   │  │
 mem_wb_result  │  │  10: MEM/WB reg (mem_wb_result)   │  │
     [31:0]  ───┼─►│  11: WB forward (wb_result_fwd)   │  │
 wb_result_fwd  │  └──────────┬─────────────────────────┘  │
     [31:0]  ───┼─────────────┘                            │
                │             │ rs1_forward[31:0]          │
                │             │                            │
 id_ex_rs2_data │  ┌──────────▼─────────────────────────┐  │
     [31:0]  ───┼─►│  RS2 Forwarding Multiplexer       │  │
 forward_rs2_sel│  │  (4-way select, 同様)              │  │
     [1:0]   ───┼─►│                                    │  │
                │  └──────────┬─────────────────────────┘  │
                │             │ rs2_forward[31:0]          │
                │             │                            │
                │  ┌──────────▼──────┬──────────────────┐  │
                │  │   ALU Operand   │   ALU Operand    │  │
                │  │   Mux A         │   Mux B          │  │
 alu_src1_sel───┼─►│  0: rs1_forward │  0: rs2_forward  │◄─┼─ alu_src2_sel
 id_ex_pc ──────┼─►│  1: PC          │  1: imm          │◄─┼─ id_ex_imm
                │  └────────┬────────┴────────┬─────────┘  │
                │           │ alu_a    alu_b  │            │
                │           │                 │            │
                │  ┌────────▼─────────────────▼─────────┐  │
 alu_op[3:0] ───┼─►│         ALU (32-bit)              │  │
                │  │                                    │  │
                │  │  Operations:                       │  │
                │  │   0000: ADD, 0001: SUB            │  │
                │  │   0010: SLL, 0011: SLT            │  │
                │  │   0100: SLTU, 0101: XOR           │  │
                │  │   0110: SRL, 0111: SRA            │  │
                │  │   1000: OR, 1001: AND             │  │
                │  │   1010: PASS_B (for LUI)          │  │
                │  └────────────────┬───────────────────┘  │
                │                   │ alu_result[31:0]     │
                │                   │                      │
                │  ┌────────────────▼───────────────────┐  │
 rs1_forward────┼─►│   Branch Comparator               │  │
 rs2_forward────┼─►│   (BEQ/BNE/BLT/BGE/BLTU/BGEU)     │  │
 funct3[2:0]────┼─►│                                    │  │
 is_branch──────┼─►│   branch_condition = f(rs1, rs2)  │  │
                │  └─────────────────┬──────────────────┘  │
                │                    │ branch_condition    │
                │                    │                     │
                │  ┌─────────────────▼──────────────────┐  │
                │  │   Branch Target Calculator         │  │
 id_ex_pc[31:0]─┼─►│   target = PC + imm (B-type)       │  │
 id_ex_imm──────┼─►│   target = (rs1 + imm) & ~1 (JALR) │  │
 is_jalr────────┼─►│                                    │  │
                │  └─────────────────┬──────────────────┘  │
                │                    │ branch_target[31:0] │
                │                    │                     │
                │  ┌─────────────────▼──────────────────┐  │
                │  │   Branch Decision Logic            │  │
                │  │   branch_taken = is_branch &&      │  │
                │  │                  branch_condition  │  │
                │  │   OR is_jal OR is_jalr            │  │
                │  └─────────────────┬──────────────────┘  │
                │                    │                     │
                │  ┌─────────────────▼──────────────────┐  │
                │  │     EX/MEM Pipeline Register       │  │
                │  │                                    │  │
                │  │  - ex_mem_valid                    │  │
                │  │  - ex_mem_pc                       │  │
                │  │  - ex_mem_alu_result              │  │
                │  │  - ex_mem_rs2_data (store)        │  │
                │  │  - ex_mem_ctrl                     │  │
                │  └────────────────────────────────────┘  │
                │                    │                     │
                └────────────────────┼─────────────────────┘
                                     ▼
                              to MEM stage
```

---

## 機能詳細

### 3.1 フォワーディングマルチプレクサ

```systemverilog
logic [31:0] rs1_forward, rs2_forward;

// RS1フォワーディング
always_comb begin
    case (id_ex_forward_rs1)
        2'b00: rs1_forward = id_ex_rs1_data;    // ID RF
        2'b01: rs1_forward = ex_mem_alu_result; // EX fwd
        2'b10: rs1_forward = mem_wb_result;     // MEM fwd
        2'b11: rs1_forward = wb_result_fwd;     // WB fwd
    endcase
end

// RS2フォワーディング（同様）
always_comb begin
    case (id_ex_forward_rs2)
        2'b00: rs2_forward = id_ex_rs2_data;
        2'b01: rs2_forward = ex_mem_alu_result;
        2'b10: rs2_forward = mem_wb_result;
        2'b11: rs2_forward = wb_result_fwd;
    endcase
end
```

### 3.2 ALUオペランド選択

```systemverilog
logic [31:0] alu_a, alu_b;

// Operand A: rs1 or PC
assign alu_a = id_ex_ctrl.alu_src1_sel ? id_ex_pc : rs1_forward;

// Operand B: rs2 or immediate
assign alu_b = id_ex_ctrl.alu_src2_sel ? id_ex_imm : rs2_forward;
```

### 3.3 ALU演算

```systemverilog
logic [31:0] alu_result;

always_comb begin
    case (id_ex_ctrl.alu_op)
        4'b0000: alu_result = alu_a + alu_b;           // ADD/ADDI
        4'b0001: alu_result = alu_a - alu_b;           // SUB
        4'b0010: alu_result = alu_a << alu_b[4:0];     // SLL/SLLI
        4'b0011: alu_result = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0; // SLT/SLTI
        4'b0100: alu_result = (alu_a < alu_b) ? 32'd1 : 32'd0; // SLTU/SLTIU
        4'b0101: alu_result = alu_a ^ alu_b;           // XOR/XORI
        4'b0110: alu_result = alu_a >> alu_b[4:0];     // SRL/SRLI
        4'b0111: alu_result = $signed(alu_a) >>> alu_b[4:0]; // SRA/SRAI
        4'b1000: alu_result = alu_a | alu_b;           // OR/ORI
        4'b1001: alu_result = alu_a & alu_b;           // AND/ANDI
        4'b1010: alu_result = alu_b;                   // PASS_B (LUI)
        default: alu_result = 32'h0;
    endcase
end
```

### 3.4 分岐比較器

```systemverilog
logic branch_condition;

always_comb begin
    case (id_ex_funct3)
        3'b000: branch_condition = (rs1_forward == rs2_forward);        // BEQ
        3'b001: branch_condition = (rs1_forward != rs2_forward);        // BNE
        3'b100: branch_condition = ($signed(rs1_forward) < $signed(rs2_forward)); // BLT
        3'b101: branch_condition = ($signed(rs1_forward) >= $signed(rs2_forward)); // BGE
        3'b110: branch_condition = (rs1_forward < rs2_forward);         // BLTU
        3'b111: branch_condition = (rs1_forward >= rs2_forward);        // BGEU
        default: branch_condition = 1'b0;
    endcase
end

// 分岐判定
assign branch_taken = (id_ex_ctrl.is_branch && branch_condition) ||
                      id_ex_ctrl.is_jal ||
                      id_ex_ctrl.is_jalr;
```

### 3.5 分岐ターゲット計算

```systemverilog
logic [31:0] branch_target;

always_comb begin
    if (id_ex_ctrl.is_jalr)
        // JALR: (rs1 + imm) & ~1
        branch_target = {(rs1_forward + id_ex_imm)[31:1], 1'b0};
    else
        // JAL/Branch: PC + imm
        branch_target = id_ex_pc + id_ex_imm;
end
```

---

## 実装ガイド

### 4.1 ALU実装のポイント

**シフト量は下位5ビットのみ**:
```systemverilog
alu_result = alu_a << alu_b[4:0];  // 32ビットなので0-31のみ有効
```

**符号付き比較**:
```systemverilog
alu_result = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;
```

**算術右シフト**:
```systemverilog
alu_result = $signed(alu_a) >>> alu_b[4:0];  // 符号ビット拡張
```

---

## デバッグガイド

### 5.1 フォワーディング確認

```systemverilog
`ifdef DEBUG_EX_STAGE
always @(posedge clk) begin
    $display("[EX_DEBUG] fwd_rs1_sel=%b, rs1_fwd=0x%08X (ID=0x%08X, EX=0x%08X, MEM=0x%08X, WB=0x%08X)",
             id_ex_forward_rs1, rs1_forward, 
             id_ex_rs1_data, ex_mem_alu_result, mem_wb_result, wb_result_fwd);
end
`endif
```

### 5.2 分岐判定確認

```systemverilog
always @(posedge clk) begin
    if (id_ex_ctrl.is_branch)
        $display("[EX_DEBUG] Branch: PC=0x%08X, rs1=0x%08X, rs2=0x%08X, cond=%b, taken=%b, target=0x%08X",
                 id_ex_pc, rs1_forward, rs2_forward, branch_condition, branch_taken, branch_target);
end
```

---

## 関連ドキュメント

- **[03_hazard_unit.md](03_hazard_unit.md)** - フォワーディング制御生成
- **[05_mem_stage.md](05_mem_stage.md)** - ALU結果の使用
- **[06_wb_stage.md](06_wb_stage.md)** - wb_result_fwd生成

---

**このドキュメントの目的**: 
EXステージの**ALU演算**、**フォワーディング**、**分岐判定**を理解し、正確に実装できる知識を提供します。
