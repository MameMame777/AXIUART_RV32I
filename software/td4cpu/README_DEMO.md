# TD4 CPU Interactive Demo Tool

FPGAハードウェアをインタラクティブに操作するためのデモツール

## 機能

### LEDデモ
1. **Lチカ（バイナリカウンター）** - 4ビットLEDで0-15をカウント表示
2. **チェイスパターン** - LEDが順番に点灯する追いかけパターン
3. **手動パターン設定** - 0-15の値でLEDパターンを直接設定

### CPUデモ
4. **ALU演算デモ** - ADD, SUB, AND, OR演算のデモンストレーション
5. **フィボナッチ数列** - TD4 CPUでフィボナッチ数列を計算
6. **CPUカウンター** - CPU制御のカウンター表示

### 情報表示
7. **CPU状態表示** - PC, SP, フラグ、実行状態を表示
8. **レジスタ表示** - R0-R7の値を表示
9. **トレースバッファ表示** - 最近実行された命令の履歴

### 制御
- **h** - CPUを停止
- **s** - 1命令だけ実行（シングルステップ）
- **q** - 終了

## 使い方

### インタラクティブモード
```bash
python software/td4cpu/interactive_demo.py --port COM3
```

メニューから番号を選んでデモを実行。

### 特定のデモを直接実行
```bash
# LEDチカチカ
python software/td4cpu/interactive_demo.py --port COM3 --demo led

# ALU演算デモ
python software/td4cpu/interactive_demo.py --port COM3 --demo alu

# フィボナッチ数列（n=10）
python software/td4cpu/interactive_demo.py --port COM3 --demo fib

# カウンターデモ
python software/td4cpu/interactive_demo.py --port COM3 --demo counter
```

## 動作例

### LED Lチカデモ
```
Running LED demo for 10.0 seconds (speed=0.50s)...
  LED: 0000 (0)
  LED: 0001 (1)
  LED: 0010 (2)
  ...
  LED: 1111 (15)
```

FPGAボード上の4個のLEDが2進数カウンターとして動作します。

### ALU演算デモ
```
Simple ALU Demo
  ✓ ADD : 5 op 3 = 8 (expected 8)
  ✓ SUB : 10 op 3 = 7 (expected 7)
  ✓ AND : 255 op 15 = 15 (expected 15)
  ✓ OR  : 240 op 15 = 255 (expected 255)
```

### フィボナッチ数列デモ
```
Fibonacci Demo: Computing first 10 numbers
Loading Fibonacci program...
Executing...

Results:
CPU Registers:
  R0 = 0x0037 (   55)
  R1 = 0x0022 (   34)
  ...

Fibonacci(10) = 55
```

## 必要なもの
- FPGAボード（TD4UART実装済み）
- USBシリアル接続（デフォルト: COM3 @ 115200 baud）
- Python 3.8以上
- axiuart_driverモジュール

## トラブルシューティング

### ポート接続エラー
```bash
python software/td4cpu/interactive_demo.py --port COM4  # ポート変更
```

### LEDが光らない
- ハードウェアのREG_TEST_LED（0x1044）が正しく接続されているか確認
- 物理的なLED接続を確認

### CPUデモが動かない
- CPU状態を確認: オプション「7」
- CPUをハルト: オプション「h」
- 最近のトレースを確認: オプション「9」

## カスタマイズ

新しいデモを追加するには：

```python
def demo_my_custom(self):
    """My custom demo"""
    print("Running my custom demo...")
    # Your code here
    self.cpu_halt()
    # Load program
    # Execute
    # Show results
```

`interactive_menu()`にメニュー項目を追加。

## 参考
- TD4 CPU ISA: `docs/specification_plan.md`
- レジスタマップ: `register_map/axiuart_registers.json`
- デバッグガイド: `sim/tests/TEST_TIMING_GUIDE.md`
