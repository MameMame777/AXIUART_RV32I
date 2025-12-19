#!/usr/bin/env pwsh
# DSIM 簡素化UVM環境セットアップスクリプト
# UBUS-style simplified UVM testbench用

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DSIM 簡素化UVM環境セットアップ" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# DSIM 環境変数設定
$env:DSIM_HOME = "C:\Program Files\Altair\DSim\2025.1"
$env:DSIM_ROOT = "C:\Program Files\Altair\DSim\2025.1"
$env:DSIM_LIB_PATH = "C:\Program Files\Altair\DSim\2025.1\lib"
$env:DSIM_LICENSE = "C:\Program Files\Altair\DSim\2025.1\dsim-license.json"

# PATHに追加（DLL読み込み用）
$dsimBin = "C:\Program Files\Altair\DSim\2025.1\bin"
if ($env:PATH -notlike "*$dsimBin*") {
    $env:PATH = "$dsimBin;" + $env:PATH
    Write-Host "[INFO] DSIMバイナリパスを追加: $dsimBin" -ForegroundColor Green
}

# 環境変数確認
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "環境変数確認" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DSIM_HOME    : $env:DSIM_HOME"
Write-Host "DSIM_ROOT    : $env:DSIM_ROOT"
Write-Host "DSIM_LIB_PATH: $env:DSIM_LIB_PATH"
Write-Host "DSIM_LICENSE : $env:DSIM_LICENSE"
Write-Host "PATH (DSIM)  : $dsimBin"

# 作業ディレクトリ設定
$tbDir = Join-Path $PSScriptRoot "tb"
if (Test-Path $tbDir) {
    Set-Location $tbDir
    Write-Host "`n[INFO] 作業ディレクトリ: $tbDir" -ForegroundColor Green
} else {
    Write-Host "`n[WARN] テストベンチディレクトリが見つかりません: $tbDir" -ForegroundColor Yellow
}

# DSIM実行確認
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DSIM実行可能性確認" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    $dsimExe = Join-Path $env:DSIM_HOME "bin\dsim.exe"
    if (Test-Path $dsimExe) {
        Write-Host "[OK] DSIM実行ファイル: $dsimExe" -ForegroundColor Green
        
        # バージョン確認（オプション - 失敗してもOK）
        $versionOutput = & $dsimExe -version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] DSIM バージョン確認成功" -ForegroundColor Green
        } else {
            Write-Host "[WARN] DSIM -versionが失敗しましたが、コンパイルは試行可能です" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[ERROR] DSIM実行ファイルが見つかりません: $dsimExe" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "[WARN] DSIM確認中にエラー: $_" -ForegroundColor Yellow
    Write-Host "[INFO] コンパイルは試行可能です" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "セットアップ完了" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[INFO] 次のコマンドでテストを実行できます:"
Write-Host "  dsim -uvm 1.2 -timescale 1ns/1ps -f dsim_config.f -top axiuart_tb_top +UVM_TESTNAME=axiuart_basic_test -work work -genimage image" -ForegroundColor Cyan
