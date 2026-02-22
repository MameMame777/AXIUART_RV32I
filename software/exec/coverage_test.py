#!/usr/bin/env python3
"""
coverage_test.py — RV32I 命令カバレッジ拡張テストスクリプト

computation_test.py でカバーできていない命令を重点的に検証する。
同じビルダーパターン (builder → run_test) を使用。

新規カバー命令:
  imm_arith   : SLTI, SLTIU, XORI, ORI, ANDI, SRAI
  reg_arith   : SUB, XOR, OR, SLT, SLTU, SRL, SRA
  mem_rw      : SW, LW, SB, LB, LBU, SH, LH, LHU  (8命令)
  branch_jalr : BEQ, BGE, BLTU, BGEU, JALR
  auipc_test  : AUIPC

computation_test.py と合わせると RV32I の約79% (37/47命令) をカバー。

使い方:
  python coverage_test.py --port COM3
  python coverage_test.py --port COM3 --test mem_rw --dump
  python coverage_test.py --port COM3 --test all
"""

import sys
import os
import argparse

_exec_dir = os.path.dirname(os.path.abspath(__file__))
_sw_dir   = os.path.dirname(_exec_dir)
sys.path.insert(0, _sw_dir)
sys.path.insert(0, os.path.join(_sw_dir, 'rv32i'))

from axiuart_driver import AXIUARTDriver, AXIUARTException
import axiuart_driver.registers as _reg
from rv32i.cpu import (
    halt_cpu, run_cpu, cpu_status, wait_for_ebreak,
    write_program, read_register,
    BRAM_BASE,
)
from encoder import RV32IInstructionEncoder

# computation_test.py の run_test を再利用
from computation_test import run_test

# BRAM 内スクラッチ領域 (mem_rw テスト用)
# BRAM = 0x80000000 - 0x80003FFF (16KB)
# 命令領域 = 0x80000000 - 0x800003FF
# スクラッチ = 0x80000400 - (examples の DATA_AREA_START 慣例に準拠)
SCRATCH_BASE = BRAM_BASE + 0x400  # 0x80000400


# ---------------------------------------------------------------------------
# 共通ヘルパー
# ---------------------------------------------------------------------------

def _load_imm32(enc, rd, value):
    """32-bit 即値を LUI+ADDI でレジスタにロードする命令ペアを生成。"""
    upper20 = (value >> 12) & 0xF_FFFF
    lower12 = value & 0xFFF
    if lower12 >= 2048:          # bit[11] = 1 → ADDI が符号拡張で減算になるため補正
        upper20 = (upper20 + 1) & 0xF_FFFF
        lower12 -= 4096
    return [enc.lui(rd, upper20), enc.addi(rd, rd, lower12)]


# ---------------------------------------------------------------------------
# テストプログラム定義
# ---------------------------------------------------------------------------

def build_imm_arith() -> tuple:
    """
    即値演算命令テスト: SLTI, SLTIU, XORI, ORI, ANDI, SRAI

    計算トレース (x10 = アキュムレータ):
      x10 = 0, x11 = 7
      SLTI  x12, x11, 10   → x12 = 1  (7 < 10 signed)
      x10 += 1 → 1
      SLTIU x12, x11, 100  → x12 = 1  (7 <u 100)
      x10 += 1 → 2
      XORI  x12, x11, 5    → x12 = 7 ^ 5 = 2
      x10 += 2 → 4
      ORI   x12, x11, 8    → x12 = 7 | 8 = 15
      x10 += 15 → 19
      ANDI  x12, x11, 3    → x12 = 7 & 3 = 3
      x10 += 3 → 22
      ADDI  x13, x0, -176  → x13 = -176 (0xFFFFFF50)
      SRAI  x12, x13, 4    → x12 = -176 >> 4 = -11 (算術右シフト)
      x10 += -11 → 11
      EBREAK

    期待値: x10 = 11
    """
    enc = RV32IInstructionEncoder()
    prog = [
        enc.addi(10, 0, 0),             # x10 = 0  (アキュムレータ)
        enc.addi(11, 0, 7),             # x11 = 7
        enc.slti(12, 11, 10),           # x12 = (7 < 10) = 1
        enc.add(10, 10, 12),            # x10 += 1 → 1
        enc.sltiu(12, 11, 100),         # x12 = (7 <u 100) = 1
        enc.add(10, 10, 12),            # x10 += 1 → 2
        enc.xori(12, 11, 5),            # x12 = 7 ^ 5 = 2
        enc.add(10, 10, 12),            # x10 += 2 → 4
        enc.ori(12, 11, 8),             # x12 = 7 | 8 = 15
        enc.add(10, 10, 12),            # x10 += 15 → 19
        enc.andi(12, 11, 3),            # x12 = 7 & 3 = 3
        enc.add(10, 10, 12),            # x10 += 3 → 22
        enc.addi(13, 0, -176),          # x13 = -176 (0xFFFFFF50)
        enc.srai(12, 13, 4),            # x12 = -176 >> 4 = -11 (算術)
        enc.add(10, 10, 12),            # x10 += -11 → 11
        enc.ebreak(),
    ]
    return prog, "a0 (x10)", 11, "SLTI+SLTIU+XORI+ORI+ANDI+SRAI"


