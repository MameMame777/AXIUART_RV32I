#!/usr/bin/env python3
"""
LED Blink (Lチカ) - AXIUART_RV32I 実機動作確認プログラム

このスクリプトはFPGA実機動作確認の最初のステップとして
RV32I CPUによるLEDナイトライダーパターンを実行します。

フロー:
  1. UART経由でFPGAに接続
  2. CPU停止 (halt)
  3. メモリ R/W 動作確認 (--verify オプション)
  4. LEDブリンクプログラムをBRAMに書き込み
  5. CPU実行開始

メモリマップ (CPU空間):
  BRAM:     0x80000000 - 0x80003FFF  (16KB, リセットベクタ)
  LED MMIO: 0x8000407C               (下位4bit → LED[3:0])

LEDパターン (ナイトライダー):
  0001 → 0010 → 0100 → 1000 → 0001 → ...

使い方:
  python led_blink.py --port COM3
  python led_blink.py --port /dev/ttyUSB0 --baud 115200
  python led_blink.py --port COM3 --delay-ms 500 --verify
"""

import sys
import os
import time
import argparse

# ---------------------------------------------------------------------------
# パスの設定
# ---------------------------------------------------------------------------
_script_dir  = os.path.dirname(os.path.abspath(__file__))
_rv32i_dir   = _script_dir                                # software/rv32i/
_sw_dir      = os.path.dirname(_rv32i_dir)                # software/

sys.path.insert(0, _sw_dir)
sys.path.insert(0, _rv32i_dir)

from axiuart_driver import AXIUARTDriver
from axiuart_driver import registers as _reg
from encoder import RV32IInstructionEncoder

# ---------------------------------------------------------------------------
# ハードウェア定数
# ---------------------------------------------------------------------------
BRAM_BASE = 0x8000_0000   # BRAM ベースアドレス (CPU空間)
LED_ADDR  = 0x8000_407C   # LED MMIO レジスタ (CPU空間)
CLK_MHZ   = 125           # クロック周波数 [MHz]

# CPU制御レジスタ ビットマスク (axiuart_registers.json より)
_BYTE_ALL   = 0x0F        # [3:0]  バイトイネーブル (全有効)
_READ_REQ   = 1 << 4      # [4]    メモリ読み出しリクエスト (W1P)
_WRITE_REQ  = 1 << 5      # [5]    メモリ書き込みリクエスト (W1P)
_BUSY       = 1 << 6      # [6]    メモリ操作中 (RO)
_CPU_RUN    = 1 << 7      # [7]    CPU 実行
_CPU_HALT   = 1 << 8      # [8]    CPU 停止要求
_CPU_HALTED = 1 << 9      # [9]    CPU 停止状態 (RO)
_CPU_BREAK  = 1 << 10     # [10]   EBREAK 発生 (RO)

# ---------------------------------------------------------------------------
# CPU制御
# ---------------------------------------------------------------------------

def halt_cpu(driver, timeout: float = 2.0) -> bool:
    """CPUを停止し、HALTED状態になるまで待機"""
    driver.write_reg32(_reg.REG_CPU_MEM_CTRL, _CPU_HALT)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if driver.read_reg32(_reg.REG_CPU_MEM_CTRL) & _CPU_HALTED:
            return True
        time.sleep(0.01)
    return False


def run_cpu(driver) -> None:
    """CPU停止を解除して実行開始"""
    driver.write_reg32(_reg.REG_CPU_MEM_CTRL, _CPU_RUN)


def cpu_status(driver) -> dict:
    """CPU状態レジスタを読み取る"""
    raw = driver.read_reg32(_reg.REG_CPU_MEM_CTRL)
    return {
        "halted": bool(raw & _CPU_HALTED),
        "break":  bool(raw & _CPU_BREAK),
        "busy":   bool(raw & _BUSY),
        "raw":    raw,
    }

# ---------------------------------------------------------------------------
# メモリアクセス (デバッグインターフェース)
# ---------------------------------------------------------------------------

def _wait_idle(driver, timeout: float = 1.0) -> None:
    """メモリコントローラのBUSYが落ちるまで待機"""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not (driver.read_reg32(_reg.REG_CPU_MEM_CTRL) & _BUSY):
            return
        time.sleep(0.001)
    raise TimeoutError("Memory controller busy timeout")


