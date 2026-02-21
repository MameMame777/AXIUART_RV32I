#!/usr/bin/env python3
"""
led_blink.py — LED ナイトライダー (AXIUART_RV32I 実機動作確認スクリプト)

RV32I CPU によるナイトライダーパターンを FPGA 実機で実行する。
HW ブリングアップの最初のステップとして使用する。

メモリマップ (CPU 空間):
  BRAM:     0x80000000 - 0x80003FFF  (16KB, リセットベクタ)
  LED MMIO: 0x8000407C               (bit[3:0] → LED[3:0])

LEDパターン: 0001 → 0010 → 0100 → 1000 → 0001 → ...

使い方:
  python led_blink.py --port COM3
  python led_blink.py --port COM3 --delay-ms 500 --verify --dump
  python led_blink.py --port /dev/ttyUSB0 --baud 115200
"""

import sys
import os
import time
import argparse

# パス設定: software/ を検索パスに追加
_exec_dir = os.path.dirname(os.path.abspath(__file__))
_sw_dir   = os.path.dirname(_exec_dir)   # software/
sys.path.insert(0, _sw_dir)
sys.path.insert(0, os.path.join(_sw_dir, 'rv32i'))  # encoder を直接 import するため

from axiuart_driver import AXIUARTDriver, AXIUARTException
import axiuart_driver.registers as _reg
from rv32i.cpu import (
    halt_cpu, run_cpu, cpu_status,
    write_program, verify_program, memory_sanity_check,
    BRAM_BASE, CLK_MHZ,
)
from encoder import RV32IInstructionEncoder

# LED MMIO アドレス (CPU 空間)
LED_ADDR = 0x8000_407C


# ---------------------------------------------------------------------------
# プログラムビルダ
# ---------------------------------------------------------------------------

def _load_imm32_insns(enc, rd, value):
    """32-bit 即値を LUI+ADDI でレジスタにロードする命令ペアを生成。"""
    upper20 = (value >> 12) & 0xF_FFFF
    lower12 = value & 0xFFF
    if lower12 >= 2048:
        upper20 = (upper20 + 1) & 0xF_FFFF
        lower12 -= 4096
    return [enc.lui(rd, upper20), enc.addi(rd, rd, lower12)]


def build_knight_rider(delay_ms: int = 250):
    """
    LED ナイトライダープログラムを生成する。

    レジスタ割り当て:
      x9  = ディレイカウント定数
      x10 = LED MMIO アドレス (0x8000_407C)
      x11 = 現在の LED パターン (1, 2, 4, 8)
      x13 = 比較値 (= 8, 溢れ検出用)
      x14 = ディレイダウンカウンタ

    Returns:
        (instructions, actual_delay_ms)
    """
    enc = RV32IInstructionEncoder()

    loop_iters = max(1, int(delay_ms / 1000 * CLK_MHZ * 1_000_000 / 2))
    actual_ms  = loop_iters * 2 / (CLK_MHZ * 1_000_000) * 1000

    prog = []
    prog.append(enc.lui(10, 0x80004))          # x10 = 0x80004000
    prog.append(enc.addi(10, 10, 0x7C))        # x10 = 0x8000407C (LED)
    prog.append(enc.addi(11, 0, 1))            # x11 = 1 (初期パターン)
    prog.extend(_load_imm32_insns(enc, 9, loop_iters))  # x9 = ディレイ値

    loop_start_pc  = len(prog) * 4             # 0x14
    prog.append(enc.sw(11, 0, 10))             # SW x11, 0(x10)  → LED 書き込み
    prog.append(enc.addi(14, 9, 0))            # x14 = x9 (カウンタ初期化)

    delay_loop_pc  = len(prog) * 4             # 0x1C
    prog.append(enc.addi(14, 14, -1))          # x14--
    bne_pc         = len(prog) * 4
    prog.append(enc.bne(14, 0, delay_loop_pc - bne_pc))  # x14 != 0 → delay_loop

    prog.append(enc.slli(11, 11, 1))           # x11 <<= 1
    prog.append(enc.addi(13, 0, 8))            # x13 = 8 (最大値)

    blt_idx = len(prog)
    blt_pc  = blt_idx * 4
    prog.append(0)                              # BLT (後でパッチ)

    jal1_pc = len(prog) * 4
    prog.append(enc.jal(0, loop_start_pc - jal1_pc))  # → LOOP_START

    reset_pc = len(prog) * 4
    prog.append(enc.addi(11, 0, 1))            # x11 = 1 (リセット)
    jal2_pc  = len(prog) * 4
    prog.append(enc.jal(0, loop_start_pc - jal2_pc))  # → LOOP_START

    prog[blt_idx] = enc.blt(13, 11, reset_pc - blt_pc)  # BLT のパッチ適用

    return prog, actual_ms


