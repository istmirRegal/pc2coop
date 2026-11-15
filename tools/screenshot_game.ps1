# Captures the PC2 window (by process id) to a PNG for automated visual checks.
# Reads the window's own content (PrintWindow); it never brings the game to the front and
# never copies the screen, so it cannot disturb or capture what the owner is doing.
param([Parameter(Mandatory)][int]$ProcessId, [Parameter(Mandatory)][string]$Out)
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class PC2Shot {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
[PC2Shot]::SetProcessDPIAware() | Out-Null
$process = Get-Process -Id $ProcessId -ErrorAction Stop
$rect = New-Object PC2Shot+RECT
[PC2Shot]::GetClientRect($process.MainWindowHandle, [ref]$rect) | Out-Null
$width = $rect.R - $rect.L; $height = $rect.B - $rect.T
if ($width -le 0 -or $height -le 0) { throw 'Game window has no size (minimised?).' }
$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$dc = $graphics.GetHdc()
# 1 = client area only, 2 = PW_RENDERFULLCONTENT (needed for GPU-rendered windows)
$ok = [PC2Shot]::PrintWindow($process.MainWindowHandle, $dc, 3)
$graphics.ReleaseHdc($dc)
if (-not $ok) { throw 'PrintWindow failed.' }
$small = New-Object System.Drawing.Bitmap $bitmap, ([int]($width / 2)), ([int]($height / 2))
$small.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
"$Out ${width}x${height}"
