# software/ 開発ガイド

FPGA (Zybo Z7-20 / AXIUART_RV32I) 向けホストスクリプトの開発リファレンス。

---

## パッケージ構成

```
software/
├── axiuart_driver/             # レイヤ1: UART通信・レジスタアクセス (ライブラリ)
│   ├── axiuart_driver.py       #   AXIUARTDriver クラス
│   ├── protocol.py             #   フレーム組み立て・解析
│   ├── registers.py            #   レジスタアドレス定数 (自動生成)
│   └── tools/gen_registers.py  #   registers.py 再生成ツール
│
├── rv32i/                      # レイヤ2: RV32I CPU制御・命令生成 (ライブラリ)
│   ├── encoder.py              #   RV32I命令エンコーダ (純計算、外部依存なし)
│   ├── cpu.py                  #   CPU制御 + BRAM R/W (axiuart_driver 必要)
│   └── examples/
│       └── generate_comprehensive_rv32i_test.py  # UVM Stage1テスト用生成スクリプト
│
└── exec/                       # 実行スクリプト (直接 python で実行)
    ├── led_blink.py            #   LEDナイトライダー (HW動作確認)
    ├── test_driver.py          #   ドライバ接続テスト (5テスト)
    ├── regfile_dump.py         #   CPUレジスタファイル (x0-x31) ダンプ
    └── computation_test.py     #   RV32I計算結果検証 (sum100/fibonacci/bitcount)
```

---

## 使い分け

| 用途 | 使うもの |
|------|----------|
| レジスタ読み書き、バースト転送 | `axiuart_driver.AXIUARTDriver` |
| CPU halt/run、BRAM アクセス | `rv32i.cpu` |
| RV32I 機械語プログラムの生成 | `rv32i.encoder.RV32IInstructionEncoder` |
| 実機動作確認・デバッグ | `exec/` 配下のスクリプト |

---

## exec/ スクリプト

### led_blink.py — LED ナイトライダー

```powershell
cd software/exec
python led_blink.py --port COM3
python led_blink.py --port COM3 --delay-ms 500 --verify --dump
```

フロー: halt → BRAM書き込み → run → PERF モニタ (Ctrl+C で停止)

---

### test_driver.py — ドライバ接続テスト

接続確認・TEST レジスタ R/W・バースト転送の5テストを実行する。
新ビットストリーム書き込み直後の疎通確認に使う。

```powershell
python test_driver.py --port COM3
python test_driver.py --port COM3 --no-debug   # ログなし
```

---

### regfile_dump.py — レジスタファイルダンプ

CPU halt 後に x0–x31 を ABI 名付きテーブルで表示する。
EBREAK 停止後の計算結果確認やバグ調査に使う。

```powershell
python regfile_dump.py --port COM3
python regfile_dump.py --port COM3 --perf        # PERF カウンタも表示
python regfile_dump.py --port COM3 --no-halt     # 既に halt 済みの場合
```

出力例:
```
  reg   ABI    hex          dec (signed)
  ──────────────────────────────────────────
  x0    zero   0x00000000              0
  x1    ra     0x80000034   -2147483596
  x2    sp     0x00000000              0
  ...
  x10   a0     0x000013BA           5050   ← 計算結果
```

---

### computation_test.py — RV32I 計算結果検証

決定論的プログラムを実行して x10 (a0) の結果を期待値と比較する。

```powershell
python computation_test.py --port COM3                # 全テスト
python computation_test.py --port COM3 --test sum100
python computation_test.py --port COM3 --test fibonacci
python computation_test.py --port COM3 --test bitcount --dump
```

| テスト名 | 内容 | 期待値 |
|----------|------|--------|
| `sum100` | 1 + 2 + ... + 100 | 5050 (0x13BA) |
| `fibonacci` | fib(10) | 55 (0x37) |
| `bitcount` | popcount(0xA5A5A5A5) | 16 (0x10) |

---

## 新規スクリプトのテンプレート

