"""
rv32i.cpu — RV32I CPU Control Helpers

AXIUART デバッグIF経由の CPU 制御・BRAM アクセス関数。
実機スクリプト (exec/) から import して使用する。

必要前提: CPU が halt 状態であること (write_word/read_word 使用前)

使い方:
    from axiuart_driver import AXIUARTDriver
    import axiuart_driver.registers as reg
    from rv32i.cpu import halt_cpu, run_cpu, write_program, verify_program

    driver = AXIUARTDriver('COM3', 115200)
    driver.open()
    halt_cpu(driver)
    write_program(driver, instructions)
    run_cpu(driver)
"""

import time

# ---------------------------------------------------------------------------
# ハードウェア定数
# ---------------------------------------------------------------------------
BRAM_BASE = 0x8000_0000   # BRAM ベースアドレス (CPU空間, リセットベクタ)
LED_ADDR  = 0x8000_407C   # LED MMIO アドレス (CPU空間, bit[3:0] → LED[3:0])
CLK_MHZ   = 125           # クロック周波数 [MHz]

# REG_CPU_MEM_CTRL ビットマスク (register_map/axiuart_registers.json より)
_BYTE_ALL   = 0x0F        # [3:0]  バイトイネーブル (全有効)
_READ_REQ   = 1 << 4      # [4]    メモリ読み出しリクエスト (W1P: Write-1-Pulse)
_WRITE_REQ  = 1 << 5      # [5]    メモリ書き込みリクエスト (W1P)
_BUSY       = 1 << 6      # [6]    メモリ操作中 (RO)
_CPU_RUN    = 1 << 7      # [7]    CPU 実行開始
_CPU_HALT   = 1 << 8      # [8]    CPU 停止要求
_CPU_HALTED = 1 << 9      # [9]    CPU 停止状態 (RO)
_CPU_BREAK  = 1 << 10     # [10]   EBREAK 発生 (RO)


# ---------------------------------------------------------------------------
# CPU 制御
# ---------------------------------------------------------------------------

def halt_cpu(driver, timeout: float = 2.0) -> bool:
    """
    CPU を停止し HALTED 状態になるまで待機する。

    Args:
        driver:  AXIUARTDriver インスタンス (open 済み)
        timeout: タイムアウト秒数 (デフォルト: 2.0)

    Returns:
        True: halt 完了。 False: タイムアウト。
    """
    import axiuart_driver.registers as _reg
    driver.write_reg32(_reg.REG_CPU_MEM_CTRL, _CPU_HALT)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if driver.read_reg32(_reg.REG_CPU_MEM_CTRL) & _CPU_HALTED:
            return True
        time.sleep(0.01)
    return False


def run_cpu(driver) -> None:
    """CPU 停止を解除して実行を開始する。"""
    import axiuart_driver.registers as _reg
    driver.write_reg32(_reg.REG_CPU_MEM_CTRL, _CPU_RUN)


def cpu_status(driver) -> dict:
    """
    CPU 状態を読み取る。

    Returns:
        dict: {
            'halted': bool,   # CPU 停止中
            'break':  bool,   # EBREAK 発生
            'busy':   bool,   # デバッグIF 使用中
            'raw':    int,    # REG_CPU_MEM_CTRL 生値
        }
    """
    import axiuart_driver.registers as _reg
    raw = driver.read_reg32(_reg.REG_CPU_MEM_CTRL)
    return {
        "halted": bool(raw & _CPU_HALTED),
        "break":  bool(raw & _CPU_BREAK),
        "busy":   bool(raw & _BUSY),
        "raw":    raw,
    }


def wait_for_ebreak(driver, timeout: float = 5.0) -> bool:
    """
    CPU が EBREAK を実行して停止するまで待機する。

    Args:
        timeout: タイムアウト秒数

    Returns:
        True: EBREAK 検出。 False: タイムアウト (EBREAK なし)。
    """
    import axiuart_driver.registers as _reg
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        raw = driver.read_reg32(_reg.REG_CPU_MEM_CTRL)
        if (raw & _CPU_HALTED) and (raw & _CPU_BREAK):
            return True
        time.sleep(0.01)
    return False


# ---------------------------------------------------------------------------
# BRAM アクセス (デバッグ IF 経由)
# ---------------------------------------------------------------------------

def _wait_idle(driver, timeout: float = 1.0) -> None:
    """デバッグ IF の BUSY が落ちるまで待機 (内部用)。"""
    import axiuart_driver.registers as _reg
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not (driver.read_reg32(_reg.REG_CPU_MEM_CTRL) & _BUSY):
            return
        time.sleep(0.001)
    raise TimeoutError("Memory controller busy timeout")


def write_word(driver, cpu_addr: int, data: int) -> None:
    """
    BRAM へ 32-bit ワードを書き込む (デバッグ IF 経由)。
    CPU halt 状態で呼び出すこと。

    Args:
        cpu_addr: CPU バイトアドレス (4 バイトアライン, 例: 0x80000000)
        data:     書き込む 32-bit データ
    """
    import axiuart_driver.registers as _reg
    driver.write_reg32(_reg.REG_CPU_MEM_ADDR,  cpu_addr)
    driver.write_reg32(_reg.REG_CPU_MEM_WDATA, data)
    driver.write_reg32(_reg.REG_CPU_MEM_CTRL,
                       _CPU_HALT | _WRITE_REQ | _BYTE_ALL)
    _wait_idle(driver)


