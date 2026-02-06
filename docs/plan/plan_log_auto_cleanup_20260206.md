# Plan: DSIM Log Auto-Cleanup

**Date**: 2026-02-06
**Status**: Implementing

## Goals

Automatically clean up old DSIM test logs to prevent unbounded accumulation in `sim/exec/logs/` and `sim/exec/wave/`. Currently 86+ files accumulate from iterative debugging sessions.

## Current State

- `run_test.ps1` and `run_regression.ps1` have `-CleanupDays N` (default `0` = disabled)
- `clean_logs.ps1` exists for manual cleanup (interactive, `-OlderThanDays`, `-DryRun`, `-Force`)
- No per-test retention limit: a single test debugged iteratively can generate 10+ log sets in one day
- `sim/reports/` contains 78 legacy files from Dec 2025 - Jan 2026 (deprecated MCP workflow)

## Approach

Two complementary cleanup strategies, both running automatically before each DSIM execution:

1. **Age-based cleanup** (existing `Cleanup-OldLogs`): Delete all files older than N days
   - Change default from `0` (disabled) to `7` (enabled)

2. **Per-test retention limit** (new `Cleanup-PerTestLogs`): Keep only N most recent log sets per test name
   - Group files by test name prefix (regex: `^(.+?)_\d{8}_\d{6}`)
   - Sort by `LastWriteTime` descending, delete excess beyond keep count
   - Default: keep 5 most recent per test

## Implementation Steps

1. **`scripts/run_test.ps1`**:
   - Change `-CleanupDays` default: `0` -> `7`
   - Add `-KeepRecent` parameter (default: `5`, `0` = disable)
   - Add `Cleanup-PerTestLogs` function
   - Call both cleanup functions in `Setup-Environment`
   - Update header comments and `-Help` text

2. **`scripts/run_regression.ps1`**:
   - Same parameter changes (`CleanupDays=7`, `KeepRecent=5`)
   - Add `Cleanup-PerTestLogs` function (duplicated for script independence)
   - Call both cleanup functions before regression starts
   - Update header comments and `-Help` text

3. **Legacy cleanup** (one-time manual):
   - `.\scripts\clean_logs.ps1 -OlderThanDays 30 -Force` for `sim/reports/`

## File Changes

| File | Change |
|------|--------|
| `scripts/run_test.ps1` | Default changes, new param, new function |
| `scripts/run_regression.ps1` | Default changes, new param, new function |

## Risks

- **Risk**: Active debugging session loses useful logs
  - **Mitigation**: Keep 5 recent per test; override with `-KeepRecent 0` to disable
- **Risk**: Regression results deleted before review
  - **Mitigation**: `regression_*.json` grouped separately from per-test logs

## Success Criteria

- [ ] Both scripts compile and run without errors
- [ ] Old logs are deleted automatically before test execution
- [ ] Per-test limit prevents accumulation from iterative debugging
- [ ] `-KeepRecent 0` and `-CleanupDays 0` disable respective features
- [ ] Test passes after cleanup (no false deletions)
