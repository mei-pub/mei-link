# Meilink SDD · 02 · 功能清单

> 本文列出 Meilink 当前实现的所有功能，每条功能给出触发入口、关键代码位置、依赖关系，便于后续修改时定位。

## F1 · 服务器配置（Setup / Settings）

### F1.1 首次配置向导
- **入口**：`MenuBarView.onAppear` 检测 `!manager.isConfigured` 自动打开 Setup 窗口。
- **实现**：<kfile name="SetupView.swift" path="Meilink/UI/Setup/SetupView.swift">SetupView.swift</kfile>
- **字段**：服务器地址、端口（默认 7000）、认证 Token、子域名基域、TLS 开关。
- **动作**：
  - "测试连接" → `NetworkHelper.testConnection`（TCP 握手 5s 超时）
  - "保存" → `manager.saveConfiguration(config)` → `manager.start()` 自动连接
- **校验**：`serverAddr`、`authToken`、`subDomainHost` 非空才允许保存。

### F1.2 设置面板
- **入口**：主窗口"设置"按钮 / 菜单栏"设置"按钮。
- **实现**：<kfile name="SettingsView.swift" path="Meilink/UI/Settings/SettingsView.swift">SettingsView.swift</kfile>
- **分组**：
  - 服务器配置：地址、客户端端口、管理端口（Admin API 端口）、Token（可显隐切换）、子域名基域、TLS。
  - 应用设置：开机自启、菜单栏图标（5 选 1）、远程探测间隔（30-600s Stepper）、完全退出。
- **动作**：
  - "测试连接" → 同上
  - "保存" → `manager.saveConfiguration` → 若 `isFrpcRunning` 则自动 `restart`
  - "保存并重启" → 强制 `restart`
  - "完全退出" → 确认对话框 → `manager.stop()` + `allowQuit = true` + `NSApp.terminate`
- **特殊**：保存配置时同步把 `authToken` 写 Keychain（`KeychainHelper.save("auth-token", ...)`）。

### F1.3 DNS 引导
- **入口**：暂未直接挂到任何按钮（独立组件，待接线）。
- **实现**：<kfile name="DNSGuideView.swift" path="Meilink/UI/Setup/DNSGuideView.swift">DNSGuideView.swift</kfile>
- **内容**：展示 A 记录泛解析 `*.<subDomainHost>` → VPS IP 的指引。

## F2 · 隧道管理（CRUD）

### F2.1 隧道列表
- **入口**：主窗口 `MainWindow`。
- **实现**：<kfile name="MainWindow.swift" path="Meilink/UI/Main/MainWindow.swift">MainWindow.swift</kfile> + <kfile name="TunnelListRow.swift" path="Meilink/UI/Main/TunnelListRow.swift">TunnelListRow.swift</kfile>
- **列**：状态圆点 + 名称 / 类型 + 本地地址 / 外网访问 + 状态文案 + 复制按钮 + 打开按钮 + 启用 Toggle + 操作 Menu。
- **空状态**：`manager.tunnels.isEmpty` 时显示"还没有隧道"+添加按钮。
- **页脚**：添加隧道按钮 + `启用/总数` 统计 + 查看日志 + 清空日志。

### F2.2 隧道编辑
- **入口**：主窗口"添加隧道" / 列表行"编辑" / 菜单栏"添加"（跳到主窗口）。
- **实现**：<kfile name="TunnelEditView.swift" path="Meilink/UI/Main/TunnelEditView.swift">TunnelEditView.swift</kfile>
- **字段**：
  - 基本信息：名称、类型（HTTP/HTTPS/TCP/UDP 分段选择器）
  - 本地配置：本地端口、本地地址（默认 `127.0.0.1`）
  - 远程配置：HTTP/HTTPS 显示"子域名"，TCP/UDP 显示"远程端口"（留空自动分配）
  - 状态：启用开关
- **校验**：`name` 非空 + `localPort` 是数字 + 未在保存中。
- **保存**：编辑走 `manager.updateTunnel`，新增走 `manager.addTunnel`，均 `reload` frpc。

### F2.3 隧道增删改的后端
- **实现**：<kfile name="TunnelManager.swift" path="Meilink/Core/TunnelManager.swift">TunnelManager.swift</kfile>
- **API 路径**：
  - `addTunnel` → `adminAPI.createProxy` + `reload`
  - `updateTunnel` → `adminAPI.updateProxy` + `reload`
  - `deleteTunnel` → `adminAPI.deleteProxy` + `reload`（API 失败仅记日志，仍删除本地）
  - `toggleTunnel(true)` → `createProxy` + `reload`，状态置 `waitStart`
  - `toggleTunnel(false)` → `deleteProxy` + `reload`，状态置 `closed`
