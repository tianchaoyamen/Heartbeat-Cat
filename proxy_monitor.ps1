<#
.SYNOPSIS
    Clash Verge / 代理服务器实时连接状态任务栏托盘监测脚本 (像素猫猫动态版)
    🟢 绿猫猫：正常连通（动态挥手招财猫，摇尾巴、眨眼）
    🔴 红猫猫：连接断开（晕倒 x x 眼、耷拉耳朵、流泪）
    🟡 黄猫猫：检测中 / 启动中（大圆眼好奇歪头）
#>

param(
    [switch]$ShowConsole
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 脚本目录 (兼容控制台、快捷方式与计划任务)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = [System.AppDomain]::CurrentDomain.BaseDirectory }
$ConfigFile = Join-Path $ScriptDir "config.json"
$ErrorLogFile = Join-Path $ScriptDir "error.log"

# 全局错误捕获，防止任何异常导致程序静默闪退
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.AppDomain]::CurrentDomain.add_UnhandledException({
    param($sender, $e)
    try {
        $ex = $e.ExceptionObject
        $msg = "[{0}] Unhandled Exception: {1}`r`n{2}`r`n" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $ex.Message, $ex.StackTrace
        [System.IO.File]::AppendAllText($ErrorLogFile, $msg, [System.Text.Encoding]::UTF8)
    } catch {}
})

# 优化 .NET 底层网络连接池，避免长时间运行导致的句柄与 Socket 泄漏
[System.Net.ServicePointManager]::DefaultConnectionLimit = 50
[System.Net.ServicePointManager]::MaxServicePointIdleTime = 2000
[System.Net.ServicePointManager]::DnsRefreshTimeout = 10000

# 内核级文件锁单实例控制（防重复运行、防权限异常、进程退出由操作系统内核自动回收）
$lockFilePath = Join-Path $env:TEMP "clash_proxy_monitor_kt.lock"
$script:lockStream = $null
try {
    $script:lockStream = [System.IO.File]::Open($lockFilePath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
} catch {
    if ($ShowConsole) {
        Write-Host "检测到 Clash 代理监控已在后台运行中，请查看屏幕右下角任务栏托盘。" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
    exit
}

# 读取配置函数
function Load-Config {
    if (-not (Test-Path $ConfigFile)) {
        $defaultConfig = @{
            mode = "proxy"
            proxy_host = "127.0.0.1"
            proxy_port = 7897
            test_url = "http://www.gstatic.com/generate_204"
            direct_host = "1.1.1.1"
            direct_port = 443
            check_interval_seconds = 3
            timeout_seconds = 2
            show_notification = $true
            notify_delay_seconds = 5
            animation_speed_ms = 400
        }
        $defaultConfig | ConvertTo-Json -Depth 4 | Set-Content -Path $ConfigFile -Encoding UTF8
        return $defaultConfig
    }
    try {
        $raw = Get-Content -Path $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        return $raw
    } catch {
        return @{
            mode = "proxy"
            proxy_host = "127.0.0.1"
            proxy_port = 7897
            test_url = "http://www.gstatic.com/generate_204"
            direct_host = "1.1.1.1"
            direct_port = 443
            check_interval_seconds = 3
            timeout_seconds = 2
            show_notification = $true
            notify_delay_seconds = 5
            animation_speed_ms = 400
        }
    }
}

$config = Load-Config

# 声明 User32 DestroyIcon API，确保完全释放 GDI 句柄，杜绝任何 GDI 内存泄露
if (-not ([System.Management.Automation.PSTypeName]'Win32.NativeMethods').Type) {
    Add-Type -MemberDefinition @"
    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)]
    public static extern bool DestroyIcon(IntPtr handle);
"@ -Name "NativeMethods" -Namespace "Win32" -ErrorAction SilentlyContinue
}

