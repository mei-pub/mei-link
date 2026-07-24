# Meilink v1.1.0 Release Notes

## 版本信息

- **版本号**: 1.1.0
- **发布日期**: 2026-07-22
- **frp 版本**: v0.70.0

## v1.1.0 变更摘要

### 跨平台客户端（重大修复 + 功能补齐）

修复了 v1.0.0 中导致客户端**完全无法工作**的多个致命 Bug，并补齐了与 macOS 原生客户端对齐的核心运行时能力：

**致命 Bug 修复：**
- 🔴 修复 frpc Store API 调用：之前发送的是扁平 JSON，frpc 要求**嵌套结构** `{name,type,tcp:{localIP,localPort,remotePort}}`。现在生成正确的 ProxyDefinition（对照 frp v0.70 源码验证）。
- 🔴 修复 Basic Auth：之前发送明文 `user:pass`，frpc 要求 `Authorization: Basic <base64>`。
- 🔴 修复 `/api/status` 响应解析：字段名是 `local_addr`/`remote_addr`（snake_case），之前无法映射。
- 🔴 修复 UpdateProxy/DeleteProxy 的 URL 拼接 Bug。
- 🔴 修复构建脚本：`go build ./cmd/meilink` 产出的是归档文件而非可执行文件（根包 `main.go` 才是入口）。

**新增运行时能力（对齐 macOS 原生客户端）：**
- ✅ 状态轮询（3–30s 间隔，可配置）：周期获取每个隧道的实时状态/错误/远程地址。
- ✅ 远程可达性探活（30–600s 间隔）：对运行中的隧道做 TCP 探活，标记不可达。
- ✅ 自动重连：连续 3 次失败自动重启 frpc（20s 冷却防抖）。
- ✅ 事件日志：最近 100 条 info/warning/error 事件，Web UI 实时展示。
- ✅ 守护进程 + 服务优先：`start` 前台运行并写 PID 文件；`stop`/`status`/`restart` 优先调用系统服务，其次用 PID 文件兜底。
- ✅ `run` 子命令：系统服务的真正入口（被 systemd ExecStart 调用）。

**Web UI 升级：**
- 实时隧道状态徽章（运行中/连接中/启动失败/检查失败/已关闭）。
- 每条隧道的远程地址、错误信息展示。
- 启用/禁用开关。
- 启动/停止/重启控制按钮。
- 事件日志面板。
- 设置面板（轮询间隔、远程探活间隔）。
- 隧道编辑补齐：远程端口、自定义域名、HTTP 认证、Host Header Rewrite。

### 服务端部署维护程序（完全重写）

从一次性安装向导升级为**多实例管理程序**，支持「一个域名一个 token、多台机器各自穿透」：

- **多 profile 架构**：每个 profile = 一个域名 + 一个 token + 一个独立的 frps systemd 服务（`frps-<name>.service`），隔离性最佳，可单独启停/重启/撤销。
- **自动端口分配**：bindPort 从 7000 递增，避免实例间冲突。
- **交互式菜单**：无参数运行即进入交互菜单。
- **完整子命令**：`setup` / `add` / `edit` / `remove` / `list` / `start` / `stop` / `restart` / `status` / `install-frps` / `upgrade`。
- **开机自启**：每个服务 `systemctl enable --now`，确保服务器重启后自动恢复。
- **升级**：一键升级 frps 二进制并重启所有实例。

---

## 包含产物

### 1. macOS 原生客户端（特色版本）

| 文件 | 平台 | 架构 | 说明 |
|------|------|------|------|
| `meilink-1.1.0-macOS-native.dmg` | macOS | arm64 | 标准 DMG 安装包（含 .app bundle + 图标） |

**使用方式：**
```bash
# 双击 DMG，将 Meilink.app 拖入 Applications 即可
open meilink-1.1.0-macOS-native.dmg
# 或命令行挂载
hdiutil attach meilink-1.1.0-macOS-native.dmg
cp -R /Volumes/Meilink/Meilink.app /Applications/
hdiutil detach /Volumes/Meilink
```

