<#
.SYNOPSIS
    Open Claude Code worktree in a new VS Code window

.DESCRIPTION
    Opens the Claude Code worktree (.worktrees/claude) in a new VS Code window.
    Optionally creates the worktree if it doesn't exist.

.PARAMETER Setup
    Create the worktree if it doesn't exist before opening

.PARAMETER Wait
    Wait for the VS Code window to close before returning

.EXAMPLE
    .\scripts\open_claude_workspace.ps1
    Opens the Claude worktree in a new window

.EXAMPLE
    .\scripts\open_claude_workspace.ps1 -Setup
    Creates worktree if needed, then opens in new window
#>

param(
    [switch]$Setup,
    [switch]$Wait
)

$ErrorActionPreference = "Stop"

# Configuration
$WorktreeName = "claude"
$WorktreePath = ".worktrees/$WorktreeName"
$WorkspaceFile = ".worktrees/Claude.code-workspace"

# Get repository root
$RepoRoot = git rev-parse --show-toplevel 2>$null
if (-not $RepoRoot) {
    Write-Error "Not in a git repository"
    exit 1
}

# Normalize path
$RepoRoot = $RepoRoot -replace '/', '\'
$FullWorktreePath = Join-Path $RepoRoot $WorktreePath
$FullWorkspaceFile = Join-Path $RepoRoot $WorkspaceFile

# Check if worktree exists
if (-not (Test-Path $FullWorktreePath)) {
    if ($Setup) {
        Write-Host "Worktree not found. Creating..." -ForegroundColor Yellow
        & "$RepoRoot\scripts\setup_worktree.ps1"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create worktree"
            exit 1
        }
    } else {
        Write-Error "Worktree does not exist: $FullWorktreePath`nRun with -Setup to create it, or run: .\scripts\setup_worktree.ps1"
        exit 1
    }
}

# Check if workspace file exists
if (-not (Test-Path $FullWorkspaceFile)) {
    Write-Error "Workspace file not found: $FullWorkspaceFile"
    exit 1
}

# Verify it's a valid worktree
$gitFile = Join-Path $FullWorktreePath ".git"
if (-not (Test-Path $gitFile)) {
    Write-Error "Invalid worktree (missing .git): $FullWorktreePath"
    exit 1
}

# Open workspace file in new VS Code window
Write-Host "Opening Claude workspace in new VS Code window..." -ForegroundColor Cyan
Write-Host "Workspace: $FullWorkspaceFile" -ForegroundColor White

if ($Wait) {
    code -n $FullWorkspaceFile --wait
} else {
    code -n $FullWorkspaceFile
}

Write-Host "Done!" -ForegroundColor Green
