# RV32I Software ABI (Application Binary Interface)

## 概要

このドキュメントは、RV32I CPUのソフトウェア開発者向けに、標準的なRISC-V呼び出し規約（Calling Convention）とレジスタ使用規則を説明します。ハードウェア実装の詳細については、[02_id_stage.md](02_id_stage.md)を参照してください。

**重要**: ハードウェア的には、x1-x31はすべて同等の汎用レジスタです（x0を除く）。しかし、ソフトウェアの相互運用性のため、標準的なRISC-V ABIに従った使用を**強く推奨**します。

---

## レジスタABI名と役割

### 完全なレジスタマップ

| Register | ABI Name | Description | Saver | Notes |
|----------|----------|-------------|-------|-------|
| **x0** | **zero** | 硬配線ゼロ | - | 常に0、書き込み不可 |
| **x1** | **ra** | リターンアドレス | Caller | 関数呼び出し時の戻り先 |
| **x2** | **sp** | スタックポインタ | Callee | スタックのトップを指す |
| **x3** | **gp** | グローバルポインタ | - | グローバル変数領域ベース（固定） |
| **x4** | **tp** | スレッドポインタ | - | スレッドローカルストレージ（未使用可） |
| **x5-x7** | **t0-t2** | 一時レジスタ 0-2 | Caller | 関数呼び出し前に保存不要 |
| **x8** | **s0/fp** | 保存レジスタ 0 / フレームポインタ | Callee | スタックフレームベース（オプション） |
| **x9** | **s1** | 保存レジスタ 1 | Callee | 関数跨ぎで値を保持 |
| **x10-x11** | **a0-a1** | 引数/戻り値 0-1 | Caller | 第1-2引数、関数戻り値 |
| **x12-x17** | **a2-a7** | 引数 2-7 | Caller | 第3-8引数 |
| **x18-x27** | **s2-s11** | 保存レジスタ 2-11 | Callee | 関数跨ぎで値を保持 |
| **x28-x31** | **t3-t6** | 一時レジスタ 3-6 | Caller | 関数呼び出し前に保存不要 |

### Caller-Saved vs Callee-Saved

**Caller-Savedレジスタ** (t0-t6, a0-a7, ra):
- **呼び出し側**が値を保存する責任を持つ
- 関数呼び出し後、値が**破壊される可能性**がある
- 使用例: 一時計算、関数引数

**Callee-Savedレジスタ** (s0-s11, sp):
- **呼び出された側**が値を保存・復元する責任を持つ
- 関数呼び出し前後で値が**保証される**
- 使用例: ループカウンタ、長期保持する変数

**Neither** (zero, gp, tp):
- **zero**: 常に0（不変）
- **gp**, **tp**: 通常は初期化後固定

---

## 関数呼び出し規約

### 引数と戻り値

#### 引数渡し

| 引数番号 | レジスタ | 備考 |
|---------|---------|------|
| 第1引数 | a0 (x10) | |
| 第2引数 | a1 (x11) | |
| 第3引数 | a2 (x12) | |
| 第4引数 | a3 (x13) | |
| 第5引数 | a4 (x14) | |
| 第6引数 | a5 (x15) | |
| 第7引数 | a6 (x16) | |
| 第8引数 | a7 (x17) | |
| 第9引数以降 | スタック | 下位アドレスから順に配置 |

**大きな構造体**: 参照渡し（ポインタをa0-a7で渡す）

#### 戻り値

| 戻り値サイズ | レジスタ | 備考 |
|-------------|---------|------|
| 32ビット以下 | a0 (x10) | int, short, char, ポインタなど |
| 33-64ビット | a0, a1 (x10, x11) | long long, double |
| 64ビット超 | メモリ経由 | ポインタをa0で返す |

---

## スタックフレームレイアウト

### 標準的なスタック構造

