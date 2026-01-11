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

## 例外処理ワークフロー

### 4.1 トラップハンドリングシーケンス

例外（exception）または割り込み（interrupt）が発生した際の、ハードウェアとソフトウェアの協調動作を説明します。

#### 完全なトラップフロー

```
┌─────────────────────────────────────────────────────────────┐
│ Phase 1: Exception Detection (MEMステージ)                  │
├─────────────────────────────────────────────────────────────┤
│ - アドレスミスアライン検出                                  │
│ - 不正命令検出 (IDステージで事前検出済み)                   │
│ - ECALL命令実行                                             │
│ - EBREAK命令実行（ブレークポイント）                        │
│ - ストアアクセス違反（未実装アドレス）                      │
└─────────────────────────────────────────────────────────────┘
                        ↓ (同一サイクル)
┌─────────────────────────────────────────────────────────────┐
│ Phase 2: PC Capture & Exception Code Recording             │
├─────────────────────────────────────────────────────────────┤
│ mepc  ← 例外発生命令のPC (faulting instruction address)    │
│ mcause ← 例外コード (下表参照)                              │
│ mtval ← 追加情報 (ミスアラインアドレス等)                   │
└─────────────────────────────────────────────────────────────┘
                        ↓ (同一サイクル)
┌─────────────────────────────────────────────────────────────┐
│ Phase 3: PC Redirect                                        │
├─────────────────────────────────────────────────────────────┤
│ PC ← mtvec (トラップハンドラエントリポイント)               │
│ IF/ID/EXステージフラッシュ（バブル注入）                    │
└─────────────────────────────────────────────────────────────┘
                        ↓ (次サイクル)
┌─────────────────────────────────────────────────────────────┐
│ Phase 4: Trap Handler Execution (ソフトウェア)             │
├─────────────────────────────────────────────────────────────┤
│ 1. コンテキスト保存（レジスタをスタックに退避）            │
│ 2. mcause読み出し（例外原因を特定）                        │
│ 3. mepc読み出し（例外発生PCを確認）                        │
│ 4. mtval読み出し（追加情報取得）                           │
│ 5. 例外処理実行（エラー処理、修正、ログ記録など）          │
│ 6. コンテキスト復元（レジスタをスタックから復元）          │
│ 7. MRET命令実行                                             │
└─────────────────────────────────────────────────────────────┘
                        ↓ (MRET実行時)
┌─────────────────────────────────────────────────────────────┐
│ Phase 5: Exception Return (MRET)                           │
├─────────────────────────────────────────────────────────────┤
│ PC ← mepc (例外発生命令 or 次命令に復帰)                    │
│ 通常実行再開                                                │
└─────────────────────────────────────────────────────────────┘
```

#### 例外コード (mcause値)

| mcause値 | 例外名 | 説明 | mtvalの内容 |
|---------|--------|------|------------|
| 0x00000000 | Instruction address misaligned | 命令フェッチアドレスが4バイト境界でない | ミスアラインPC |
| 0x00000002 | Illegal instruction | 不正または未実装命令 | 不正命令コード |
| 0x00000003 | Breakpoint | EBREAK命令実行 | EBREAK命令のPC |
| 0x00000004 | Load address misaligned | ロードアドレスが境界でない | ミスアラインアドレス |
| 0x00000006 | Store address misaligned | ストアアドレスが境界でない | ミスアラインアドレス |
| 0x0000000B | Environment call (M-mode) | ECALL命令実行 | 0 |

**注意**: このCPUは割り込み未実装のため、mcause[31](割り込みフラグ)は常に0です。

#### 例外優先度

複数の例外が同時に発生した場合、以下の優先順位で処理されます（高い方から）：

1. **命令アドレスミスアライン** (IFステージ)
2. **不正命令** (IDステージ)
3. **ブレークポイント (EBREAK)** (MEMステージ)
4. **ロード/ストアアドレスミスアライン** (MEMステージ)
5. **環境呼び出し (ECALL)** (MEMステージ)

**実装詳細**: 
- パイプライン後段の例外が優先（older instructions take precedence）
- 同一ステージ内では上記順序に従う

---

### 4.2 トラップハンドラの実装例

#### ベーシックなトラップハンドラ