# 像素网格图标渲染器 (16x16 -> 32x32 点阵，高 DPI 清晰保真)
function Render-PixelIcon {
    param(
        [string[]]$Grid,
        [hashtable]$Palette,
        [int]$Scale = 2
    )
    $height = $Grid.Length
    $width = $Grid[0].Replace(" ", "").Length
    $bmp = New-Object System.Drawing.Bitmap ($width * $Scale), ($height * $Scale)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $g.Clear([System.Drawing.Color]::Transparent)

    for ($y = 0; $y -lt $height; $y++) {
        $row = $Grid[$y].Replace(" ", "")
        for ($x = 0; $x -lt $row.Length; $x++) {
            $char = [string]$row[$x]
            if ($Palette.ContainsKey($char) -and $null -ne $Palette[$char]) {
                $color = $Palette[$char]
                $brush = New-Object System.Drawing.SolidBrush $color
                $g.FillRectangle($brush, ($x * $Scale), ($y * $Scale), $Scale, $Scale)
                $brush.Dispose()
            }
        }
    }
    $g.Dispose()

    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon).Clone()
    try { [Win32.NativeMethods]::DestroyIcon($hIcon) | Out-Null } catch {}
    $bmp.Dispose()
    return $icon
}

# ==================== 像素猫猫点阵与调色板设计 (参考经典像素猫 19x17 精准复刻) ====================

# 调色板
# 🟢 绿猫猫（翠绿薄荷毛色 + 纯白口鼻 + 绿色项圈 + 金黄铃铛）
$paletteGreen = @{
    "." = $null
    "#" = [System.Drawing.Color]::FromArgb(35, 45, 40)        # 柔和炭黑描边
    "G" = [System.Drawing.Color]::FromArgb(195, 196, 198)     # 银灰体色（精准复刻参考原图）
    "D" = [System.Drawing.Color]::FromArgb(139, 141, 145)     # 耳窝深灰阴影
    "W" = [System.Drawing.Color]::FromArgb(255, 255, 255)     # 纯白口鼻与爪尖
    "C" = [System.Drawing.Color]::FromArgb(78, 113, 255)      # 宝蓝色项圈（精准复刻参考原图）
    "Y" = [System.Drawing.Color]::FromArgb(255, 215, 0)       # 金黄色铃铛
}

# 🔴 红猫猫（珊瑚红体色 + 纯白口鼻 + 红色项圈 + 蓝色流泪）
$paletteRed = @{
    "." = $null
    "#" = [System.Drawing.Color]::FromArgb(50, 25, 25)        # 深红炭黑描边
    "G" = [System.Drawing.Color]::FromArgb(235, 90, 80)       # 警报珊瑚红体色
    "D" = [System.Drawing.Color]::FromArgb(170, 50, 45)       # 耳窝深红阴影
    "W" = [System.Drawing.Color]::FromArgb(255, 255, 255)     # 纯白口鼻
    "C" = [System.Drawing.Color]::FromArgb(180, 30, 30)       # 红色项圈
    "Y" = [System.Drawing.Color]::FromArgb(240, 200, 50)      # 铃铛
    "B" = [System.Drawing.Color]::FromArgb(52, 152, 219)      # 蓝色断网眼泪
}

# 🟡 黄猫猫（温暖金黄体色 + 纯白口鼻 + 橙色项圈 + 好奇大圆眼）
$paletteYellow = @{
    "." = $null
    "#" = [System.Drawing.Color]::FromArgb(50, 40, 20)        # 深琥珀炭黑描边
    "G" = [System.Drawing.Color]::FromArgb(244, 208, 63)      # 温暖金黄体色
    "D" = [System.Drawing.Color]::FromArgb(214, 137, 16)      # 耳窝深琥珀阴影
    "W" = [System.Drawing.Color]::FromArgb(255, 255, 255)     # 纯白口鼻与眼白
    "C" = [System.Drawing.Color]::FromArgb(230, 126, 34)      # 橙色项圈
    "Y" = [System.Drawing.Color]::FromArgb(255, 235, 120)     # 浅金铃铛
    "Q" = [System.Drawing.Color]::FromArgb(230, 126, 34)      # 疑惑问号标识
}