def write_word(driver, cpu_addr: int, data: int) -> None:
    """
    BRAMへ32bitワードを書き込む (デバッグIF経由)

    CPUをhaltした状態で呼び出すこと。
    RTLは cpu_mem_addr_reg[13:2] をワードアドレスとして使用するため
    CPU空間の完全なバイトアドレス (例: 0x80000000) を渡してよい。

    Args:
        cpu_addr: CPUバイトアドレス (4バイトアライン)
        data:     書き込む32bitデータ
    """
    driver.write_reg32(_reg.REG_CPU_MEM_ADDR,  cpu_addr)
    driver.write_reg32(_reg.REG_CPU_MEM_WDATA, data)
    driver.write_reg32(_reg.REG_CPU_MEM_CTRL,
                       _CPU_HALT | _WRITE_REQ | _BYTE_ALL)
    _wait_idle(driver)


def read_word(driver, cpu_addr: int) -> int:
    """
    BRAMから32bitワードを読み出す (デバッグIF経由)

    CPUをhaltした状態で呼び出すこと。

    Args:
        cpu_addr: CPUバイトアドレス (4バイトアライン)

    Returns:
        読み出した32bitデータ
    """
    driver.write_reg32(_reg.REG_CPU_MEM_ADDR, cpu_addr)
    driver.write_reg32(_reg.REG_CPU_MEM_CTRL,
                       _CPU_HALT | _READ_REQ | _BYTE_ALL)
    _wait_idle(driver)
    return driver.read_reg32(_reg.REG_CPU_MEM_RDATA)


def write_program(driver, instructions: list, base: int = BRAM_BASE,
                  verbose: bool = False) -> None:
    """
    命令リストをBRAMへ書き込む

    Args:
        instructions: エンコード済み32bit命令のリスト
        base:         書き込み先ベースアドレス (デフォルト: BRAM_BASE)
        verbose:      各ワードの書き込みを表示する
    """
    for i, insn in enumerate(instructions):
        addr = base + i * 4
        write_word(driver, addr, insn)
        if verbose:
            print(f"    [0x{addr:08X}] = 0x{insn:08X}")


def verify_program(driver, instructions: list,
                   base: int = BRAM_BASE) -> tuple[bool, list]:
    """
    書き込んだプログラムを読み返して検証する

    Returns:
        (ok, mismatches)
        ok:         全ワード一致の場合 True
        mismatches: 不一致リスト [(addr, expected, actual), ...]
    """
    mismatches = []
    for i, expected in enumerate(instructions):
        addr = base + i * 4
        actual = read_word(driver, addr)
        if actual != expected:
            mismatches.append((addr, expected, actual))
    return len(mismatches) == 0, mismatches


def memory_sanity_check(driver) -> bool:
    """
    BRAMへのR/W動作確認 (既知パターンを書き込み・読み返す)

    BRAM末尾付近 (アドレス 0x80003F00-0x80003F0C) を使用。
    実行前にCPUをhaltしておくこと。

    Returns:
        True: 全パターン一致
        False: 不一致あり
    """
    TEST_PATTERNS = [
        (0x8000_3F00, 0xDEAD_BEEF),
        (0x8000_3F04, 0xCAFE_BABE),
        (0x8000_3F08, 0x1234_5678),
        (0x8000_3F0C, 0xA5A5_A5A5),
    ]
    ok = True
    for addr, pattern in TEST_PATTERNS:
        write_word(driver, addr, pattern)
        actual = read_word(driver, addr)
        if actual != pattern:
            print(f"    [FAIL] 0x{addr:08X}: "
                  f"expected=0x{pattern:08X} actual=0x{actual:08X}")
            ok = False
        else:
            print(f"    [OK]   0x{addr:08X}: 0x{pattern:08X}")
    return ok

# ---------------------------------------------------------------------------
# RV32I プログラムビルダ
# ---------------------------------------------------------------------------

def _load_imm32_insns(enc: RV32IInstructionEncoder,
                      rd: int, value: int) -> list:
    """
    32bitの即値をレジスタにロードする命令列を生成 (LUI + ADDI)

    ADDIの符号拡張を補正するため、下位12bitが 2048 以上の場合は
    LUI即値に +1 して ADDI 即値を負にする。

    Returns:
        [lui_insn, addi_insn]  (常に2命令)
    """
    upper20 = (value >> 12) & 0xF_FFFF
    lower12 = value & 0xFFF
    if lower12 >= 2048:          # bit11 が立つ → 符号拡張で負になる
        upper20 = (upper20 + 1) & 0xF_FFFF
        lower12 -= 4096          # 負値にして補正
    return [enc.lui(rd, upper20), enc.addi(rd, rd, lower12)]


