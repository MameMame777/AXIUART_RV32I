# AXIUART_RV32I Project Instructions

## Base Instructions

See: [base-instructions.md](../.claude/shared/instructions/base-instructions.md)

---

## Project-Specific Configuration

### Reference

```
E:\Nautilus\workspace\fpgawork\AXIUART_\reference\Accellera\uvm\distrib\examples\integrated\ubus
```

### Git Branch Workflow

- Work on the default branch (`main`) for this workspace.
- Claude Code uses a separate worktree (`.worktrees/claude` with `work/claude` branch).
- To create Claude worktree: `.\scripts\setup_worktree.ps1`
- To remove Claude worktree: `.\scripts\setup_worktree.ps1 -Remove`
- **Sync with main regularly**: Before starting new tasks, sync with main to prevent conflicts:

  ```bash
  git fetch origin main
  git merge origin/main
  ```

- If merge conflicts occur, resolve them before proceeding with other work.

### Tooling Workflow (PowerShell Scripts - MANDATORY)

- Primary workflow: use PowerShell scripts in `scripts/` directory.
- **Single test**: `.\scripts\run_test.ps1 <test_name> [-Verbosity UVM_LOW] [-Waves]`
- **Regression**: `.\scripts\run_regression.ps1 [-Stage 1] [-Tests test1,test2]`
- See `dsim-workflow` skill for detailed command sequences and VS Code task integration.
- **Note**: MCP-based execution has been deprecated. Files in `deprecated_mcp_server/` are for reference only.

### Directory Discipline

- Production RTL in `rtl/`
- Verification in `sim/uvm/` and `sim/tests/`
- Documentation in `docs/`
- Ad-hoc experiments in `temporary/`
- Do not relocate or duplicate files outside the defined structure.

### Prohibited Actions (Project-Specific)

- Do not execute scripts from `deprecated_mcp_server/` directory. Use `scripts/run_test.ps1` and `scripts/run_regression.ps1` instead.
