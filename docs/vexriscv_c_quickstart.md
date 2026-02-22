# C言語プログラム → FPGA実行 クイックスタート

VexRiscv (RV32I) コアが搭載された AXIUART_RV32I FPGA ボードで、  
C言語プログラムをコンパイルして実行するまでの手順です。

---

## 前提条件

| 項目 | 内容 |
|------|------|
| FPGA ボード | AXIUART_RV32I (Zynq-7020) |
| CPU コア | VexRiscv RV32I |
| BRAM サイズ | 8 KB (`0x80000000` – `0x80001FFF`) |
| LED MMIO | `0x8000407C` (bit[3:0] → LED[3:0]) |
| クロック | 125 MHz |
| UART ポート | COM3 @ 115200 bps |
| OS | Windows 10/11 (PowerShell 7 / pwsh) |
| Python | 3.x、`pyserial` インストール済み |

---

## 1. ツールチェーンのインストール

### xPack GNU RISC-V Embedded GCC (推奨)

1. [xPack GNU RISC-V Embedded GCC リリースページ](https://github.com/xpack-binutils/riscv-none-elf-gcc-xpack/releases) から最新の Windows x64 `.zip` をダウンロード

2. 任意の場所に展開  
   例: `C:\Users\<ユーザー名>\AppData\Local\xpack-riscv-none-elf-gcc-15.2.0-1\`

3. ブロック解除 (インターネットからダウンロードしたファイルに必要):
   ```powershell
   Get-ChildItem "C:\Users\<ユーザー名>\AppData\Local\xpack-riscv-none-elf-gcc-15.2.0-1\" -Recurse | Unblock-File
   ```

4. 動作確認:
   ```powershell
   & "C:\Users\<ユーザー名>\AppData\Local\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-gcc.exe" --version
   # riscv-none-elf-gcc (xPack GNU RISC-V Embedded GCC x86_64) 15.2.0
   ```

> **Note**: `PATH` に `\bin` を追加するか、`RISCV_TOOLCHAIN_BIN` 環境変数を設定することもできます。  
> ビルドスクリプトは以下の順序で GCC を自動検出します:
> 1. `$env:RISCV_TOOLCHAIN_BIN` 環境変数
> 2. `PATH` 内の `riscv-none-elf-gcc`
> 3. `%LOCALAPPDATA%\xpack-riscv-none-elf-gcc-*\` の自動スキャン (最新版優先)

---

## 2. プロジェクト構成

```
software/rv32i/c/
├── crt0.s          # ベアメタルスタートアップ (SP初期化・.bssゼロクリア)
├── rv32i_bram.ld   # リンカスクリプト (8KB BRAM @ 0x80000000)
└── led_blink.c     # サンプル: LED ナイトライダー

software/rv32i/
└── bin_loader.py   # .bin ファイル → list[int] ローダー (Python)

software/exec/
└── c_blink.py      # FPGA書き込み & 実行スクリプト

scripts/
└── build_c.ps1     # PowerShell ビルドスクリプト
```

---

## 3. ビルド手順

### 3-1. ビルドスクリプトを使う (推奨)

```powershell
# リポジトリルートから実行
pwsh -ExecutionPolicy Bypass -File "scripts/build_c.ps1" led_blink
```

成功時の出力例:
```
[TOOL] xPack インストール自動検出: C:\Users\...\xpack-riscv-none-elf-gcc-15.2.0-1\bin
============================================================
[BUILD] RV32I C ビルド: led_blink
============================================================
[CC]   コンパイル成功

[SIZE] セクションサイズ:
   text    data     bss     dec     hex filename
    152       0       0     152      98 led_blink.elf

[BIN]  led_blink.bin
       サイズ: 152 bytes (1.9% / 8KB BRAM)

[DONE] ビルド完了
```

### 3-2. 手動でビルドする

```powershell
$GCC = "riscv-none-elf-gcc"   # PATH に GCC が通っている場合

cd software/rv32i/c

# コンパイル & リンク (ELF 生成)
& $GCC -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -Os `
       -T rv32i_bram.ld crt0.s led_blink.c `
       -o led_blink.elf

# ELF → raw binary 変換
riscv-none-elf-objcopy -O binary led_blink.elf led_blink.bin

# サイズ確認
riscv-none-elf-size led_blink.elf
```

---

## 4. ファイル説明

### `crt0.s` — スタートアップ

BRAM (8KB) レイアウト:

```
0x80000000  ┌─────────────────┐
            │  .text           │  コード
            │  .data           │  初期化済みグローバル変数
            │  .bss            │  未初期化グローバル変数 (ゼロクリア)
            ├─────────────────┤
0x80001FF0  │  ← Stack Top    │  スタックポインタ (下向きに伸びる)
0x80001FFF  └─────────────────┘
```

処理の流れ:
```
_start:
  1. SP = 0x80001FF0 に設定
  2. .bss セクションをゼロクリア
  3. main() 呼び出し
  4. 戻ったら無限ループ (halt)
```

### `rv32i_bram.ld` — リンカスクリプト

```ld
MEMORY {
  BRAM (rwx) : ORIGIN = 0x80000000, LENGTH = 8K
}
```

- `.text`, `.data`, `.bss` を BRAM に配置
- BRAMオーバーフロー時にリンクエラーで通知

### `led_blink.c` — LED ナイトライダー

```c
#define LED_ADDR   ((volatile unsigned int *)0x8000407CU)
#define DELAY_CYCLES  15625000U   // 125MHz × 250ms / 2サイクル/ループ

// パターン: 0001 → 0010 → 0100 → 1000 → 繰り返し
```

---

## 5. FPGA への書き込みと実行

```powershell
cd software/exec

# 書き込み + 検証 + 実行
python c_blink.py --port COM3 --verify
```

オプション:

| オプション | 説明 |
|-----------|------|
| `--port COM3` | UART ポート番号 (必須) |
| `--verify` | 書き込み後に読み戻し検証 |
| `--bin <path>` | .bin ファイルパスを指定 (省略時: `../rv32i/c/led_blink.bin`) |
| `--build` | 実行前に `build_c.ps1` を自動呼び出し |

成功時の出力例:
```
[UART] COM3 @ 115200 bps に接続中...
[UART] 接続 OK  VERSION=0x00010000  REVISION=0x20260103

[CPU]  halt 要求...
[CPU]  halt 完了  STATUS=0x00000300

[MEM]  BRAM 書き込み (38 words → 0x80000000)...
[MEM]  書き込み完了
[MEM]  読み返し検証中...
[MEM]  検証 OK (38 words 全一致)

[CPU]  実行開始... (PC = 0x80000000)
[CPU]  Running!

       LEDを確認してください: 0001 → 0010 → 0100 → 1000 → ...
       Ctrl+C で停止

[PERF] t=   5s  cycles= 628,433,262  insns= 114,515,113  IPC=0.182  halted=False
```

### パフォーマンス指標

| 指標 | 値 |
|------|----|
| クロック周波数 | ~126 MHz (計測値) |
| IPC | 0.182 (LED ナイトライダー) |
| BRAM 使用率 | 1.9% (152 / 8192 bytes) |

---

## 6. ビルドから実行までの一括フロー

```powershell
# リポジトリルートから1コマンドで完結
pwsh -ExecutionPolicy Bypass -File "scripts/build_c.ps1" led_blink
cd software/exec
python c_blink.py --port COM3 --build --verify
```

または `--build` オプションで自動ビルド:
```powershell
cd software/exec
python c_blink.py --port COM3 --build --verify
```

---

## 7. 新しいCプログラムの追加

1. `software/rv32i/c/` に `.c` ファイルを作成
2. `scripts/build_c.ps1` でビルド:
   ```powershell
   pwsh scripts/build_c.ps1 <プログラム名 (拡張子なし)>
   ```
3. `software/exec/c_blink.py` で実行:
   ```powershell
   python software/exec/c_blink.py --port COM3 --bin software/rv32i/c/<名前>.bin
   ```

> **制約**: BRAM は 8KB のみ。スタック + コード + データを合計 ~7.75KB 以内に収める必要があります。

---

## 8. トラブルシューティング

### GCC が見つからない

```
ERROR: riscv-none-elf-gcc が見つかりません
```

→ `RISCV_TOOLCHAIN_BIN` 環境変数を設定する:
```powershell
$env:RISCV_TOOLCHAIN_BIN = "C:\Users\<名前>\AppData\Local\xpack-riscv-none-elf-gcc-15.2.0-1\bin"
```

### Zone.Identifier ブロック (ダウンロードしたファイルに適用される Windows セキュリティ)

```
このシステムではスクリプトの実行が無効
```

→ `Unblock-File` を実行:
```powershell
Get-ChildItem "C:\Users\<名前>\AppData\Local\xpack-riscv-none-elf-gcc-15.2.0-1\" -Recurse | Unblock-File
```

### デバイスが見つからない

```
serial.SerialException: could not open port 'COM3'
```

→ デバイスマネージャーで正しいCOMポートを確認し `--port` オプションで指定する。

### BRAM オーバーフロー

```
ld: section `.text' will not fit in region `BRAM'
```

→ コードサイズを削減する (`-Os` フラグ確認、不要なデータ削除)。

---

## 関連ドキュメント

- [vexriscv_architecture.md](cpu/vexriscv_architecture.md) — VexRiscv アーキテクチャ
- [vexriscv_signal_reference.md](cpu/vexriscv_signal_reference.md) — 信号リファレンス
- [vexriscv_test_quickstart.md](vexriscv_test_quickstart.md) — アセンブリ/Pythonテスト手順