- **持久化**：每次本地 tunnels 变更后 `store.saveTunnels(tunnels)`。

## F3 · 连接管理（frpc 生命周期）

### F3.1 启动
- **入口**：主窗口/菜单栏"连接"按钮、Setup 保存后、`startIfNeeded`（应用启动后 0.5s 自动触发）。
- **实现**：`TunnelManager.start(force:)`
- **流程**：
  1. 生成 `frpc.toml`（`ConfigGenerator.generate` + `writeToFile` 0600 权限）
  2. `frpcProcess.start(configPath:)` 启动 frpc 子进程
  3. 等 Admin API 就绪（5s 超时，`waitForAdminAPI`）
  4. 遍历 `tunnels where enabled`，`createProxy` 恢复代理，部分失败仅告警
  5. `adminAPI.reload()`
  6. `startStatusPolling()` 开启状态轮询

### F3.2 停止
- **入口**：主窗口/菜单栏"断开"按钮、设置"保存并重启"、退出前。
- **实现**：`TunnelManager.stop()` / `stopImmediately()` / `killFrpcOnExit()`
- **行为**：停止轮询、停止 frpc、所有隧道置 `closed`。

### F3.3 深度重启
- **入口**：主窗口/菜单栏"重启"按钮、设置保存后自动触发。
- **实现**：`TunnelManager.restart()`
- **5 层流程**：
  1. 停状态轮询
  2. 停 frpc 进程（`stopImmediately(timeout: 3)` → 0.5s sleep → `kill -9` 兜底）
  3. 重新生成配置 + 启动 frpc
  4. 异步等 Admin API 就绪（15s 超时，`waitForAdminAPIAsync` 回调式）
  5. 回调里恢复所有启用隧道 + `reload` + `startStatusPolling`

## F4 · 状态监控与自动恢复

### F4.1 状态轮询
- **触发**：`startStatusPolling` 启动 `Timer.scheduledTimer`，间隔 = `clamp(appSettings.statusPollingInterval, 3, 30)`。
- **实现**：`TunnelManager.pollStatus`
- **流程**：
  1. 调 `adminAPI.getStatus()` 拿 `StatusResponse`（按 `tunnel.type.rawValue` 分组）
  2. 对每条 tunnel 找对应 status，更新 `tunnels[idx].status / errorMessage / remoteAddr`
  3. 未返回的 enabled 隧道置 `checkFailed` + `"frpc 未返回该隧道状态"`
  4. 找出 `unhealthyTunnels`（status != running 或 errorMessage 非空）→ `recordConnectivityFailure`
  5. 满足探活时机时 `probeReachability` → 不可达的隧道置 `checkFailed`
  6. 全部健康 → `consecutiveFailures = 0` + `isConnected = true`
- **并发保护**：`isPollingStatus` 标志防止重入。

### F4.2 远程探活
- **触发**：`shouldProbeReachability` — 距上次探活 ≥ `clamp(remoteReachabilityInterval, 30, 600)` 秒。
- **实现**：<kfile name="TunnelReachabilityProbe.swift" path="Meilink/Core/TunnelReachabilityProbe.swift">TunnelReachabilityProbe.swift</kfile>
- **协议**：TCP 握手（`NWConnection`），4s 超时。
- **类型差异**：
  - HTTP → 远端 host:80
  - HTTPS → 远端 host:443
  - TCP → 远端 `tunnel.remotePort`
  - UDP → 跳过（`.skipped`）
- **结果**：`reachable` / `unreachable(reason)` / `skipped`，不可达的隧道置 `checkFailed` + errorMessage。

### F4.3 自动重连
- **触发**：`recordConnectivityFailure` 累计 `consecutiveFailures >= 3`，或 frpc 进程非 0 退出回调。
- **实现**：`TunnelManager.recoverConnection`
- **冷却**：距上次 `lastRecoveryAt` < 20s 时跳过（`recoveryCooldown`）。
- **流程**：停轮询 → `stopImmediately` → sleep 1s → `consecutiveFailures = 0` → `start(force: true)`。
- **frpc 异常退出路径**：`FrpcProcess.onTermination` 回调里若 `status != 0`，sleep 2s 后调 `recoverConnection`。

## F5 · 菜单栏

