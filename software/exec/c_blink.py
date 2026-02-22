#!/usr/bin/env python3
"""
c_blink.py — C でビルドした LED ナイトライダーを FPGA 実機で実行

raw binary (.bin) を BRAM に書き込み、CPU を起動して LED パターンを確認する。
C コンパイラツールチェーン (xPack riscv-none-elf-gcc) のエンドツーエンド検証スクリプト。

使い方:
  python c_blink.py --port COM3
  python c_blink.py --port COM3 --bin ../rv32i/c/led_blink.bin --verify
  python c_blink.py --port COM3 --build          # ビルドしてから実行
"""

import sys
import os
import time
import subprocess
import argparse

_exec_dir = os.path.dirname(os.path.abspath(__file__))
_sw_dir   = os.path.dirname(_exec_dir)
sys.path.insert(0, _sw_dir)

from axiuart_driver import AXIUARTDriver, AXIUARTException
import axiuart_driver.registers as _reg
from rv32i.cpu import (
    halt_cpu, run_cpu, cpu_status,
    write_program, verify_program,
    BRAM_BASE,
)
from rv32i.bin_loader import load_bin, bin_size_check

# デフォルトパス
_C_DIR      = os.path.join(_sw_dir, "rv32i", "c")
_DEFAULT_BIN = os.path.join(_C_DIR, "led_blink.bin")
_BUILD_SCRIPT = os.path.join(
    os.path.dirname(_sw_dir), "scripts", "build_c.ps1"
)

BRAM_SIZE = 8192  # 8KB


def build(target: str = "led_blink") -> bool:
    """PowerShell ビルドスクリプトを呼び出してコンパイル・変換を行う。"""
    print(f"[BUILD] {target} をビルド中...")
    result = subprocess.run(
        ["powershell", "-ExecutionPolicy", "Bypass",
         "-File", _BUILD_SCRIPT, target],
        capture_output=False,
    )
    if result.returncode != 0:
        print(f"[BUILD] FAILED (exit code {result.returncode})")
        return False
    print("[BUILD] 完了")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="C ビルド LED ナイトライダー — AXIUART_RV32I 実機実行",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--port",  required=True,
                        help="シリアルポート (例: COM3)")
    parser.add_argument("--baud",  type=int, default=115200)
    parser.add_argument("--bin",   default=_DEFAULT_BIN,
                        help=f"バイナリファイルのパス (デフォルト: {_DEFAULT_BIN})")
    parser.add_argument("--verify", action="store_true",
                        help="書き込み後に BRAM 読み返し検証を行う")
    parser.add_argument("--build", action="store_true",
                        help="実行前に build_c.ps1 で自動ビルドする")
    args = parser.parse_args()

    print("=" * 60)
    print("[C-BLINK] C コンパイル Lチカ — FPGA 実機確認")
    print("=" * 60)

    # ビルド (--build フラグ)
    if args.build:
        if not build():
            return 1

    # バイナリ読み込み
    print(f"\n[BIN]  {args.bin}")
    if not os.path.exists(args.bin):
        print(f"[BIN]  ERROR: ファイルが見つかりません: {args.bin}")
        print(f"       先に build_c.ps1 led_blink を実行してください")
        return 1

    try:
        bin_size_check(args.bin, BRAM_SIZE)
    except ValueError as e:
        print(f"[BIN]  SIZE ERROR: {e}")
        return 1

    instructions = load_bin(args.bin)
    bin_bytes = len(instructions) * 4
    print(f"[BIN]  {len(instructions)} words ({bin_bytes} bytes, "
          f"BRAM 使用率 {bin_bytes / BRAM_SIZE * 100:.1f}%)")

    print(f"\n[UART] {args.port} @ {args.baud} bps に接続中...")
    try:
        with AXIUARTDriver(args.port, args.baud) as driver:

            version  = driver.read_reg32(_reg.REG_VERSION)
            revision = driver.read_reg32(_reg.REG_REVISION)
            print(f"[UART] 接続 OK  VERSION=0x{version:08X}  REVISION=0x{revision:08X}")

            # CPU halt
            print("\n[CPU]  halt 要求...")
            if not halt_cpu(driver):
                print("[CPU]  ERROR: タイムアウト")
                return 1
            st = cpu_status(driver)
            print(f"[CPU]  halt 完了  STATUS=0x{st['raw']:08X}")

            # プログラム書き込み
            print(f"\n[MEM]  BRAM 書き込み ({len(instructions)} words → 0x{BRAM_BASE:08X})...")
            write_program(driver, instructions)
            print("[MEM]  書き込み完了")

            # 検証
            if args.verify:
                print("[MEM]  読み返し検証中...")
                ok, mismatches = verify_program(driver, instructions)
                if ok:
                    print(f"[MEM]  検証 OK ({len(instructions)} words 全一致)")
                else:
                    print(f"[MEM]  検証 FAIL ({len(mismatches)} 箇所不一致):")
                    for addr, exp, act in mismatches[:5]:
                        print(f"         0x{addr:08X}: expected=0x{exp:08X} actual=0x{act:08X}")
                    return 1

            # CPU 実行開始
            print(f"\n[CPU]  実行開始... (PC = 0x{BRAM_BASE:08X})")
            run_cpu(driver)
            print("[CPU]  Running!")
            print("\n       LEDを確認してください: 0001 → 0010 → 0100 → 1000 → ...")
            print("       Ctrl+C で停止\n")

            try:
                elapsed = 0
                while True:
                    time.sleep(5)
                    elapsed += 5
                    cycles = driver.read_reg32(_reg.REG_PERF_CYCLE_COUNT)
                    insns  = driver.read_reg32(_reg.REG_PERF_INSN_COUNT)
                    st     = cpu_status(driver)
                    ipc    = insns / cycles if cycles > 0 else 0
                    print(f"[PERF] t={elapsed:4d}s  "
                          f"cycles={cycles:>12,}  insns={insns:>12,}  "
                          f"IPC={ipc:.3f}  halted={st['halted']}")
            except KeyboardInterrupt:
                print("\n[USER] Ctrl+C — CPU 停止中...")
                halt_cpu(driver)
                cycles  = driver.read_reg32(_reg.REG_PERF_CYCLE_COUNT)
                insns   = driver.read_reg32(_reg.REG_PERF_INSN_COUNT)
                stalls  = driver.read_reg32(_reg.REG_PERF_STALL_COUNT)
                flushes = driver.read_reg32(_reg.REG_PERF_FLUSH_COUNT)
                print("\n[PERF] 最終統計:")
                print(f"         cycles  = {cycles:,}")
                print(f"         insns   = {insns:,}")
                print(f"         stalls  = {stalls:,}")
                print(f"         flushes = {flushes:,}")
                if cycles > 0:
                    print(f"         IPC     = {insns / cycles:.3f}")
                print("[DONE] C Lチカ テスト完了")

    except KeyboardInterrupt:
        print("\n[USER] 接続前にキャンセル")
        return 1
    except AXIUARTException as exc:
        print(f"\n[ERROR] AXIUARTException: {exc}")
        return 1
    except Exception as exc:
        print(f"\n[ERROR] {type(exc).__name__}: {exc}")
        import traceback
        traceback.print_exc()
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
