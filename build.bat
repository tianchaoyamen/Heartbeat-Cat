@echo off
chcp 65001 >nul
echo [Heartbeat-Cat] 开始编译独立可执行程序 HeartbeatCat.exe ...

set CSC=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC%" (
    set CSC=C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe
)

if not exist "%CSC%" (
    echo [错误] 未在系统中检测到 .NET Framework 4.0+ 编译工具 csc.exe！
    pause
    exit /b 1
)

"%CSC%" /target:winexe /optimize+ /r:System.Drawing.dll,System.Windows.Forms.dll,System.Web.Extensions.dll /out:"HeartbeatCat.exe" "src\Program.cs"

if %errorlevel% equ 0 (
    echo [成功] 编译完成: HeartbeatCat.exe
) else (
    echo [失败] 编译出错，返回代码: %errorlevel%
)

pause
