# build_c.ps1 — RV32I C ソース → raw binary ビルドスクリプト
#
# 使い方 (pwsh / PowerShell 7 必須):
#   pwsh -ExecutionPolicy Bypass -File .\scripts\build_c.ps1 led_blink
#
# ツールチェーン設定 (優先順位):
#   1. 環境変数 RISCV_TOOLCHAIN_BIN を設定する (推奨)
#      例: $env:RISCV_TOOLCHAIN_BIN = 'C:\path\to\riscv-none-elf-gcc\bin'
#   2. PATH に riscv-none-elf-gcc の bin ディレクトリを追加する
#   3. %LOCALAPPDATA%\xpack-riscv-none-elf-gcc-* を自動スキャン
#
# 生成物:
#   software\rv32i\c\<target>.elf  — ELF (デバッグ情報付き)
#   software\rv32i\c\<target>.bin  — raw binary (FPGA 書き込み用)

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Target
)

# ────────────────────────────────────────────────
# パス設定
# ────────────────────────────────────────────────
$WorkspaceRoot = Split-Path -Parent $PSScriptRoot
$CDir          = Join-Path $WorkspaceRoot "software\rv32i\c"
$BramSizeBytes = 8192   # 8KB

# ────────────────────────────────────────────────
# ツールチェーン自動検出
# ────────────────────────────────────────────────
$ToolchainBin = $null

# 優先度 1: 環境変数 RISCV_TOOLCHAIN_BIN
if ($env:RISCV_TOOLCHAIN_BIN) {
    $ToolchainBin = $env:RISCV_TOOLCHAIN_BIN
    Write-Host "  [TOOL] 環境変数 RISCV_TOOLCHAIN_BIN より: $ToolchainBin"
}

# 優先度 2: PATH 上の riscv-none-elf-gcc
if (-not $ToolchainBin) {
    $found = Get-Command "riscv-none-elf-gcc" -ErrorAction SilentlyContinue
    if ($found) {
        $ToolchainBin = Split-Path $found.Source -Parent
        Write-Host "  [TOOL] PATH より自動検出: $ToolchainBin"
    }
}

# 優先度 3: %LOCALAPPDATA% 内の xpack インストールをスキャン (最新版を優先)
if (-not $ToolchainBin) {
    $xpackDirs = Get-ChildItem "$env:LOCALAPPDATA" -Filter "xpack-riscv-none-elf-gcc-*" `
                     -Directory -ErrorAction SilentlyContinue |
                 Sort-Object Name -Descending
    if ($xpackDirs) {
        $ToolchainBin = Join-Path $xpackDirs[0].FullName "bin"
        Write-Host "  [TOOL] xPack インストール自動検出: $ToolchainBin"
    }
}

if (-not $ToolchainBin) {
    Write-Error @"
riscv-none-elf-gcc が見つかりません。以下のいずれかを実施してください:
  A) xPack riscv-none-elf-gcc を %LOCALAPPDATA% に展開する
     https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases
  B) PATH に riscv-none-elf-gcc の bin ディレクトリを追加する
  C) 環境変数 RISCV_TOOLCHAIN_BIN に bin ディレクトリのパスを設定する
     例: `$env:RISCV_TOOLCHAIN_BIN = 'C:\path\to\riscv-none-elf-gcc\bin'
"@
    exit 1
}

$CC  = Join-Path $ToolchainBin "riscv-none-elf-gcc.exe"
$OC  = Join-Path $ToolchainBin "riscv-none-elf-objcopy.exe"
$OS_ = Join-Path $ToolchainBin "riscv-none-elf-size.exe"

# ────────────────────────────────────────────────
# ファイルチェック
# ────────────────────────────────────────────────
Write-Host ("=" * 60)
Write-Host "[BUILD] RV32I C ビルド: $Target"
Write-Host ("=" * 60)

if (-not (Test-Path $CC)) {
    Write-Error "gcc が見つかりません: $CC"
    Write-Error "RISCV_TOOLCHAIN_BIN の設定を確認してください"
    exit 1
}

$CSrc  = Join-Path $CDir "$Target.c"
$CrtS  = Join-Path $CDir "crt0.s"
$LdSrc = Join-Path $CDir "rv32i_bram.ld"
$ElfOut= Join-Path $CDir "$Target.elf"
$BinOut= Join-Path $CDir "$Target.bin"

foreach ($f in @($CSrc, $CrtS, $LdSrc)) {
    if (-not (Test-Path $f)) {
        Write-Error "ファイルが見つかりません: $f"
        exit 1
    }
}

Write-Host "  ソース  : $CSrc"
Write-Host "  スタートアップ: $CrtS"
Write-Host "  リンカ  : $LdSrc"
Write-Host "  出力ELF : $ElfOut"
Write-Host "  出力BIN : $BinOut"

# ────────────────────────────────────────────────
# コンパイル & リンク
# ────────────────────────────────────────────────
$CFlags = @(
    "-march=rv32i",         # RV32I 命令セットのみ
    "-mabi=ilp32",          # 32-bit integer ABI, float なし
    "-nostdlib",            # 標準ライブラリ不使用
    "-nostartfiles",        # 標準スタートアップ不使用 (crt0.s を使用)
    "-Os",                  # サイズ最適化 (BRAM 節約)
    "-Wall",                # 警告を有効化
    "-T", $LdSrc,           # リンカスクリプト
    $CrtS, $CSrc,           # スタートアップ + C ソース
    "-o", $ElfOut           # 出力 ELF
)

Write-Host "`n[CC]   コンパイル中..."
& $CC @CFlags
if ($LASTEXITCODE -ne 0) {
    Write-Error "コンパイル失敗 (exit code $LASTEXITCODE)"
    exit $LASTEXITCODE
}
Write-Host "[CC]   コンパイル成功"

# ────────────────────────────────────────────────
# サイズ表示
# ────────────────────────────────────────────────
Write-Host "`n[SIZE] セクションサイズ:"
& $OS_ $ElfOut

# ────────────────────────────────────────────────
# ELF → raw binary 変換
# ────────────────────────────────────────────────
Write-Host "`n[COPY] ELF → raw binary 変換..."
& $OC -O binary $ElfOut $BinOut
if ($LASTEXITCODE -ne 0) {
    Write-Error "objcopy 失敗 (exit code $LASTEXITCODE)"
    exit $LASTEXITCODE
}

# ────────────────────────────────────────────────
# サイズチェック
# ────────────────────────────────────────────────
$BinSize = (Get-Item $BinOut).Length
$UsePct  = [math]::Round($BinSize / $BramSizeBytes * 100, 1)
Write-Host "[BIN]  $BinOut"
Write-Host "       サイズ: $BinSize bytes ($UsePct% / 8KB BRAM)"

if ($BinSize -gt $BramSizeBytes) {
    Write-Error "BRAM オーバーフロー: $BinSize bytes > $BramSizeBytes bytes (8KB)"
    exit 1
}

Write-Host "`n[DONE] ビルド完了: $BinOut"
Write-Host "       実行: cd software\exec ; python c_blink.py --port COM3 --verify"
exit 0
