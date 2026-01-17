# Test compilation of VexRiscv SystemVerilog modules
# Usage: .\test_vexriscv_compile.ps1

$ErrorActionPreference = "Stop"

# Setup DSIM environment
if (-not (Test-Path env:DSIM_HOME)) {
    Write-Error "DSIM_HOME not set. Please run setup_dsim_2025.ps1 first."
    exit 1
}

$dvlcom = Join-Path $env:DSIM_HOME "bin\dvlcom.exe"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "VexRiscv SystemVerilog Module Compilation Test" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Clean work directory
if (Test-Path "work") {
    Remove-Item -Recurse -Force "work"
}

# Compile package
Write-Host "[1/2] Compiling vexriscv_pkg.sv..." -ForegroundColor Yellow
& $dvlcom -sv -work work rtl/cpu/vexriscv_pkg.sv
if ($LASTEXITCODE -ne 0) {
    Write-Error "Package compilation failed!"
    exit 1
}
Write-Host "  ✓ Package compiled successfully`n" -ForegroundColor Green

# Compile RegFile module
Write-Host "[2/2] Compiling vexriscv_regfile.sv..." -ForegroundColor Yellow
& $dvlcom -sv -work work rtl/cpu/vexriscv_regfile.sv
if ($LASTEXITCODE -ne 0) {
    Write-Error "RegFile compilation failed!"
    exit 1
}
Write-Host "  ✓ RegFile compiled successfully`n" -ForegroundColor Green

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✓ All modules compiled successfully!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Proof-of-concept complete. Ready for full refactoring." -ForegroundColor Cyan
