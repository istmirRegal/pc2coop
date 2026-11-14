# After a forced stop, PC2 asks at the next start whether to enable extended GPU
# debugging ("Absturz des Grafikkartentreibers"). This answers "Nein" for that start only.
param([Parameter(Mandatory)][int]$ProcessId, [string]$Button = 'Nein')
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class PC2Click {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
[PC2Click]::SetProcessDPIAware() | Out-Null
$process = Get-Process -Id $ProcessId -ErrorAction Stop
if ($process.MainWindowTitle -notmatch 'Grafikkartentreiber|graphics driver') { 'no-dialog'; exit 0 }
[PC2Click]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
$root = [System.Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
$condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Button)
$target = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
if (-not $target) { 'button-missing'; exit 1 }
$rect = $target.Current.BoundingRectangle
[PC2Click]::SetCursorPos([int]($rect.X + $rect.Width / 2), [int]($rect.Y + $rect.Height / 2)) | Out-Null
Start-Sleep -Milliseconds 300
[PC2Click]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80
[PC2Click]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
'dismissed'