```assembly
# トラップハンドラエントリポイント (mtvec = 0x0000_1000)
trap_handler:
    # ──────────────────────────────────────────────────
    # Phase 1: コンテキスト保存（最小限の例）
    # ──────────────────────────────────────────────────
    # スタックポインタを32レジスタ分確保
    addi sp, sp, -128       # 32 regs × 4 bytes = 128 bytes
    
    # すべてのレジスタを保存（x0除く）
    sw   x1,   4(sp)        # ra
    sw   x2,   8(sp)        # sp (古い値は後で調整)
    sw   x3,  12(sp)        # gp
    sw   x4,  16(sp)        # tp
    sw   x5,  20(sp)        # t0
    sw   x6,  24(sp)        # t1
    sw   x7,  28(sp)        # t2
    sw   x8,  32(sp)        # s0/fp
    sw   x9,  36(sp)        # s1
    sw   x10, 40(sp)        # a0
    sw   x11, 44(sp)        # a1
    sw   x12, 48(sp)        # a2
    sw   x13, 52(sp)        # a3
    sw   x14, 56(sp)        # a4
    sw   x15, 60(sp)        # a5
    sw   x16, 64(sp)        # a6
    sw   x17, 68(sp)        # a7
    sw   x18, 72(sp)        # s2
    sw   x19, 76(sp)        # s3
    sw   x20, 80(sp)        # s4
    sw   x21, 84(sp)        # s5
    sw   x22, 88(sp)        # s6
    sw   x23, 92(sp)        # s7
    sw   x24, 96(sp)        # s8
    sw   x25, 100(sp)       # s9
    sw   x26, 104(sp)       # s10
    sw   x27, 108(sp)       # s11
    sw   x28, 112(sp)       # t3
    sw   x29, 116(sp)       # t4
    sw   x30, 120(sp)       # t5
    sw   x31, 124(sp)       # t6
    
    # 古いsp値を修正して保存
    addi t0, sp, 128        # t0 = 例外発生前のsp
    sw   t0, 8(sp)          # 正しいsp値を保存
    
    # ──────────────────────────────────────────────────
    # Phase 2: 例外原因の判定
    # ──────────────────────────────────────────────────
    csrr a0, mcause         # a0 = mcause (例外コード)
    csrr a1, mepc           # a1 = mepc (例外PC)
    csrr a2, mtval          # a2 = mtval (追加情報)
    
    # mcauseで分岐
    addi t0, zero, 0x02     # t0 = 0x02 (Illegal instruction)
    beq  a0, t0, handle_illegal_insn
    
    addi t0, zero, 0x03     # t0 = 0x03 (Breakpoint)
    beq  a0, t0, handle_breakpoint
    
    addi t0, zero, 0x0B     # t0 = 0x0B (ECALL)
    beq  a0, t0, handle_ecall
    
    # デフォルト: 不明な例外
    j    handle_unknown
    
# ──────────────────────────────────────────────────
# 個別例外ハンドラ
# ──────────────────────────────────────────────────

handle_illegal_insn:
    # 不正命令処理
    # 例: LEDに0xEを表示（エラーインジケータ）
    lui  t0, 0x4            # t0 = 0x0000_4000
    addi t1, t0, 0x7C       # t1 = 0x0000_407C (LED address)
    addi t2, zero, 0xE      # t2 = 0b1110 (Error pattern)
    sw   t2, 0(t1)          # LEDに書き込み
    
    # mepcを+4して次命令から再開（スキップ）
    addi a1, a1, 4          # a1 (mepc) += 4
    csrw mepc, a1           # mepcを更新
    j    trap_return
    
handle_breakpoint:
    # EBREAK処理（デバッガ通知など）
    # 例: 何もせず同じ命令を再実行（デバッガ介入待ち）
    j    trap_return
    
handle_ecall:
    # システムコール処理
    # a0-a7に引数が入っている（標準ABI）
    # 例: a0がシステムコール番号
    
    # システムコール番号0: プログラム終了
    beq  a0, zero, syscall_exit
    
    # システムコール番号1: 文字列出力（未実装）
    addi t0, zero, 1
    beq  a0, t0, syscall_print
    
    # 不明なシステムコール
    j    trap_return
    
syscall_exit:
    # プログラム終了（無限ループ）
    j    syscall_exit
    
syscall_print:
    # 文字列出力（UARTがあれば実装）
    # ここでは何もしない
    j    trap_return
    
handle_unknown:
    # 不明な例外: LED全点灯して無限ループ
    lui  t0, 0x4
    addi t1, t0, 0x7C
    addi t2, zero, 0xF      # All LEDs on
    sw   t2, 0(t1)
    j    handle_unknown     # Hang
    
# ──────────────────────────────────────────────────
# Phase 3: コンテキスト復元とリターン
# ──────────────────────────────────────────────────
trap_return:
    # すべてのレジスタを復元
    lw   x1,   4(sp)        # ra
    # x2 (sp) は最後に復元
    lw   x3,  12(sp)        # gp
    lw   x4,  16(sp)        # tp
    lw   x5,  20(sp)        # t0
    lw   x6,  24(sp)        # t1
    lw   x7,  28(sp)        # t2
    lw   x8,  32(sp)        # s0/fp
    lw   x9,  36(sp)        # s1
    lw   x10, 40(sp)        # a0
    lw   x11, 44(sp)        # a1
    lw   x12, 48(sp)        # a2
    lw   x13, 52(sp)        # a3
    lw   x14, 56(sp)        # a4
    lw   x15, 60(sp)        # a5
    lw   x16, 64(sp)        # a6
    lw   x17, 68(sp)        # a7
    lw   x18, 72(sp)        # s2
    lw   x19, 76(sp)        # s3
    lw   x20, 80(sp)        # s4
    lw   x21, 84(sp)        # s5
    lw   x22, 88(sp)        # s6
    lw   x23, 92(sp)        # s7
    lw   x24, 96(sp)        # s8
    lw   x25, 100(sp)       # s9
    lw   x26, 104(sp)       # s10
    lw   x27, 108(sp)       # s11
    lw   x28, 112(sp)       # t3
    lw   x29, 116(sp)       # t4
    lw   x30, 120(sp)       # t5
    lw   x31, 124(sp)       # t6
    
    lw   x2,   8(sp)        # sp（最後に復元）
    
    # 例外復帰
    mret                    # PC ← mepc, 実行再開
```

