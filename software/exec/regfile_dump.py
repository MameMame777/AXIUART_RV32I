#!/usr/bin/env python3
"""
regfile_dump.py — RV32I レジスタファイル ダンプ

CPU halt 後に x0–x31 の全レジスタ値を読み出してテーブル表示する。
EBREAK 停止後の計算結果確認や、バグ調査の事後解析に使用する。

使い方:
  python regfile_dump.py --port COM3
  python regfile_dump.py --port COM3 --no-halt   # 既に halt 済みの場合
  python regfile_dump.py --port COM3 --perf       # パフォーマンスカウンタも表示
"""

import sys
import os
import argparse

_exec_dir = os.path.dirname(os.path.abspath(__file__))
_sw_dir   = os.path.dirname(_exec_dir)
sys.path.insert(0, _sw_dir)

from axiuart_driver import AXIUARTDriver, AXIUARTException
import axiuart_driver.registers as _reg
from rv32i.cpu import halt_cpu, cpu_status, read_all_registers, format_regfile


def read_perf_counters(driver) -> dict:
    """パフォーマンスカウンタを全て読み出す。"""
    cycles  = driver.read_reg32(_reg.REG_PERF_CYCLE_COUNT)
    insns   = driver.read_reg32(_reg.REG_PERF_INSN_COUNT)
    stalls  = driver.read_reg32(_reg.REG_PERF_STALL_COUNT)
    flushes = driver.read_reg32(_reg.REG_PERF_FLUSH_COUNT)
    return {
        "cycles":  cycles,
        "insns":   insns,
        "stalls":  stalls,
        "flushes": flushes,
        "ipc":     insns / cycles if cycles > 0 else 0.0,
        "stall_rate":  stalls  / cycles if cycles > 0 else 0.0,
        "flush_rate":  flushes / cycles if cycles > 0 else 0.0,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="RV32I レジスタファイル ダンプ",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--port",     required=True,
                        help="シリアルポート (例: COM3)")
    parser.add_argument("--baud",     type=int, default=115200)
    parser.add_argument("--no-halt",  action="store_true",
                        help="CPU halt をスキップ (既に halt 済みの場合)")
    parser.add_argument("--perf",     action="store_true",
                        help="パフォーマンスカウンタも表示する")
    args = parser.parse_args()

    print("=" * 60)
    print("[REG]  RV32I レジスタファイル ダンプ")
    print("=" * 60)

    try:
        with AXIUARTDriver(args.port, args.baud) as driver:

            # 接続確認
            version  = driver.read_reg32(_reg.REG_VERSION)
            revision = driver.read_reg32(_reg.REG_REVISION)
            print(f"[UART] 接続 OK  VERSION=0x{version:08X}  REVISION=0x{revision:08X}")

            # CPU 停止
            if not args.no_halt:
                print("[CPU]  halt 要求中...")
                if not halt_cpu(driver):
                    print("[CPU]  ERROR: タイムアウト - CPU が halt しませんでした")
                    return 1

            st = cpu_status(driver)
            print(f"[CPU]  halt 完了  halted={st['halted']}  break={st['break']}")
            if st['break']:
                print("[CPU]  (EBREAK 停止)")

            # パフォーマンスカウンタ (--perf またはデフォルト表示)
            if args.perf:
                perf = read_perf_counters(driver)
                print("\n[PERF] パフォーマンスカウンタ:")
                print(f"         cycles  = {perf['cycles']:>12,}")
                print(f"         insns   = {perf['insns']:>12,}")
                print(f"         stalls  = {perf['stalls']:>12,}")
                print(f"         flushes = {perf['flushes']:>12,}")
                if perf['cycles'] > 0:
                    print(f"         IPC        = {perf['ipc']:.4f}")
                    print(f"         stall rate = {perf['stall_rate']*100:.2f}%")
                    print(f"         flush rate = {perf['flush_rate']*100:.2f}%")

            # レジスタファイル読み出し
            print("\n[REG]  x0–x31 読み出し中...")
            values = read_all_registers(driver)

            print("\n[REG]  レジスタファイル:")
            print(format_regfile(values))

    except AXIUARTException as exc:
        print(f"\n[ERROR] AXIUARTException: {exc}")
        return 1
    except Exception as exc:
        print(f"\n[ERROR] {type(exc).__name__}: {exc}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
