# AXIUART_Register_Block Register Map

**AUTO-GENERATED FILE - DO NOT EDIT MANUALLY**

- **Source:** `register_map/axiuart_registers.json`
- **Generated:** 2025-12-21 05:19:06
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
| CPU_DBG_CTRL | `0x1200` | `0x200` | RW | `0x00000000` | CPU debug control: halt/run/step requests, halt_on_reset, breakpoint global enable |
| CPU_DBG_STATUS | `0x1204` | `0x204` | RO | `0x00000001` | CPU debug status: halted/running, break/brk hit, halt reason |
| CPU_PC | `0x1208` | `0x208` | RW | `0x00000000` | CPU program counter (word address). Write allowed only when halted |
| CPU_SP | `0x120C` | `0x20C` | RW | `0x0000FFFE` | CPU stack pointer (word address). Write allowed only when halted |
| CPU_FLAGS | `0x1210` | `0x210` | RW | `0x00000000` | CPU flags (Z/N/C in low bits). Write allowed only when halted |
| CPU_REG_INDEX | `0x1214` | `0x214` | RW | `0x00000000` | CPU register index selector (0..7) |
| CPU_REG_DATA | `0x1218` | `0x218` | RW | `0x00000000` | CPU selected register data (16-bit). Write allowed only when halted |
| CPU_BP0_PC | `0x121C` | `0x21C` | RW | `0x00000000` | Breakpoint 0 PC match value (word address) |
| CPU_BP1_PC | `0x1220` | `0x220` | RW | `0x00000000` | Breakpoint 1 PC match value (word address) |
| CPU_BP_CTRL | `0x1224` | `0x224` | RW | `0x00000004` | Breakpoint control (BP0_EN/BP1_EN/BP_MATCH_FETCH) |
| CPU_MEM_ADDR | `0x1228` | `0x228` | RW | `0x00000000` | Debug memory address (word address) |
| CPU_MEM_WDATA | `0x122C` | `0x22C` | RW | `0x00000000` | Debug memory write data (16-bit in low bits) |
| CPU_MEM_RDATA | `0x1230` | `0x230` | RO | `0x00000000` | Debug memory read data (16-bit in low bits) |
| CPU_MEM_CTRL | `0x1234` | `0x234` | RW | `0x00000000` | Debug memory control: read/write request, auto-inc, busy/err |
| CPU_ID | `0x1238` | `0x238` | RO | `0x54443331` | CPU identification/version (ASCII 'TD31' placeholder) |

## Regeneration Instructions

To update this file after modifying the register map:

```bash
python software/axiuart_driver/tools/gen_registers.py --in register_map/axiuart_registers.json
```

## Access Types

- **RO:** Read-only
- **RW:** Read-write
