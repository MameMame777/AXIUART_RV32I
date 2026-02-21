#!/usr/bin/env python3
"""
computation_test.py — RV32I 計算結果検証スクリプト

決定論的なRV32Iプログラムを FPGA 実機で実行し、
x10 (a0) レジスタの計算結果を期待値と比較して PASS/FAIL を判定する。

CPU が EBREAK に到達したら停止し、デバッグ IF 経由でレジスタを読み出す。
ループ・分岐・加算・シフトを含む命令セット全体のサニティチェックに使える。

テスト一覧:
  sum100      1 + 2 + ... + 100 = 5050 (ループ + 加算)
  fibonacci   fib(10) = 55             (ループ + 加算 + コピー)
  bitcount    popcount(0xA5A5A5A5)= 16 (ループ + シフト + AND + 加算)
  all         上記全テストを連続実行

使い方:
  python computation_test.py --port COM3
  python computation_test.py --port COM3 --test sum100
  python computation_test.py --port COM3 --test all --dump
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
    write_program, verify_program, read_register,
    BRAM_BASE,
)
from encoder import RV32IInstructionEncoder


# ---------------------------------------------------------------------------
# テストプログラム定義
# ---------------------------------------------------------------------------

def build_sum100() -> tuple:
    """
    1 + 2 + ... + 100 = 5050 を計算するプログラム。

    レジスタ:
      x10 (a0) = result (初期値 0, 結果 5050 = 0x13BA)
      x11 (a1) = i      (1 から 101 まで)
      x12 (a2) = limit  (= 101, ループ終了判定)

    命令 (6命令):
      ADDI x10, x0, 0    ; result = 0
      ADDI x11, x0, 1    ; i = 1
      ADDI x12, x0, 101  ; limit = 101
      ADD  x10, x10, x11 ; result += i       ← LOOP
      ADDI x11, x11, 1   ; i++
      BNE  x11, x12, -8  ; if i != 101 goto LOOP
      EBREAK
    """
    enc = RV32IInstructionEncoder()
    prog = [
        enc.addi(10, 0, 0),            # x10 = 0  (result)
        enc.addi(11, 0, 1),            # x11 = 1  (i)
        enc.addi(12, 0, 101),          # x12 = 101 (limit)
    ]
    loop_pc = len(prog) * 4            # = 0x0C
    prog.append(enc.add(10, 10, 11))   # result += i
    prog.append(enc.addi(11, 11, 1))   # i++
    bne_pc = len(prog) * 4
    prog.append(enc.bne(11, 12, loop_pc - bne_pc))  # i != 101 → loop
    prog.append(enc.ebreak())
    return prog, "a0 (x10)", 5050, "sum(1..100)"


def build_fibonacci() -> tuple:
    """
    fib(10) = 55 を計算するプログラム。

    フィボナッチ数列: 0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55
    fib(10) は 10 番目 (0-indexed) = 55

    レジスタ:
      x10 (a0) = a     (初期値 0, 最終結果)
      x11 (a1) = b     (初期値 1)
      x12 (a2) = n     (カウンタ: 10 から 0 まで)
      x13 (a3) = c     (一時変数: a + b)

    命令 (8命令):
      ADDI x10, x0, 0   ; a = 0
      ADDI x11, x0, 1   ; b = 1
      ADDI x12, x0, 10  ; n = 10
      ADD  x13, x10, x11 ; c = a + b     ← LOOP
      ADDI x10, x11, 0   ; a = b
      ADDI x11, x13, 0   ; b = c
      ADDI x12, x12, -1  ; n--
      BNE  x12, x0, -16  ; n != 0 → LOOP
      EBREAK
    """
    enc = RV32IInstructionEncoder()
    prog = [
        enc.addi(10, 0, 0),            # a = 0
        enc.addi(11, 0, 1),            # b = 1
        enc.addi(12, 0, 10),           # n = 10
    ]
    loop_pc = len(prog) * 4            # = 0x0C
    prog.append(enc.add(13, 10, 11))   # c = a + b
    prog.append(enc.addi(10, 11, 0))   # a = b
    prog.append(enc.addi(11, 13, 0))   # b = c
    prog.append(enc.addi(12, 12, -1))  # n--
    bne_pc = len(prog) * 4
    prog.append(enc.bne(12, 0, loop_pc - bne_pc))  # n != 0 → loop
    prog.append(enc.ebreak())
    return prog, "a0 (x10)", 55, "fibonacci(10)"


def build_bitcount() -> tuple:
    """
    popcount(0xA5A5_A5A5) = 16 を計算するプログラム。

    0xA5A5A5A5 = 1010_0101_1010_0101_1010_0101_1010_0101
    → set bits = 16

    レジスタ:
      x10 (a0) = count   (初期値 0, 結果 16)
      x11 (a1) = val     (定数 0xA5A5A5A5, ループで右シフト)
      x12 (a2) = loop_n  (カウンタ 32 → 0)
      x13 (a3) = 1       (AND マスク)

    命令 (11命令):
      LUI  x11, 0xA5A5B  ; x11 上位 ← 0xA5A5A5A5 の上位 (LUI+ADDI で32bit即値)
      ADDI x11, x11, ... ; x11 下位補正
      ADDI x10, x0, 0    ; count = 0
      ADDI x12, x0, 32   ; loop_n = 32
      ADDI x13, x0, 1    ; mask = 1
      AND  x14, x11, x13 ; bit = val & 1  ← LOOP
      ADD  x10, x10, x14 ; count += bit
      SRLI x11, x11, 1   ; val >>= 1
      ADDI x12, x12, -1  ; loop_n--
      BNE  x12, x0, -16  ; loop_n != 0 → LOOP
      EBREAK
    """
    enc = RV32IInstructionEncoder()

    # 0xA5A5A5A5 = LUI(0xA5A5B) + ADDI(-1371)
    # 0xA5A5A5A5 upper20 = 0xA5A5A (bit11=1 なので upper +1 → 0xA5A5B, lower = 0xA5A5 - 0x1000 = -1371)
    val = 0xA5A5_A5A5
    upper20 = (val >> 12) & 0xFFFFF
    lower12 = val & 0xFFF
    if lower12 >= 2048:
        upper20 = (upper20 + 1) & 0xFFFFF
        lower12 -= 4096

    prog = [
        enc.lui(11, upper20),          # x11 = upper
        enc.addi(11, 11, lower12),     # x11 = 0xA5A5A5A5
        enc.addi(10, 0, 0),            # count = 0
        enc.addi(12, 0, 32),           # loop_n = 32
        enc.addi(13, 0, 1),            # mask = 1
    ]
    loop_pc = len(prog) * 4            # = 0x14
    prog.append(enc.and_(14, 11, 13))  # bit = val & 1
    prog.append(enc.add(10, 10, 14))   # count += bit
    prog.append(enc.srli(11, 11, 1))   # val >>= 1
    prog.append(enc.addi(12, 12, -1))  # loop_n--
    bne_pc = len(prog) * 4
    prog.append(enc.bne(12, 0, loop_pc - bne_pc))  # loop_n != 0 → loop
    prog.append(enc.ebreak())
    return prog, "a0 (x10)", 16, "popcount(0xA5A5A5A5)"


# テスト名 → ビルダのマッピング
TESTS = {
    "sum100":    build_sum100,
    "fibonacci": build_fibonacci,
    "bitcount":  build_bitcount,
}


# ---------------------------------------------------------------------------
# テスト実行
# ---------------------------------------------------------------------------

def run_test(driver, name: str, builder, dump: bool = False) -> bool:
    """
    1 テストを実行して PASS/FAIL を返す。

    Returns:
        True: PASS (期待値と一致)
        False: FAIL
    """
    prog, result_reg, expected, description = builder()

    reg_idx = int(result_reg.split("x")[1].rstrip(")"))  # "a0 (x10)" → 10

    print(f"\n{'─'*60}")
    print(f"[TEST] {name}: {description}")
    print(f"       期待値 = {expected} (0x{expected:08X})")
    print(f"       結果レジスタ: {result_reg}")

    if dump:
        print(f"       命令数: {len(prog)} ({len(prog)*4} bytes)")

    # CPU halt
    if not halt_cpu(driver):
        print("  [FAIL] CPU halt タイムアウト")
        return False

    # プログラム書き込み
    write_program(driver, prog)

    if dump:
        from rv32i.cpu import read_word
        print("  [DUMP] BRAM 書き込み済みプログラム (先頭8命令):")
        for i in range(min(8, len(prog))):
            addr = BRAM_BASE + i * 4
            val  = read_word(driver, addr)
            print(f"    0x{addr:08X}: 0x{val:08X}")

    # CPU 実行 → EBREAK 待ち
    run_cpu(driver)
    print("  [CPU]  実行中... (EBREAK 待ち)")

    if not wait_for_ebreak(driver, timeout=5.0):
        halt_cpu(driver)
        print("  [FAIL] EBREAK タイムアウト (5秒以内に完了しませんでした)")
        return False

    st = cpu_status(driver)
    print(f"  [CPU]  EBREAK 検出  STATUS=0x{st['raw']:08X}")

    # 結果読み出し
    actual = read_register(driver, reg_idx)
    print(f"  [RESULT] {result_reg} = {actual} (0x{actual:08X})")

    if actual == expected:
        print(f"  [PASS] ✓ {actual} == {expected}")
        return True
    else:
        print(f"  [FAIL] ✗ {actual} != {expected}")
        return False


def main() -> int:
    parser = argparse.ArgumentParser(
        description="RV32I 計算結果検証 (FPGA 実機)",
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
    print("[COMP] RV32I 計算結果検証")
    print("=" * 60)
    print(f"  ポート: {args.port}  ボーレート: {args.baud}")
    print(f"  テスト: {', '.join(test_names)}")

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
            print(f"  Total: {len(results)}, Passed: {passed_count}, Failed: {len(results)-passed_count}")

            if passed_count == len(results):
                print("\n[DONE] 全テスト PASS")
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
