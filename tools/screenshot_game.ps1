# Captures the PC2 window (by process id) to a PNG for automated visual checks.
param([Parameter(Mandatory)][int]$ProcessId, [Parameter(Mandatory)][string]$Out)
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class PC2Shot {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
[PC2Shot]::SetProcessDPIAware() | Out-Null
$process = Get-Process -Id $ProcessId -ErrorAction Stop
[PC2Shot]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 700
$rect = New-Object PC2Shot+RECT
[PC2Shot]::GetWindowRect($process.MainWindowHandle, [ref]$rect) | Out-Null
$width = $rect.R - $rect.L; $height = $rect.B - $rect.T
$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($rect.L, $rect.T, 0, 0, $bitmap.Size)
$small = New-Object System.Drawing.Bitmap $bitmap, ([int]($width / 2)), ([int]($height / 2))
$small.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
"$Out ${width}x${height}"
