#!/usr/bin/env python3
"""
bin_loader.py — raw binary (.bin) → list[int] ローダー

ELF から objcopy -O binary で生成した raw バイナリを
write_program() に渡せる 32-bit ワードリストに変換する。

使い方:
    from rv32i.bin_loader import load_bin
    instructions = load_bin("led_blink.bin")
    write_program(driver, instructions)
"""

import struct
import os


def load_bin(path: str) -> list:
    """
    raw binary ファイルを 32-bit ワードリストとして読み込む。

    Args:
        path: raw binary ファイルのパス (.bin)

    Returns:
        list[int]: 32-bit ワードのリスト (little-endian)
        末尾が 4 バイト未満の場合はゼロパディングする。

    Raises:
        FileNotFoundError: ファイルが存在しない場合
        ValueError: ファイルが空の場合
    """
    if not os.path.exists(path):
        raise FileNotFoundError(f"Binary file not found: {path}")

    with open(path, "rb") as f:
        data = f.read()

    if len(data) == 0:
        raise ValueError(f"Binary file is empty: {path}")

    # 4 バイト境界にパディング
    remainder = len(data) % 4
    if remainder != 0:
        data += b"\x00" * (4 - remainder)

    n_words = len(data) // 4
    words = list(struct.unpack(f"<{n_words}I", data))
    return words


def bin_size_check(path: str, max_bytes: int = 8192) -> None:
    """
    バイナリサイズが BRAM 容量を超えていないか確認する。

    Args:
        path: バイナリファイルのパス
        max_bytes: 最大許容バイト数 (デフォルト: 8192 = 8KB BRAM)

    Raises:
        ValueError: サイズが max_bytes を超えている場合
    """
    size = os.path.getsize(path)
    if size > max_bytes:
        raise ValueError(
            f"Binary too large: {size} bytes > BRAM limit {max_bytes} bytes "
            f"({size - max_bytes} bytes over)"
        )


if __name__ == "__main__":
    import sys
    if len(sys.argv) < 2:
        print(f"Usage: python {sys.argv[0]} <file.bin>")
        sys.exit(1)
    path = sys.argv[1]
    words = load_bin(path)
    size  = os.path.getsize(path)
    print(f"  File   : {path}")
    print(f"  Size   : {size} bytes ({size / 1024:.1f} KB)")
    print(f"  Words  : {len(words)}")
    print(f"  BRAM   : {size / 8192 * 100:.1f}% used (8KB)")
    print(f"  First 4: {[f'0x{w:08X}' for w in words[:4]]}")
