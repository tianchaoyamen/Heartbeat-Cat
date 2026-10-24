using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace HeartbeatCat {
    public class AppConfig {
        public string mode { get; set; }
        public string proxy_host { get; set; }
        public int proxy_port { get; set; }
        public string test_url { get; set; }
        public string direct_host { get; set; }
        public int direct_port { get; set; }
        public int check_interval_seconds { get; set; }
        public int timeout_seconds { get; set; }
        public bool show_notification { get; set; }
        public int notify_delay_seconds { get; set; }
        public int animation_speed_ms { get; set; }

        public static AppConfig CreateDefault() {
            return new AppConfig {
                mode = "proxy",
                proxy_host = "127.0.0.1",
                proxy_port = 7897,
                test_url = "http://www.gstatic.com/generate_204",
                direct_host = "1.1.1.1",
                direct_port = 443,
                check_interval_seconds = 3,
                timeout_seconds = 2,
                show_notification = true,
                notify_delay_seconds = 5,
                animation_speed_ms = 400
            };
        }
    }

    internal static class NativeMethods {
        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern bool DestroyIcon(IntPtr handle);
    }

    public class CatTrayContext : ApplicationContext {
        private NotifyIcon notifyIcon;
        private ContextMenuStrip contextMenu;
        private ToolStripMenuItem menuStatus;
        private System.Windows.Forms.Timer checkTimer;
        private System.Windows.Forms.Timer animTimer;

        private AppConfig config;
        private string scriptDir;
        private string configPath;
        private string errorLogPath;
        private FileStream lockStream;

        private Icon[] greenFrames;
        private Icon iconRed;
        private Icon iconYellow;
        private int animFrameIndex = 0;

        private bool? lastState = null; // true = ok, false = down
        private bool isChecking = false;
        private DateTime? disconnectStartTime = null;
        private bool disconnectNotified = false;
        private WebProxy cachedProxy;
        private int checkCounter = 0;
        private string lastToolTip = "";

        public CatTrayContext() {
            scriptDir = AppDomain.CurrentDomain.BaseDirectory;
            configPath = Path.Combine(scriptDir, "config.json");
            errorLogPath = Path.Combine(scriptDir, "error.log");

            // Global exception handling
            Application.ThreadException += (s, e) => LogException(e.Exception);
            AppDomain.CurrentDomain.UnhandledException += (s, e) => {
                var ex = e.ExceptionObject as Exception;
                if (ex != null) LogException(ex);
            };

            // Network ServicePoint tuning
            ServicePointManager.DefaultConnectionLimit = 50;
            ServicePointManager.MaxServicePointIdleTime = 2000;
            ServicePointManager.DnsRefreshTimeout = 10000;

            // Kernel file lock for single instance
            string lockPath = Path.Combine(Path.GetTempPath(), "clash_heartbeat_cat.lock");
            try {
                lockStream = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            } catch {
                MessageBox.Show("Heartbeat-Cat (心跳猫猫) 已经在运行中！\n请查看屏幕右下角任务栏托盘区域（可从折叠箭头 ^ 拖出常驻）。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
                Environment.Exit(0);
                return;
            }

            LoadConfiguration();
            InitializeCatIcons();
            InitializeTrayUI();

            // Setup timers
            checkTimer = new System.Windows.Forms.Timer();
            checkTimer.Interval = Math.Max(1000, config.check_interval_seconds * 1000);
            checkTimer.Tick += (s, e) => DoCheckAndUpdate();

            animTimer = new System.Windows.Forms.Timer();
            animTimer.Interval = Math.Max(100, config.animation_speed_ms);
            animTimer.Tick += (s, e) => {
                if (lastState == true && greenFrames != null && greenFrames.Length > 0) {
                    animFrameIndex = (animFrameIndex + 1) % greenFrames.Length;
                    try {
                        notifyIcon.Icon = greenFrames[animFrameIndex];
                    } catch {}
                }
            };

            checkTimer.Start();
            DoCheckAndUpdate();
        }

        private void LoadConfiguration() {
            var serializer = new JavaScriptSerializer();
            if (!File.Exists(configPath)) {
                config = AppConfig.CreateDefault();
                try {
                    File.WriteAllText(configPath, serializer.Serialize(config));
                } catch {}
            } else {
                try {
                    string json = File.ReadAllText(configPath);
                    config = serializer.Deserialize<AppConfig>(json) ?? AppConfig.CreateDefault();
                } catch {
                    config = AppConfig.CreateDefault();
                }
            }

            if (config.check_interval_seconds <= 0) config.check_interval_seconds = 3;
            if (config.timeout_seconds <= 0) config.timeout_seconds = 2;
            if (config.notify_delay_seconds <= 0) config.notify_delay_seconds = 5;
            if (config.animation_speed_ms <= 0) config.animation_speed_ms = 400;

            cachedProxy = new WebProxy("http://" + config.proxy_host + ":" + config.proxy_port);
        }

        private void InitializeCatIcons() {
            // Palettes
            // Connected: Exact Silver-Gray Reference Cat with Blue Collar & Golden Bell
            var palConnected = new Dictionary<char, Color> {
                { '#', Color.FromArgb(35, 45, 40) },       // Soft charcoal outline
                { 'G', Color.FromArgb(195, 196, 198) },   // Silver-gray fur (exact reference)
                { 'D', Color.FromArgb(139, 141, 145) },   // Dark gray inner ear (exact reference)
                { 'W', Color.FromArgb(255, 255, 255) },   // Pure white muzzle & paws
                { 'C', Color.FromArgb(78, 113, 255) },    // Royal blue collar (exact reference)
                { 'Y', Color.FromArgb(255, 215, 0) }      // Golden bell (exact reference)
            };

            // Disconnected: Coral Red theme, droopy ears, x x eyes, blue teardrop
            var palRed = new Dictionary<char, Color> {
                { '#', Color.FromArgb(50, 25, 25) },
                { 'G', Color.FromArgb(235, 90, 80) },
                { 'D', Color.FromArgb(170, 50, 45) },
                { 'W', Color.FromArgb(255, 255, 255) },
                { 'C', Color.FromArgb(180, 30, 30) },
                { 'Y', Color.FromArgb(240, 200, 50) },
                { 'B', Color.FromArgb(52, 152, 219) }
            };

            // Checking: Warm amber-yellow, curious round eyes, question mark
            var palYellow = new Dictionary<char, Color> {
                { '#', Color.FromArgb(50, 40, 20) },
                { 'G', Color.FromArgb(244, 208, 63) },
                { 'D', Color.FromArgb(214, 137, 16) },
                { 'W', Color.FromArgb(255, 255, 255) },
                { 'C', Color.FromArgb(230, 126, 34) },
                { 'Y', Color.FromArgb(255, 235, 120) },
                { 'Q', Color.FromArgb(230, 126, 34) }
            };

            // 20x20 Grids: Tail is completely STATIC in all connected frames!
            string[] g1 = new string[] {
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
            };

            string[] g2 = new string[] {
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
            };

            string[] g3 = new string[] {
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
            };

            string[] g4 = new string[] {
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
            };

            string[] gRed = new string[] {
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
            };

            string[] gYellow = new string[] {
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
            };

            greenFrames = new Icon[] {
                RenderPixelIcon(g1, palConnected, 2),
                RenderPixelIcon(g2, palConnected, 2),
                RenderPixelIcon(g3, palConnected, 2),
                RenderPixelIcon(g4, palConnected, 2)
            };
            iconRed = RenderPixelIcon(gRed, palRed, 2);
            iconYellow = RenderPixelIcon(gYellow, palYellow, 2);
        }

        private Icon RenderPixelIcon(string[] grid, Dictionary<char, Color> palette, int scale) {
            int height = grid.Length;
            int width = grid[0].Length;
            using (var bmp = new Bitmap(width * scale, height * scale)) {
                using (var g = Graphics.FromImage(bmp)) {
                    g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;
                    g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
                    g.Clear(Color.Transparent);

                    for (int y = 0; y < height; y++) {
                        string row = grid[y];
                        for (int x = 0; x < width; x++) {
                            char ch = row[x];
                            if (palette.ContainsKey(ch)) {
                                using (var brush = new SolidBrush(palette[ch])) {
                                    g.FillRectangle(brush, x * scale, y * scale, scale, scale);
                                }
                            }
                        }
                    }
                }
                IntPtr hIcon = bmp.GetHicon();
                Icon icon = (Icon)Icon.FromHandle(hIcon).Clone();
                NativeMethods.DestroyIcon(hIcon);
                return icon;
            }
        }

        private void InitializeTrayUI() {
            contextMenu = new ContextMenuStrip();
            menuStatus = new ToolStripMenuItem("状态: 初始化中...") { Enabled = false };
            var menuCheckNow = new ToolStripMenuItem("立即检测", null, (s, e) => DoCheckAndUpdate());
            var menuOpenConfig = new ToolStripMenuItem("修改配置 (config.json)", null, (s, e) => {
                try { Process.Start("notepad.exe", "\"" + configPath + "\""); } catch {}
            });
            var menuReloadConfig = new ToolStripMenuItem("重新加载配置", null, (s, e) => {
                LoadConfiguration();
                checkTimer.Interval = Math.Max(1000, config.check_interval_seconds * 1000);
                animTimer.Interval = Math.Max(100, config.animation_speed_ms);
                MessageBox.Show(
                    string.Format("配置文件已重载！\n检测间隔: {0}秒\n通知防抖延时: {1}秒\n动画速度: {2}ms\n代理端口: {3}",
                        config.check_interval_seconds, config.notify_delay_seconds, config.animation_speed_ms, config.proxy_port),
                    "配置重载成功", MessageBoxButtons.OK, MessageBoxIcon.Information);
                DoCheckAndUpdate();
            });
            var menuExit = new ToolStripMenuItem("退出监控", null, (s, e) => ExitApplication());

            contextMenu.Items.AddRange(new ToolStripItem[] {
                menuStatus,
                new ToolStripSeparator(),
                menuCheckNow,
                menuOpenConfig,
                menuReloadConfig,
                new ToolStripSeparator(),
                menuExit
            });

            notifyIcon = new NotifyIcon {
                Icon = iconYellow,
                Visible = true,
                ContextMenuStrip = contextMenu
            };
            SetSafeToolTip("Heartbeat-Cat: 正在检测网络...");

            notifyIcon.DoubleClick += (s, e) => DoCheckAndUpdate();
        }

        private void SetSafeToolTip(string text) {
            try {
                if (text.Length > 63) text = text.Substring(0, 60) + "...";
                if (lastToolTip != text) {
                    lastToolTip = text;
                    notifyIcon.Text = text;
                }
            } catch {}
        }

        private void DoCheckAndUpdate() {
            if (isChecking) return;
            isChecking = true;

            try {
                checkCounter++;
                if (checkCounter % 100 == 0) {
                    GC.Collect();
                }

                string timeStr = DateTime.Now.ToString("HH:mm:ss");
                bool isSuccess = false;
                long delayMs = 0;
                string errMsg = null;

                int timeoutMs = Math.Max(500, config.timeout_seconds * 1000);

                if (config.mode == "direct") {
                    var sw = Stopwatch.StartNew();
                    using (var tcp = new TcpClient()) {
                        try {
                            var ar = tcp.BeginConnect(config.direct_host, config.direct_port, null, null);
                            bool ok = ar.AsyncWaitHandle.WaitOne(timeoutMs);
                            if (ok) {
                                tcp.EndConnect(ar);
                                sw.Stop();
                                delayMs = sw.ElapsedMilliseconds;
                                isSuccess = true;
                            } else {
                                errMsg = "TCP连接超时";
                            }
                            ar.AsyncWaitHandle.Close();
                        } catch (Exception ex) {
                            errMsg = ex.Message;
                        }
                    }
                } else {
                    var sw = Stopwatch.StartNew();
                    HttpWebRequest req = null;
                    HttpWebResponse resp = null;
                    Stream respStream = null;
                    try {
                        req = (HttpWebRequest)WebRequest.Create(config.test_url);
                        req.Proxy = cachedProxy;
                        req.Timeout = timeoutMs;
                        req.ReadWriteTimeout = timeoutMs;
                        req.Method = "GET";
                        req.KeepAlive = false;

                        resp = (HttpWebResponse)req.GetResponse();
                        sw.Stop();
                        int code = (int)resp.StatusCode;
                        respStream = resp.GetResponseStream();
                        if (respStream != null) respStream.Close();
                        resp.Close();

                        if (code >= 200 && code < 400) {
                            delayMs = sw.ElapsedMilliseconds;
                            isSuccess = true;
                        } else {
                            errMsg = "HTTP状态码: " + code;
                        }
                    } catch (WebException wex) {
                        if (wex.Response != null) {
                            try { wex.Response.Close(); } catch {}
                        }
                        string status = wex.Status.ToString();
                        if (status == "Timeout") errMsg = "请求超时";
                        else if (status == "ConnectFailure") errMsg = "无法连接代理端口";
                        else errMsg = status;
                    } catch (Exception ex) {
                        errMsg = ex.Message;
                    } finally {
                        if (respStream != null) { try { respStream.Dispose(); } catch {} }
                        if (resp != null) { try { resp.Dispose(); } catch {} }
                        if (req != null) { try { req.Abort(); } catch {} }
                    }
                }

                int notifyDelaySec = Math.Max(1, config.notify_delay_seconds);

                if (isSuccess) {
                    if (lastState != true) {
                        animFrameIndex = 0;
                        notifyIcon.Icon = greenFrames[0];
                        animTimer.Start();
                    }

                    string statusStr = string.Format("连接正常 ({0}ms)", delayMs);
                    SetSafeToolTip(string.Format("猫猫: 连通正常 ({0}ms) [{1}]", delayMs, timeStr));
                    menuStatus.Text = string.Format("当前: {0} [{1}]", statusStr, timeStr);

                    if (disconnectNotified && config.show_notification) {
                        try {
                            notifyIcon.ShowBalloonTip(3000, "代理连接已恢复",
                                string.Format("当前节点连接正常，延迟: {0}ms，猫猫已恢复招手！", delayMs),
                                ToolTipIcon.Info);
                        } catch {}
                    }

                    disconnectStartTime = null;
                    disconnectNotified = false;
                    lastState = true;
                } else {
                    if (lastState != false) {
                        animTimer.Stop();
                        notifyIcon.Icon = iconRed;
                    }

                    string statusStr = "已断开 (" + errMsg + ")";
                    SetSafeToolTip(string.Format("猫猫: 连接已断开 ({0}) [{1}]", errMsg, timeStr));
                    menuStatus.Text = string.Format("当前: {0} [{1}]", statusStr, timeStr);

                    if (!disconnectStartTime.HasValue) {
                        disconnectStartTime = DateTime.UtcNow;
                    }

                    double disconnectedDuration = (DateTime.UtcNow - disconnectStartTime.Value).TotalSeconds;

                    if (disconnectedDuration >= notifyDelaySec && !disconnectNotified && config.show_notification) {
                        try {
                            notifyIcon.ShowBalloonTip(5000, "⚠️ 代理服务器已断开！",
                                string.Format("代理已持续断开超过 {0} 秒 ({1})，猫猫已断线晕倒，请检查节点。", notifyDelaySec, errMsg),
                                ToolTipIcon.Warning);
                        } catch {}
                        disconnectNotified = true;
                    }

                    lastState = false;
                }
            } catch (Exception ex) {
                LogException(ex);
            } finally {
                isChecking = false;
            }
        }

        private void LogException(Exception ex) {
            try {
                string msg = string.Format("[{0}] Exception: {1}\r\n{2}\r\n",
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"), ex.Message, ex.StackTrace);
                File.AppendAllText(errorLogPath, msg);
            } catch {}
        }

        private void ExitApplication() {
            try {
                if (animTimer != null) { animTimer.Stop(); animTimer.Dispose(); }
                if (checkTimer != null) { checkTimer.Stop(); checkTimer.Dispose(); }
                if (notifyIcon != null) { notifyIcon.Visible = false; notifyIcon.Dispose(); }
                if (greenFrames != null) {
                    foreach (var f in greenFrames) f.Dispose();
                }
                if (iconRed != null) iconRed.Dispose();
                if (iconYellow != null) iconYellow.Dispose();
                if (lockStream != null) {
                    lockStream.Close();
                    lockStream.Dispose();
                }
            } catch {}
            ExitThread();
            Application.Exit();
        }
    }

    static class Program {
        [STAThread]
        static void Main() {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new CatTrayContext());
        }
    }
}