def build_reg_arith() -> tuple:
    """
    レジスタ演算命令テスト: SUB, XOR, OR, SLT, SLTU, SRL, SRA

    計算トレース (x10 = アキュムレータ):
      x10 = 0, x11 = 20, x12 = 12
      SUB  x13, x11, x12  → x13 = 8
      x10 += 8 → 8
      XOR  x13, x11, x12  → x13 = 20^12 = 0x14^0x0C = 0x18 = 24
      x10 += 24 → 32
      OR   x13, x11, x12  → x13 = 20|12 = 0x14|0x0C = 0x1C = 28
      x10 += 28 → 60
      x14 = 5
      SLT  x13, x14, x12  → x13 = (5 < 12 signed) = 1
      x10 += 1 → 61
      SLTU x13, x14, x12  → x13 = (5 <u 12 unsigned) = 1
      x10 += 1 → 62
      x15 = 128
      SRL  x13, x15, x14  → x13 = 128 >> 5 = 4  (論理右シフト)
      x10 += 4 → 66
      x16 = -128 (0xFFFFFF80)
      SRA  x13, x16, x14  → x13 = -128 >> 5 = -4 (算術右シフト)
      x10 += -4 → 62
      EBREAK

    期待値: x10 = 62
    """
    enc = RV32IInstructionEncoder()
    prog = [
        enc.addi(10, 0, 0),             # x10 = 0  (アキュムレータ)
        enc.addi(11, 0, 20),            # x11 = 20
        enc.addi(12, 0, 12),            # x12 = 12
        enc.sub(13, 11, 12),            # x13 = 20 - 12 = 8
        enc.add(10, 10, 13),            # x10 += 8 → 8
        enc.xor(13, 11, 12),            # x13 = 20 ^ 12 = 24  (xor, アンダースコアなし)
        enc.add(10, 10, 13),            # x10 += 24 → 32
        enc.or_(13, 11, 12),            # x13 = 20 | 12 = 28  (or_, アンダースコアあり)
        enc.add(10, 10, 13),            # x10 += 28 → 60
        enc.addi(14, 0, 5),             # x14 = 5  (シフト量 兼 SLT用)
        enc.slt(13, 14, 12),            # x13 = (5 < 12 signed) = 1
        enc.add(10, 10, 13),            # x10 += 1 → 61
        enc.sltu(13, 14, 12),           # x13 = (5 <u 12 unsigned) = 1
        enc.add(10, 10, 13),            # x10 += 1 → 62
        enc.addi(15, 0, 128),           # x15 = 128
        enc.srl(13, 15, 14),            # x13 = 128 >> 5 = 4  (論理, x14=5)
        enc.add(10, 10, 13),            # x10 += 4 → 66
        enc.addi(16, 0, -128),          # x16 = -128 (0xFFFFFF80)
        enc.sra(13, 16, 14),            # x13 = -128 >> 5 = -4 (算術, x14=5)
        enc.add(10, 10, 13),            # x10 += -4 → 62
        enc.ebreak(),
    ]
    return prog, "a0 (x10)", 62, "SUB+XOR+OR+SLT+SLTU+SRL+SRA"


