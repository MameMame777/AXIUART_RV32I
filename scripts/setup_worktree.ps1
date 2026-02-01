<#
.SYNOPSIS
    Setup git worktree for Claude Code development

.DESCRIPTION
    Creates a separate worktree for Claude Code to work independently.
    This allows parallel development without branch conflicts.

.PARAMETER Remove
    Remove the existing worktree instead of creating it

.EXAMPLE
    .\scripts\setup_worktree.ps1
    Creates .worktrees/claude with work/claude branch

.EXAMPLE
    .\scripts\setup_worktree.ps1 -Remove
    Removes the claude worktree
#>

param(
    [switch]$Remove
)

$ErrorActionPreference = "Stop"

# Configuration
$WorktreeName = "claude"
$BranchName = "work/claude"
$WorktreePath = ".worktrees/$WorktreeName"

# Get repository root
$RepoRoot = git rev-parse --show-toplevel 2>$null
if (-not $RepoRoot) {
    Write-Error "Not in a git repository"
    exit 1
}

Push-Location $RepoRoot
try {
    if ($Remove) {
        # Remove worktree
        Write-Host "Removing worktree: $WorktreePath" -ForegroundColor Yellow
        
        if (Test-Path $WorktreePath) {
            git worktree remove $WorktreePath --force
            Write-Host "Worktree removed successfully" -ForegroundColor Green
        } else {
            Write-Host "Worktree does not exist: $WorktreePath" -ForegroundColor Yellow
        }
    } else {
        # Check if worktree already exists
        $existingWorktrees = git worktree list --porcelain | Select-String "worktree"
        if ($existingWorktrees -match [regex]::Escape($WorktreeName)) {
            Write-Host "Worktree already exists: $WorktreePath" -ForegroundColor Yellow
            git worktree list
            exit 0
        }

        # Create .worktrees directory if needed
        if (-not (Test-Path ".worktrees")) {
            New-Item -ItemType Directory -Path ".worktrees" | Out-Null
        }

        # Check if branch exists
        $branchExists = git show-ref --verify --quiet "refs/heads/$BranchName" 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            # Branch doesn't exist, create it from main
            Write-Host "Creating branch: $BranchName from main" -ForegroundColor Cyan
            git branch $BranchName main
        }

        # Create worktree
        Write-Host "Creating worktree: $WorktreePath -> $BranchName" -ForegroundColor Cyan
        git worktree add $WorktreePath $BranchName

        Write-Host "`nWorktree created successfully!" -ForegroundColor Green
        Write-Host "Path: $RepoRoot/$WorktreePath" -ForegroundColor White
        Write-Host "Branch: $BranchName" -ForegroundColor White
    }

    # Show current worktree status
    Write-Host "`nCurrent worktrees:" -ForegroundColor Cyan
    git worktree list

} finally {
    Pop-Location
}
