@echo off
rem HEXhand here — activate the connector for a folder.
rem   hexhand-here            (current folder)
rem   hexhand-here D:\folder  (that folder)
setlocal
set "FOLDER=%~1"
if "%FOLDER%"=="" set "FOLDER=%CD%"
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Superuser\.hexhand\connector\hexhand-here.ps1" -Path "%FOLDER%"
endlocal