def read_word(driver, cpu_addr: int) -> int:
    """
    BRAM から 32-bit ワードを読み出す (デバッグ IF 経由)。
    CPU halt 状態で呼び出すこと。

    Args:
        cpu_addr: CPU バイトアドレス (4 バイトアライン)

    Returns:
        読み出した 32-bit データ
    """
    import axiuart_driver.registers as _reg
    driver.write_reg32(_reg.REG_CPU_MEM_ADDR, cpu_addr)
    driver.write_reg32(_reg.REG_CPU_MEM_CTRL,
                       _CPU_HALT | _READ_REQ | _BYTE_ALL)
    _wait_idle(driver)
    return driver.read_reg32(_reg.REG_CPU_MEM_RDATA)


def write_program(driver, instructions: list,
                  base: int = BRAM_BASE) -> None:
    """
    命令リストを BRAM へ書き込む。

    Args:
        instructions: エンコード済み 32-bit 命令のリスト
        base:         書き込み先ベースアドレス (デフォルト: BRAM_BASE = 0x80000000)
    """
    for i, insn in enumerate(instructions):
        write_word(driver, base + i * 4, insn)


def verify_program(driver, instructions: list,
                   base: int = BRAM_BASE) -> tuple:
    """
    書き込んだプログラムを読み返して検証する。

    Returns:
        (ok, mismatches)
        ok:         全ワード一致のとき True
        mismatches: 不一致リスト [(addr, expected, actual), ...]
    """
    mismatches = []
    for i, expected in enumerate(instructions):
        addr   = base + i * 4
        actual = read_word(driver, addr)
        if actual != expected:
            mismatches.append((addr, expected, actual))
    return len(mismatches) == 0, mismatches


def memory_sanity_check(driver) -> bool:
    """
    BRAM の R/W 動作確認 (既知パターンを書き込んで読み返す)。
    BRAM 末尾付近 (0x80003F00–0x80003F0C) を使用。

    Returns:
        True: 全パターン一致。 False: 不一致あり。
    """
    patterns = [
        (0x8000_3F00, 0xDEAD_BEEF),
        (0x8000_3F04, 0xCAFE_BABE),
        (0x8000_3F08, 0x1234_5678),
        (0x8000_3F0C, 0xA5A5_A5A5),
    ]
    ok = True
    for addr, pat in patterns:
        write_word(driver, addr, pat)
        actual = read_word(driver, addr)
        if actual != pat:
            print(f"    [FAIL] 0x{addr:08X}: expected=0x{pat:08X} actual=0x{actual:08X}")
            ok = False
        else:
            print(f"    [OK]   0x{addr:08X}: 0x{pat:08X}")
    return ok


# ---------------------------------------------------------------------------
# レジスタファイル読み出し
# ---------------------------------------------------------------------------

# RV32I ABI レジスタ名
_ABI_NAMES = [
    "zero", "ra",  "sp",  "gp",  "tp",  "t0",  "t1",  "t2",
    "s0",   "s1",  "a0",  "a1",  "a2",  "a3",  "a4",  "a5",
    "a6",   "a7",  "s2",  "s3",  "s4",  "s5",  "s6",  "s7",
    "s8",   "s9",  "s10", "s11", "t3",  "t4",  "t5",  "t6",
]


def read_register(driver, reg_idx: int) -> int:
    """
    CPU レジスタファイルから 1 レジスタを読み出す (デバッグ IF)。
    CPU halt 状態で呼び出すこと。

    Args:
        reg_idx: レジスタ番号 (0–31, x0 は常に 0)

    Returns:
        レジスタ値 (32-bit)
    """
    import axiuart_driver.registers as _reg
    driver.write_reg32(_reg.REG_DBG_RF_ADDR, reg_idx & 0x1F)
    return driver.read_reg32(_reg.REG_DBG_RF_DATA)


def read_all_registers(driver) -> list:
    """
    x0–x31 全レジスタを読み出す。

    Returns:
        32 要素のリスト [x0_val, x1_val, ..., x31_val]
    """
    return [read_register(driver, i) for i in range(32)]


def format_regfile(values: list) -> str:
    """
    レジスタファイルを ABI 名付きの表形式でフォーマットする。

    Args:
        values: read_all_registers() の戻り値

    Returns:
        表示用文字列
    """
    lines = []
    lines.append(f"  {'reg':<5} {'ABI':<6} {'hex':>10}  {'dec (signed)':>13}")
    lines.append("  " + "-" * 42)
    for i, val in enumerate(values):
        signed = val if val < 0x8000_0000 else val - 0x1_0000_0000
        lines.append(
            f"  x{i:<4d} {_ABI_NAMES[i]:<6} 0x{val:08X}  {signed:>13}"
        )
    return "\n".join(lines)
