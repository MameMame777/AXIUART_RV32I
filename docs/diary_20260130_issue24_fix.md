# Diary: Issue #24 IBus/DBus alignment fix

## Purpose
Resolve Issue #24 (stores not executing in vexriscv_led_uart_test) by stabilizing IBus response/PC alignment and verifying end-to-end UART/MMIO store behavior.

## Scope of Work
- IBus response PC alignment using command/response FIFO pairing.
- DBus/IBus FIFO count/full tracking adjustments in crossbar.
- EBREAK detection moved to writeback retirement point.
- Test validation updates for DBus access and LED/BRAM stores.

## Commands Run
- .\scripts\run_test.ps1 vexriscv_led_uart_test

## Results
- vexriscv_led_uart_test: PASS
  - LED register: 0x0000000F
  - BRAM[0x1FF0]: 0x0000000F
  - BRAM[0x1FF4]: 0x0000000F
  - UVM errors: 0

## Outcome
- Issue #24 reproduction path now passes with correct LED/MMIO and BRAM store visibility.
- IBus response PC alignment stable without rsp-join buffering.

## Follow-up Actions
- Decide whether to run full regression before PR.
- Review debug logging and keep/remove any temporary prints before final merge.
