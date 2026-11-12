<#
  hexhand-here — activate the HEXhand connector for a folder.

  From Explorer: right-click a folder -> "HEXhand here"  (after running register-context-menu.ps1 once)
  From a terminal:  powershell -ExecutionPolicy Bypass -File hexhand-here.ps1 -Path "D:\some\folder"
  Or simply:        cd D:\some\folder ; powershell -ExecutionPolicy Bypass -File hexhand-here.ps1

  The chosen folder becomes the workspace the HEXhand container works in.
#>

param(
    [string]$Path = ".",
    [int]$Port = 3210
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Path)) { throw "Folder not found: $Path" }
$target = (Resolve-Path $Path).Path

Write-Host ""
Write-Host "  Activating HEXhand for: $target" -ForegroundColor Cyan
Write-Host ""

# Take over: stop any connector already running, so a new folder becomes the workspace.
$others = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
          Where-Object { ($_.CommandLine -like "*hexhand-connect.ps1*" -or $_.CommandLine -like "*hexhand-here.ps1*") -and $_.ProcessId -ne $PID }
foreach ($o in $others) {
    Write-Host ("  stopping connector for another folder (pid " + $o.ProcessId + ")") -ForegroundColor Yellow
    try { Stop-Process -Id $o.ProcessId -Force } catch {}
}
if ($others) { Start-Sleep -Seconds 2 }

& "$PSScriptRoot\hexhand-connect.ps1" -Folder $target -Port $Port