def disassemble(instructions):
    """生成したプログラムを逆アセンブル風に表示 (簡易版)。"""
    opmap = {
        0x37: "LUI", 0x17: "AUIPC", 0x6F: "JAL", 0x67: "JALR",
        0x63: "BRANCH", 0x03: "LOAD", 0x23: "STORE",
        0x13: "OP-IMM", 0x33: "OP", 0x73: "SYSTEM",
    }
    f3_branch = {0:"BEQ",1:"BNE",4:"BLT",5:"BGE",6:"BLTU",7:"BGEU"}
    f3_store  = {0:"SB",1:"SH",2:"SW"}
    f3_opimm  = {0:"ADDI",2:"SLTI",3:"SLTIU",4:"XORI",6:"ORI",7:"ANDI"}

    for i, insn in enumerate(instructions):
        pc  = BRAM_BASE + i * 4
        op  = insn & 0x7F
        rd  = (insn >> 7)  & 0x1F
        f3  = (insn >> 12) & 0x7
        rs1 = (insn >> 15) & 0x1F
        rs2 = (insn >> 20) & 0x1F
        name = opmap.get(op, f"OP=0x{op:02X}")

        if op == 0x37:
            detail = f"x{rd}, 0x{(insn>>12)&0xFFFFF:05X}"
        elif op == 0x13:
            imm = insn >> 20
            if imm >= 2048: imm -= 4096
            mn = f3_opimm.get(f3, f"f3={f3}")
            detail = f"{mn} x{rd}, x{rs1}, {imm}"
        elif op == 0x23:
            imm = ((insn>>25)<<5) | ((insn>>7)&0x1F)
            if imm >= 2048: imm -= 4096
            detail = f"{f3_store.get(f3,'?')} x{rs2}, {imm}(x{rs1})"
        elif op == 0x63:
            imm = (((insn>>31)&1)<<12)|(((insn>>7)&1)<<11)|\
                  (((insn>>25)&0x3F)<<5)|(((insn>>8)&0xF)<<1)
            if imm >= 4096: imm -= 8192
            detail = f"{f3_branch.get(f3,'?')} x{rs1}, x{rs2}, 0x{pc+imm:08X}"
        elif op == 0x6F:
            imm = (((insn>>31)&1)<<20)|(((insn>>12)&0xFF)<<12)|\
                  (((insn>>20)&1)<<11)|(((insn>>21)&0x3FF)<<1)
            if imm >= 1<<20: imm -= 1<<21
            detail = f"x{rd}, 0x{pc+imm:08X}"
        else:
            detail = f"0x{insn:08X}"

        print(f"  0x{pc:08X}  [{i:2d}]  0x{insn:08X}  {name:8s} {detail}")


