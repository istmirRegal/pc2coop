param(
    [ValidateSet('Install', 'Uninstall')][string]$Action = 'Install',
    [string]$GameDir = '',
    [switch]$NonInteractive,
    [switch]$LibraryOnly
)
$ErrorActionPreference = 'Stop'
$script:SupportedExeHash = '9da90ae2611bf41af532a30611082bd90cdda6b325e570ac63a469051e736c12'

function File-Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

function Get-GameFolder {
    $roots = @()
    foreach ($entry in @(
        @('HKCU:\Software\Valve\Steam', 'SteamPath'),
        @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath')
    )) {
        try { $roots += (Get-ItemProperty -LiteralPath $entry[0] -Name $entry[1]).($entry[1]) } catch {}
    }
    if (${env:ProgramFiles(x86)}) { $roots += Join-Path ${env:ProgramFiles(x86)} 'Steam' }
    $libraries = @($roots)
    foreach ($root in $roots) {
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf -PathType Leaf) {
            $body = Get-Content -LiteralPath $vdf -Raw
            foreach ($match in [regex]::Matches($body, '"path"\s*"((?:[^"\\]|\\.)*)"')) {
                $libraries += $match.Groups[1].Value.Replace('\\', '\')
            }
        }
    }
    foreach ($library in ($libraries | Select-Object -Unique)) {
        $manifest = Join-Path $library 'steamapps\appmanifest_2688950.acf'
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }
        $body = Get-Content -LiteralPath $manifest -Raw
        $match = [regex]::Match($body, '"installdir"\s*"([^"/\\:]+)"')
        if ($match.Success -and $match.Groups[1].Value -notin @('.', '..')) {
            $candidate = Join-Path $library ('steamapps\common\' + $match.Groups[1].Value)
            if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
        }
    }
    return ''
}

function Safe-ModPath([string]$Root, [string]$Relative) {
    if ($Relative -notmatch '^(ACSE|PC2CoopProbe)/[A-Za-z0-9_.-]+$') { throw "Ungueltiger Paketpfad: $Relative" }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $target = [IO.Path]::GetFullPath((Join-Path $Root $Relative.Replace('/', [IO.Path]::DirectorySeparatorChar)))
    if (-not $target.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw 'Pfad liegt ausserhalb des Modordners.' }
    return $target
}

function Install-IntoGame([string]$Folder, [string]$Package, [string]$ExpectedExeHash) {
    $game = [IO.Path]::GetFullPath($Folder)
    $exe = Join-Path $game 'Win64\PlanetCoaster2.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { $exe = Join-Path $game 'PlanetCoaster2.exe' }
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'PlanetCoaster2.exe wurde in diesem Ordner nicht gefunden.' }
    if ((File-Hash $exe) -ne $ExpectedExeHash) {
        # The mod finds what it needs in the game at start-up; a new game build usually works.
        Write-Host 'Hinweis: Diese Spielversion wurde mit PC2Coop noch nicht getestet (getestet: Build 26255360). Wird trotzdem installiert.' -ForegroundColor Yellow
        Write-Host 'Klappt der Multiplayer nicht, bitte die Log-Datei aus Win64\ovldata\PC2CoopProbe an den Host schicken.' -ForegroundColor Yellow
    }
    $ovldata = Join-Path $game 'Win64\ovldata'
    if (-not (Test-Path -LiteralPath $ovldata -PathType Container)) { throw 'Win64\ovldata fehlt. Installation abgebrochen.' }
    $journalPath = Join-Path $ovldata '.pc2coop-alpha-install.json'
    $oldFiles = @{}
    if (Test-Path -LiteralPath $journalPath -PathType Leaf) {
        $journal = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
        foreach ($entry in @($journal.files)) { $oldFiles[$entry.path] = $entry }
    }
    $manifest = Get-Content -LiteralPath (Join-Path $Package 'payload-manifest.json') -Raw | ConvertFrom-Json
    $plan = @()
    $newFiles = @()
    foreach ($entry in @($manifest.files)) {
        $source = Safe-ModPath (Join-Path $Package 'payload') $entry.path
        $target = Safe-ModPath $ovldata $entry.path
        if ((File-Hash $source) -ne $entry.sha256) { throw "Paket beschaedigt: $($entry.path). ZIP erneut entpacken." }
        $exists = Test-Path -LiteralPath $target -PathType Leaf
        $old = $oldFiles[$entry.path]
        if ($exists) {
            $actual = File-Hash $target
            if ($old -and $actual -ne $old.sha256) { throw "Lokal veraenderte Datei wird nicht ueberschrieben: $($entry.path)" }
            if (-not $old -and $actual -ne $entry.sha256) { throw "Andere Modversion vorhanden: $($entry.path). Diese zuerst mit ihrem Installer entfernen." }
        }
        $owned = [bool]$old -or -not $exists
        if ($owned) { $newFiles += [pscustomobject]@{ path = $entry.path; sha256 = $entry.sha256 } }
        if (-not $exists -or (File-Hash $target) -ne $entry.sha256) {
            $plan += [pscustomobject]@{ source = $source; target = $target; relative = $entry.path; existed = $exists }
        }
    }
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fffffff')
    $backupRoot = Join-Path $ovldata ('.pc2coop-alpha-backups\' + $stamp)
    $applied = @()
    try {
        foreach ($step in $plan) {
            $parent = Split-Path -Parent $step.target
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
            if ($step.existed) {
                $backup = Safe-ModPath $backupRoot $step.relative
                New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
                Copy-Item -LiteralPath $step.target -Destination $backup
            }
            $applied += $step
            Copy-Item -LiteralPath $step.source -Destination $step.target -Force
        }
        $state = [pscustomobject]@{ schema = 1; package = 'PC2Coop'; installed_utc = $stamp; files = @($newFiles) }
        [pscustomobject]@{ game_dir = $game } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Package 'installation.json') -Encoding UTF8
        $journalTemp = $journalPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
        $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $journalTemp -Encoding UTF8
        Move-Item -LiteralPath $journalTemp -Destination $journalPath -Force
    } catch {
        foreach ($step in ($applied | Sort-Object -Property target -Descending)) {
            if ($step.existed) { Copy-Item -LiteralPath (Safe-ModPath $backupRoot $step.relative) -Destination $step.target -Force }
            elseif (Test-Path -LiteralPath $step.target -PathType Leaf) { Remove-Item -LiteralPath $step.target }
        }
        throw
    }
    Write-Host "Installiert: $($plan.Count) Dateien. Spiel starten: Hauptmenue -> Multiplayer oder im Park Pausemenue -> Multiplayer (F7)." -ForegroundColor Green
    Write-Host "Installationsprotokoll: $journalPath"
}

