# CSR Module - 詳細設計

**モジュール名:** `rv32i_csr`  
**ファイル:** `rtl/cpu/rv32i_csr.sv`  
**バージョン:** 1.1  
**最終更新:** 2026年1月5日

---

## 設計意図

CSRモジュールは**Machine Mode制御と例外処理**を担当：

1. **CSRレジスタバンク**: mtvec, mepc, mcause, mtval
2. **例外ハンドラ**: トラップ時のPC保存、ベクタジャンプ
3. **MRET処理**: 例外復帰時のPC復元
4. **CSR読み書き**: CSRRW/CSRRS/CSRRC命令対応

### 主要なCSRレジスタ

| CSRアドレス | 名前 | 説明 |
|------------|------|------|
| 0x305 | mtvec | Machine Trap-Vector Base-Address (例外ハンドラPC) |
| 0x341 | mepc | Machine Exception Program Counter (例外発生時のPC) |
| 0x342 | mcause | Machine Cause (例外原因コード) |
| 0x343 | mtval | Machine Trap Value (例外関連付加情報) |

---

## ブロック図

```
                ┌────────────────────────────────────────────────┐
                │         rv32i_csr Module                       │
                │                                                │
                │  ┌──────────────────────────────────────────┐  │
                │  │    CSR Register Bank                     │  │
                │  │                                          │  │
                │  │  mtvec[31:0]  (0x305)                   │  │
                │  │   - Exception handler PC                │  │
                │  │   - Default: 0x1000                     │  │
                │  │                                          │  │
                │  │  mepc[31:0]   (0x341)                   │  │
                │  │   - Saved PC on trap                    │  │
                │  │                                          │  │
                │  │  mcause[31:0] (0x342)                   │  │
                │  │   - Exception cause code                │  │
                │  │   - MSB=1: interrupt (未実装)            │  │
                │  │   - MSB=0: exception                    │  │
                │  │                                          │  │
                │  │  mtval[31:0]  (0x343)                   │  │
                │  │   - Additional exception info           │  │
                │  └──────────────┬───────────────────────────┘  │
                │                 │                              │
 csr_raddr ─────┼────────────────►│  CSR Read Logic             │
 [11:0]         │                 │  (combinational)            │
                │                 ▼                              │
                │            csr_rdata[31:0] ──────────────────►│ to ID stage
                │                                                │
 trap_req ──────┼────────────────►┌───────────────────────────┐ │
 trap_cause ────┼────────────────►│   Exception Handler        │ │
 trap_value ────┼────────────────►│                            │ │
 trap_pc ───────┼────────────────►│  On trap:                  │ │
                │                 │   mepc <= trap_pc          │ │
                │                 │   mcause <= trap_cause     │ │
                │                 │   mtval <= trap_value      │ │
                │                 │   trap_redirect = 1        │ │
                │                 │   trap_vector = mtvec      │ │
                │                 └────────────┬───────────────┘ │
                │                              │                  │
                │                              ▼                  │
                │                         trap_redirect ──────────┼─► to hazard
                │                         trap_vector[31:0] ──────┼─► to IF
                │                                                 │
 mret_req ──────┼────────────────►┌───────────────────────────┐  │
                │                 │   MRET Handler             │  │
                │                 │                            │  │
                │                 │  On MRET:                  │  │
                │                 │   mret_pc = mepc           │  │
                │                 └────────────┬───────────────┘  │
                │                              │                  │
                │                              ▼                  │
                │                         mret_pc[31:0] ──────────┼─► to IF
                │                                                 │
 csr_write ─────┼────────────────►┌───────────────────────────┐  │
 csr_waddr ─────┼────────────────►│   CSR Write Logic          │  │
 csr_wdata ─────┼────────────────►│   (CSRRW/CSRRS/CSRRC)     │  │
 csr_op ────────┼────────────────►│                            │  │
                │                 │  Op:                       │  │
                │                 │   01: CSRRW (write)        │  │
                │                 │   10: CSRRS (set bits)     │  │
                │                 │   11: CSRRC (clear bits)   │  │
                │                 └────────────────────────────┘  │
                │                                                 │
                └─────────────────────────────────────────────────┘
```