def build_mem_rw() -> tuple:
    """
    メモリ読み書き命令テスト: SW, LW, SB, LB, LBU, SH, LH, LHU

    スクラッチアドレス: SCRATCH_BASE (= BRAM_BASE + 0x400)
    x9 = SCRATCH_BASE, x10 = pass_countter

    5サブテスト:
      1. SW/LW   : 42 を書いて読み出し一致 → +1
      2. SB/LBU  : 165 (0xA5) を書いてゼロ拡張ロード一致 → +1
      3. SB/LB   : -91 を書いて符号拡張ロード一致 → +1
      4. SH/LHU  : 2047 を書いてゼロ拡張ロード一致 → +1
      5. SH/LH   : -100 を書いて符号拡張ロード一致 → +1

    期待値: x10 = 5 (全サブテスト PASS)

    BNE パターン: BNE x12, x11, +8 で "不一致ならADDIをスキップ"
    """
    enc = RV32IInstructionEncoder()
    prog = []

    # スクラッチアドレス x9 = SCRATCH_BASE (0x80000400)
    # LUI x9, 0x80000 → x9 = 0x80000000
    # ADDI x9, x9, 0x400 → x9 = 0x80000400  (0x400=1024, < 2048 なので補正不要)
    prog.append(enc.lui(9, 0x80000))            # x9 = 0x80000000
    prog.append(enc.addi(9, 9, 0x400))          # x9 = 0x80000400
    prog.append(enc.addi(10, 0, 0))             # x10 = 0 (pass_count)

    # --- サブテスト 1: SW + LW ---
    prog.append(enc.addi(11, 0, 42))            # x11 = 42
    prog.append(enc.sw(11, 0, 9))               # mem[x9+0] = 42  (SW: rs2, imm, rs1)
    prog.append(enc.lw(12, 9, 0))               # x12 = mem[x9+0]  (LW: rd, rs1, imm)
    prog.append(enc.bne(12, 11, 8))             # x12 != x11 → skip pass
    prog.append(enc.addi(10, 10, 1))            # PASS: x10 = 1

    # --- サブテスト 2: SB + LBU (ゼロ拡張) ---
    # 165 = 0xA5, bit7=1 → LBU でゼロ拡張 = 165, LB なら -91
    prog.append(enc.addi(11, 0, 165))           # x11 = 165 (0xA5)
    prog.append(enc.sb(11, 4, 9))               # mem[x9+4] = 0xA5  (SB: rs2, imm, rs1)
    prog.append(enc.lbu(12, 9, 4))              # x12 = 0x000000A5 = 165 (ゼロ拡張)
    prog.append(enc.bne(12, 11, 8))
    prog.append(enc.addi(10, 10, 1))            # PASS: x10 = 2

    # --- サブテスト 3: SB + LB (符号拡張) ---
    # x11 = -91 (0xFFFFFFA5). LSB = 0xA5 を格納 → LB で 0xFFFFFFA5 = -91
    prog.append(enc.addi(11, 0, -91))           # x11 = -91 (0xFFFFFFA5)
    prog.append(enc.sb(11, 8, 9))               # mem[x9+8] = 0xA5
    prog.append(enc.lb(12, 9, 8))               # x12 = sign_ext(0xA5) = -91
    prog.append(enc.bne(12, 11, 8))
    prog.append(enc.addi(10, 10, 1))            # PASS: x10 = 3

    # --- サブテスト 4: SH + LHU (ゼロ拡張) ---
    prog.append(enc.addi(11, 0, 2047))          # x11 = 2047 (0x7FF, 16-bit 正値最大付近)
    prog.append(enc.sh(11, 12, 9))              # mem[x9+12] = 0x07FF  (SH: rs2, imm, rs1)
    prog.append(enc.lhu(12, 9, 12))             # x12 = 0x000007FF = 2047 (ゼロ拡張)
    prog.append(enc.bne(12, 11, 8))
    prog.append(enc.addi(10, 10, 1))            # PASS: x10 = 4

    # --- サブテスト 5: SH + LH (符号拡張) ---
    prog.append(enc.addi(11, 0, -100))          # x11 = -100 (0xFFFFFF9C)
    prog.append(enc.sh(11, 16, 9))              # mem[x9+16] = 0xFF9C
    prog.append(enc.lh(12, 9, 16))              # x12 = sign_ext(0xFF9C) = -100
    prog.append(enc.bne(12, 11, 8))
    prog.append(enc.addi(10, 10, 1))            # PASS: x10 = 5

    prog.append(enc.ebreak())
    return prog, "a0 (x10)", 5, "SW/LW+SB/LBU+SB/LB+SH/LHU+SH/LH"


