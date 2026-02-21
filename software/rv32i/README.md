# RV32I Control Package

Production-ready Python package for RV32I instruction generation and CPU control via AXIUART bridge.

## Features

- **Instruction Encoding**: Complete RV32I base ISA encoder (R/I/S/B/U/J-type instructions)
- **CPU Control**: Halt, run, reset, and program loading via debug interface
- **Memory Access**: Read/write CPU memory via UART-AXI bridge
- **Pattern Generators**: Pre-built LED animation patterns (blink, counter, knight rider)
- **CLI Demo**: Interactive command-line tool for LED control

## Installation

No installation required - import directly from repository:

```python
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from rv32i import RV32IInstructionEncoder, halt_cpu, run_cpu, write_program
from axiuart_driver import AXIUARTDriver
```

## Quick Start

### LED Blink (Lチカ) - 実機動作確認スクリプト

**`led_blink.py`** は FPGA 実機動作確認用のスタンドアロンスクリプトです。
UART 経由で接続し、RV32I CPU にナイトライダー LED プログラムを書き込んで実行します。

```bash
# 基本実行 (COM3 ポート)
python led_blink.py --port COM3

# Linux/Mac の場合
python led_blink.py --port /dev/ttyUSB0

# メモリ R/W 動作確認付き (推奨)
python led_blink.py --port COM3 --verify

# 点灯間隔を変える (デフォルト 250ms)
python led_blink.py --port COM3 --delay-ms 500

# BRAM 内容をダンプ表示
python led_blink.py --port COM3 --dump

# メモリサニティチェックのみ実行
python led_blink.py --port COM3 --mem-check
```

コマンドラインオプション:

| オプション | デフォルト | 説明 |
| --- | --- | --- |
| `--port PORT` | (必須) | シリアルポート (COM3 / /dev/ttyUSB0 等) |
| `--baud BAUD` | 115200 | ボーレート |
| `--delay-ms MS` | 250 | LED 切り替え間隔 [ms] |
| `--verify` | - | メモリ書き込み後に読み返し検証を行う |
| `--dump` | - | 書き込んだプログラムの BRAM ダンプを表示 |
| `--mem-check` | - | メモリサニティチェックのみ実行 (CPU は起動しない) |

実行フロー:

```text
1. UART 接続 (axiuart_driver 経由)
2. CPU halt (デバッグインターフェース使用)
3. BRAM メモリ R/W 確認 (--verify / --mem-check 時)
4. ナイトライダープログラム書き込み (15命令, 60バイト)
5. CPU run → LED アニメーション開始
   パターン: 0001 → 0010 → 0100 → 1000 → 繰り返し
```

実行例:

```text
======================================================================
AXIUART_RV32I LED Blink (Lチカ) - 実機動作確認
======================================================================
[CONNECT] COM3 @ 115200 baud
[OK] UART 接続成功

[HALT] CPU 停止中...
[OK] CPU 停止完了

[PROGRAM] ナイトライダープログラム生成 (遅延: 250ms @ 125MHz)
  命令数: 15 (60 bytes)
  遅延カウント: 15,625,000

[LOAD] BRAM 書き込み中...
  [0x80000000] 0x80004537 (LUI  x10, 0x80004)
  [0x80000004] 0x07C50513 (ADDI x10, x10, 0x7C)
  ...
[OK] プログラム書き込み完了

[RUN] CPU 実行開始
[OK] LED アニメーション動作中 → Ctrl+C で停止
```

### Basic LED Control (ライブラリとして使用)

