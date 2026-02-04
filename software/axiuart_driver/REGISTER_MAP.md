# AXIUART_Register_Block Register Map

**AUTO-GENERATED FILE - DO NOT EDIT MANUALLY**

- **Source:** `register_map/axiuart_registers.json`
- **Generated:** 2026-02-04 04:42:25
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
| CPU_MEM_ADDR | `0x2228` | `0x1228` | RW | `0x00000000` | RV32I CPU memory address (32-bit byte address, converted to word address [12:2] internally for 8KB RAM) |
| CPU_MEM_WDATA | `0x222C` | `0x122C` | RW | `0x00000000` | RV32I CPU memory write data (full 32-bit data) |
| CPU_MEM_RDATA | `0x2230` | `0x1230` | RO | `0x00000000` | RV32I CPU memory read data (full 32-bit data, captured after read operation) |
| CPU_MEM_CTRL | `0x2234` | `0x1234` | RW | `0x00000000` | RV32I CPU control and memory access: [3:0]=byte_enables, [4]=read_req(W1P), [5]=write_req(W1P), [6]=busy(RO), [7]=cpu_run, [8]=cpu_halt, [9]=cpu_halted(RO), [10]=cpu_break(RO) |
| REVISION | `0x223C` | `0x123C` | RO | `0x20260103` | Hardware revision (RV32I-only design, date: 2026-01-03) |
| DBG_BP0_ADDR | `0x2240` | `0x1240` | RW | `0x00000000` | Hardware breakpoint 0 address (32-bit PC value, halts CPU when PC matches) |
| DBG_BP1_ADDR | `0x2244` | `0x1244` | RW | `0x00000000` | Hardware breakpoint 1 address (32-bit PC value, halts CPU when PC matches) |
| DBG_BP2_ADDR | `0x2248` | `0x1248` | RW | `0x00000000` | Hardware breakpoint 2 address (32-bit PC value, halts CPU when PC matches) |
| DBG_BP3_ADDR | `0x224C` | `0x124C` | RW | `0x00000000` | Hardware breakpoint 3 address (32-bit PC value, halts CPU when PC matches) |
| DBG_BP_CTRL | `0x2250` | `0x1250` | RW | `0x00000000` | Breakpoint control: [3:0]=bp_enable(RW), [7:4]=bp_hit_flags(RO), cleared on cpu_run |
| PERF_CYCLE_COUNT | `0x2260` | `0x1260` | RO | `0x00000000` | Performance counter: total cycles executed (counts when CPU running) |
| PERF_INSN_COUNT | `0x2264` | `0x1264` | RO | `0x00000000` | Performance counter: total instructions committed (WB stage valid) |
| PERF_STALL_COUNT | `0x2268` | `0x1268` | RO | `0x00000000` | Performance counter: total pipeline stalls (IF or ID stage stalled) |
| PERF_FLUSH_COUNT | `0x226C` | `0x126C` | RO | `0x00000000` | Performance counter: total pipeline flushes (branch/jump taken) |
| DBG_RF_ADDR | `0x2270` | `0x1270` | RW | `0x00000000` | Register file read address: [4:0]=register_address (0-31), read DBG_RF_DATA after setting |
| DBG_RF_DATA | `0x2274` | `0x1274` | RO | `0x00000000` | Register file read data: 32-bit value of register specified by DBG_RF_ADDR (x0 always returns 0) |
| TRACE_READ_ADDR | `0x2280` | `0x1280` | RW | `0x00000000` | Trace buffer read address: [5:0]=entry_index (0-63), read TRACE_DATA_* registers after setting |
| TRACE_DATA_LOW | `0x2284` | `0x1284` | RO | `0x00000000` | Trace entry data [31:0]: lower 32 bits of trace data |
| TRACE_DATA_MID | `0x2288` | `0x1288` | RO | `0x00000000` | Trace entry data [63:32]: middle-low 32 bits (rd_value) |
| TRACE_DATA_HI0 | `0x228C` | `0x128C` | RO | `0x00000000` | Trace entry data [95:64]: middle-high 32 bits (instruction opcode) |
| TRACE_DATA_HI1 | `0x2290` | `0x1290` | RO | `0x00000000` | Trace entry data [127:96]: upper 32 bits (PC address) |
| TRACE_STATUS | `0x2294` | `0x1294` | RO | `0x00000000` | Trace buffer status: [5:0]=write_ptr, [13:8]=entry_count, [16]=buffer_full_flag |
| DBG_RESET_CTRL | `0x2298` | `0x1298` | RW | `0x00000000` | Debug reset control: [0]=soft_reset(W1P), [1]=reset_done(RO), [2]=cpu_step(W1P) |
| TRACE_DATA_HI2 | `0x229C` | `0x129C` | RO | `0x00000000` | Trace entry data [159:128]: extended trace flags |
| TRACE_DATA_HI3 | `0x22A0` | `0x12A0` | RO | `0x00000000` | Trace entry data [191:160]: extended trace upper |

## Regeneration Instructions

To update this file after modifying the register map:

```bash
python software/axiuart_driver/tools/gen_registers.py --in register_map/axiuart_registers.json
```

## Access Types

- **RO:** Read-only
- **RW:** Read-write