```python
#!/usr/bin/env python3
"""スクリプトの目的"""

import sys, os, argparse

_exec_dir = os.path.dirname(os.path.abspath(__file__))
_sw_dir   = os.path.dirname(_exec_dir)   # software/
sys.path.insert(0, _sw_dir)
sys.path.insert(0, os.path.join(_sw_dir, 'rv32i'))  # encoder を直接 import する場合

from axiuart_driver import AXIUARTDriver, AXIUARTException
import axiuart_driver.registers as _reg
from rv32i.cpu import halt_cpu, run_cpu, write_program, wait_for_ebreak, read_register
from encoder import RV32IInstructionEncoder

parser = argparse.ArgumentParser()
parser.add_argument("--port", required=True)
parser.add_argument("--baud", type=int, default=115200)
args = parser.parse_args()

enc = RV32IInstructionEncoder()
program = [
    enc.addi(10, 0, 42),   # x10 = 42
    enc.ebreak(),          # 停止
]

with AXIUARTDriver(args.port, args.baud) as driver:
    halt_cpu(driver)
    write_program(driver, program)
    run_cpu(driver)
    wait_for_ebreak(driver)
    result = read_register(driver, 10)   # x10 = a0
    print(f"x10 = {result}")
```

---

## レイヤ2: `rv32i.cpu` — CPU 制御 API

```python
from rv32i.cpu import (
    halt_cpu,             # CPU 停止 (REG_CPU_MEM_CTRL bit8, HALTED ポーリング)
    run_cpu,              # CPU 実行開始 (bit7)
    cpu_status,           # {'halted', 'break', 'busy', 'raw'}
    wait_for_ebreak,      # EBREAK 待機 (timeout あり)
    write_word,           # BRAM へ 1 ワード書き込み
    read_word,            # BRAM から 1 ワード読み出し
    write_program,        # 命令リスト → BRAM 連続書き込み
    verify_program,       # 書き込み後読み返し検証 → (ok, mismatches)
    memory_sanity_check,  # BRAM R/W 動作確認 (既知パターン 4 種)
    read_register,        # CPUレジスタ読み出し (REG_DBG_RF_ADDR/DATA)
    read_all_registers,   # x0-x31 全レジスタ読み出し → list[32]
    format_regfile,       # ABI名付きテーブル文字列生成
    BRAM_BASE,            # 0x80000000
    LED_ADDR,             # 0x8000407C
    CLK_MHZ,              # 125
)
```

---

## レイヤ1: `axiuart_driver` — UART通信 API

```python
from axiuart_driver import AXIUARTDriver, AXIUARTException
import axiuart_driver.registers as reg

with AXIUARTDriver('COM3', baudrate=115200) as driver:
    val = driver.read_reg32(reg.REG_VERSION)
    driver.write_reg32(reg.REG_TEST_0, 0xDEAD)
    driver.write_burst(reg.REG_TEST_0, [0x1, 0x2, 0x3, 0x4])
    data = driver.read_burst(reg.REG_TEST_0, count=4)
```

**主要レジスタ (register_map/axiuart_registers.json より自動生成):**

| 定数 | アドレス | 説明 |
|------|----------|------|
| `REG_VERSION` | `0x101C` | HW バージョン (RO) |
| `REG_REVISION` | `0x223C` | HW リビジョン日付 (RO) |
| `REG_STATUS` | `0x1004` | ブリッジステータス (RO) |
| `REG_TEST_0` | `0x1020` | R/W テストレジスタ |
| `REG_CPU_MEM_ADDR` | `0x2228` | BRAM アクセスアドレス |
| `REG_CPU_MEM_WDATA` | `0x222C` | BRAM 書き込みデータ |
| `REG_CPU_MEM_RDATA` | `0x2230` | BRAM 読み出しデータ (RO) |
| `REG_CPU_MEM_CTRL` | `0x2234` | CPU 制御 + BRAM アクセス制御 |
| `REG_PERF_CYCLE_COUNT` | `0x2260` | サイクルカウンタ (RO) |
| `REG_PERF_INSN_COUNT` | `0x2264` | 命令カウンタ (RO) |
| `REG_DBG_RF_ADDR` | `0x2270` | レジスタ読み出しアドレス |
| `REG_DBG_RF_DATA` | `0x2274` | レジスタ読み出しデータ (RO) |

---

## メモリマップ (CPU 空間)

| 範囲 | 説明 |
|------|------|
| `0x80000000 - 0x80003FFF` | BRAM (16KB, リセットベクタ) |
| `0x8000407C` | LED MMIO (`SW x11, 0(x10)` → bit[3:0] = LED[3:0]) |

---

## 動作確認済みスクリプト

| スクリプト | 確認日 | 内容 |
|-----------|--------|------|
| `exec/test_driver.py` | 2026-02-21 | 全5テスト PASS (接続・R/W・バースト) |
| `exec/led_blink.py` | 2026-02-21 | LED ナイトライダー HW 動作確認 |