function Uninstall-FromGame([string]$Folder, [string]$Package) {
    $ovldata = Join-Path ([IO.Path]::GetFullPath($Folder)) 'Win64\ovldata'
    $journalPath = Join-Path $ovldata '.pc2coop-alpha-install.json'
    if (-not (Test-Path -LiteralPath $journalPath -PathType Leaf)) { throw 'Kein Installationsprotokoll gefunden. Es wurden keine Dateien entfernt.' }
    $journal = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
    foreach ($entry in @($journal.files)) {
        $target = Safe-ModPath $ovldata $entry.path
        if ((Test-Path -LiteralPath $target -PathType Leaf) -and (File-Hash $target) -ne $entry.sha256) {
            throw "Datei wurde nach Installation veraendert: $($entry.path). Deinstallation abgebrochen; Dateien bleiben erhalten."
        }
    }
    foreach ($entry in @($journal.files)) {
        $target = Safe-ModPath $ovldata $entry.path
        if (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target }
    }
    foreach ($name in @('PC2CoopProbe', 'ACSE')) {
        $directory = Join-Path $ovldata $name
        if ((Test-Path -LiteralPath $directory -PathType Container) -and @(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) {
            Remove-Item -LiteralPath $directory
        }
    }
    Remove-Item -LiteralPath $journalPath
    Write-Host 'Eigene installierte Dateien entfernt. Bereits vorhandene identische ACSE-Dateien, Protokolle und Sicherungen bleiben erhalten.' -ForegroundColor Green
}

if ($LibraryOnly) { return }
try {
    if (Get-Process -Name PlanetCoaster2 -ErrorAction SilentlyContinue) { throw 'Bitte Planet Coaster 2 zuerst normal beenden.' }
    if (-not $GameDir -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'installation.json'))) {
        $GameDir = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'installation.json') -Raw | ConvertFrom-Json).game_dir
    }
    if (-not $GameDir) { $GameDir = Get-GameFolder }
    if (-not $GameDir -and -not $NonInteractive) { $GameDir = Read-Host 'PC2-Installationsordner (enthaelt Win64)' }
    if (-not $GameDir) { throw 'Spielordner fehlt. INSTALL.cmd -GameDir "D:\SteamLibrary\steamapps\common\Planet Coaster 2" verwenden.' }
    Write-Host "Spielordner: $GameDir"
    if ($Action -eq 'Install') { Install-IntoGame $GameDir $PSScriptRoot $script:SupportedExeHash }
    else { Uninstall-FromGame $GameDir $PSScriptRoot }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host 'Bei Zugriffsproblemen: Ordnerberechtigung pruefen. Der Installer fordert keine Administratorrechte an.'
    exit 1
}