# 🟢 绿猫猫 4 帧动态连贯点阵 (正统像素猫猫：招手、翘尾巴、眨眼微笑)
$gridGreen1 = @(
    "....................",
    "..##........###.....",
    ".#GG#......#GGG#....",
    ".#DGG#######GGD#....",
    ".#DDGGGGGGGGGDD#....",
    ".#DDGGGGGGGGGDD#....",
    ".#DGGGGGGGGGGGD#....",
    ".#GGGGGGGGGGGGG#....",
    ".#GGG#GGGGG#GGG#.##.",
    ".#GGG#GWWWG#GGG##GG#",
    ".#GGGGWW#WWGGGG#G##G",
    "..#GGWWWWWWWGG##G#.#",
    "...##CCCCCCC##.#G#..",
    "...#GGGGYGGGG#.#G#..",
    "..#GGGGGGGGGGG#G#...",
    "..#GGG#GGG#GGGG#....",
    "..#GGG#GGG#GGG#.....",
    "...###########......",
    "....................",
    "...................."
)

$gridGreen2 = @(
    "....................",
    "..##........###.....",
    ".#GG#......#GGG#....",
    ".#DGG#######GGD#....",
    ".#DDGGGGGGGGGDD#....",
    ".#DDGGGGGGGGGDD#....",
    ".#DGGGGGGGGGGGD#....",
    ".#GGGGGGGGGGGGG#....",
    ".#GGG#GGGGG#GGG#.##.",
    ".#GGG#GWWWG#GGG##GG#",
    ".#GGGGWW#WWGGGG#G##G",
    "..#GGWWWWWWWGG##G#.#",
    "...##CCCCCCC##W#G#..",
    "...#GGGGYGGGG#W#G#..",
    "..#GGGGGGGGGGG#G#...",
    "..#GGG#GGG#GGGG#....",
    "..#GGG#GGG#GGG#.....",
    "...###########......",
    "....................",
    "...................."
)

$gridGreen3 = @(
    "....................",
    "..##........###.....",
    ".#GG#......#GGG#....",
    ".#DGG#######GGD#....",
    ".#DDGGGGGGGGGDD#....",
    ".#DDGGGGGGGGGDD#....",
    ".#DGGGGGGGGGGGD#....",
    ".#GGGGGGGGGGGGG#....",
    ".#GG##GGGGG##GG#.##.",
    ".#G#GGWWWG#G#GG##GG#",
    ".#GGGGWW#WWGGGG#G##G",
    "..#GGWWWWWWWGGW#G#.#",
    "...##CCCCCCC##W#G#..",
    "...#GGGGYGGGG##.G#..",
    "..#GGGGGGGGGGG#G#...",
    "..#GGG#GGG#GGGG#....",
    "..#GGG#GGG#GGG#.....",
    "...###########......",
    "....................",
    "...................."
)

$gridGreen4 = @(
    "....................",
    "..##........###.....",
    ".#GG#......#GGG#....",
    ".#DGG#######GGD#....",
    ".#DDGGGGGGGGGDD#....",
    ".#DDGGGGGGGGGDD#....",
    ".#DGGGGGGGGGGGD#....",
    ".#GGGGGGGGGGGGG#....",
    ".#GG##GGGGG#GGG#.##.",
    ".#GG#GGWWWG#GGG##GG#",
    ".#GGGGWW#WWGGGG#G##G",
    "..#GGWWWWWWWGG##G#.#",
    "...##CCCCCCC##W#G#..",
    "...#GGGGYGGGG##.G#..",
    "..#GGGGGGGGGGG#G#...",
    "..#GGG#GGG#GGGG#....",
    "..#GGG#GGG#GGG#.....",
    "...###########......",
    "....................",
    "...................."
)

# 🔴 红猫猫点阵 (断开连接：耳朵耷拉侧折、x x 晕倒眼、流泪、尾巴垂下)
$gridRed = @(
    "....................",
    "....................",
    "...##........##.....",
    "..#GG########GG#....",
    ".#DGGGGGGGGGGGD#....",
    ".#DDGGGGGGGGGDD#....",
    ".#DGGGGGGGGGGGD#....",
    ".#GGGGGGGGGGGGG#....",
    ".#G#G#GGGGG#G#G#....",
    ".#GG#GGWWWG#GG#G....",
    ".#G#G#WW#WWG#G#GB...",
    "..#GGWWWWWWWGGB#B...",
    "...##CCCCCCC##.BB...",
    "...#GGGGYGGGG#......",
    "..#GGGGGGGGGGG#.....",
    "..#GGG#GGG#GGGG#....",
    "..#GGG#GGG#GGG#####.",
    "...################.",
    "....................",
    "...................."
)

