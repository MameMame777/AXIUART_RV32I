# Diary: Full SoC Regression + Assertions

## Purpose
Run full SoC regression after IBus/DBus alignment changes and add assertion modules/binds for PC/FIFO integrity.

## Changes
- Added IBus response/PC alignment assertions.
- Added crossbar FIFO count range assertions.
- Bound both specs via bind files and updated assertions filelist.
- Switched debug writeback valid to `writeBack_arbitration_isFiring`.

## Commands Run
- .\scripts\run_regression.ps1

## Results
- Updated regression logic now flags failures based on per-test JSON output.
- vexriscv_load_use_stall_test: PASS (cycles=20)
  Log: sim/exec/logs/vexriscv_load_use_stall_test_20260201_122951.log
- vexriscv_dbus_access_test: FAIL (BRAM/store + load checks)
  Log: sim/exec/logs/vexriscv_dbus_access_test_20260201_123005.log
- Regression summary: 6 PASS / 4 FAIL
  Report: sim/exec/logs/regression_20260201_122754.txt

## Follow-up Actions
- Investigate DBus access test store/load failures.
