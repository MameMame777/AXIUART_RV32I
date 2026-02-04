# Plan: Issue #41 (WB/EX bypass stall detection via trace_stall + perf delta)

## Goals
- Use `trace_stall` as the primary PASS/FAIL criterion for WB/EX bypass tests.
- Use `perf_stall_count` only as a delta (start/end) for supplemental logging.
- Extend trace register readout so `trace_stall` is available via UART path.

## Approach
1. Extend trace register window to include the `trace_stall` bit.
2. Wire trace signals through the AXIUART UART register path as needed.
3. Update WB/EX bypass tests to use `trans.stall` under `trace_valid` for PASS/FAIL.
4. Add `perf_stall_count` delta logging only.

## Implementation Steps
1. Update trace register definitions and decode to cover full trace width.
2. Ensure `trace_stall` is captured in transactions and available to tests.
3. Modify `vexriscv_ex_bypass_test` to fail on any stall during the measured interval.
4. Modify `vexriscv_wb_bypass_test` to use the same stall-based criterion.
5. Add `perf_stall_count` delta logging to both tests (no PASS/FAIL gating).

## Risks
- Trace register width changes may affect existing tooling or testbench assumptions.
- UART register decode updates may require regeneration of generated packages.

## Success Criteria
- `vexriscv_wb_bypass_test` and `vexriscv_ex_bypass_test` PASS using stall-based criterion.
- `perf_stall_count` delta is reported in logs.
- Stage 1 regression improves by at least one test (wb_bypass PASS).