# 🟡 黄猫猫点阵 (检测/初始化：歪头斜耳、大圆眼好奇四顾、疑惑问号)
$gridYellow = @(
    "....................",
    "...##.......###Q....",
    "..#GG#.....#GGG#Q...",
    ".#DGG#######GGD##...",
    ".#DDGGGGGGGGGDD#....",
    ".#DDGGGGGGGGGDD#....",
    ".#DGGGGGGGGGGGD#....",
    ".#GGGGGGGGGGGGG#....",
    ".#GWW#GGGGG#WWG#.##.",
    ".#G##GGWWWG#G##G#GG#",
    ".#GGGGWW#WWGGGG#G##G",
    "..#GGWWWWWWWGG##G#.#",
    "...##CCCCCCC##.#G#..",
    "...#GGGGYGGGG#.#G#..",
    "..#GGGGGGGGGGG#G#...",
    "..#GGG#GGG#GGGG#....",
    "..#GGG#GGG#GGG#.....",
    "...###########......",
    "....................",
    "...................."
)

# 预先生成所有状态图标，内存中驻留复用
$script:greenFrames = @(
    (Render-PixelIcon -Grid $gridGreen1 -Palette $paletteGreen),
    (Render-PixelIcon -Grid $gridGreen2 -Palette $paletteGreen),
    (Render-PixelIcon -Grid $gridGreen3 -Palette $paletteGreen),
    (Render-PixelIcon -Grid $gridGreen4 -Palette $paletteGreen)
)
$script:iconRed = Render-PixelIcon -Grid $gridRed -Palette $paletteRed
$script:iconYellow = Render-PixelIcon -Grid $gridYellow -Palette $paletteYellow

# 缓存的 WebProxy 实例，避免每次重新创建对象
$script:cachedProxy = New-Object System.Net.WebProxy("http://$($config.proxy_host):$($config.proxy_port)")

# 网络连通性测试函数 (严格资源释放与句柄清理)
function Test-ConnectionStatus {
    param($cfg)
    $timeoutMs = [int]($cfg.timeout_seconds * 1000)

    if ($cfg.mode -eq "direct") {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar = $null
        try {
            $ar = $tcp.BeginConnect($cfg.direct_host, [int]$cfg.direct_port, $null, $null)
            $success = $ar.AsyncWaitHandle.WaitOne($timeoutMs)
            if ($success) {
                $tcp.EndConnect($ar)
                $sw.Stop()
                return @{ Success = $true; Delay = $sw.ElapsedMilliseconds; Error = $null }
            } else {
                return @{ Success = $false; Delay = 0; Error = "TCP连接超时" }
            }
        } catch {
            return @{ Success = $false; Delay = 0; Error = $_.Exception.Message }
        } finally {
            if ($null -ne $ar -and $null -ne $ar.AsyncWaitHandle) {
                try { $ar.AsyncWaitHandle.Close() } catch {}
                try { $ar.AsyncWaitHandle.Dispose() } catch {}
            }
            if ($null -ne $tcp) {
                try { $tcp.Close() } catch {}
                try { $tcp.Dispose() } catch {}
            }
        }
    } else {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $req = $null
        $resp = $null
        $respStream = $null
        try {
            $req = [System.Net.HttpWebRequest]::Create($cfg.test_url)
            $req.Proxy = $script:cachedProxy
            $req.Timeout = $timeoutMs
            $req.ReadWriteTimeout = $timeoutMs
            $req.Method = "GET"
            $req.KeepAlive = $false

            $resp = [System.Net.HttpWebResponse]$req.GetResponse()
            $sw.Stop()
            $code = [int]$resp.StatusCode

            $respStream = $resp.GetResponseStream()
            if ($null -ne $respStream) { $respStream.Close() }
            $resp.Close()

            if ($code -ge 200 -and $code -lt 400) {
                return @{ Success = $true; Delay = $sw.ElapsedMilliseconds; Error = $null }
            } else {
                return @{ Success = $false; Delay = 0; Error = "HTTP状态码: $code" }
            }
        } catch [System.Net.WebException] {
            $err = $_.Exception.Status.ToString()
            if ($err -eq "Timeout") { $err = "请求超时" }
            elseif ($err -eq "ConnectFailure") { $err = "无法连接代理端口" }
            
            if ($null -ne $_.Exception.Response) {
                try { $_.Exception.Response.Close() } catch {}
            }
            return @{ Success = $false; Delay = 0; Error = $err }
        } catch {
            return @{ Success = $false; Delay = 0; Error = $_.Exception.Message }
        } finally {
            if ($null -ne $respStream) { try { $respStream.Dispose() } catch {} }
            if ($null -ne $resp) { try { $resp.Dispose() } catch {} }
            if ($null -ne $req) { try { $req.Abort() } catch {} }
        }
    }
}