#### 軽量版トラップハンドラ（一時レジスタのみ保存）

```assembly
# メモリ節約版（a0-a7, t0-t6のみ保存）
lightweight_trap_handler:
    addi sp, sp, -64        # 16 regs × 4 bytes
    
    # Caller-savedレジスタのみ保存
    sw   a0,  0(sp)
    sw   a1,  4(sp)
    sw   a2,  8(sp)
    sw   a3, 12(sp)
    sw   a4, 16(sp)
    sw   a5, 20(sp)
    sw   a6, 24(sp)
    sw   a7, 28(sp)
    sw   t0, 32(sp)
    sw   t1, 36(sp)
    sw   t2, 40(sp)
    sw   t3, 44(sp)
    sw   t4, 48(sp)
    sw   t5, 52(sp)
    sw   t6, 56(sp)
    sw   ra, 60(sp)         # raも保存（関数呼び出し用）
    
    # 例外処理（例: システムコール）
    csrr a0, mcause
    jal  ra, process_exception  # C関数呼び出し可能
    
    # 復元
    lw   ra, 60(sp)
    lw   t6, 56(sp)
    lw   t5, 52(sp)
    lw   t4, 48(sp)
    lw   t3, 44(sp)
    lw   t2, 40(sp)
    lw   t1, 36(sp)
    lw   t0, 32(sp)
    lw   a7, 28(sp)
    lw   a6, 24(sp)
    lw   a5, 20(sp)
    lw   a4, 16(sp)
    lw   a3, 12(sp)
    lw   a2,  8(sp)
    lw   a1,  4(sp)
    lw   a0,  0(sp)
    
    addi sp, sp, 64
    mret
```

---

### 4.3 例外処理のベストプラクティス

#### ✅ 推奨される実装

1. **mtvecの初期化**:
   ```assembly
   _start:
       lui  t0, 0x1        # t0 = 0x0000_1000
       csrw mtvec, t0      # mtvecをトラップハンドラに設定
   ```

2. **スタックの十分な確保**:
   - 完全コンテキスト保存: 128バイト
   - 軽量版: 64バイト
   - ネストしたトラップ: さらに追加領域

3. **mepcの適切な更新**:
   - EBREAK: 通常は同じ命令を再実行（mepc不変）
   - Illegal instruction: 次命令にスキップ（mepc += 4）
   - ECALL: 次命令にスキップ（mepc += 4）

4. **レジスタ保存順序の一貫性**:
   - GDB互換: x1, x2, x3, ..., x31の順
   - スタックフレーム構造を明確に文書化

#### ❌ 避けるべきパターン

1. **コンテキスト不完全保存**:
   ```assembly
   # ❌ Bad: s0-s11を保存せず上書き
   trap_handler:
       add  s0, a0, zero   # s0破壊！（ユーザーコードの値消失）
   ```

2. **spの破壊**:
   ```assembly
   # ❌ Bad: spを保存せず変更
   trap_handler:
       addi sp, sp, -64
       # ... spの古い値を保存していない！
       mret                # 復帰後のspが不正
   ```

3. **MRETの忘れ**:
   ```assembly
   # ❌ Bad: jalrでリターン
   trap_handler:
       # ... 処理 ...
       jalr zero, ra, 0    # バグ！mepcにジャンプすべき
   ```

---

### 4.4 デバッグのヒント

#### 例外ループの検出

例外ハンドラ内で再び例外が発生すると無限ループになります。

**対策**:
```assembly
trap_handler:
    # グローバルフラグで再入検出
    lui  t0, 0x1
    lw   t1, 0xFF0(t0)      # in_trap_handler flag
    bne  t1, zero, nested_trap
    
    addi t1, zero, 1
    sw   t1, 0xFF0(t0)      # Set flag
    
    # ... 通常の例外処理 ...
    
    sw   zero, 0xFF0(t0)    # Clear flag
    mret
    
nested_trap:
    # ネストしたトラップ: LEDで警告して停止
    lui  t0, 0x4
    addi t1, t0, 0x7C
    addi t2, zero, 0xF
    sw   t2, 0(t1)
    j    nested_trap        # Hang
```

#### トレースログの活用

MCP serverのトレース機能で例外発生を確認:
```
Cycle, PC, Instruction, ...
895000, 0x00000048, 0x00000073, ECALL, ...  ← ECALL実行
900000, 0x00001000, 0xf8010113, ADDI, ...   ← trap_handlerエントリ
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
