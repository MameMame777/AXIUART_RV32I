# Issue #60: ISA テスト無限ループ - mtvec ハードワイヤード問題

**Date:** 2026-02-07
**Status:** 根本原因特定済み、修正待ち (SpinalHDL 再生成が必要)
**Related:** Issue #50 (ISA テスト基盤構築)

---

## 症状

`vexriscv_isa_add_test` (rv32ui-p-add) が 200,000 サイクルでタイムアウト。
CPU は正常に命令を実行するが、tohost (0x80001000) への書き込みが発生しない。

---

## 根本原因

### CsrPlugin 設定

VexRiscv GenSmallOptimized の CsrPlugin は `mtvec` を定数として構成:

```scala
// docs/cpu/vexriscv_architecture.md L233-239
new CsrPlugin(
  CsrPluginConfig(
    catchIllegalAccess = false,        // 不正CSRアクセスで例外を出さない
    mtvecAccess = CsrAccess.NONE,      // mtvec は書込み不可 (定数)
    mtvecInit = 0x80000000l,           // トラップベクタ固定値
    mepcAccess = CsrAccess.READ_WRITE,
    mcauseAccess = CsrAccess.READ_ONLY,
    // ...
  )
)
```

### VexRiscv.v の該当箇所

```verilog
// rtl/cpu/VexRiscv.v L2906-2907
assign CsrPlugin_mtvec_mode = 2'b00;       // wire (定数) - Direct mode
assign CsrPlugin_mtvec_base = 30'h20000000; // wire (定数) → mtvec = 0x80000000
```

`mtvec_base` は `wire` (定数割当) であり、`reg` (レジスタ) ではない。
CSR 0x305 への CSRW 命令は静かに無視される。

### サポートCSR一覧

VexRiscv.v L3992-4022 で登録されているCSR:

| CSR名 | アドレス | 10進 | アクセス | 用途 |
| --- | --- | --- | --- | --- |
| mstatus | 0x300 | 768 | R/W | マシンステータス |
| mie | 0x304 | 772 | R/W | 割込みイネーブル |
| mepc | 0x341 | 833 | R/W | 例外PC |
| mcause | 0x342 | 834 | R/O | 例外原因 |
| mip | 0x344 | 836 | R/W | 割込みペンディング |
| mcycle | 0xB00 | 2816 | R/O | サイクルカウンタ |
| minstret | 0xB02 | 2818 | R/O | 命令カウンタ |
| mcycleh | 0xB80 | 2944 | R/O | サイクルカウンタ上位 |
| minstreth | 0xB82 | 2946 | R/O | 命令カウンタ上位 |
| cycle | 0xC00 | 3072 | R/O | サイクルカウンタ (U-mode) |
| cycleh | 0xC80 | 3200 | R/O | サイクルカウンタ上位 (U-mode) |
| **mtvec** | **0x305** | **773** | **未登録** | **トラップベクタ (書込み不可)** |
| **misa** | **0x301** | **769** | **未登録** | **ISA情報 (アクセス不可)** |

---

## 障害メカニズム

### riscv-tests の期待するフロー

```
_start (0x80000000):
    JAL x0, +0x4C          → reset_vector (0x8000004C) へジャンプ

trap_handler (0x80000004-0x8000004B):
    csrr t5, mcause         → トラップ原因を読出し
    beq t5, ECALL_U, write_tohost  → ECALL(U-mode) ならtohost書込み
    beq t5, ECALL_S, write_tohost  → ECALL(S-mode) ならtohost書込み
    beq t5, ECALL_M, write_tohost  → ECALL(M-mode) ならtohost書込み
    ...

write_tohost (0x80000040-0x80000048):
    AUIPC x30, 0x1          → x30 = PC + 0x1000 = 0x80001040
    SW x28, -64(x30)        → tohost (0x80001000) に x28 を書込み
    J write_tohost           → 無限ループ (ホスト側が読取る)

reset_vector (0x8000004C):
    csrr a0, mhartid        → ハードウェアスレッドID確認
    csrw mtvec, t0          → ★ trap_handler アドレスを mtvec に設定
    ... テスト初期化 ...
    J test_begin             → テストケース実行開始
```