```
高位アドレス
    │
    ├─────────────────┐
    │ 引数8以降      │ ← Caller's stack frame
    │ (arg8, arg9...) │
    ├─────────────────┤ ← sp (関数入口時)
    │ ra (return addr)│ ← 保存されたリターンアドレス
    ├─────────────────┤
    │ s0/fp (old)     │ ← 保存されたフレームポインタ（使用時）
    ├─────────────────┤
    │ s1-s11 (used)   │ ← 使用したcallee-savedレジスタ
    ├─────────────────┤
    │ Local variables │ ← ローカル変数領域
    ├─────────────────┤
    │ Spill area      │ ← レジスタ退避領域
    ├─────────────────┤ ← sp (関数実行中)
    │ Outgoing args   │ ← 呼び出し先の引数（8個超の場合）
    └─────────────────┘
低位アドレス
```

**スタック成長方向**: 下方向（spデクリメント）

**アラインメント**: 16バイト境界（RISC-V ABI標準）
- このCPUは4バイトアクセスのみサポートのため、実質4バイトアラインメント

---

## 関数呼び出しの実例

### Example 1: 単純な関数呼び出し

```assembly
# int add(int a, int b) { return a + b; }
add:
    add  a0, a0, a1      # a0 = a0 + a1 (引数を加算)
    jalr zero, ra, 0     # return (ret疑似命令)

# main() での呼び出し
main:
    addi a0, zero, 5     # 第1引数: a0 = 5
    addi a1, zero, 10    # 第2引数: a1 = 10
    jal  ra, add         # add()を呼び出し、ra = PC+4
    # この時点で a0 = 15 (戻り値)
    add  t0, a0, zero    # t0 = 戻り値 (15)
```

**レジスタ状態遷移**:
```
main (call前):  a0=5, a1=10
add (実行中):   a0=5, a1=10 → a0=15
main (call後):  a0=15
```

---

### Example 2: スタックを使う関数

```assembly
# int calc(int x, int y) {
#     int temp1 = x * 2;    // s1に保存
#     int temp2 = y * 3;    // s2に保存
#     call_other_func();    // s1, s2を保持したまま他関数呼び出し
#     return temp1 + temp2;
# }

calc:
    # プロローグ: スタックフレーム確保
    addi sp, sp, -16        # スタックポインタを16バイト下げる
    sw   ra, 12(sp)         # リターンアドレスを保存
    sw   s1, 8(sp)          # s1を保存（callee-saved）
    sw   s2, 4(sp)          # s2を保存（callee-saved）
    
    # 本体処理
    slli s1, a0, 1          # s1 = x * 2
    add  t0, a1, a1         # t0 = y * 2
    add  s2, t0, a1         # s2 = y * 3
    
    # 他の関数を呼び出し（s1, s2は保持される）
    jal  ra, other_func     # other_func()呼び出し
    
    # 戻り値計算
    add  a0, s1, s2         # a0 = temp1 + temp2
    
    # エピローグ: レジスタ復元とリターン
    lw   s2, 4(sp)          # s2を復元
    lw   s1, 8(sp)          # s1を復元
    lw   ra, 12(sp)         # raを復元
    addi sp, sp, 16         # スタックポインタを戻す
    jalr zero, ra, 0        # return
```

**スタック状態** (calc内):
```
sp+16: ─┬─────────────
       │ (Caller's frame)
sp+12: ├─────────────
       │ ra (saved)   ← リターンアドレス
sp+8:  ├─────────────
       │ s1 (saved)   ← 0x... (x*2の結果)
sp+4:  ├─────────────
       │ s2 (saved)   ← 0x... (y*3の結果)
sp:    └─────────────
```

---

### Example 3: 引数が8個を超える場合

```assembly
# int sum9(int a1, int a2, ..., int a9) { ... }
# 第9引数はスタック経由

# Caller側:
main:
    # a0-a7に第1-8引数をセット
    addi a0, zero, 1
    addi a1, zero, 2
    addi a2, zero, 3
    addi a3, zero, 4
    addi a4, zero, 5
    addi a5, zero, 6
    addi a6, zero, 7
    addi a7, zero, 8
    
    # 第9引数をスタックに配置
    addi sp, sp, -16        # 16バイトアラインメント
    addi t0, zero, 9        # t0 = 9
    sw   t0, 0(sp)          # スタックに第9引数を格納
    
    jal  ra, sum9           # 関数呼び出し
    
    addi sp, sp, 16         # スタックをクリーンアップ

# Callee側:
sum9:
    # a0-a7から第1-8引数を取得
    add  t1, a0, a1         # t1 = a1 + a2
    add  t1, t1, a2         # ...
    add  t1, t1, a3
    add  t1, t1, a4
    add  t1, t1, a5
    add  t1, t1, a6
    add  t1, t1, a7
    
    # 第9引数をスタックから読み込み
    lw   t2, 0(sp)          # t2 = 第9引数（スタック上）
    add  a0, t1, t2         # a0 = 合計
    
    jalr zero, ra, 0        # return
```