DMG 内含完整的 `Meilink.app` bundle（带 `AppIcon.icns` 图标、内置 frpc、代码签名）和 Applications 文件夹快捷方式，是标准的 macOS 分发形态。常驻菜单栏，首次运行配置 VPS 信息即可。支持 Keychain 存储、Login Items 自启动、实时隧道监控与自动重连。

> 注：本 DMG 由预构建的 `.app` bundle 打包（Swift 源码未改动）。从源码重新构建需要完整的 Xcode（非 Command Line Tools），运行 `bash scripts/build-all.sh` 即可。

### 2. Go 跨平台客户端

| 文件 | 平台 | 架构 | 说明 |
|------|------|------|------|
| `meilink-1.1.0-darwin-arm64.dmg` | macOS | Apple Silicon | **DMG（含 .app bundle + 图标）** |
| `meilink-1.1.0-darwin-amd64.dmg` | macOS | Intel | **DMG（含 .app bundle + 图标）** |
| `meilink-1.1.0-windows-amd64.zip` | Windows | x86_64 | **单个 meilink.exe（嵌入应用图标）** |
| `meilink-1.1.0-linux-amd64.tar.gz` | Linux | x86_64 | 跨平台客户端（含桌面集成） |
| `meilink-1.1.0-linux-arm64.tar.gz` | Linux | ARM64 | 跨平台客户端（含桌面集成） |

**macOS Go 客户端：** DMG 内含 `Meilink.app` bundle（带 `AppIcon.icns` 图标 + 启动脚本 + Go 二进制）和 Applications 快捷方式。双击 `.app` 会自动启动 frpc 客户端并打开浏览器到 Web UI；也可在终端直接调用 `Meilink.app/Contents/MacOS/meilink-bin` 运行 CLI 命令。

**Windows：** zip 内只有一个 `meilink.exe`，应用图标已嵌入（在文件管理器/任务栏显示 Meilink 图标）。解压后直接在 PowerShell/cmd 运行即可。

**Linux 包内容（含桌面集成）：**
```
meilink-1.1.0-linux-amd64/
├── meilink              # 主程序（静态链接，无依赖）
├── meilink.png          # 256×256 应用图标
├── meilink.desktop      # 桌面启动器（应用菜单显示 Meilink，点击打开 Web UI）
├── meilink-webui        # 桌面启动辅助脚本（自动启动 + 打开浏览器）
├── install.sh           # 一键安装到系统（含图标、菜单项）
└── README.md            # 使用说明
```

**Linux/macOS 使用方式：**
```bash
tar xzf meilink-1.1.0-linux-amd64.tar.gz
cd meilink-1.1.0-linux-amd64

# 方式一：一键安装到系统（Linux，含桌面图标和菜单项）
sudo ./install.sh
# 安装后在应用菜单找到 Meilink，或在终端运行 meilink

# 方式二：直接运行
# 交互式配置
./meilink setup

# 前台启动（Ctrl+C 停止）
./meilink start

# 另开终端：停止 / 状态 / 重启（服务优先，PID 兜底）
./meilink stop
./meilink status
./meilink restart

# 注册系统服务（开机自启）
sudo ./meilink install-service
sudo ./meilink uninstall-service

# 访问 Web UI
open http://localhost:7400
```

**Windows 使用方式：**
```powershell
# 解压 zip 得到 meilink.exe
.\meilink setup          # 交互式配置
.\meilink start          # 前台启动
.\meilink status         # 查看状态
# 浏览器打开 http://localhost:7400
```

### 3. 服务端部署维护程序（Linux）

| 文件 | 平台 | 架构 | 说明 |
|------|------|------|------|
| `meilink-setup-1.1.0-linux-amd64.tar.gz` | Linux | x86_64 | 多 profile frps 管理工具 |
| `meilink-setup-1.1.0-linux-arm64.tar.gz` | Linux | ARM64 | 多 profile frps 管理工具 |