```python
from rv32i import RV32IInstructionEncoder, halt_cpu, run_cpu, write_program
from axiuart_driver import AXIUARTDriver

# Create encoder
encoder = RV32IInstructionEncoder()

# Generate simple LED program
# LED MMIO: 0x8000407C (CPU space)
program = [
    encoder.lui(15, 0x80004),    # x15 = 0x80004000 (LED base address)
    encoder.addi(16, 15, 0x7C),  # x16 = 0x8000407C (LED MMIO register)
    encoder.addi(17, 0, 0x5),    # x17 = 0x5 (LED pattern 0101)
    encoder.sw(17, 0, 16),       # MEM[x16+0] = x17 (write to LED)
    encoder.ebreak()             # Halt execution
]

# Execute on FPGA
with AXIUARTDriver('COM3', 115200) as driver:
    halt_cpu(driver)
    write_program(driver, program, start_addr=0)
    run_cpu(driver)
```

### Using Pattern Generators

```python
from rv32i import generate_led_blink, halt_cpu, run_cpu, write_program
from axiuart_driver import AXIUARTDriver

# Generate blinking pattern (0x5 <-> 0xA)
program = generate_led_blink(value1=0x5, value2=0xA, delay_cycles=10000000)

with AXIUARTDriver('COM3', 115200) as driver:
    halt_cpu(driver)
    write_program(driver, program)
    run_cpu(driver)
```

### CLI Demo

```bash
# Simple toggle pattern
python examples/led_demo.py --port COM3 --pattern simple

# Binary counter (0-15)
python examples/led_demo.py --port COM3 --pattern counter

# Knight rider effect
python examples/led_demo.py --port COM3 --pattern blink
```

## API Reference

### RV32IInstructionEncoder

Complete RV32I instruction encoder with methods for all base ISA instructions.

#### R-type (register-register)

- `add(rd, rs1, rs2)` - Add
- `sub(rd, rs1, rs2)` - Subtract
- `sll(rd, rs1, rs2)` - Shift left logical
- `slt(rd, rs1, rs2)` - Set less than
- `sltu(rd, rs1, rs2)` - Set less than unsigned
- `xor(rd, rs1, rs2)` - XOR
- `srl(rd, rs1, rs2)` - Shift right logical
- `sra(rd, rs1, rs2)` - Shift right arithmetic
- `or_(rd, rs1, rs2)` - OR
- `and_(rd, rs1, rs2)` - AND

#### I-type (immediate)

- `addi(rd, rs1, imm)` - Add immediate
- `slti(rd, rs1, imm)` - Set less than immediate
- `sltiu(rd, rs1, imm)` - Set less than immediate unsigned
- `xori(rd, rs1, imm)` - XOR immediate
- `ori(rd, rs1, imm)` - OR immediate
- `andi(rd, rs1, imm)` - AND immediate
- `slli(rd, rs1, shamt)` - Shift left logical immediate
- `srli(rd, rs1, shamt)` - Shift right logical immediate
- `srai(rd, rs1, shamt)` - Shift right arithmetic immediate
- `lb(rd, rs1, imm)` - Load byte
- `lh(rd, rs1, imm)` - Load halfword
- `lw(rd, rs1, imm)` - Load word
- `lbu(rd, rs1, imm)` - Load byte unsigned
- `lhu(rd, rs1, imm)` - Load halfword unsigned
- `jalr(rd, rs1, imm)` - Jump and link register
- `ebreak()` - Breakpoint

#### S-type (store)

Note: argument order is `(rs2, imm, rs1)` — `imm` is offset, `rs1` is base register.

- `sb(rs2, imm, rs1)` - Store byte
- `sh(rs2, imm, rs1)` - Store halfword
- `sw(rs2, imm, rs1)` - Store word

#### B-type (branch)

- `beq(rs1, rs2, offset)` - Branch if equal
- `bne(rs1, rs2, offset)` - Branch if not equal
- `blt(rs1, rs2, offset)` - Branch if less than
- `bge(rs1, rs2, offset)` - Branch if greater or equal
- `bltu(rs1, rs2, offset)` - Branch if less than unsigned
- `bgeu(rs1, rs2, offset)` - Branch if greater or equal unsigned

#### U-type (upper immediate)

- `lui(rd, imm)` - Load upper immediate
- `auipc(rd, imm)` - Add upper immediate to PC

#### J-type (jump)