# 辅助函数：安全设置托盘提示文字（Windows限制<=63字符，且仅在文字变化时才写入）
$script:lastToolTip = ""
function Set-SafeToolTip {
    param($notifyIcon, [string]$text)
    try {
        if ($text.Length -gt 63) {
            $text = $text.Substring(0, 60) + "..."
        }
        if ($script:lastToolTip -ne $text) {
            $script:lastToolTip = $text
            $notifyIcon.Text = $text
        }
    } catch {}
}

# 创建托盘图标组件
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = $script:iconYellow
Set-SafeToolTip $notifyIcon "Clash 像素猫猫: 正在检测..."
$notifyIcon.Visible = $true

# 创建右键上下文菜单
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

$menuStatus = New-Object System.Windows.Forms.ToolStripMenuItem("状态: 初始化中...")
$menuStatus.Enabled = $false

$runRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$runAppName = "HeartbeatCat_PS"

function Test-AutoStartPS {
    try {
        $val = (Get-ItemProperty -Path $runRegPath -Name $runAppName -ErrorAction SilentlyContinue).$runAppName
        return ($null -ne $val)
    } catch { return $false }
}

function Set-AutoStartPS {
    param([bool]$Enable)
    try {
        if ($Enable) {
            $vbsPath = Join-Path $ScriptDir "start_silent.vbs"
            $cmd = "wscript.exe `"$vbsPath`""
            Set-ItemProperty -Path $runRegPath -Name $runAppName -Value $cmd
        } else {
            Remove-ItemProperty -Path $runRegPath -Name $runAppName -ErrorAction SilentlyContinue
        }
    } catch {}
}

$menuCheckNow = New-Object System.Windows.Forms.ToolStripMenuItem("立即检测")
$menuAutoStart = New-Object System.Windows.Forms.ToolStripMenuItem("开机自动启动")
$menuAutoStart.CheckOnClick = $true
$menuAutoStart.Checked = Test-AutoStartPS
$menuAutoStart.Add_Click({
    Set-AutoStartPS $menuAutoStart.Checked
    try {
        if ($menuAutoStart.Checked) {
            $notifyIcon.ShowBalloonTip(2000, "开机自启已开启", "Heartbeat-Cat 已成功注册开机启动项。", [System.Windows.Forms.ToolTipIcon]::Info)
        } else {
            $notifyIcon.ShowBalloonTip(2000, "开机自启已关闭", "已取消开机自动启动。", [System.Windows.Forms.ToolTipIcon]::Info)
        }
    } catch {}
})

$menuOpenConfig = New-Object System.Windows.Forms.ToolStripMenuItem("修改配置 (config.json)")
$menuReloadConfig = New-Object System.Windows.Forms.ToolStripMenuItem("重新加载配置")
$menuSeparator = New-Object System.Windows.Forms.ToolStripSeparator
$menuExit = New-Object System.Windows.Forms.ToolStripMenuItem("退出监控")

$contextMenu.Items.AddRange(@(
    $menuStatus,
    (New-Object System.Windows.Forms.ToolStripSeparator),
    $menuCheckNow,
    $menuAutoStart,
    $menuOpenConfig,
    $menuReloadConfig,
    $menuSeparator,
    $menuExit
))

$notifyIcon.ContextMenuStrip = $contextMenu

# 状态记录
$script:lastState = $null # $true=正常, $false=断开
$script:isChecking = $false
$script:checkCounter = 0

# 延迟通知状态（5秒防抖机制）
$script:disconnectStartTime = $null
$script:disconnectNotified = $false

# 动态猫猫动画定时器
$script:animTimer = New-Object System.Windows.Forms.Timer
$animSpeed = 400
if ($config.animation_speed_ms) { $animSpeed = [int]$config.animation_speed_ms }
$script:animTimer.Interval = $animSpeed
$script:animFrameIndex = 0

$script:animTimer.Add_Tick({
    # 仅在正常连接状态下播放动态帧
    if ($script:lastState -eq $true -and $null -ne $script:greenFrames -and $script:greenFrames.Length -gt 0) {
        $script:animFrameIndex = ($script:animFrameIndex + 1) % $script:greenFrames.Length
        try {
            $notifyIcon.Icon = $script:greenFrames[$script:animFrameIndex]
        } catch {}
    }
})

# 核心检测并更新托盘界面的处理逻辑 (包裹完整 try-catch 保护)
function Do-CheckAndUpdate {
    if ($script:isChecking) { return }
    $script:isChecking = $true

    try {
        # 定期轻量垃圾回收（每运行 100 次检测回收一次），防止长期运行内存缓慢爬升
        $script:checkCounter++
        if ($script:checkCounter % 100 -eq 0) {
            [System.GC]::Collect()
        }

        $timeStr = (Get-Date).ToString("HH:mm:ss")
        $res = Test-ConnectionStatus -cfg $config

        $notifyDelaySec = if ($config.notify_delay_seconds) { [double]$config.notify_delay_seconds } else { 5.0 }

        if ($res.Success) {
            # 状态切换至正常连通：启动动态绿猫猫动画
            if ($script:lastState -ne $true) {
                $script:animFrameIndex = 0
                $notifyIcon.Icon = $script:greenFrames[0]
                $script:animTimer.Start()
            }

            $statusStr = "连接正常 ($($res.Delay)ms)"
            Set-SafeToolTip $notifyIcon "猫猫: 连通正常 ($($res.Delay)ms) [$timeStr]"
            $menuStatus.Text = "当前: $statusStr [$timeStr]"

            if ($ShowConsole) {
                Write-Host "[$timeStr] 🟢 [正常] 延迟: $($res.Delay)ms (猫猫欢快招手中🐾)" -ForegroundColor Green
            }

            # 仅在之前已报警过断开的情况下，才弹窗提示恢复
            if ($script:disconnectNotified -and $config.show_notification) {
                try {
                    $notifyIcon.ShowBalloonTip(3000, "代理连接已恢复", "当前节点连接正常，延迟: $($res.Delay)ms，猫猫已恢复元气！", [System.Windows.Forms.ToolTipIcon]::Info)
                } catch {}
            }

            # 重置断开计时状态
            $script:disconnectStartTime = $null
            $script:disconnectNotified = $false
            $script:lastState = $true
        } else {
            # 状态切换至断开：停止动态动画，切换为断网红猫猫 (x x 晕倒)
            if ($script:lastState -ne $false) {
                $script:animTimer.Stop()
                $notifyIcon.Icon = $script:iconRed
            }

            $errMsg = $res.Error
            $statusStr = "已断开 ($errMsg)"
            Set-SafeToolTip $notifyIcon "猫猫: 连接已断开 ($errMsg) [$timeStr]"
            $menuStatus.Text = "当前: $statusStr [$timeStr]"

            if ($null -eq $script:disconnectStartTime) {
                $script:disconnectStartTime = [DateTime]::UtcNow
            }

            $disconnectedDuration = ([DateTime]::UtcNow - $script:disconnectStartTime).TotalSeconds

            if ($ShowConsole) {
                $durStr = [Math]::Round($disconnectedDuration, 1)
                Write-Host "[$timeStr] 🔴 [断开] 原因: $errMsg (已持续: ${durStr}秒，猫猫晕倒中)" -ForegroundColor Red
            }

            # 超过阈值才发出系统通知
            if ($disconnectedDuration -ge $notifyDelaySec -and -not $script:disconnectNotified -and $config.show_notification) {
                try {
                    $notifyIcon.ShowBalloonTip(5000, "⚠️ 代理服务器已断开！", "代理已持续断开超过 $([int]$notifyDelaySec) 秒 ($errMsg)，猫猫已断线晕倒，请检查Clash Verge节点。", [System.Windows.Forms.ToolTipIcon]::Warning)
                } catch {}
                $script:disconnectNotified = $true
            }

            $script:lastState = $false
        }
    } catch {
        try {
            $msg = "[{0}] Exception in Do-CheckAndUpdate: {1}`r`n" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $_.Exception.ToString()
            [System.IO.File]::AppendAllText($ErrorLogFile, $msg, [System.Text.Encoding]::UTF8)
        } catch {}
    } finally {
        $script:isChecking = $false
    }
}

# 绑定菜单事件
$menuCheckNow.Add_Click({
    Do-CheckAndUpdate
})

$menuOpenConfig.Add_Click({
    try {
        Start-Process notepad.exe -ArgumentList "`"$ConfigFile`""
    } catch {}
})

