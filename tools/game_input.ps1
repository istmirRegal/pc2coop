# Test input for the PC2 window: click, drag or key, in full-resolution screen pixels.
# Example: game_input.ps1 -ProcessId 123 -Action click -X 960 -Y 540
#          game_input.ps1 -ProcessId 123 -Action drag -X 800 -Y 600 -X2 1100 -Y2 600
#          game_input.ps1 -ProcessId 123 -Action key -Key 0x1B   (virtual-key code)
param([Parameter(Mandatory)][int]$ProcessId, [Parameter(Mandatory)][ValidateSet('click','rclick','drag','move','key')][string]$Action,
      [int]$X, [int]$Y, [int]$X2, [int]$Y2, [int]$Key, [int]$Steps = 20)
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class PC2Input {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s, uint f, UIntPtr e);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
[PC2Input]::SetProcessDPIAware() | Out-Null
$process = Get-Process -Id $ProcessId -ErrorAction Stop
[PC2Input]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 300
switch ($Action) {
    'move'   { [PC2Input]::SetCursorPos($X, $Y) | Out-Null }
    'click'  { [PC2Input]::SetCursorPos($X, $Y) | Out-Null; Start-Sleep -Milliseconds 250
               [PC2Input]::mouse_event(2,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [PC2Input]::mouse_event(4,0,0,0,[UIntPtr]::Zero) }
    'rclick' { [PC2Input]::SetCursorPos($X, $Y) | Out-Null; Start-Sleep -Milliseconds 250
               [PC2Input]::mouse_event(8,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [PC2Input]::mouse_event(16,0,0,0,[UIntPtr]::Zero) }
    'drag'   { [PC2Input]::SetCursorPos($X, $Y) | Out-Null; Start-Sleep -Milliseconds 250
               [PC2Input]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
               for ($i = 1; $i -le $Steps; $i++) {
                   [PC2Input]::SetCursorPos([int]($X + ($X2 - $X) * $i / $Steps), [int]($Y + ($Y2 - $Y) * $i / $Steps)) | Out-Null
                   Start-Sleep -Milliseconds 40 }
               Start-Sleep -Milliseconds 150; [PC2Input]::mouse_event(4,0,0,0,[UIntPtr]::Zero) }
    'key'    { [PC2Input]::keybd_event([byte]$Key,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 90; [PC2Input]::keybd_event([byte]$Key,0,2,[UIntPtr]::Zero) }
}
'ok'
