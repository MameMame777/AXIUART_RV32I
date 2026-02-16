# Plan: Issue #55 VexRiscv control/debug bridge tests and debug path expansion

## Goals
- Add dedicated tests for `vexriscv_control` and `vexriscv_debug_bridge` through full AXIUART system path.
- Expand RTL debug/control path so Issue #55 viewpoints are testable and meaningful.
- Keep existing Stage-1 regressions stable.

## Scope
- `rtl/register_block/Register_Block.sv`
- `rtl/AXIUART_Top.sv`
- `rtl/vexriscvwrap/vexriscv_wrapper.sv`
- `rtl/vexriscvwrap/vexriscv_debug_bridge.sv`
- `sim/tests/*` (new tests)
- `sim/uvm/tb/dsim_config.f`
- `sim/regression_tests.json`
- `docs/CHANGELOG.md`

## Approach
1. Enable all declared debug register windows in Register_Block access validation.
2. Wire missing debug signals from Register_Block to wrapper.
3. Move control ownership to debug bridge outputs while preserving EBREAK auto-halt status semantics.
4. Expand debug bridge command FSM to support run/halt/step/reset and breakpoint writes.
5. Add full-system tests for control transitions and debug bridge protocol behavior.
6. Register tests in DSIM config and regression suite.
7. Validate with targeted DSIM runs, then stage1 regression.

## Risks
- Control path behavior changes may affect existing tests relying on `cpu_mem_ctrl_reg[7:8]` pulse behavior.
- VexRiscv DebugPlugin supports 2 hardware breakpoints; external model keeps 4. Need deterministic policy.
- Full-system tests can be timing-sensitive with UART transport delays.

## Success Criteria
- New tests compile and pass: `vexriscv_control_test`, `vexriscv_debug_bridge_test`.
- Existing key tests remain passing (`axiuart_reg_rw_test`, selected VexRiscv stage1 smoke tests).
- Regression config includes both new tests and can execute without manual file edits.