### 実際のフロー (mtvec 書込み不可の場合)

```
1. CPU 起動: PC = 0x80000000
   → JAL x0, +0x4C → reset_vector (0x8000004C) へ

2. reset_vector:
   → csrw mtvec, t0  ★ 静かに無視 (mtvec = 0x80000000 のまま)
   → テストケース実行開始

3. テストケース: ADD 命令テスト → 全ケース PASS

4. テスト完了:
   → li x28, 1 (pass コード)
   → ECALL (トラップ発生)

5. ECALL トラップ → mtvec = 0x80000000 にジャンプ
   → 0x80000000 = JAL x0, +0x4C → reset_vector に再ジャンプ
   → ★ trap_handler (0x80000004) を完全にバイパス!

6. 無限ループ: 2→3→4→5→2→3→4→5→...
   → tohost に到達しない → タイムアウト
```

---

## hex ファイル検証

### rv32ui-p-add.hex の構造

| アドレス範囲 | 内容 | サイズ |
| --- | --- | --- |
| 0x80000000 | JAL x0, +0x4C (エントリポイント) | 4B |
| 0x80000004-0x8000004B | トラップハンドラ (write_tohost 含む) | 76B |
| 0x8000004C-0x800005C3 | reset_vector + テストコード | ~1.4KB |
| 0x80001000-0x80001047 | .tohost + .fromhost セクション (全ゼロ) | 72B |

### 命令デコード (エントリ付近)

| アドレス | 機械語 | 命令 | 説明 |
| --- | --- | --- | --- |
| 0x80000000 | 0x04C0006F | JAL x0, +0x4C | reset_vector へジャンプ |
| 0x80000004 | 0x34202F73 | CSRRS x30, mcause, x0 | トラップ原因読出し |
| 0x80000040 | 0x00001F17 | AUIPC x30, 0x1 | tohost アドレス計算 |
| 0x80000044 | 0xFDCF2023 | SW x28, -64(x30) | tohost に書込み |
| 0x8000004C | 0xF1402573 | CSRRS x10, mhartid, x0 | hartid 読出し (reset_vector 先頭) |
| 0x800005AC | 0x00000073 | ECALL | テスト完了トラップ |

---

## 修正方針

### 推奨: VexRiscv.v の再生成

GenSmallOptimized の CsrPlugin 設定を変更:

```scala
// Before:
mtvecAccess = CsrAccess.NONE,
// After:
mtvecAccess = CsrAccess.READ_WRITE,
```

再生成コマンド:

```powershell
.\tools\build_vexriscv.ps1 -Config GenSmallOptimized
copy vexriscv_reference\generated\VexRiscv.v rtl\cpu\VexRiscv.v
```

### 確認ポイント

再生成後の VexRiscv.v で以下を確認:

1. `CsrPlugin_mtvec_base` が `reg` (レジスタ) として宣言されていること
2. `execute_CsrPlugin_csr_773` (CSR 0x305) のデコードロジックが存在すること
3. mtvec への CSRW で `CsrPlugin_mtvec_base` が更新されること

### 影響範囲

| 項目 | 影響 |
| --- | --- |
| mtvec CSR | 読み書き可能になる (RISC-V M-mode 準拠) |
| 面積 (LUT) | 微増 (mtvec レジスタ 30bit + CSR mux、~30 LUT) |
| タイミング | 影響なし (CSR パスは既存 CsrPlugin 内) |
| Stage 1 テスト | 影響なし (mtvec を使用しない) |
| ISA テスト | PASS するようになる |

### 前提条件

SpinalHDL ビルド環境が必要:

- JDK 8/11/17
- sbt (Scala Build Tool) 1.5.0+
- VexRiscv ソース (`vexriscv_reference/source/`)

セットアップ: `.\tools\setup_vexriscv.ps1 -InstallIfMissing`
