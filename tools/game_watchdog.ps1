# Watches the PC2 test copy during automated tests and stops it before it can take the PC down.
# Every 3 s one line goes to the log (flushed at once, so it survives a freeze): RAM of the
# game, free RAM of the system, GPU memory and load, whether the window responds.
# Stops the game (only the given process) when it uses more than -MaxWorkingSetGB, or when
# its window has not responded for -MaxHungSeconds.
# Example: game_watchdog.ps1 -ProcessId 123 -Log watchdog-123.log
param([Parameter(Mandatory)][int]$ProcessId, [Parameter(Mandatory)][string]$Log,
      [double]$MaxWorkingSetGB = 24, [int]$MaxHungSeconds = 45, [int]$IntervalSeconds = 3)
$smi = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
$hungSince = $null
function Write-Line([string]$text) { Add-Content -Path $Log -Value ("{0:HH:mm:ss} {1}" -f (Get-Date), $text) -Encoding utf8 }
Write-Line "start pid=$ProcessId maxWS=${MaxWorkingSetGB}GB maxHung=${MaxHungSeconds}s"
while ($true) {
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $p -or $p.HasExited) { Write-Line 'game ended'; break }
    if ($p.ProcessName -notlike 'PlanetCoaster*') { Write-Line "pid is $($p.ProcessName), not the game: stop watching"; break }
    $ws = [math]::Round($p.WorkingSet64 / 1GB, 2)
    $private = [math]::Round($p.PrivateMemorySize64 / 1GB, 2)
    $free = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
    $gpu = ''
    if (Test-Path $smi) {
        $gpu = (& $smi --query-gpu=memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>$null) -join ' '
    }
    $responding = $p.Responding
    Write-Line "ws=${ws}GB private=${private}GB sysfree=${free}GB gpu[memMB,totalMB,load%,C]=$gpu responding=$responding"
    if ($ws -gt $MaxWorkingSetGB) {
        Write-Line "STOP: working set ${ws}GB over ${MaxWorkingSetGB}GB"
        Stop-Process -Id $ProcessId -Force; break
    }
    if (-not $responding) {
        if (-not $hungSince) { $hungSince = Get-Date }
        elseif (((Get-Date) - $hungSince).TotalSeconds -gt $MaxHungSeconds) {
            Write-Line "STOP: window not responding for more than ${MaxHungSeconds}s"
            Stop-Process -Id $ProcessId -Force; break
        }
    } else { $hungSince = $null }
    Start-Sleep -Seconds $IntervalSeconds
}