### F5.1 状态图标
- **实现**：`StatusBarController.updateButton` + <kfile name="MenuBarStatusItem.swift" path="Meilink/UI/MenuBar/MenuBarStatusItem.swift">MenuBarStatusItem.swift</kfile>
- **风格**：5 种 PNG 图标（`portal` / `topology` / `arrow-ring` / `waveform` / `relay`），从 `Bundle.main` 加载，18×18，`isTemplate = true`。
- **状态映射**：
  - `isConnected = true` → 图标着色绿
  - `isFrpcRunning = true` → 黄
  - 其余 → 灰
- **toolTip**：`Meilink - <状态文案>`。
- **fallback**：PNG 找不到时用 `AppIconProvider.image`（应用图标）。

### F5.2 弹出面板
- **入口**：点击菜单栏按钮 `togglePopover`。
- **实现**：`StatusBarController.showPanel`
- **尺寸**：330×440，`NSPanel` borderless + nonactivatingPanel，level = statusBar，canJoinAllSpaces + transient。
- **箭头**：`MenuBarPanelChrome` 顶部画一个小三角对齐按钮中心，箭头 offset = `clamp(buttonFrame.midX - originX, 24, panelSize.width - 24)`。
- **位置**：默认在按钮正下方（`buttonFrame.minY - panelSize.height - 8`），不够空间则翻转到屏幕上方。
- **自动关闭**：`installEventMonitors` 监听 local + global 鼠标按下事件，点面板外即关。

### F5.3 面板内容
- **实现**：<kfile name="MenuBarView.swift" path="Meilink/UI/MenuBar/MenuBarView.swift">MenuBarView.swift</kfile>
- **结构**：
  - 状态头：状态圆点 + 标题 + 服务器副标题 + 启停按钮
  - 启用的隧道列表：每条一个卡片（名称、状态、路由、复制/打开按钮）
  - 控制按钮组：主窗口 / 日志 / 设置 / 重启 / 退出

## F6 · 多窗口

### F6.1 窗口清单
- **实现**：<kfile name="AppRuntime.swift" path="Meilink/App/AppRuntime.swift">AppRuntime.swift</kfile> 的 `AppWindowController`
- **窗口**：
  | 窗口 | 标题 | 尺寸 | 内容视图 |
  |---|---|---|---|
  | 主窗口 | `Meilink` | 1060×820 | `MainWindow` |
  | 设置 | `设置` | 760×460 | `SettingsView` |
  | 首次配置 | `首次配置` | 560×640 | `SetupView` |
  | 隧道编辑 | `添加新隧道` / `编辑隧道` | 660×440 | `TunnelEditView` |
  | 日志 | `日志` | 820×620 | `LogWindowView` |
- **行为**：窗口已可见则 `makeKeyAndOrderFront` + `activate`；不可见则创建并居中到可见屏。
- **生命周期**：`isReleasedWhenClosed = false`，`isMovableByWindowBackground = true`，styleMask 含 titled + closable + miniaturizable + resizable。

### F6.2 关窗口不退出
- **实现**：`MeilinkAppDelegate.applicationShouldTerminateAfterLastWindowClosed` 返回 `false`。
- **副作用**：所有窗口关掉后 frpc 仍跑、菜单栏仍在。

## F7 · 日志

### F7.1 事件日志
- **实现**：<kfile name="LogWindowView.swift" path="Meilink/UI/Main/LogWindowView.swift">LogWindowView.swift</kfile> + `TunnelManager.events`
- **来源**：
  - `addEvent` 手动记录（连接检测、自动重连、隧道 CRUD、配置保存等）
  - `frpcProcess.onOutput` 把 frpc stdout/stderr 每行作为 `frpc: <line>` 事件
- **容量**：保留最近 100 条，超出 `events.prefix(100)`。
- **级别**：info / warning / error，对应蓝/橙/红 + 图标 `info.circle` / `exclamationmark.triangle` / `xmark.octagon`。

### F7.2 复制 / 导出 / 清空
- **复制选中**：`formattedLogs(selectedEvents)`
- **复制全部**：`formattedLogs(manager.events)`
- **导出**：`NSSavePanel` → `meilink-logs-<yyyyMMdd-HHmmss>.log` 纯文本
- **清空**：`manager.clearEvents()`

## F8 · 应用设置

### F8.1 AppSettings 字段
| 字段 | 默认 | 含义 |
|---|---|---|
| `autoStart` | true | 应用启动后是否自动连接 |
| `launchAtLogin` | false | 登录 macOS 后是否自动启动 Meilink |
| `showInDock` | false | 是否在 Dock 显示（当前实现未真正生效，仅占位） |
| `statusPollingInterval` | 3.0 | 状态轮询间隔（运行时 clamp 到 3-30） |
| `remoteReachabilityInterval` | 60.0 | 远程探活间隔（运行时 clamp 到 30-600） |
| `menuBarIconStyle` | .portal | 菜单栏图标风格 |

