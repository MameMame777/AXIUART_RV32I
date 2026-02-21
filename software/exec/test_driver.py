#!/usr/bin/env python3
"""
test_driver.py — AXIUART ドライバ接続テスト

FPGA に接続して axiuart_driver の基本機能を検証する。
新しい FPGA ビットストリームを書き込んだ直後や、
ドライバの動作確認として使用する。

テスト内容:
  TEST 1: 接続確認 + VERSION レジスタ読み出し
  TEST 2: STATUS / CONFIG レジスタ読み出し
  TEST 3: TEST_0 レジスタ R/W (5パターン)
  TEST 4: CPU 制御レジスタ確認 (REVISION, CPU_MEM_CTRL)
  TEST 5: バースト転送 (4-word write + read)

使い方:
  python test_driver.py --port COM3
  python test_driver.py --port COM3 --no-debug
"""

import sys
import os
import time
import logging
import argparse

_exec_dir = os.path.dirname(os.path.abspath(__file__))
_sw_dir   = os.path.dirname(_exec_dir)
sys.path.insert(0, _sw_dir)

from axiuart_driver import AXIUARTDriver, AXIUARTException
import axiuart_driver.registers as _reg


def test_connection(driver) -> bool:
    print("\n[TEST 1] 接続確認 + VERSION レジスタ")
    print("-" * 60)
    try:
        version = driver.read_reg32(_reg.REG_VERSION)
        print(f"  ✓ VERSION:  0x{version:08X}")
        return True
    except Exception as e:
        print(f"  ✗失敗: {e}")
        return False


def test_status_registers(driver) -> bool:
    print("\n[TEST 2] STATUS / CONFIG レジスタ")
    print("-" * 60)
    try:
        status = driver.read_reg32(_reg.REG_STATUS)
        config = driver.read_reg32(_reg.REG_CONFIG)
        print(f"  ✓ STATUS:   0x{status:08X}")
        print(f"  ✓ CONFIG:   0x{config:08X}")
        return True
    except Exception as e:
        print(f"  ✗ 失敗: {e}")
        return False


def test_test_registers(driver) -> bool:
    print("\n[TEST 3] TEST_0 レジスタ R/W (5パターン)")
    print("-" * 60)
    test_values = [0x12345678, 0xDEADBEEF, 0xCAFEBABE, 0x00000000, 0xFFFFFFFF]
    for i, val in enumerate(test_values, 1):
        try:
            driver.write_reg32(_reg.REG_TEST_0, val)
            read_val = driver.read_reg32(_reg.REG_TEST_0)
            if read_val == val:
                print(f"  [{i}] 0x{val:08X} → 0x{read_val:08X}  ✓")
            else:
                print(f"  [{i}] 0x{val:08X} → 0x{read_val:08X}  ✗ MISMATCH")
                return False
        except Exception as e:
            print(f"  [{i}] ✗ 失敗: {e}")
            return False
    return True


def test_cpu_registers(driver) -> bool:
    print("\n[TEST 4] CPU 制御レジスタ")
    print("-" * 60)
    try:
        revision = driver.read_reg32(_reg.REG_REVISION)
        ctrl     = driver.read_reg32(_reg.REG_CPU_MEM_CTRL)
        print(f"  ✓ REVISION:      0x{revision:08X}")
        print(f"  ✓ CPU_MEM_CTRL:  0x{ctrl:08X}")
        print(f"       cpu_halted = {(ctrl >> 9) & 1}")
        print(f"       cpu_break  = {(ctrl >> 10) & 1}")
        print(f"       busy       = {(ctrl >> 6) & 1}")
        return True
    except Exception as e:
        print(f"  ✗ 失敗: {e}")
        return False


def test_burst_transfer(driver) -> bool:
    print("\n[TEST 5] バースト転送 (4-word)")
    print("-" * 60)
    try:
        write_data = [0x11111111, 0x22222222, 0x33333333, 0x44444444]
        driver.write_burst(_reg.REG_TEST_0, write_data)
        print(f"  書き込み: {[hex(v) for v in write_data]}")
        read_data = driver.read_burst(_reg.REG_TEST_0, count=4)
        print(f"  読み出し: {[hex(v) for v in read_data]}")
        if read_data == write_data:
            print("  ✓ バースト一致")
            return True
        else:
            print("  ✗ バースト不一致")
            return False
    except Exception as e:
        print(f"  ✗ 失敗: {e}")
        return False


def main() -> int:
    parser = argparse.ArgumentParser(
        description="AXIUART ドライバ接続テスト",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--port",     required=True,
                        help="シリアルポート (例: COM3)")
    parser.add_argument("--baud",     type=int, default=115200)
    parser.add_argument("--no-debug", action="store_true",
                        help="DEBUG ログを無効化する")
    args = parser.parse_args()

    if not args.no_debug:
        logging.basicConfig(
            level=logging.DEBUG,
            format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        )

    print("=" * 60)
    print("[DRIVER] AXIUART ドライバ接続テスト")
    print("=" * 60)
    print(f"  ポート: {args.port}  ボーレート: {args.baud}")

    driver = AXIUARTDriver(args.port, baudrate=args.baud, debug=not args.no_debug)
    try:
        driver.open()
        print("  ✓ 接続確立")

        results = [
            ("接続確認 + VERSION",   test_connection(driver)),
            ("STATUS / CONFIG",      test_status_registers(driver)),
            ("TEST_0 R/W",           test_test_registers(driver)),
            ("CPU 制御レジスタ",     test_cpu_registers(driver)),
            ("バースト転送",         test_burst_transfer(driver)),
        ]

        print("\n" + "=" * 60)
        print("[SUMMARY] テスト結果")
        print("=" * 60)
        passed = sum(1 for _, r in results if r)
        failed = len(results) - passed
        for name, result in results:
            symbol = "✓" if result else "✗"
            status = "PASS" if result else "FAIL"
            print(f"  {symbol} {name:<30s} [{status}]")
        print("-" * 60)
        print(f"  Total: {len(results)}, Passed: {passed}, Failed: {failed}")

        if failed == 0:
            print("\n[DONE] 全テスト PASS")
        else:
            print(f"\n[WARN] {failed} テスト FAIL")

        return 0 if failed == 0 else 1

    except AXIUARTException as e:
        print(f"\n[ERROR] AXIUARTException: {e}")
        return 1
    except Exception as e:
        print(f"\n[ERROR] {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        return 1
    finally:
        if driver.serial and driver.serial.is_open:
            driver.close()
            print("\n  接続をクローズしました")


if __name__ == "__main__":
    sys.exit(main())