$menuReloadConfig.Add_Click({
    try {
        $script:config = Load-Config
        $script:cachedProxy = New-Object System.Net.WebProxy("http://$($config.proxy_host):$($config.proxy_port)")
        $timer.Interval = [int]($config.check_interval_seconds * 1000)
        $animSpeedReload = 400
        if ($config.animation_speed_ms) { $animSpeedReload = [int]$config.animation_speed_ms }
        $script:animTimer.Interval = $animSpeedReload
        $delaySec = if ($config.notify_delay_seconds) { $config.notify_delay_seconds } else { 5 }
        [System.Windows.Forms.MessageBox]::Show(
            "配置文件已重新加载！`n检测间隔: $($config.check_interval_seconds)秒`n通知防抖延时: $($delaySec)秒`n动画速度: $($script:animTimer.Interval)ms`n模式: $($config.mode)`n端口: $($config.proxy_port)",
            "配置重载成功",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        Do-CheckAndUpdate
    } catch {}
})

# 检测定时器设置
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = [int]($config.check_interval_seconds * 1000)
$timer.Add_Tick({
    Do-CheckAndUpdate
})

# 退出清理
$exitAction = {
    try {
        $script:animTimer.Stop()
        $script:animTimer.Dispose()
        $timer.Stop()
        $timer.Dispose()
        $notifyIcon.Visible = $false
        $notifyIcon.Dispose()
        foreach ($f in $script:greenFrames) {
            try { $f.Dispose() } catch {}
        }
        $script:iconRed.Dispose()
        $script:iconYellow.Dispose()
        if ($null -ne $script:lockStream) {
            $script:lockStream.Close()
            $script:lockStream.Dispose()
        }
    } catch {}
    if ($null -ne $script:appContext) {
        try { $script:appContext.ExitThread() } catch {}
    }
    [System.Windows.Forms.Application]::Exit()
}

$menuExit.Add_Click($exitAction)

# 双击托盘图标：立即检测
$notifyIcon.Add_DoubleClick({
    Do-CheckAndUpdate
})

# 启动定时器并执行初次检测
$timer.Start()
Do-CheckAndUpdate

# 启动 Windows 消息循环 (使用 ApplicationContext 确保无窗体时消息循环永不主动退出)
$script:appContext = New-Object System.Windows.Forms.ApplicationContext
[System.Windows.Forms.Application]::Run($script:appContext)

# 保持锁文件流存活，防止垃圾回收提前回收导致释放锁
[System.GC]::KeepAlive($script:lockStream)
