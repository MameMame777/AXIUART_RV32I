# Diary 2026-02-01 - Issue #37 PC FIFO Fix

## Purpose
Implement the PC FIFO alignment fix for VexRiscv IBus responses, update AUIPC expected value, and add observer-only assertions for FIFO integrity.

## Scope
- RTL: Add PC FIFO tracking of request PCs and use it for decode PC injection.
- Test: Correct AUIPC expected value to the instruction address.
- Assertions: Add PC FIFO integrity checks and bind them for debug builds.

## Changes
- Added PC FIFO logic and alignment in rtl/cpu/vexriscv_ibus_simple.sv.
- Updated AUIPC expected value in sim/tests/vexriscv_alu_test.sv.
- Added sim/assertions/vexriscv_ibus_pc_fifo_assertions.sv and bind.
- Updated sim/uvm/tb/dsim_assertions.f to include new assertion files.

## Tests
- Run: vexriscv_alu_test (UVM_LOW)
- Result: FAIL (x30 = 0x80000080 expected 0x80000084)

## Update
- Fixed PC FIFO bypass accounting to avoid count underflow on empty push+pop.
- Kept discard-aware response buffering while leaving injector timing unchanged.

## Re-test
- Run: vexriscv_alu_test (UVM_LOW)
- Result: PASS (all 28 ALU operations correct)

## Follow-up
- Adjust PC FIFO for same-cycle push/pop bypass when empty; re-run vexriscv_alu_test.
- Consider enabling assertions (+define+ENABLE_ASSERTIONS) to verify FIFO integrity.
- Open/track separate BRAM read timing issue as planned.