---

## 機能詳細

### 3.1 CSR読み出し

```systemverilog
always_comb begin
    case (csr_raddr)
        12'h305: csr_rdata = mtvec;
        12'h341: csr_rdata = mepc;
        12'h342: csr_rdata = mcause;
        12'h343: csr_rdata = mtval;
        default: csr_rdata = 32'h0;
    endcase
end
```

### 3.2 例外処理

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mepc   <= 32'h0;
        mcause <= 32'h0;
        mtval  <= 32'h0;
    end else if (trap_req) begin
        mepc   <= trap_pc;      // 例外発生時のPC保存
        mcause <= trap_cause;   // 例外原因コード
        mtval  <= trap_value;   // 付加情報（アドレスなど）
    end
end

// トラップリダイレクト
assign trap_redirect = trap_req;
assign trap_vector = mtvec;
```

**例外原因コード**:
- 0x00: Instruction address misaligned
- 0x02: Illegal instruction
- 0x04: Load address misaligned
- 0x06: Store address misaligned
- 0x0B: Environment call (ECALL)
- 0x03: Breakpoint (EBREAK)

### 3.3 MRET処理

```systemverilog
assign mret_pc = mepc;  // 保存されたPCに復帰
```

### 3.4 CSR書き込み

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mtvec <= 32'h0000_1000;  // デフォルトハンドラアドレス
    end else if (csr_write) begin
        case (csr_waddr)
            12'h305: begin  // mtvec
                case (csr_op)
                    2'b01: mtvec <= csr_wdata;              // CSRRW
                    2'b10: mtvec <= mtvec | csr_wdata;      // CSRRS
                    2'b11: mtvec <= mtvec & ~csr_wdata;     // CSRRC
                endcase
            end
            // 他のCSRも同様
        endcase
    end
end
```

---

## 実装ガイド

### 4.1 CSRレジスタ宣言

```systemverilog
logic [31:0] mtvec;
logic [31:0] mepc;
logic [31:0] mcause;
logic [31:0] mtval;

// リセット値
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mtvec  <= 32'h0000_1000;  // 例外ハンドラアドレス
        mepc   <= 32'h0;
        mcause <= 32'h0;
        mtval  <= 32'h0;
    end
    // 以下、例外処理とCSR書き込みロジック
end
```

### 4.2 例外検出とトラップ

```systemverilog
// MEM/EXステージから例外情報受信
input logic        trap_req;
input logic [31:0] trap_pc;
input logic [31:0] trap_cause;
input logic [31:0] trap_value;

// 例外時にmepc/mcause/mtvalを更新
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mepc   <= 32'h0;
        mcause <= 32'h0;
        mtval  <= 32'h0;
    end else if (trap_req) begin
        mepc   <= trap_pc;
        mcause <= trap_cause;
        mtval  <= trap_value;
    end
end
```

---

## デバッグガイド

```systemverilog
`ifdef DEBUG_CSR_MODULE
always @(posedge clk) begin
    if (trap_req)
        $display("[CSR_DEBUG] Trap: PC=0x%08X, cause=0x%08X, value=0x%08X",
                 trap_pc, trap_cause, trap_value);
    if (mret_req)
        $display("[CSR_DEBUG] MRET: returning to PC=0x%08X", mepc);
    if (csr_write)
        $display("[CSR_DEBUG] CSR Write: addr=0x%03X, data=0x%08X, op=%b",
                 csr_waddr, csr_wdata, csr_op);
end
`endif
```

---

## 関連ドキュメント

- **[00_overview.md](00_overview.md)** - CPU全体アーキテクチャ
- **[01_if_stage.md](01_if_stage.md)** - trap_vectorとmret_pc使用
- **[05_mem_stage.md](05_mem_stage.md)** - 例外検出
- **[08_integration.md](08_integration.md)** - 例外処理フロー

---

**このドキュメントの目的**: 
CSRモジュールの**レジスタ管理**、**例外処理**、**MRET復帰**を理解し、正確に実装できる知識を提供します。
