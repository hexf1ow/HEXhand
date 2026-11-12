# Keeps the HEXhand connector alive.
# A dead connector makes every ChatGPT tool call hang until it times out, which
# looks like a server problem. Run this from Task Scheduler every few minutes.
$ErrorActionPreference = "SilentlyContinue"
$dir = "C:\Users\Superuser\.hexhand\connector"
$log = Join-Path $dir "watchdog.log"

$listening = Get-NetTCPConnection -LocalPort 3210 -State Listen
if ($listening) { exit 0 }

# not listening: is the process gone, or wedged?
$proc = Get-CimInstance Win32_Process -Filter "name='powershell.exe'" |
        Where-Object { $_.CommandLine -like "*hexhand-here.ps1*" }
if ($proc) {
    # alive but not serving — kill it so the fresh start can bind
    foreach ($p in $proc) { Stop-Process -Id $p.ProcessId -Force }
    Start-Sleep -Seconds 3
    "$(Get-Date -Format s)  killed wedged connector" | Out-File $log -Append -Encoding ascii
}

# Restart the folder the user last activated from the right-click menu.
$stateFile = Join-Path $dir "last_folder.txt"
$folder = "D:\NumeCORE_Firm"
if (Test-Path $stateFile) {
    $saved = (Get-Content $stateFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($saved -and (Test-Path $saved)) { $folder = $saved.Trim() }
}
"$(Get-Date -Format s)  restarting for $folder" | Out-File $log -Append -Encoding ascii

Start-Process -FilePath (Join-Path $dir "hexhand-here.cmd") `
    -ArgumentList ('"' + $folder + '"') -WindowStyle Hidden
Start-Sleep -Seconds 6
$ok = [bool](Get-NetTCPConnection -LocalPort 3210 -State Listen)
"$(Get-Date -Format s)  restarted connector ok=$ok" | Out-File $log -Append -Encoding ascii