**使用方式：**
```bash
tar xzf meilink-setup-1.1.0-linux-amd64.tar.gz
cd meilink-setup-1.1.0-linux-amd64
sudo ./meilink-setup            # 交互式菜单

# 或直接用子命令
sudo ./meilink-setup setup      # 首次初始化（安装 frps + 创建第一个 profile）
sudo ./meilink-setup add        # 添加新 profile（域名+token）
sudo ./meilink-setup list       # 列出所有 profile
sudo ./meilink-setup start      # 启动所有实例
sudo ./meilink-setup start office   # 启动指定 profile
sudo ./meilink-setup stop|restart|status [name]
sudo ./meilink-setup upgrade    # 升级 frps 并重启所有实例
```

每个 profile 会创建独立的 systemd 服务 `frps-<name>.service`，自动 `enable --now`，服务器重启后自动恢复。

---

## 多域名/多机器穿透架构

```
                       VPS (运行 meilink-setup)
                     ┌─────────────────────────────────┐
                     │  profile A: domainA + tokenA    │
                     │    → frps-a.service (port 7000) │
                     │  profile B: domainB + tokenB    │
                     │    → frps-b.service (port 7001) │
                     └─────────────────────────────────┘
                          ▲                ▲
                          │                │
            ┌─────────────┘                └─────────────┐
            │                                            │
      机器 A (meilink)                            机器 B (meilink)
      连接 profile A                              连接 profile B
      (domainA / tokenA / 7000)                  (domainB / tokenB / 7001)
```

每个域名一个 token，不同机器使用不同凭证，互不影响。

---

## 项目结构

```
release/
├── meilink-1.1.0-macOS-native.dmg             # macOS 原生客户端 (DMG，含 .app + 图标)
├── meilink-1.1.0-darwin-arm64.dmg             # Go 客户端 (macOS Apple Silicon，DMG)
├── meilink-1.1.0-darwin-amd64.dmg             # Go 客户端 (macOS Intel，DMG)
├── meilink-1.1.0-windows-amd64.zip            # Go 客户端 (Windows，单 exe 嵌图标)
├── meilink-1.1.0-linux-amd64.tar.gz           # Go 客户端 (Linux x86_64，含桌面集成)
├── meilink-1.1.0-linux-arm64.tar.gz           # Go 客户端 (Linux ARM64，含桌面集成)
├── meilink-setup-1.1.0-linux-amd64.tar.gz     # 服务端管理程序 (Linux x86_64)
├── meilink-setup-1.1.0-linux-arm64.tar.gz     # 服务端管理程序 (Linux ARM64)
└── RELEASE_NOTES.md                            # 本文档
```

### 打包细节

- **macOS DMG**：用 `hdiutil` 从 `Meilink.app` bundle 生成 UDZO 压缩 DMG，内含 `.app`（带 `AppIcon.icns` 图标 + 内置 frpc）和 Applications 快捷方式。构建脚本：`scripts/build-all.sh`。
- **Windows exe 图标**：用 `scripts/gen-icons.sh` 从 `AppIcon.png` 生成多尺寸 ICO（16/24/32/48/64/128/256），经 `rsrc` 编译为 `resource_windows_amd64.syso`，`go build GOOS=windows` 自动链接嵌入 exe 的 `.rsrc` 资源段。仅用 macOS 系统工具（`sips` + `python3`），无需 ImageMagick/Pillow。
- **重新构建全部产物**：`bash scripts/build-all.sh 1.1.0`

## 两种客户端对比

| 特性 | macOS 原生客户端 | Go 跨平台客户端 |
|------|-----------------|----------------|
| 平台 | macOS only | Windows / Linux / macOS |
| UI | Menu Bar 原生体验 | Web UI 浏览器管理 |
| 语言 | Swift AppKit | Go |
| 状态监控 | ✅ 轮询 + 探活 + 自动重连 | ✅ 轮询 + 探活 + 自动重连 |
| 自启动 | Login Items (SMAppService) | systemd / launchd / Windows Service |
| 认证存储 | Keychain | JSON 文件 (0600) |
| 适合场景 | Mac 用户日常使用 | 多平台统一部署 |

## 系统要求

- **macOS 原生客户端**: macOS 13.0+
- **Go 客户端**: 无需额外依赖，单二进制运行（内含 frpc 自动下载）
- **服务端管理程序**: Linux (systemd)，需要 sudo 权限
