param([string]$GameDir = '')
$ErrorActionPreference = 'Stop'
try {
    if (-not $GameDir) {
        $config = Join-Path $PSScriptRoot 'installation.json'
        if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { throw 'Bitte zuerst INSTALL.cmd ausfuehren.' }
        $GameDir = (Get-Content -LiteralPath $config -Raw | ConvertFrom-Json).game_dir
    }
    if (-not (Test-Path -LiteralPath (Join-Path $GameDir 'Win64\ovldata\PC2CoopProbe\Main.ovl'))) {
        throw 'Mod nicht gefunden. Bitte zuerst INSTALL.cmd ausfuehren.'
    }
    Push-Location -LiteralPath $PSScriptRoot
    try { & (Join-Path $PSScriptRoot 'runtime\python.exe') -m pc2coop.coop --game-dir $GameDir; exit $LASTEXITCODE }
    finally { Pop-Location }
} catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