- `jal(rd, offset)` - Jump and link

### CPU Control Functions

#### halt_cpu(driver)

- Halt CPU execution via CPU_MEM_CTRL register
- Waits for cpu_halted status bit
- Returns: None

#### run_cpu(driver)

- Resume CPU execution
- Clears cpu_halt bit, sets cpu_run bit
- Returns: None

#### reset_cpu(driver)

- Soft reset CPU (halt + clear PC + run)
- Returns: None

#### write_program(driver, instructions, start_addr=0)

- Write instruction list to CPU memory
- Args: instructions (list of 32-bit encoded instructions), start_addr (byte address, default 0)
- Returns: None

#### get_cpu_status(driver)

- Read CPU control register status
- Returns: dict with keys `halted`, `break`, `busy`

### Memory Access Functions

#### write_cpu_mem(driver, addr, data)

- Write 32-bit word to CPU memory
- Args: addr (4-byte-aligned byte address), data (32-bit value)
- Returns: None

#### read_cpu_mem(driver, addr)

- Read 32-bit word from CPU memory
- Args: addr (4-byte-aligned byte address)
- Returns: 32-bit value

#### verify_memory(driver, addr, expected)

- Verify memory contents match expected value
- Args: addr (byte address), expected (32-bit value)
- Returns: bool (True if match)

### Pattern Generators

#### generate_led_blink(value1, value2, delay_cycles)

- Generate toggling pattern between two values
- Returns: List of RV32I instructions

#### generate_led_count(start, end, delay_cycles)

- Generate binary counter pattern
- Returns: List of RV32I instructions

#### generate_led_knight_rider()

- Generate knight rider shift pattern (1→2→4→8→1)
- Returns: List of RV32I instructions

## Architecture

### Memory Map (CPU Perspective)

- **BRAM**: `0x80000000` - `0x80003FFF` (16KB, reset vector)
- **LED MMIO**: `0x8000407C` (bit[3:0] → LED[3:0])

### Register Map (UART-AXI Perspective)

- **CPU_MEM_ADDR** (`0x2228`): Memory address for debug access
- **CPU_MEM_WDATA** (`0x222C`): Write data
- **CPU_MEM_RDATA** (`0x2230`): Read data
- **CPU_MEM_CTRL** (`0x2234`): Control register — `bit[9]`=cpu_halted(RO), `bit[8]`=cpu_halt(W), `bit[7]`=cpu_run(W), `bit[6]`=busy(RO), `bit[5]`=write_req(W1P), `bit[4]`=read_req(W1P), `bit[3:0]`=byte_enables(W)

## Directory Structure

```text
software/rv32i/
├── __init__.py           # Package exports
├── README.md             # This file
├── encoder.py            # RV32IInstructionEncoder class
├── cpu_control.py        # CPU control functions
├── memory.py             # Memory access helpers
├── patterns.py           # LED pattern generators
├── led_blink.py          # Hardware bring-up / Lチカ script
└── examples/
    ├── __init__.py       # Examples package
    └── led_demo.py       # CLI demonstration
```

## Examples

See [examples/led_demo.py](examples/led_demo.py) for complete working demonstrations.

## Dependencies

- **axiuart_driver**: UART-AXI bridge communication (required)
- **pyserial**: Serial port access (installed by axiuart_driver)

## License

Follows parent project licensing (TD4UART repository).

## Development

### Testing

```bash
# Unit tests for encoder (future)
python -m pytest tests/test_encoder.py

# Integration test with mock driver (future)
python -m pytest tests/test_integration.py
```

### Auto-generation from ISA JSON

Future enhancement: Generate encoder methods from `isa/rv32i_isa.json` following SSOT principle.

## References

- RISC-V ISA Specification: [riscv.org/specifications](https://riscv.org/specifications/)
- AXIUART Driver: [../axiuart_driver/README.md](../axiuart_driver/README.md)
- Register Map: [../../register_map/axiuart_registers.json](../../register_map/axiuart_registers.json)
