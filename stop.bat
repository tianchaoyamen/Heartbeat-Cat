@echo off
title Stop Clash Proxy Monitor
echo Stopping Clash Proxy Monitor...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*proxy_monitor.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host ('[Stopped] PID: ' + $_.ProcessId) }"
echo Done.
ping 127.0.0.1 -n 2 >nul