### F8.2 开机自启
- **实现**：<kfile name="AutoStartManager.swift" path="Meilink/Utils/AutoStartManager.swift">AutoStartManager.swift</kfile>
- **API**：`SMAppService.mainApp.register/unregister`，`status == .enabled` 判断已启用。
- **触发**：SettingsView 的"开机自启动"Toggle `onChange` 即时注册/注销。

## F9 · 服务端部署

### F9.1 Shell 脚本部署
- **入口**：`./deploy-frps.sh [deploy|start|stop|restart|status|help]`。
- **实现**：<kfile name="deploy-frps.sh" path="deploy-frps.sh">deploy-frps.sh</kfile>
- **流程**：校验 `frps.toml` → 下载 frp v0.70.0 linux 二进制 → 安装到 `/usr/local/bin/frps` → 配置到 `/etc/frps/frps.toml`（0600）→ 写 `/etc/systemd/system/frps.service` → `systemctl enable --now frps`。
- **校验项**：`bindPort` / `vhostHTTPPort` / `vhostHTTPSPort` 必填，`subDomainHost` 不能是默认占位，`auth.token` 不能是默认占位。

### F9.2 meilink-setup 多 profile 部署
- **入口**：`sudo ./meilink-setup [setup|add|list|start|stop|restart|status|upgrade]`。
- **实现**：`cross-platform-client/cmd/meilink-setup`（本次未读源码，描述来自 README + build-all.sh 第 169-195 行的产物说明）。
- **能力**：每个 profile = 一个域名 + 一个 token + 一个独立的 `frps-<name>.service`，端口从 7000 递增，`systemctl enable --now` 确保开机自启。

### F9.3 Docker 部署
- **入口**：`docker compose up -d`。
- **实现**：<kfile name="docker-compose.yml" path="docker-compose.yml">docker-compose.yml</kfile>
- **镜像**：`snowdreamtech/frps:latest`，挂载 `./frps.toml`，暴露 7000 / 8080 / 8443。

## F10 · 构建与发布

### F10.1 macOS 原生客户端构建
- **方式 A（XcodeGen + Xcode）**：`xcodegen generate` → `xcodebuild`。
- **方式 B（SwiftPM）**：`swift build`。
- **frpc 集成**：`project.yml` 的 `preBuildScripts` 调 `Scripts/download-frpc.sh`，下载 frpc 到 `.app/Contents/MacOS/frpc`。
- **图标**：`Meilink/Resources/AppIcon.icns` + `Assets.xcassets`。
- **配置**：`LSUIElement = true`（不显示 Dock）、`LSMinimumSystemVersion = 13.0`、`ENABLE_HARDENED_RUNTIME = true`、`CODE_SIGN_STYLE = Automatic`。

### F10.2 跨平台发布（`Scripts/build-all.sh`）
- **产物**：
  - `meilink-<ver>-linux-amd64.tar.gz` / `linux-arm64.tar.gz`（含桌面集成：图标/.desktop/install.sh）
  - `meilink-<ver>-darwin-amd64.dmg` / `darwin-arm64.dmg`（Go 客户端包成 .app + DMG）
  - `meilink-<ver>-windows-amd64.zip`（单 exe 嵌入图标）
  - `meilink-setup-<ver>-linux-amd64.tar.gz` / `linux-arm64.tar.gz`
  - `meilink-<ver>-macOS-native.dmg`（Swift 原生客户端 DMG）
- **版本号**：默认 `1.1.0`，可作第一个参数覆盖。
- **图标生成**：`Scripts/gen-icons.sh` 从 `Meilink/Resources/AppIcon.png` 派生 Windows ICO + .syso + Linux PNG。

### F10.3 Tauri 桌面客户端构建（`Scripts/build-desktop.sh`）
- **流程**：
  1. Go 交叉编译 sidecar 二进制（按 target-triple 命名）到 `desktop/src-tauri/binaries/`
  2. `npm install` + `npx vite build`
  3. `npx tauri build`（Rust 编译 + 打包 .app/.dmg/.msi/.deb）
- **平台限制**：Tauri 无法在同一主机交叉编译，多平台发布需对应平台 CI runner。
- `--copy` 可选把产物复制到 `release/`。

详见 `07-build-release.md`。