def build_knight_rider(delay_ms: int = 250) -> tuple[list, float]:
    """
    LEDナイトライダーパターンのRV32I命令列を生成

    パターン: 0001 → 0010 → 0100 → 1000 → 0001 → ...

    レジスタ割り当て:
      x9  = ディレイカウント定数
      x10 = LED MMIO アドレス (0x8000_407C)
      x11 = 現在のLEDパターン
      x13 = 比較用 (= 8, 溢れ検出)
      x14 = ディレイカウンタ (実行時)

    プログラムレイアウト (PC=0x80000000 基準):
      0x00  LUI  x10, 0x80004      ; x10 = 0x80004000
      0x04  ADDI x10, x10, 0x7C   ; x10 = 0x8000407C (LED)
      0x08  ADDI x11, x0,  1      ; x11 = 1 (初期パターン)
      0x0C  LUI  x9,  delay_hi    ; x9 = ディレイ上位
      0x10  ADDI x9,  x9,  delay_lo ; x9 = ディレイカウント値
      ---LOOP_START (0x14)---
      0x14  SW   x11, 0(x10)      ; LED = x11
      0x18  ADDI x14, x9,  0      ; x14 = ディレイカウント (コピー)
      ---DELAY_LOOP (0x1C)---
      0x1C  ADDI x14, x14, -1     ; x14--
      0x20  BNE  x14, x0,  -4     ; x14!=0 → 0x1C へ
      0x24  SLLI x11, x11, 1      ; x11 <<= 1 (パターンシフト)
      0x28  ADDI x13, x0,  8      ; x13 = 8 (最大値)
      0x2C  BLT  x13, x11, 8      ; x11 > 8 → 0x34 (RESET) へ
      0x30  JAL  x0,  -28         ; → 0x14 (LOOP_START) へ
      ---RESET (0x34)---
      0x34  ADDI x11, x0,  1      ; x11 = 1 (リセット)
      0x38  JAL  x0,  -36         ; → 0x14 (LOOP_START) へ

    Args:
        delay_ms: 1パターンあたりのディレイ [ms] (CLK_MHZ=125想定)

    Returns:
        (instructions, actual_delay_ms)
    """
    enc = RV32IInstructionEncoder()

    # -----------------------------------------------------------------------
    # ディレイ値の計算
    # DELAYループ: addi + bne = 約2サイクル/イテレーション
    # -----------------------------------------------------------------------
    loop_iters = max(1, int(delay_ms / 1000 * CLK_MHZ * 1_000_000 / 2))
    actual_ms  = loop_iters * 2 / (CLK_MHZ * 1_000_000) * 1000

    # -----------------------------------------------------------------------
    # プログラム生成
    # -----------------------------------------------------------------------
    prog = []

    # --- セットアップ (PC=0x00) ---
    prog.append(enc.lui(10, 0x80004))           # x10 = 0x80004000
    prog.append(enc.addi(10, 10, 0x7C))         # x10 = 0x8000407C
    prog.append(enc.addi(11, 0, 1))             # x11 = 1 (初期パターン)
    prog.extend(_load_imm32_insns(enc, 9, loop_iters))  # x9 = ディレイ値

    # --- LOOP_START (PC = len*4 = 0x14) ---
    loop_start_pc = len(prog) * 4
    prog.append(enc.sw(11, 0, 10))              # MEM[x10+0] = x11 (LED書き込み)
    prog.append(enc.addi(14, 9, 0))             # x14 = x9 (ディレイカウント)

    # --- DELAY_LOOP (PC = 0x1C) ---
    delay_loop_pc = len(prog) * 4
    prog.append(enc.addi(14, 14, -1))           # x14--
    bne_pc = len(prog) * 4
    prog.append(enc.bne(14, 0, delay_loop_pc - bne_pc))  # x14!=0 → delay_loop

    # --- パターンシフト & 溢れ検出 ---
    prog.append(enc.slli(11, 11, 1))            # x11 <<= 1
    prog.append(enc.addi(13, 0, 8))             # x13 = 8 (最大値)

    # BLT x13, x11: x13 < x11 (= x11 > 8) のとき RESET へ分岐
    blt_idx = len(prog)
    blt_pc  = blt_idx * 4
    prog.append(0)                               # ← 後でパッチ

    # LOOP_START へのジャンプ (溢れなし)
    jal1_pc = len(prog) * 4
    prog.append(enc.jal(0, loop_start_pc - jal1_pc))

    # --- RESET (PC = 0x34) ---
    reset_pc = len(prog) * 4
    prog.append(enc.addi(11, 0, 1))             # x11 = 1
    jal2_pc  = len(prog) * 4
    prog.append(enc.jal(0, loop_start_pc - jal2_pc))

    # BLT のパッチ (reset_pc が確定してから)
    prog[blt_idx] = enc.blt(13, 11, reset_pc - blt_pc)

    return prog, actual_ms