def build_branch_jalr() -> tuple:
    """
    分岐・ジャンプ命令テスト: BEQ, BGE, BLTU, BGEU, JALR

    x10 = pass_count (0 スタート)
    x11 = 5, x12 = 10

    各 "should be taken" 分岐: 成立 → +8 (ADDI スキップ不発) → x10 += 1
    不成立 (CPU バグ) → fall-through で ADDI x10, x0, -999 → 期待値不一致

    BEQ  x11 == x13 (5 == 5)  → TAKEN (+8, fail-ADDI スキップ) → x10 = 1
    BGE  x12 >= x11 (10 >= 5) → TAKEN (+8)                    → x10 = 2
    BLTU x11 <u x12 (5 <u 10) → TAKEN (+8)                    → x10 = 3
    BGEU x12 >=u x11 (10>=u5) → TAKEN (+8)                    → x10 = 4

    JALR: JAL x1, func で関数呼び出し
          func: ADDI x15, x0, 10 / JALR x0, x1, 0 (戻り)
          戻り後: ADD x10, x10, x15 → x10 = 4 + 10 = 14

    期待値: x10 = 14

    "fail-ADDI" パターン:
      beq_pc:   BXX rx, ry, +8    ; 成立→skip, 不成立→fall-through
      beq_pc+4: ADDI x10, x0, -999 ; [不成立パス] x10 に毒値をセット
      beq_pc+8: ADDI x10, x10, 1   ; [成立パス] x10 インクリメント
                                   ; 不成立パスはここも通るが -999+1=-998 で FAIL
    """
    enc = RV32IInstructionEncoder()
    prog = []

    prog.append(enc.addi(10, 0, 0))    # x10 = 0 (pass_count)
    prog.append(enc.addi(11, 0, 5))    # x11 = 5
    prog.append(enc.addi(12, 0, 10))   # x12 = 10
    prog.append(enc.addi(13, 0, 5))    # x13 = 5 (BEQ 比較用)

    # --- BEQ: x11 == x13 (5 == 5) TAKEN → +8 → skip fail-ADDI ---
    prog.append(enc.beq(11, 13, 8))    # BEQ +8 (skip fail-ADDI)
    prog.append(enc.addi(10, 0, -999)) # [fail] NOT taken パス
    prog.append(enc.addi(10, 10, 1))   # [pass] x10 = 1

    # --- BGE: x12 >= x11 (10 >= 5) TAKEN → +8 ---
    prog.append(enc.bge(12, 11, 8))    # BGE +8
    prog.append(enc.addi(10, 0, -999)) # [fail]
    prog.append(enc.addi(10, 10, 1))   # [pass] x10 = 2

    # --- BLTU: x11 <u x12 (5 <u 10) TAKEN → +8 ---
    prog.append(enc.bltu(11, 12, 8))   # BLTU +8
    prog.append(enc.addi(10, 0, -999)) # [fail]
    prog.append(enc.addi(10, 10, 1))   # [pass] x10 = 3

    # --- BGEU: x12 >=u x11 (10 >=u 5) TAKEN → +8 ---
    prog.append(enc.bgeu(12, 11, 8))   # BGEU +8
    prog.append(enc.addi(10, 0, -999)) # [fail]
    prog.append(enc.addi(10, 10, 1))   # [pass] x10 = 4

    # --- JALR: JAL x1, func_pc / func: ADDI x15,10 / JALR x0, x1, 0 ---
    jal_idx = len(prog)
    jal_pc  = jal_idx * 4
    prog.append(0)                      # JAL x1, func (後でパッチ)

    # JAL の戻り先: ADD x10, x10, x15 → x10 = 4 + 10 = 14
    prog.append(enc.add(10, 10, 15))   # x10 += x15

    ebreak_pc = len(prog) * 4
    prog.append(enc.ebreak())

    # --- 関数本体 ---
    func_pc = len(prog) * 4
    prog.append(enc.addi(15, 0, 10))   # x15 = 10 (戻り値)
    prog.append(enc.jalr(0, 1, 0))     # JALR x0, x1, 0 → x1 に戻る

    # JAL パッチ: JAL x1, (func_pc - jal_pc)
    prog[jal_idx] = enc.jal(1, func_pc - jal_pc)

    return prog, "a0 (x10)", 14, "BEQ+BGE+BLTU+BGEU+JALR"


