---
name: worktree-management
description: Git worktree setup and VS Code workspace management for parallel development with Claude Code. Use when setting up worktrees, opening workspaces in new windows, or managing parallel development environments.
---

# Git Worktree Management

Managing separate worktrees for Claude Code and Copilot parallel development.

## When to Use This Skill

- Setting up Claude Code worktree environment
- Opening worktree in a new VS Code window
- Synchronizing worktrees with main branch
- Troubleshooting worktree conflicts

## Worktree Architecture

```
AXIUART_RV32I/                 # Main workspace (main branch)
├── .worktrees/
│   └── claude/                # Claude Code worktree (work/claude branch)
└── ...
```

| Workspace | Branch | Agent | Purpose |
|-----------|--------|-------|---------|
| `AXIUART_RV32I` | `main` | Copilot / Manual | Primary development |
| `.worktrees/claude` | `work/claude` | Claude Code | Parallel development |

## Quick Commands

### Setup Worktree

```powershell
# Create Claude worktree
.\scripts\setup_worktree.ps1

# Remove Claude worktree
.\scripts\setup_worktree.ps1 -Remove
```

### Open Claude Workspace in New Window

```powershell
# Open workspace with orange status bar
.\scripts\open_claude_workspace.ps1

# Or use the workspace file directly
code -n ".worktrees\Claude.code-workspace"
```

**Note:** The `.code-workspace` file provides:
- Orange status bar for visual distinction
- Custom window title: `[Claude]`
- Pre-configured extensions

### Check Worktree Status

```powershell
git worktree list
```

## Automated Scripts

### scripts/setup_worktree.ps1

Creates or removes the Claude Code worktree.

**Parameters:**
- `-Remove`: Remove existing worktree instead of creating

**Usage:**
```powershell
# Create worktree
.\scripts\setup_worktree.ps1

# Remove worktree
.\scripts\setup_worktree.ps1 -Remove
```

### scripts/open_claude_workspace.ps1

Opens the Claude worktree in a new VS Code window automatically.

**Parameters:**
- `-Setup`: Create worktree if it doesn't exist before opening

**Usage:**
```powershell
# Open existing worktree
.\scripts\open_claude_workspace.ps1

# Setup and open
.\scripts\open_claude_workspace.ps1 -Setup
```

## Synchronization Workflow

### Before Starting Work (in Claude worktree)

```powershell
cd E:\Nautilus\workspace\fpgawork\AXIUART_RV32I\.worktrees\claude
git fetch origin main
git merge origin/main
```

### Merging Claude Work to Main

```powershell
# In main workspace
cd E:\Nautilus\workspace\fpgawork\AXIUART_RV32I
git fetch origin work/claude
git merge origin/work/claude
```

## Branch Protection Rules

| Branch | Protection |
|--------|------------|
| `main` | Cannot be checked out in `.worktrees/claude` |
| `work/claude` | Cannot be checked out in main workspace |

**Important:** Each branch can only be checked out in ONE worktree at a time.

## Troubleshooting

### Worktree Already Exists

```powershell
# Force remove and recreate
.\scripts\setup_worktree.ps1 -Remove
.\scripts\setup_worktree.ps1
```

### Branch Conflict

```
fatal: 'work/claude' is already checked out at '...'
```

**Solution:** The branch is in use by another worktree. Check `git worktree list` and remove the conflicting worktree first.

### Stale Worktree Reference

```powershell
# Prune stale worktree entries
git worktree prune
```

### VS Code Not Recognizing Worktree

Ensure the worktree path exists and contains a valid `.git` file:

```powershell
Test-Path "E:\Nautilus\workspace\fpgawork\AXIUART_RV32I\.worktrees\claude\.git"
```

## Best Practices

1. **Always sync before work**: Merge main into work/claude before starting tasks
2. **Commit frequently**: Keep changes atomic and well-documented
3. **Review before merge**: User reviews Claude's changes before merging to main
4. **Keep worktrees clean**: Remove unused worktrees to avoid confusion

## Integration with Claude Code

Claude Code should:
1. Work exclusively on `work/claude` branch
2. Never attempt to switch to `main` or other branches
3. Sync with `origin/main` at the start of each session
4. Push changes to `origin/work/claude` for user review