---

## 特殊レジスタの詳細

### x0 (zero) - 硬配線ゼロ

**ハードウェア実装**:
```systemverilog
// rtl/cpu/rv32i_id.sv
assign rs1_data_raw = (rs1_addr == 5'd0) ? 32'h0000_0000 : regfile[rs1_addr];
assign rs2_data_raw = (rs2_addr == 5'd0) ? 32'h0000_0000 : regfile[rs2_addr];

always_ff @(posedge clk) begin
    if (wb_reg_write && wb_rd_addr != 5'd0) begin  // x0への書き込みは無視
        regfile[wb_rd_addr] <= wb_result;
    end
end
```

**使用例**:
```assembly
# 定数0が必要な場合
add  t0, zero, zero    # t0 = 0
addi t1, zero, 100     # t1 = 100 (即値をロード)

# NOP命令（No Operation）
addi zero, zero, 0     # 何もしない（x0に0を書き込む）
```

---

### x1 (ra) - リターンアドレス

**使用パターン**:
```assembly
# パターン1: jal命令での自動設定
jal  ra, func          # ra = PC+4, PC = func

# パターン2: 明示的なリンクレジスタ指定
jalr ra, t0, 0         # ra = PC+4, PC = t0+0

# パターン3: リターン（ret疑似命令の実体）
jalr zero, ra, 0       # PC = ra+0（戻り先にジャンプ）
```

**Leaf関数の最適化**:
```assembly
# Leaf関数（他の関数を呼ばない）はraを保存不要
simple_add:
    add  a0, a0, a1
    jalr zero, ra, 0    # raは破壊されていないので直接return

# Non-Leaf関数はraを保存必須
complex_calc:
    addi sp, sp, -4
    sw   ra, 0(sp)      # raを保存
    jal  ra, other      # raが上書きされる
    lw   ra, 0(sp)      # raを復元
    addi sp, sp, 4
    jalr zero, ra, 0
```

---

### x2 (sp) - スタックポインタ

**初期化**:
```assembly
# ブートコード（0x0000_0000番地から実行）
_start:
    # スタックポインタを初期化（RAMの上端に設定）
    lui  sp, 0x2        # sp = 0x0000_2000
    # 注: RAM範囲は0x0000-0x1FFFなので、sp=0x2000（範囲外）からデクリメント開始
    
    jal  ra, main       # main()へジャンプ
    
    # main()から戻ったらループ（CPUを停止）
_end:
    j    _end           # 無限ループ
```

**スタック操作の注意点**:
- **アラインメント**: 4バイト境界を推奨（このCPUは非整列アクセス不可）
- **オーバーフロー検出**: ハードウェア保護なし（ソフトウェアで管理）
- **成長方向**: 下方向（addi sp, sp, -N で確保、addi sp, sp, +N で解放）

```assembly
# ✅ 正しいスタック操作
addi sp, sp, -16    # 16バイト確保（4命令分）
sw   t0, 12(sp)
sw   t1, 8(sp)
sw   t2, 4(sp)
sw   t3, 0(sp)
# ... 処理 ...
addi sp, sp, 16     # 16バイト解放

# ❌ 間違ったスタック操作（アラインメント不整合）
addi sp, sp, -3     # 3バイト確保（非推奨！）
sw   t0, 0(sp)      # ミスアラインドアクセス → 例外発生
```

---

### x3 (gp) - グローバルポインタ

