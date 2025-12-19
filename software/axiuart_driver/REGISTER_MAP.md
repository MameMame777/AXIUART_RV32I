# AXIUART_Register_Block Register Map

**AUTO-GENERATED FILE - DO NOT EDIT MANUALLY**

- **Source:** `register_map/axiuart_registers.json`
- **Generated:** 2025-12-18 22:27:25
- **Base Address:** `0x1000`
- **Stride:** 4 bytes

## Register Summary

| Name | Address | Offset | Access | Reset | Description |
|------|---------|--------|--------|-------|-------------|
| CONTROL | `0x1000` | `0x000` | RW | `0x00000000` | Control register - includes bridge reset control |
| STATUS | `0x1004` | `0x004` | RO | `0x00000000` | Status register - bridge busy and error code |
| CONFIG | `0x1008` | `0x008` | RW | `0x00000000` | Configuration register - baud rate and timeout |
| DEBUG | `0x100C` | `0x00C` | RW | `0x00000000` | Debug control register - debug mode selection |
| TX_COUNT | `0x1010` | `0x010` | RO | `0x00000000` | TX transaction counter (read-only) |
| RX_COUNT | `0x1014` | `0x014` | RO | `0x00000000` | RX transaction counter (read-only) |
| FIFO_STAT | `0x1018` | `0x018` | RO | `0x00000000` | FIFO status flags (read-only) |
| VERSION | `0x101C` | `0x01C` | RO | `0x00010000` | Hardware version register (read-only) |
| TEST_0 | `0x1020` | `0x020` | RW | `0x00000000` | Test register 0 - pure read/write test |
| TEST_1 | `0x1024` | `0x024` | RW | `0x00000000` | Test register 1 - pattern test |
| TEST_2 | `0x1028` | `0x028` | RW | `0x00000000` | Test register 2 - increment test |
| TEST_3 | `0x102C` | `0x02C` | RW | `0x00000000` | Test register 3 - mirror test |
| TEST_4 | `0x1040` | `0x040` | RW | `0x00000000` | Test register 4 - gap test |
| TEST_LED | `0x1044` | `0x044` | RW | `0x00000000` | 4-bit LED control register |
| TEST_5 | `0x1050` | `0x050` | RW | `0x00000000` | Test register 5 - larger gap test |
| TEST_6 | `0x1080` | `0x080` | RW | `0x00000000` | Test register 6 - even larger gap test |
| TEST_7 | `0x1100` | `0x100` | RW | `0x00000000` | Test register 7 - different range test |

## Regeneration Instructions

To update this file after modifying the register map:

```bash
python software/axiuart_driver/tools/gen_registers.py --in register_map/axiuart_registers.json
```

## Access Types

- **RO:** Read-only
- **RW:** Read-write
