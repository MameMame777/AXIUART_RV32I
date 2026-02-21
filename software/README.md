# software/ 開発ガイド

FPGA (Zybo Z7-20 / AXIUART_RV32I) 向けホストスクリプトの開発リファレンス。

---

## パッケージ構成

```
software/
├── axiuart_driver/          # レイヤ1: UART通信・レジスタアクセス
│   ├── axiuart_driver.py    # AXIUARTDriver クラス
│   ├── protocol.py          # フレーム組み立て・解析
│   ├── registers.py         # レジスタアドレス定数 (自動生成)
│   └── tools/gen_registers.py  # registers.py の再生成ツール
│
└── rv32i/                   # レイヤ2: RV32I CPUプログラム生成
    ├── encoder.py           # RV32I命令エンコーダ
    ├── led_blink.py         # HW動作確認スクリプト (実機確認済み)
    └── examples/
        └── generate_comprehensive_rv32i_test.py  # UVM Stage1テスト用
```

---

## 使い分け

| 用途 | 使うもの |
|------|----------|
| レジスタ読み書き、CPU制御、デバッグ | `axiuart_driver` |
| BRAMに書き込むRV32Iプログラムの生成 | `rv32i.encoder` |
| FPGAへの接続 + プログラム書き込み + 実行 | 両方 |

### レイヤ1: `axiuart_driver` — FPGA通信

UART経由でAXI4-Liteアドレス空間への読み書きを行う。
CPUの実行制御やBRAMアクセスもこのレイヤを通じて行う。

```python
from axiuart_driver import AXIUARTDriver
import axiuart_driver.registers as reg

driver = AXIUARTDriver('COM3', baudrate=115200)
driver.open()

# --- 基本操作 ---
val = driver.read_reg32(reg.REG_VERSION)       # レジスタ読み込み
driver.write_reg32(reg.REG_TEST_0, 0xDEAD)    # レジスタ書き込み

# --- バースト転送 ---
driver.write_burst(reg.REG_TEST_0, [0x1, 0x2, 0x3, 0x4])
data = driver.read_burst(reg.REG_TEST_0, count=4)

# --- CPU制御 ---
driver.write_reg32(reg.REG_CPU_MEM_CTRL, 0x100)   # halt (bit8=1)
driver.write_reg32(reg.REG_CPU_MEM_CTRL, 0x080)   # run  (bit7=1)

driver.close()
```

**主要レジスタ (registers.py より):**

| 定数 | アドレス | 説明 |
|------|----------|------|
| `REG_VERSION` | `0x101C` | ハードウェアバージョン (RO) |
| `REG_REVISION` | `0x223C` | リビジョン日付 (RO) |
| `REG_STATUS` | `0x1004` | ブリッジステータス (RO) |
| `REG_TEST_0` | `0x1020` | R/Wテストレジスタ |
| `REG_CPU_MEM_ADDR` | `0x2228` | BRAMアクセスアドレス |
| `REG_CPU_MEM_WDATA` | `0x222C` | BRAM書き込みデータ |
| `REG_CPU_MEM_RDATA` | `0x2230` | BRAM読み出しデータ (RO) |
| `REG_CPU_MEM_CTRL` | `0x2234` | CPU制御・BRAMアクセス制御 |
| `REG_PERF_CYCLE_COUNT` | `0x2260` | サイクルカウンタ (RO) |
| `REG_PERF_INSN_COUNT` | `0x2264` | 命令カウンタ (RO) |
| `REG_DBG_RF_ADDR/DATA` | `0x2270/74` | レジスタファイル読み出し |
| `REG_TRACE_*` | `0x2280-A0` | トレースバッファ |

`REG_CPU_MEM_CTRL` のビットフィールド:
```
[3:0]  byte_enables    書き込みバイトイネーブル (通常 0xF)
[4]    read_req        W1P: BRAMから読み出しトリガ
[5]    write_req       W1P: BRAMへ書き込みトリガ
[6]    busy            RO: アクセス中
[7]    cpu_run         CPU実行開始
[8]    cpu_halt        CPU停止要求
[9]    cpu_halted      RO: CPU停止完了
[10]   cpu_break       RO: EBREAK検出
```

---

### レイヤ2: `rv32i.encoder` — RV32I命令生成

CPUに書き込む機械語プログラムを Python で生成する。
**FPGAとの通信機能は持たない**。純粋な計算モジュール。

```python
from encoder import RV32IInstructionEncoder

enc = RV32IInstructionEncoder()

# 命令生成 (戻り値は 32-bit int)
insns = [
    enc.lui(rd=10, imm=0x80004),        # LUI  x10, 0x80004
    enc.addi(rd=10, rs1=10, imm=0x7C),  # ADDI x10, x10, 124  → x10 = 0x8000407C (LED)
    enc.addi(rd=11, rs1=0,  imm=1),     # ADDI x11, x0,  1
    enc.sw(rs2=11, imm=0, rs1=10),      # SW   x11, 0(x10)    → LED = x11
    enc.jal(rd=0, offset=-4),           # JAL  x0, -4         → 無限ループ
]
```

**対応命令:** RV32I 全命令 (R/I/S/B/U/J 型 + CSR + SYSTEM)

---

## 新規スクリプトのテンプレート

```python
#!/usr/bin/env python3
"""スクリプトの目的"""

import sys
import os

# axiuart_driver はパス追加が必要 (rv32i/ から実行する場合)
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from axiuart_driver import AXIUARTDriver, AXIUARTException
import axiuart_driver.registers as reg

# encoder が必要な場合 (rv32i/ 配下から実行)
from encoder import RV32IInstructionEncoder

PORT = 'COM3'
BAUD = 115200

driver = AXIUARTDriver(PORT, baudrate=BAUD)
try:
    driver.open()

    # 1. CPU停止
    driver.write_reg32(reg.REG_CPU_MEM_CTRL, 0x100)
    # (halt完了待ち: REG_CPU_MEM_CTRL bit9 が 1 になるまでポーリング)

    # 2. プログラム生成
    enc = RV32IInstructionEncoder()
    program = [
        enc.addi(rd=1, rs1=0, imm=42),
        enc.ebreak(),
    ]

    # 3. BRAMに書き込み (1 word = 4 bytes)
    BRAM_BASE = 0x80000000
    for i, word in enumerate(program):
        addr = BRAM_BASE + i * 4
        driver.write_reg32(reg.REG_CPU_MEM_ADDR,  addr)
        driver.write_reg32(reg.REG_CPU_MEM_WDATA, word)
        driver.write_reg32(reg.REG_CPU_MEM_CTRL,  0x02F)  # write_req + byte_enables=0xF

    # 4. CPU実行
    driver.write_reg32(reg.REG_CPU_MEM_CTRL, 0x080)  # cpu_run

finally:
    if driver.serial and driver.serial.is_open:
        driver.close()
```

---

## メモリマップ (CPU空間)

| 範囲 | 説明 |
|------|------|
| `0x80000000 - 0x80003FFF` | BRAM (16KB, リセットベクタ) |
| `0x8000407C` | LED MMIO (`SW x11, 0(x10)` で bit[3:0] → LED[3:0]) |

---

## 動作確認済みスクリプト

| スクリプト | 確認日 | 内容 |
|-----------|--------|------|
| `axiuart_driver/test_driver.py` | 2026-02-21 | 全5テスト PASS (接続・R/W・バースト) |
| `rv32i/led_blink.py` | 2026-02-21 | LEDナイトライダー HW動作確認 |