# ---------------------------------------------------------------------------
# メイン
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="LED Blink (Lチカ) - AXIUART_RV32I 実機動作確認",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--port",      required=True,
                        help="シリアルポート (例: COM3, /dev/ttyUSB0)")
    parser.add_argument("--baud",      type=int, default=115200)
    parser.add_argument("--delay-ms",  type=int, default=250,
                        help="1パターンあたりのディレイ [ms] (デフォルト: 250)")
    parser.add_argument("--verify",    action="store_true",
                        help="書き込み後に BRAM 読み返し検証を行う")
    parser.add_argument("--dump",      action="store_true",
                        help="生成プログラムを逆アセンブル表示")
    parser.add_argument("--mem-check", action="store_true",
                        help="事前に BRAM R/W 動作確認を行う")
    args = parser.parse_args()

    print("=" * 60)
    print("[PROG] LED ナイトライダープログラム生成")
    print("=" * 60)
    prog, actual_ms = build_knight_rider(delay_ms=args.delay_ms)
    print(f"  命令数:          {len(prog)} instructions ({len(prog)*4} bytes)")
    print(f"  LEDアドレス:     0x{LED_ADDR:08X}  (MMIO)")
    print(f"  ロードアドレス:  0x{BRAM_BASE:08X}  (BRAM)")
    print(f"  ディレイ:        {actual_ms:.1f} ms / pattern")
    print(f"  パターン:        0001 → 0010 → 0100 → 1000 → ...")

    if args.dump:
        print("\n[DUMP] 生成プログラム:")
        disassemble(prog)

    print(f"\n[UART] {args.port} @ {args.baud} bps に接続中...")
    try:
        with AXIUARTDriver(args.port, args.baud) as driver:

            version  = driver.read_reg32(_reg.REG_VERSION)
            revision = driver.read_reg32(_reg.REG_REVISION)
            print(f"[UART] 接続 OK  VERSION=0x{version:08X}  REVISION=0x{revision:08X}")

            print("\n[CPU]  halt 要求...")
            if not halt_cpu(driver):
                print("[CPU]  ERROR: タイムアウト - CPU が halt しませんでした")
                return 1
            st = cpu_status(driver)
            print(f"[CPU]  halt 完了  STATUS=0x{st['raw']:08X}")

            if args.mem_check:
                print("\n[MEM]  BRAM R/W 動作確認...")
                if not memory_sanity_check(driver):
                    print("[MEM]  ERROR: メモリ動作確認に失敗しました")
                    return 1
                print("[MEM]  BRAM R/W OK")

            print(f"\n[MEM]  プログラム書き込み ({len(prog)} words → 0x{BRAM_BASE:08X})...")
            write_program(driver, prog)
            print("[MEM]  書き込み完了")

            if args.verify:
                print("[MEM]  読み返し検証中...")
                ok, mismatches = verify_program(driver, prog)
                if ok:
                    print(f"[MEM]  検証 OK ({len(prog)} words 全一致)")
                else:
                    print(f"[MEM]  検証 FAIL ({len(mismatches)} 箇所不一致):")
                    for addr, exp, act in mismatches:
                        print(f"         0x{addr:08X}: expected=0x{exp:08X} actual=0x{act:08X}")
                    return 1

            print(f"\n[CPU]  実行開始... (PC = 0x{BRAM_BASE:08X})")
            run_cpu(driver)
            print("[CPU]  Running!")
            print(f"\n       LEDを確認してください: 0001 → 0010 → 0100 → 1000 → ...")
            print("       Ctrl+C で停止\n")

            try:
                interval = 0
                while True:
                    time.sleep(5)
                    interval += 5
                    cycles  = driver.read_reg32(_reg.REG_PERF_CYCLE_COUNT)
                    insns   = driver.read_reg32(_reg.REG_PERF_INSN_COUNT)
                    stalls  = driver.read_reg32(_reg.REG_PERF_STALL_COUNT)
                    st      = cpu_status(driver)
                    print(f"[PERF] t={interval:4d}s  "
                          f"cycles={cycles:>12,}  insns={insns:>12,}  "
                          f"stalls={stalls:>8,}  "
                          f"halted={st['halted']}  break={st['break']}")
            except KeyboardInterrupt:
                print("\n[USER] Ctrl+C 検出 - CPU 停止中...")
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
                print("[DONE] LED blink テスト完了")

    except KeyboardInterrupt:
        print("\n[USER] 接続前にキャンセルされました")
        return 1
    except AXIUARTException as exc:
        print(f"\n[ERROR] AXIUARTException: {exc}")
        return 1
    except Exception as exc:
        print(f"\n[ERROR] {type(exc).__name__}: {exc}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
