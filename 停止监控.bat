@echo off
taskkill /f /im HeartbeatCat.exe >nul 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*proxy_monitor.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
exit /b 0
