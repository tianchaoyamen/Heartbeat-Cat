@echo off
title Clash Proxy Monitor Console
cd /d "%~dp0"
echo ========================================================
echo        Clash Proxy Server Monitor (Debug Console)
echo ========================================================
echo.
echo Tray icon is running in the bottom-right taskbar (Green/Red dot).
echo Closing this window will stop the monitor.
echo For silent background mode without console, run:
echo   [启动监控(静默后台).vbs]
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0proxy_monitor.ps1" -ShowConsole
pause