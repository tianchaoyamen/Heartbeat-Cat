<div align="center">

# 🐾 Heartbeat-Cat (心跳猫猫)

**专为 Clash Verge / 代理打造的 Windows 任务栏「像素猫猫」实时连通性监控工具**

[![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows&logoColor=white)](https://github.com/tianchaoyamen/Heartbeat-Cat)
[![Runtime](https://img.shields.io/badge/Runtime-PowerShell%205.1+-5391FE?logo=powershell&logoColor=white)](https://github.com/tianchaoyamen/Heartbeat-Cat)
[![Dependency](https://img.shields.io/badge/Dependency-Zero%20(开箱即用)-brightgreen)](https://github.com/tianchaoyamen/Heartbeat-Cat)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

<br/>

<img src="assets/cat_showcase.png" alt="Heartbeat-Cat Showcase" width="680"/>

<br/>
<br/>

经常在使用 Clash Verge 等代理时突然断网却毫无察觉？  
**Heartbeat-Cat** 在 Windows 右下角任务栏安插了一只敏锐可爱的**像素小猫猫**，时刻帮你盯着代理连接心跳！

</div>

---

## ✨ 核心特性

- 🐱 **生动的像素猫猫视觉反馈**
  - 🟢 **正常连通 · 动态招财猫**：薄荷翠绿体色，小肉爪欢快挥动、摇晃尾巴、开心眨眼，一眼便知节点畅通！
  - 🔴 **异常断开 · 晕倒红猫猫**：警示珊瑚红，耷拉着耳朵，双眼晕倒打叉 `x x`，脸颊挂着泪滴 💧，瞬间警觉！
  - 🟡 **检测等待 · 歪头黄猫猫**：温暖金黄，大圆眼 `o o` 好奇四顾，头顶带疑惑小问号。

- ⚡ **零环境依赖，开箱即用**
  - 基于 Windows 原生 PowerShell 与 WinForms GDI+，**无需安装 Python、Node.js 或任何运行库**。
  - 双击即跑，纯原生 API 内存仅占用约 **20~25 MB**，CPU 消耗趋近于 **0%**。

- 🛡️ **工业级防崩防泄漏设计 (24/7 长期守护)**
  - **网络连接池严格清理**：每个请求独立释放底层 Socket 句柄与 Stream，杜绝长期运行导致的句柄耗尽。
  - **内核级独占文件锁**：替代易在非管理员或异常中断时死锁的 Mutex，彻底防重复启动。
  - **异常全熔断保护**：定时器与气泡通知内含多层异常防护，并输出 `error.log`，绝不因单次网络闪断发生程序闪退。

- 🔕 **智能通知延时防抖**
  - 网络经常闪断 1~2 秒就恢复？频繁弹窗很扰民！
  - **默认 5 秒延时防抖**：短于 5 秒的瞬时闪断静默忽略，只变猫猫不弹窗；仅在断线超过 5 秒时才弹出系统预警，节点恢复时对应提示。

- 🪟 **多启动模式支持**
  - **静默后台模式 (`.vbs`)**：完全后台隐身运行，桌面任务栏无任何黑框 CMD 窗口。
  - **控制台调试模式 (`.bat`)**：实时滚动彩色终端日志，方便测速调优。

---

## 🚀 快速开始

### 1. 下载与解压
直接下载本项目 ZIP 解压至任意文件夹，或使用 Git 克隆：
```bash
git clone https://github.com/tianchaoyamen/Heartbeat-Cat.git
```

### 2. 启动运行
- **推荐日常使用**：双击运行 **`start_silent.vbs`**（或 `启动监控(静默后台).vbs`）。
  > 💡 **提示**：如果任务栏右下角没有直接看到猫猫，通常是被 Windows 折叠在任务栏向上的小箭头 `^` 里面。建议按住鼠标左键把猫猫拖出到任务栏常驻显示！
- **调试排查问题**：双击运行 **`start_console.bat`**（或 `启动监控(调试窗口).bat`），可查看每次探测的实时延迟与日志。

### 3. 退出程序
- 方法一：鼠标右键点击任务栏的小猫猫，在菜单中选择 **「退出监控」**。
- 方法二：双击运行 **`stop.bat`**（或 `停止监控.bat`）。

---

## ⚙️ 配置说明 (`config.json`)

程序支持通过 `config.json` 灵活定制检测行为：

```json
{
  "mode": "proxy",
  "proxy_host": "127.0.0.1",
  "proxy_port": 7897,
  "test_url": "http://www.gstatic.com/generate_204",
  "direct_host": "1.1.1.1",
  "direct_port": 443,
  "check_interval_seconds": 3,
  "timeout_seconds": 2,
  "show_notification": true,
  "notify_delay_seconds": 5,
  "animation_speed_ms": 400
}
```

### 参数详解

| 配置项 | 类型 | 默认值 | 详细说明 |
| :--- | :---: | :---: | :--- |
| `mode` | `string` | `"proxy"` | **`"proxy"`**：通过本地代理端口发包（最贴近实际翻墙体验）；<br/>**`"direct"`**：直连指定服务器 IP/域名做 TCP 握手。 |
| `proxy_host` | `string` | `"127.0.0.1"` | 代理客户端本地监听地址。 |
| `proxy_port` | `number` | `7897` | Clash 代理端口。Clash Verge / Verge Rev 默认为 `7897`，CFW 默认为 `7890`。 |
| `test_url` | `string` | `"http://www.gstatic.com/generate_204"` | 极轻量探测网址（HTTP 204 无内容极速返回，完全不耗流量）。 |
| `direct_host` | `string` | `"1.1.1.1"` | 当 `mode` 为 `"direct"` 时生效，指定要盯防的固定落地服务器。 |
| `direct_port` | `number` | `443` | 当 `mode` 为 `"direct"` 时生效的目标端口。 |
| `check_interval_seconds`| `number` | `3` | 检测心跳频率（秒），默认每 3 秒检测一次。 |
| `timeout_seconds` | `number` | `2` | 判定断开的超时阈值（秒）。 |
| `show_notification` | `boolean` | `true` | 是否允许发送 Windows 任务栏气泡通知。 |
| `notify_delay_seconds` | `number` | `5` | **通知防抖延时（秒）**。断网超过此时长才报警，闪断闪连不打扰。 |
| `animation_speed_ms` | `number` | `400` | **绿猫猫招手动画帧率（毫秒）**。数值越小猫猫招手越快。 |

> 💡 **修改后立即生效**：修改 `config.json` 保存后，只需在任务栏猫猫上 **右键 -> 重新加载配置**，无需重启程序！

---

## 🖱️ 托盘右键菜单

右键点击任务栏的猫猫图标，即可弹出功能菜单：
- 🟢 **状态展示**：悬停或查看当前网络延迟与最后检测时间戳。
- 🔄 **立即检测**：立即触发一次探测，不等倒计时。
- 📝 **修改配置 (config.json)**：一键调用系统记事本打开配置文件。
- ⚡ **重新加载配置**：热重载设置，无需退出重新启动。
- 🚪 **退出监控**：安全销毁图标，干净释放全部系统资源。

---

## 📁 项目结构

```text
Heartbeat-Cat/
├── assets/                       # 像素猫猫图形资源
│   ├── cat_showcase.png          # 状态展示大图
│   ├── cat_green_1.png ~ 4.png   # 绿猫猫 4 帧动画分解
│   ├── cat_red.png               # 红猫猫 (断开状态)
│   └── cat_yellow.png            # 黄猫猫 (检测状态)
├── proxy_monitor.ps1             # 核心监控与托盘绘制主程序
├── config.json                   # 配置文件
├── start_silent.vbs              # 静默后台启动器 (英文名)
├── start_console.bat             # 调试控制台启动器 (英文名)
├── stop.bat                      # 退出停止脚本 (英文名)
├── 启动监控(静默后台).vbs          # 静默后台启动器 (中文名)
├── 启动监控(调试窗口).bat          # 调试控制台启动器 (中文名)
├── 停止监控.bat                  # 退出停止脚本 (中文名)
├── .gitignore
├── LICENSE                       # MIT 许可证
└── README.md                     # 项目说明文档
```

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源，欢迎自由分享与二次改进。