def build_auipc() -> tuple:
    """
    AUIPC 命令テスト

    プログラム構造 (BRAM_BASE = 0x80000000 基準):
      [0] ADDI  x10, x0, 0              ; x10 = 0
      [1] AUIPC x11, 0                  ; x11 = PC + 0 = BRAM_BASE + 4 = 0x80000004
      [2] LUI   x12, 0x80000            ; x12 = 0x80000000
      [3] ADDI  x12, x12, 4             ; x12 = 0x80000004 (期待値)
      [4] BEQ   x11, x12, +8            ; 一致 → TAKEN (+8, fail-ADDI スキップ)
      [5] ADDI  x10, x0, -1             ; [fail] NOT taken パス
      [6] ADDI  x10, x10, 1             ; [pass] x10 = 1
      [7] EBREAK

    AUIPC imm=0 の場合: x11 = PC + (0 << 12) = PC (命令 [1] のアドレス)
    命令 [1] は BRAM_BASE + 1*4 = BRAM_BASE + 4 = 0x80000004

    期待値: x10 = 1
    """
    enc = RV32IInstructionEncoder()
    prog = [
        enc.addi(10, 0, 0),             # [0] x10 = 0
        enc.auipc(11, 0),               # [1] x11 = PC = BRAM_BASE + 4
        enc.lui(12, 0x80000),           # [2] x12 = 0x80000000
        enc.addi(12, 12, 4),            # [3] x12 = 0x80000004
        enc.beq(11, 12, 8),             # [4] BEQ +8: 一致 → skip fail-ADDI
        enc.addi(10, 0, -1),            # [5] [fail] NOT taken
        enc.addi(10, 10, 1),            # [6] [pass] x10 = 1
        enc.ebreak(),                   # [7]
    ]
    return prog, "a0 (x10)", 1, "AUIPC (PC相対アドレス)"


# テスト名 → ビルダのマッピング
TESTS = {
    "imm_arith":   build_imm_arith,
    "reg_arith":   build_reg_arith,
    "mem_rw":      build_mem_rw,
    "branch_jalr": build_branch_jalr,
    "auipc_test":  build_auipc,
}


# ---------------------------------------------------------------------------
# メイン
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="RV32I カバレッジ拡張テスト (FPGA 実機)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--port",  required=True,
                        help="シリアルポート (例: COM3)")
    parser.add_argument("--baud",  type=int, default=115200)
    parser.add_argument("--test",  default="all",
                        choices=list(TESTS.keys()) + ["all"],
                        help="実行するテスト (デフォルト: all)")
    parser.add_argument("--dump",  action="store_true",
                        help="BRAM 書き込み内容を表示する")
    args = parser.parse_args()

    test_names = list(TESTS.keys()) if args.test == "all" else [args.test]

    print("=" * 60)
    print("[COV]  RV32I カバレッジ拡張テスト")
    print("=" * 60)
    print(f"  ポート: {args.port}  ボーレート: {args.baud}")
    print(f"  テスト: {', '.join(test_names)}")
    print(f"\n  新規カバー命令:")
    print(f"    imm_arith   : SLTI, SLTIU, XORI, ORI, ANDI, SRAI")
    print(f"    reg_arith   : SUB, XOR, OR, SLT, SLTU, SRL, SRA")
    print(f"    mem_rw      : SW, LW, SB, LB, LBU, SH, LH, LHU")
    print(f"    branch_jalr : BEQ, BGE, BLTU, BGEU, JALR")
    print(f"    auipc_test  : AUIPC")

    try:
        with AXIUARTDriver(args.port, args.baud) as driver:

            version  = driver.read_reg32(_reg.REG_VERSION)
            revision = driver.read_reg32(_reg.REG_REVISION)
            print(f"\n[UART] 接続 OK  VERSION=0x{version:08X}  REVISION=0x{revision:08X}")

            results = []
            for name in test_names:
                passed = run_test(driver, name, TESTS[name], dump=args.dump)
                results.append((name, passed))

            # サマリ
            print(f"\n{'='*60}")
            print("[SUMMARY] テスト結果")
            print("=" * 60)
            passed_count = sum(1 for _, r in results if r)
            for name, result in results:
                symbol = "✓" if result else "✗"
                status = "PASS" if result else "FAIL"
                print(f"  {symbol} {name:<20s} [{status}]")
            print(f"{'─'*60}")
            print(f"  Total: {len(results)}, Passed: {passed_count}, "
                  f"Failed: {len(results)-passed_count}")

            if passed_count == len(results):
                print("\n[DONE] 全テスト PASS")
                print(f"[COV]  computation_test.py との合計カバレッジ: 約37/47命令 (~79%)")
                return 0
            else:
                print(f"\n[WARN] {len(results)-passed_count} テスト FAIL")
                return 1

    except AXIUARTException as exc:
        print(f"\n[ERROR] AXIUARTException: {exc}")
        return 1
    except Exception as exc:
        print(f"\n[ERROR] {type(exc).__name__}: {exc}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