**使用例** (大規模プログラム向け):
```assembly
# グローバル変数領域の基準アドレス
# 例: グローバル変数領域を0x0000_1000-0x0000_1FFFに配置

_start:
    lui  gp, 0x1        # gp = 0x0000_1000 (グローバル領域ベース)
    addi gp, gp, 0x800  # gp = 0x0000_1800 (中央値、±2KBアクセス可能)

# グローバル変数へのアクセス（即値オフセットで効率的）
# int global_counter = 0;  // 0x0000_1800番地に配置
main:
    lw   t0, 0(gp)          # t0 = global_counter
    addi t0, t0, 1          # t0++
    sw   t0, 0(gp)          # global_counter = t0
```

**小規模プログラム**: gpは未使用でOK（汎用レジスタとして使用可能）

---

### x8 (s0/fp) - 保存レジスタ / フレームポインタ

**フレームポインタとしての使用**:
```assembly
# ローカル変数が多い関数で使用
complex_func:
    addi sp, sp, -64        # 64バイトのスタックフレーム
    sw   ra, 60(sp)
    sw   s0, 56(sp)         # 古いfpを保存
    
    addi s0, sp, 64         # s0/fp = 古いsp値（フレームベース）
    
    # ローカル変数へのアクセス（fpからの固定オフセット）
    sw   a0, -4(s0)         # local_var1 = a0
    sw   a1, -8(s0)         # local_var2 = a1
    # sp が変化しても s0 からの相対位置は不変
    
    # ... 処理（sp が変動する可能性あり）...
    
    lw   s0, 56(sp)         # fpを復元
    lw   ra, 60(sp)
    addi sp, sp, 64
    jalr zero, ra, 0
```

**単純な保存レジスタとしての使用**:
```assembly
# フレームポインタが不要な場合、通常のs0として使用
simple_func:
    addi sp, sp, -8
    sw   ra, 4(sp)
    sw   s0, 0(sp)          # s0を普通のcallee-savedとして使用
    
    add  s0, a0, a1         # s0に計算結果を保持
    jal  ra, other          # 他関数呼び出し後もs0は保持
    add  a0, s0, zero       # s0から戻り値を設定
    
    lw   s0, 0(sp)
    lw   ra, 4(sp)
    addi sp, sp, 8
    jalr zero, ra, 0
```

---

## メモリレイアウトとの関係

### アドレス空間マップ（再掲）

| Address Range | Size | Type | Usage | ABI関連 |
|--------------|------|------|-------|---------|
| **0x0000_0000 - 0x0000_1FFF** | 8KB | RAM | コード+データ+スタック | すべてこの領域内 |
| 0x0000_2000 - 0x0000_3FFF | - | 未使用 | - | - |
| 0x0000_4000 - 0x0000_4FFF | 4KB | MMIO | ペリフェラル | gpで直接アクセス可 |
| **0x0000_407C** | 4B | MMIO | LED制御 | 明示的アドレス指定 |
| 0x0000_5000 - 0xFFFF_FFFF | - | 未定義 | アクセス禁止 | 例外発生 |

### 典型的なメモリ配置例

```
0x0000_0000: ┌─────────────────┐
             │ .text (Code)    │ ← _start, main, 関数群
             │                 │
0x0000_0800: ├─────────────────┤
             │ .rodata (const) │ ← 文字列定数、定数テーブル
0x0000_0C00: ├─────────────────┤
             │ .data (globals) │ ← 初期化済みグローバル変数
             │                 │    (gpで効率的にアクセス)
0x0000_1000: ├─────────────────┤
             │ .bss (uninit)   │ ← 未初期化グローバル変数
0x0000_1800: ├─────────────────┤
             │ Heap (future)   │ ← 動的メモリ（未実装）
0x0000_1C00: ├─────────────────┤
             │ Stack (grows ↓) │ ← sp が指す領域
             │                 │    (初期値 sp=0x2000)
0x0000_2000: └─────────────────┘
             (RAM範囲外)
```

**スタックとヒープの衝突回避**: 
- 現在のシステムではヒープ未実装
- スタック最大深度: ~1KB（256命令分のネスト）
- 実装時は衝突検出機構が必要

---

## ABI準拠のベストプラクティス

### ✅ 推奨される使い方

