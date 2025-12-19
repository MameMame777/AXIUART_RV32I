#!/usr/bin/env pwsh
# DSIM 2025.1 環境セットアップスクリプト
# このスクリプトは DSIM 2025.1 の環境を初期化します

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DSIM 2025.1 環境セットアップ" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# DSIM shell環境を有効化（QuickStart Guide推奨）
$shellActivateScript = 'C:\Program Files\Altair\DSim\2025.1\shell_activate.ps1'

if (Test-Path $shellActivateScript) {
    Write-Host "[INFO] DSIM shell環境を有効化中..." -ForegroundColor Green
    & $shellActivateScript
} else {
    Write-Host "[WARN] shell_activate.ps1が見つかりません: $shellActivateScript" -ForegroundColor Yellow
    Write-Host "[INFO] 手動で環境変数を設定します..." -ForegroundColor Yellow
    
    # 環境変数を手動設定
    $env:DSIM_HOME = "C:\Program Files\Altair\DSim\2025.1"
    $env:DSIM_ROOT = "C:\Program Files\Altair\DSim\2025.1"
    $env:DSIM_LIB_PATH = "C:\Program Files\Altair\DSim\2025.1\lib"
    $env:DSIM_LICENSE = "C:\Users\Nautilus\AppData\Local\metrics-ca\dsim-license.json"
    
    # PATHに追加
    $env:PATH = "C:\Program Files\Altair\DSim\2025.1\bin;" + $env:PATH
}

# 環境変数の確認
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "環境変数確認" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DSIM_HOME    : $env:DSIM_HOME"
Write-Host "DSIM_ROOT    : $env:DSIM_ROOT"
Write-Host "DSIM_LIB_PATH: $env:DSIM_LIB_PATH"
Write-Host "DSIM_LICENSE : $env:DSIM_LICENSE"

# DSIM実行ファイルの確認
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DSIM実行可能性確認" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    $version = & dsim -version 2>&1 | Select-Object -First 1
    Write-Host "[OK] DSIM バージョン: $version" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] DSIMの実行に失敗しました: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "セットアップ完了" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[INFO] MCPサーバーやUVMシミュレーションを実行できます"
