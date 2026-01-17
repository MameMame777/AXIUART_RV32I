# VexRiscv RTL Generation Script
# Generates SystemVerilog RTL from SpinalHDL source using custom GenSmallOptimized config

param(
    [ValidateSet("GenSmallOptimized", "GenSmall", "GenFull")]
    [string]$Config = "GenSmallOptimized",
    
    [switch]$Clean,
    [switch]$VerifyOnly
)

$ErrorActionPreference = "Stop"
$WorkspaceRoot = "e:\Nautilus\workspace\fpgawork\AXIUART_RV32I"
$VexRiscvSource = "$WorkspaceRoot\vexriscv_reference\source"
$OutputDir = "$WorkspaceRoot\vexriscv_reference\generated"

Write-Host "=== VexRiscv RTL Generator ===" -ForegroundColor Cyan
Write-Host "Config: $Config" -ForegroundColor Yellow
Write-Host "Output: $OutputDir" -ForegroundColor Yellow

# Verify environment
Write-Host "`nVerifying build environment..." -ForegroundColor Yellow
& "$WorkspaceRoot\tools\setup_vexriscv.ps1" -CheckOnly
if ($LASTEXITCODE -ne 0) {
    Write-Host "Environment check failed. Run setup_vexriscv.ps1 -InstallIfMissing" -ForegroundColor Red
    exit 1
}

if ($VerifyOnly) {
    Write-Host "✓ Environment verification passed" -ForegroundColor Green
    exit 0
}

# Clean if requested
if ($Clean) {
    Write-Host "`nCleaning previous build..." -ForegroundColor Yellow
    if (Test-Path $OutputDir) {
        Remove-Item "$OutputDir\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Copy custom config to VexRiscv source if needed
if ($Config -eq "GenSmallOptimized") {
    Write-Host "`nCopying custom config to VexRiscv source..." -ForegroundColor Yellow
    $customConfigSrc = "$WorkspaceRoot\vexriscv_reference\config\GenSmallOptimized.scala"
    $customConfigDst = "$VexRiscvSource\src\main\scala\vexriscv\demo\GenSmallOptimized.scala"
    
    if (-not (Test-Path $customConfigSrc)) {
        Write-Host "✗ Custom config not found: $customConfigSrc" -ForegroundColor Red
        exit 1
    }
    
    Copy-Item $customConfigSrc $customConfigDst -Force
    Write-Host "✓ Custom config copied" -ForegroundColor Green
}

# Build with sbt
Write-Host "`nGenerating RTL with sbt..." -ForegroundColor Yellow
Write-Host "This may take several minutes on first run (downloading dependencies)..." -ForegroundColor Cyan

Push-Location $VexRiscvSource
try {
    $runMain = switch ($Config) {
        "GenSmallOptimized" { "vexriscv.demo.GenSmallOptimized" }
        "GenSmall" { "vexriscv.demo.GenSmall" }
        "GenFull" { "vexriscv.demo.GenFull" }
    }
    
    # Run sbt with output directory override
    $sbtCommand = "runMain $runMain $OutputDir"
    Write-Host "Executing: sbt `"$sbtCommand`"" -ForegroundColor Cyan
    
    sbt $sbtCommand
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ sbt build failed" -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}

# Verify outputs
Write-Host "`nVerifying generated files..." -ForegroundColor Yellow

$verilogFile = "$OutputDir\VexRiscv.v"
$yamlFile = "$OutputDir\cpu.yaml"

$success = $true

if (Test-Path $verilogFile) {
    $lineCount = (Get-Content $verilogFile).Count
    Write-Host "✓ VexRiscv.v generated ($lineCount lines)" -ForegroundColor Green
    
    # Verify pipeline stage signals (VexRiscv uses 4 stages: decode/execute/memory/writeBack)
    $content = Get-Content $verilogFile -Raw
    $stages = @("decode", "execute", "memory", "writeBack")
    foreach ($stage in $stages) {
        if ($content -match "${stage}_arbitration_isValid") {
            Write-Host "  ✓ Stage found: $stage" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Stage missing: $stage" -ForegroundColor Red
            $success = $false
        }
    }
    
    # Check for IBus injection (fetch equivalent)
    if ($content -match "IBusSimplePlugin") {
        Write-Host "  ✓ IBusSimplePlugin found (fetch/injection)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ IBusSimplePlugin missing" -ForegroundColor Red
        $success = $false
    }
} else {
    Write-Host "✗ VexRiscv.v not generated" -ForegroundColor Red
    $success = $false
}

if (Test-Path $yamlFile) {
    $yamlContent = Get-Content $yamlFile -Raw
    $yamlSize = (Get-Item $yamlFile).Length
    
    # Check if YAML is just empty braces
    if ($yamlContent.Trim() -eq "{}") {
        Write-Host "⚠ cpu.yaml is empty (VexRiscv YamlPlugin may not have generated data)" -ForegroundColor Yellow
        Write-Host "  This is non-fatal - RTL is still usable" -ForegroundColor Cyan
    } else {
        Write-Host "✓ cpu.yaml generated ($yamlSize bytes)" -ForegroundColor Green
    }
} else {
    Write-Host "✗ cpu.yaml not generated" -ForegroundColor Red
    $success = $false
}

if ($success) {
    Write-Host "`n=== RTL Generation Successful ===" -ForegroundColor Green
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Review generated RTL: $verilogFile"
    Write-Host "  2. Analyze pipeline structure"
    Write-Host "  3. Extract hazard detection patterns"
    Write-Host "  4. Run: python tools\yaml_to_artifacts.py"
    exit 0
} else {
    Write-Host "`n=== RTL Generation Failed ===" -ForegroundColor Red
    exit 1
}
