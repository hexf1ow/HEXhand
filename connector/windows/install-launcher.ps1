# Registers the right-click "HEXhand here" menu entry and puts hexhand-here on PATH.
$ErrorActionPreference = "Stop"
$dir = "C:\Users\Superuser\.hexhand\connector"
$cmd = Join-Path $dir "hexhand-here.cmd"
$icon = Join-Path $dir "hexhand.ico"

# old CatDesk entries are removed so only one menu item shows
foreach ($old in @("HKCU:\Software\Classes\Directory\shell\CatDeskHere",
                   "HKCU:\Software\Classes\Directory\Background\shell\CatDeskHere")) {
    if (Test-Path $old) { Remove-Item $old -Recurse -Force }
}

foreach ($base in @("HKCU:\Software\Classes\Directory\shell\HEXhandHere",
                    "HKCU:\Software\Classes\Directory\Background\shell\HEXhandHere")) {
    New-Item -Path $base -Force | Out-Null
    Set-ItemProperty -Path $base -Name "(Default)" -Value "HEXhand here"
    if (Test-Path $icon) { Set-ItemProperty -Path $base -Name "Icon" -Value $icon }
    New-Item -Path "$base\command" -Force | Out-Null
    $arg = if ($base -like "*Background*") { "%V" } else { "%1" }
    Set-ItemProperty -Path "$base\command" -Name "(Default)" -Value ('cmd.exe /c ""' + $cmd + '" "' + $arg + '""')
}

# PATH: drop the old folder, add the new one
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$parts = $userPath -split ";" | Where-Object { $_ -and $_ -notlike "*.catdesk\connector*" }
if ($parts -notcontains $dir) { $parts += $dir }
[Environment]::SetEnvironmentVariable("Path", ($parts -join ";"), "User")

"menu:  " + (Test-Path "HKCU:\Software\Classes\Directory\shell\HEXhandHere")
"cmd:   " + (Test-Path $cmd)
"icon:  " + (Test-Path $icon)
"path:  " + (([Environment]::GetEnvironmentVariable("Path", "User")) -like "*\.hexhand\connector*")

# Reserve the connector port for this user. Without it, HttpListener needs an
# elevated shell and the right-click menu appears to do nothing. This needs admin
# ONCE; after that the menu runs as a normal user.
$port = 3210
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$admin = $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$reserved = (netsh http show urlacl) -match ":$port/"
if ($reserved) {
    "urlacl: already reserved"
} elseif ($admin) {
    netsh http add urlacl url=http://+:$port/ user="$env:USERDOMAIN\$env:USERNAME" | Out-Null
    "urlacl: " + [bool]((netsh http show urlacl) -match ":$port/")
} else {
    "urlacl: NOT reserved — re-run this script once in an ADMIN PowerShell,"
    "        otherwise the right-click menu cannot open the port."
}