1. **関数引数は a0-a7 を使う**:
   ```assembly
   # ✅ Good
   add_three_numbers:
       add  t0, a0, a1
       add  a0, t0, a2
       jalr zero, ra, 0
   ```

2. **一時計算は t0-t6 を使う**:
   ```assembly
   # ✅ Good
   complex_calc:
       add  t0, a0, a1      # 一時結果をt0に
       mul  t1, t0, a2      # さらにt1に
       add  a0, t1, zero    # 最終結果をa0に
       jalr zero, ra, 0
   ```

3. **関数跨ぎで保持する値は s0-s11 を使う**:
   ```assembly
   # ✅ Good
   loop_calc:
       addi sp, sp, -8
       sw   s0, 0(sp)
       sw   s1, 4(sp)
       
       add  s0, zero, zero  # s0 = counter (保持)
       add  s1, a0, zero    # s1 = sum (保持)
   loop:
       jal  ra, get_next    # a0-a7, t0-t6は破壊される可能性
       add  s1, s1, a0      # s0, s1は保持されている
       addi s0, s0, 1
       # ... loop条件チェック ...
       
       lw   s1, 4(sp)
       lw   s0, 0(sp)
       addi sp, sp, 8
       jalr zero, ra, 0
   ```

### ❌ 避けるべきパターン

1. **ABI名を無視した使用**:
   ```assembly
   # ❌ Bad: a0を引数以外に使用
   my_func:
       add  a0, zero, zero  # a0を破壊（引数が消える）
       # ... a0の元の値が必要なのに...
       add  t0, a0, a1      # バグ！
   ```

2. **Callee-savedレジスタを保存せず使用**:
   ```assembly
   # ❌ Bad: s0を保存せず破壊
   my_func:
       add  s0, a0, a1      # s0を破壊（呼び出し元の値が消える）
       jalr zero, ra, 0     # s0を復元していない！
   ```

3. **raを保存せずnon-leaf関数を作成**:
   ```assembly
   # ❌ Bad: raを保存せず他関数呼び出し
   my_func:
       jal  ra, other       # raが上書きされる
       jalr zero, ra, 0     # バグ！ other()の次の命令に飛ぶ
   ```

---

## まとめ

### レジスタ選択のクイックリファレンス

| 用途 | レジスタ | 保存責任 | 使用例 |
|-----|---------|---------|--------|
| **関数引数** | a0-a7 | Caller | 引数渡し、戻り値受け取り |
| **戻り値** | a0 (a1) | Caller | 関数の結果を返す |
| **一時計算** | t0-t6 | Caller | ループ内計算、条件判定 |
| **長期保持** | s0-s11 | Callee | ループカウンタ、累積値 |
| **リターンアドレス** | ra | Caller | jal/jalr自動設定、復元必要 |
| **スタックポインタ** | sp | Callee | 初期化後、関数内で操作 |
| **定数ゼロ** | zero | - | 即値0が必要な場合 |

### 関数設計チェックリスト

- [ ] **引数はa0-a7で受け取っているか？**
- [ ] **戻り値はa0（必要ならa1も）で返しているか？**
- [ ] **一時計算にt0-t6を使っているか？**
- [ ] **s0-s11を使う場合、プロローグで保存・エピローグで復元しているか？**
- [ ] **他関数を呼ぶ場合（non-leaf）、raを保存・復元しているか？**
- [ ] **スタックポインタは16バイト（または4バイト）境界に保たれているか？**
- [ ] **スタックフレームのサイズは関数入口と出口で一致しているか？**

### 参考資料

- **RISC-V Calling Convention**: [RISC-V ELF psABI Specification](https://github.com/riscv-non-isa/riscv-elf-psabi-doc)
- **ハードウェア実装**: [02_id_stage.md](02_id_stage.md) - レジスタファイルの物理実装
- **メモリマップ**: [00_overview.md](00_overview.md) - アドレス空間の詳細
- **例外処理との関連**: [07_csr_module.md](07_csr_module.md) - CSR操作とトラップハンドラ

---

**最終更新**: 2026-01-11  
**バージョン**: 1.0.0
