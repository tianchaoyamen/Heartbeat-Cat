@echo off
chcp 65001 >nul
title 停止心跳猫猫监控 (Heartbeat-Cat)
echo 正在停止 Heartbeat-Cat 进程...

taskkill /f /im HeartbeatCat.exe 2>nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*proxy_monitor.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host ('[已停止 PowerShell 监控] PID: ' + $_.ProcessId) }"

echo 停止完成。
ping 127.0.0.1 -n 2 >nul
