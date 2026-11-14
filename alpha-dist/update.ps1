# PC2Coop updater: fetches the newest release from GitHub, checks its SHA-256, unpacks it
# into its own folder and runs that version's installer. Never touches anything else.
param(
    [switch]$CheckOnly,
    [string]$GameDir = '',
    [string]$ApiUrl = ''      # for tests: a URL that answers like GitHub's "latest release"
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Release notes contain umlauts; the console's default code page would garble them.
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Package-Version([string]$Folder) {
    (Get-Content -LiteralPath (Join-Path $Folder 'payload-manifest.json') -Raw | ConvertFrom-Json).version
}

function Get-Release {
    if (-not $ApiUrl) {
        $config = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'update.json') -Raw | ConvertFrom-Json
        if ($config.repo -notmatch '^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$') { throw 'In update.json ist kein GitHub-Repository eingetragen.' }
        $script:ApiUrl = "https://api.github.com/repos/$($config.repo)/releases/latest"
    }
    Invoke-RestMethod -Uri $script:ApiUrl -Headers @{ 'User-Agent' = 'PC2Coop-Updater'; 'Accept' = 'application/vnd.github+json' }
}

# Only plain "PC2Coop/..." entries; nothing may leave the target folder.
function Expand-Package([string]$Zip, [string]$Target) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $base = [IO.Path]::GetFullPath($Target).TrimEnd('\') + '\'
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -notmatch '^PC2Coop/' -or $entry.FullName -match '(^|/)\.\.(/|$)' -or $entry.FullName -match ':') {
                throw "Unerwarteter Eintrag im Paket: $($entry.FullName)"
            }
            $path = [IO.Path]::GetFullPath((Join-Path $Target $entry.FullName.Replace('/', '\')))
            if (-not $path.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw 'Paketpfad liegt ausserhalb des Zielordners.' }
            if ($entry.FullName.EndsWith('/')) { continue }
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $path, $false)
        }
    } finally { $archive.Dispose() }
}

try {
    $current = Package-Version $PSScriptRoot
    # An older folder's UPDATE.cmd also knows about versions this updater installed since.
    $installed = Join-Path $env:LOCALAPPDATA 'PC2Coop'
    if (Test-Path -LiteralPath $installed) {
        foreach ($folder in Get-ChildItem -LiteralPath $installed -Directory) {
            if ($folder.Name -match '^\d+\.\d+\.\d+$' -and (Test-Path -LiteralPath (Join-Path $folder.FullName 'PC2Coop\installation.json')) -and
                [version]$folder.Name -gt [version]$current) { $current = $folder.Name }
        }
    }
    Write-Host "Installierte Paketversion: $current"
    $release = Get-Release
    $zipAsset = @($release.assets | Where-Object { $_.name -match '^PC2Coop-(\d+\.\d+\.\d+)\.zip$' })[0]
    if (-not $zipAsset) { throw 'Die neueste Version auf GitHub enthaelt kein PC2Coop-Paket.' }
    $latest = [regex]::Match($zipAsset.name, '(\d+\.\d+\.\d+)').Groups[1].Value
    if ([version]$latest -le [version]$current) {
        Write-Host "Du hast bereits die neueste Version ($current)." -ForegroundColor Green
        exit 0
    }
    Write-Host "Neue Version verfuegbar: $latest" -ForegroundColor Yellow
    if ($release.body) { Write-Host ''; Write-Host $release.body; Write-Host '' }
    if ($CheckOnly) { exit 0 }
    if (Get-Process -Name PlanetCoaster2 -ErrorAction SilentlyContinue) { throw 'Bitte Planet Coaster 2 zuerst beenden, dann UPDATE.cmd erneut starten.' }
    $shaAsset = @($release.assets | Where-Object { $_.name -eq ($zipAsset.name + '.sha256') })[0]
    if (-not $shaAsset) { throw 'Zur neuen Version fehlt die Pruefsumme (.sha256). Nichts installiert.' }

    $root = Join-Path $env:LOCALAPPDATA 'PC2Coop'
    $target = Join-Path $root $latest
    $download = Join-Path $root ('download-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $download -Force | Out-Null
    try {
        $zip = Join-Path $download $zipAsset.name
        Write-Host 'Lade herunter ...'
        Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zip -Headers @{ 'User-Agent' = 'PC2Coop-Updater' } -UseBasicParsing
        $shaText = (Invoke-WebRequest -Uri $shaAsset.browser_download_url -Headers @{ 'User-Agent' = 'PC2Coop-Updater' } -UseBasicParsing).Content
        if ($shaText -is [byte[]]) { $shaText = [Text.Encoding]::ASCII.GetString($shaText) }
        $expected = [regex]::Match([string]$shaText, '\b[0-9a-fA-F]{64}\b').Value.ToLowerInvariant()
        $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        if (-not $expected -or $actual -ne $expected) { throw 'Pruefsumme stimmt nicht. Download beschaedigt; nichts installiert.' }
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        Expand-Package $zip $target
    } finally {
        Remove-Item -LiteralPath $download -Recurse -Force -ErrorAction SilentlyContinue
    }
    $package = Join-Path $target 'PC2Coop'
    if ((Package-Version $package) -ne $latest) { throw 'Paketinhalt passt nicht zur Versionsnummer. Nichts installiert.' }

    if (-not $GameDir -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'installation.json'))) {
        $GameDir = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'installation.json') -Raw | ConvertFrom-Json).game_dir
    }
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $package 'install.ps1'), '-Action', 'Install', '-NonInteractive')
    if ($GameDir) { $arguments += @('-GameDir', $GameDir) }
    & powershell.exe @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Installation der neuen Version fehlgeschlagen; die bisherige Version bleibt installiert.' }
    Write-Host ''
    Write-Host "Aktualisiert auf $latest." -ForegroundColor Green
    Write-Host "Neuer Paketordner (fuer kuenftige Updates und Deinstallation): $package"
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