def disassemble_program(instructions: list) -> None:
    """生成したプログラムを逆アセンブル風に表示 (簡易版)"""
    opcode_map = {
        0x37: "LUI", 0x17: "AUIPC",
        0x6F: "JAL", 0x67: "JALR",
        0x63: "BRANCH", 0x03: "LOAD", 0x23: "STORE",
        0x13: "OP-IMM", 0x33: "OP",
        0x73: "SYSTEM",
    }
    funct3_branch = {0: "BEQ", 1: "BNE", 4: "BLT", 5: "BGE", 6: "BLTU", 7: "BGEU"}
    funct3_opimm  = {0: "ADDI", 1: "SLLI", 2: "SLTI", 3: "SLTIU",
                     4: "XORI", 5: "SRI",  6: "ORI",  7: "ANDI"}
    funct3_store  = {0: "SB", 1: "SH", 2: "SW"}

    for i, insn in enumerate(instructions):
        pc   = BRAM_BASE + i * 4
        op   = insn & 0x7F
        name = opcode_map.get(op, f"OP=0x{op:02X}")
        rd   = (insn >> 7)  & 0x1F
        f3   = (insn >> 12) & 0x7
        rs1  = (insn >> 15) & 0x1F
        rs2  = (insn >> 20) & 0x1F

        detail = ""
        if op == 0x37:  # LUI
            imm = (insn >> 12) & 0xFFFFF
            detail = f"x{rd}, 0x{imm:05X}"
        elif op == 0x13:  # OP-IMM
            imm12 = insn >> 20  # sign-extended
            if imm12 >= 2048: imm12 -= 4096
            detail = f"{funct3_opimm.get(f3,'?')} x{rd}, x{rs1}, {imm12}"
        elif op == 0x23:  # STORE
            imm = ((insn >> 25) << 5) | ((insn >> 7) & 0x1F)
            if imm >= 2048: imm -= 4096
            detail = f"{funct3_store.get(f3,'?')} x{rs2}, {imm}(x{rs1})"
        elif op == 0x63:  # BRANCH
            imm = (((insn >> 31) & 1) << 12) | (((insn >> 7) & 1) << 11) | \
                  (((insn >> 25) & 0x3F) << 5) | (((insn >> 8) & 0xF) << 1)
            if imm >= 4096: imm -= 8192
            target = pc + imm
            detail = f"{funct3_branch.get(f3,'?')} x{rs1}, x{rs2}, 0x{target:08X}"
        elif op == 0x6F:  # JAL
            imm = (((insn >> 31) & 1) << 20) | (((insn >> 12) & 0xFF) << 12) | \
                  (((insn >> 20) & 1) << 11) | (((insn >> 21) & 0x3FF) << 1)
            if imm >= 1 << 20: imm -= 1 << 21
            target = pc + imm
            detail = f"x{rd}, 0x{target:08X}"
        elif op == 0x13 and f3 == 1:  # SLLI
            shamt = rs2 & 0x1F
            detail = f"SLLI x{rd}, x{rs1}, {shamt}"
        else:
            detail = f"raw=0x{insn:08X}"

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
    parser.add_argument("--port",     required=True,
                        help="シリアルポート (例: COM3, /dev/ttyUSB0)")
    parser.add_argument("--baud",     type=int, default=115200,
                        help="ボーレート (デフォルト: 115200)")
    parser.add_argument("--delay-ms", type=int, default=250,
                        help="1パターンあたりのディレイ [ms] (デフォルト: 250)")
    parser.add_argument("--verify",   action="store_true",
                        help="書き込み後に読み返し検証を行う")
    parser.add_argument("--dump",     action="store_true",
                        help="生成したプログラムを逆アセンブル表示")
    parser.add_argument("--mem-check", action="store_true",
                        help="BRAMのR/W動作確認を行う (書き込み前)")
    args = parser.parse_args()

    # -----------------------------------------------------------------------
    # プログラム生成
    # -----------------------------------------------------------------------
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
        disassemble_program(prog)

    # -----------------------------------------------------------------------
    # FPGA 接続 & 実行
    # -----------------------------------------------------------------------
    print(f"\n[UART] {args.port} @ {args.baud} bps に接続中...")
    try:
        with AXIUARTDriver(args.port, args.baud) as driver:

            # --- 接続確認 ---
            version  = driver.read_reg32(_reg.REG_VERSION)
            revision = driver.read_reg32(_reg.REG_REVISION)
            print(f"[UART] 接続 OK  VERSION=0x{version:08X}  REVISION=0x{revision:08X}")

            # --- CPU 停止 ---
            print("\n[CPU]  halt 要求...")
            if not halt_cpu(driver):
                print("[CPU]  ERROR: タイムアウト - CPUがhaltしませんでした")
                return 1
            st = cpu_status(driver)
            print(f"[CPU]  halt 完了  STATUS=0x{st['raw']:08X}")

            # --- メモリ動作確認 (オプション) ---
            if args.mem_check:
                print("\n[MEM]  BRAM R/W 動作確認...")
                if not memory_sanity_check(driver):
                    print("[MEM]  ERROR: メモリ動作確認に失敗しました")
                    return 1
                print("[MEM]  BRAM R/W OK")

            # --- プログラム書き込み ---
            print(f"\n[MEM]  プログラム書き込み ({len(prog)} words → 0x{BRAM_BASE:08X})...")
            write_program(driver, prog)
            print(f"[MEM]  書き込み完了")

            # --- 書き込み検証 (オプション) ---
            if args.verify:
                print(f"[MEM]  読み返し検証中...")
                ok, mismatches = verify_program(driver, prog)
                if ok:
                    print(f"[MEM]  検証 OK ({len(prog)} words 全一致)")
                else:
                    print(f"[MEM]  検証 FAIL ({len(mismatches)} 箇所不一致):")
                    for addr, exp, act in mismatches:
                        print(f"         0x{addr:08X}: "
                              f"expected=0x{exp:08X} actual=0x{act:08X}")
                    return 1

            # --- CPU 実行開始 ---
            print(f"\n[CPU]  実行開始... (PC = 0x{BRAM_BASE:08X})")
            run_cpu(driver)
            print(f"[CPU]  Running!")
            print(f"\n       LEDを確認してください: 0001 → 0010 → 0100 → 1000 → ...")
            print(f"       Ctrl+C で停止\n")

            # --- 実行中モニタ ---
            try:
                interval = 0
                while True:
                    time.sleep(5)
                    interval += 5
                    cycles = driver.read_reg32(_reg.REG_PERF_CYCLE_COUNT)
                    insns  = driver.read_reg32(_reg.REG_PERF_INSN_COUNT)
                    stalls = driver.read_reg32(_reg.REG_PERF_STALL_COUNT)
                    st     = cpu_status(driver)
                    print(f"[PERF] t={interval:4d}s  "
                          f"cycles={cycles:>12,}  insns={insns:>12,}  "
                          f"stalls={stalls:>8,}  "
                          f"halted={st['halted']}  break={st['break']}")

            except KeyboardInterrupt:
                print("\n[USER] Ctrl+C 検出 - CPU停止中...")
                halt_cpu(driver)
                cycles = driver.read_reg32(_reg.REG_PERF_CYCLE_COUNT)
                insns  = driver.read_reg32(_reg.REG_PERF_INSN_COUNT)
                stalls = driver.read_reg32(_reg.REG_PERF_STALL_COUNT)
                flushes= driver.read_reg32(_reg.REG_PERF_FLUSH_COUNT)
                print(f"\n[PERF] 最終統計:")
                print(f"         cycles  = {cycles:,}")
                print(f"         insns   = {insns:,}")
                print(f"         stalls  = {stalls:,}")
                print(f"         flushes = {flushes:,}")
                if cycles > 0:
                    ipc = insns / cycles
                    print(f"         IPC     = {ipc:.3f}")
                print("[DONE] LED blink テスト完了")

    except KeyboardInterrupt:
        print("\n[USER] 接続前にキャンセルされました")
        return 1
    except Exception as exc:
        print(f"\n[ERROR] {type(exc).__name__}: {exc}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
