# Plan: Project-Wide Redundancy Cleanup

**Created**: 2026-02-16
**Status**: Active

## Summary

The project has undergone three architectural eras (TD4CPU -> Custom RV32I -> VexRiscv),
each leaving legacy artifacts. Investigation found ~50+ files that are dead, stale, or
misplaced, including previously-planned deletions that were never executed (documented in
`sim/uvm/tb/OBSOLETE_FILES.md` and `sim/uvm/tb/CLEANUP_SUMMARY.md` since 2026-01-05).
One broken config file references a non-existent source. The cleanup is organized into
5 phases by priority.

## Phase 1: Fix Broken References (Critical)

1. Fix `sim/uvm/tb/dsim_config_no_assertions.f` line 30 - references non-existent
   `rv32i_isa_pkg.sv`. Either remove the line or comment it out (matching `dsim_config.f`
   which has it commented as "Legacy RV32I - not used").
2. Add `work_vexriscv/` to `.gitignore` - build artifacts potentially tracked. Run
   `git rm -r --cached work_vexriscv/` if already committed.

## Phase 2: Execute Previously-Planned Deletions (High)

3. Delete 3 files listed as obsolete since 2026-01-05 in `OBSOLETE_FILES.md`:
   - `sim/uvm/tb/rv32i_config.f`
   - `sim/uvm/tb/dsim_assertions.f`
   - `sim/uvm/tb/dsim_assertions_rv32i.f`
4. Clean committed build artifacts from `sim/uvm/tb/` via `git rm --cached`:
   - `tr_db.log` (42,306 lines), `dsim.log`, `metrics.db`, `rv32i_test.mxd`,
     `dsm.env`, `regfile_debug.csv`
   - Directories: `dsim_work/`, `work/`
5. Delete cleanup meta-docs after actions are completed:
   - `sim/uvm/tb/OBSOLETE_FILES.md`
   - `sim/uvm/tb/CLEANUP_SUMMARY.md`
6. Delete `sim/uvm/tb/minimal_config.f` - references non-existent `fifo_sync.sv`.

## Phase 3: Remove Dead Architecture Artifacts (Medium)

7. Delete 4 root-level dead files:
   - `test_vexriscv_compile.ps1` - early PoC, superseded by `scripts/run_test.ps1`
   - `test_vexriscv.f` - references non-existent hand-written VexRiscv modules
   - `dsim.env` - hardcoded absolute paths, gitignored but may be tracked
   - `setup_dsim_2025.ps1` - only referenced by dead `test_vexriscv_compile.ps1`
8. Delete 8 TD4CPU assertion files from `sim/assertions/`:
   - `td4cpu_alu_assertions.sv`, `td4cpu_control_assertions.sv`,
     `td4cpu_datapath_assertions.sv`, `td4cpu_fetch_assertions.sv`,
     `td4cpu_hazard_assertions.sv`, `td4cpu_mem_assertions.sv`,
     `td4cpu_pipeline_assertions.sv`, `td4cpu_wb_assertions.sv`
   - Also delete `forCopilot-assertions.md` (obsolete Copilot instruction file)
9. Delete dead sim test artifacts:
   - `sim/tests/pre_migration_backup/` (6 TD4CPU-era test files)
   - `sim/tests/vexriscv_alu_test.sv.replacement`
   - `sim/tests/vexriscv_fix.ipynb`
   - `sim/uvm/tb/rv32i_tb_top.sv.backup`
10. Evaluate and potentially delete Bash scripts (no consumers, PowerShell is primary):
    - `scripts/run_test.sh`, `scripts/run_regression.sh`
11. Evaluate and potentially delete redundant `sim/uvm/tb/` runners:
    - `run_test.py` (75-line Python runner, superseded by `scripts/run_test.ps1`)
    - `Makefile`, `Makefile_rv32i` (PowerShell is primary workflow per project instructions)

## Phase 4: Documentation Cleanup (Medium)

12. Archive ~15 stale docs from TD4CPU/custom-RV32I era to `docs/archive/`:
    - **TD4CPU era**: `known_issues.md`, `ISA.md`, `specification_plan.md`,
      `bug_fixes_20251229.md`, `work_completion_20251229.md`,
      `led_mmio_fix_implementation_plan.md`, `cpu_pc_control_spec.md`,
      `cpu_mmio_design.md`, `rtl_refactoring_plan.md`, `rtl_branch_behavior_analysis.md`
    - **Custom RV32I era**: `implementation_status_20260115.txt`,
      `rv32i_control_flow_diagrams.md`, `rv32i_modular_architecture_spec.md`,
      `exception_trap_timing_spec.md`, `cpu_debug_pc_reset_fix.md`,
      `vexriscv_refactoring_status.md`
    - **Resolved issues**: `issue_vexriscv_alu_test_auipc_mismatch.md`
13. Move `docs/VexRiscv_GenSmallAndProductive.v` (3802-line Verilog) out of `docs/`
    to `reference/` or delete (different config than production `GenSmallOptimized`).
14. Delete empty `docs/drawio/` directory.
15. Update `sim/uvm/tb/README_rv32i.md` - references deleted `rv32i_core.sv`.
16. Update `known_issues.md` - replace TD4CPU bug with current VexRiscv known issues
    (or archive and create new).

## Phase 5: Miscellaneous Improvements (Low)

17. Fix typo in `reference/z7020_maseter.xdc` -> `z7020_master.xdc`.
18. Update `software/axiuart_driver/tools/gen_cpu_isa.py` - still generates
    `td4cpu_isa_pkg.sv`. Either update for VexRiscv or delete.
19. Evaluate `generated/rtl/rv32i_decode_pkg.sv` - not in any active config, potentially stale.
20. Evaluate `tools/vexriscv_rtl_parser.py` and `tools/yaml_to_artifacts.py`.
21. Evaluate `reference/uvm-hello-world-main/` - project is well past tutorial stage.
22. Clean `temporary/` - delete 6 of 7 files (keep only `issue_rtl_bug.md`);
    note: already gitignored, so only local cleanup.
23. Audit stale cross-references: 20+ docs reference deleted `mcp_server/` directory,
    20+ reference deleted `rv32i_core.sv` - update or remove in remaining active docs.

## Verification

- After Phase 1-2: Run `.\scripts\run_regression.ps1 -Stage 1` to confirm no breakage
- After Phase 3: Run `.\scripts\run_regression.ps1 -Suite full` to verify no test depends on deleted files
- After each phase: `git status` and `git diff --stat` to confirm only intended changes
- After all phases: Review `.gitignore` patterns match all build artifact directories

## Risks

- Deleting Makefiles may break undocumented CI or other developer workflows
- Some "stale" docs may still be referenced by GitHub Issues - check issue links before archiving
- The `rv32i_*` assertion files in `sim/assertions/` need individual review - some may bind to active VexRiscv wrapper modules rather than the deleted custom pipeline

## Decisions

- Stale docs archived to `docs/archive/` rather than deleted - preserves project history
- Bash scripts marked for deletion - PowerShell is explicitly the primary workflow
- Phase ordering prioritizes functional fixes (Phase 1) before cosmetic cleanup (Phase 4-5)
- `temporary/` cleanup is local-only since already gitignored
