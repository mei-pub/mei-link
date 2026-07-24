# Meilink SDD · 01 · 用户需求

> 本文从现有实现反推出 Meilink 的用户需求与典型使用场景。事实基线：`Meilink/` Swift 客户端 + `Scripts/` + 根目录部署脚本。

## 1. 目标用户

- **本地开发者**：在本地跑着 HTTP / TCP / UDP 服务（Web 后端、数据库、游戏服务器、IoT 设备），需要让外网或第三方回调访问到这些服务。
- **小团队运维**：有一台 VPS，想给团队成员各自分配一个子域名入口指向各自的本地服务。
- **macOS 重度用户**：希望常驻菜单栏，不占 Dock，关窗口不退出，跟系统原生体验一致。

## 2. 核心用户故事

### US-1 首次配置服务器
作为新用户，我希望在一个引导式窗口里填入 VPS 地址、端口、Token、子域名基域，并能"测试连接"验证可达，通过后保存即自动连接，不需要手编配置文件。

> 对应实现：<kfile name="SetupView.swift" path="Meilink/UI/Setup/SetupView.swift">SetupView.swift</kfile>
> 触发条件：`MenuBarView.onAppear` 检测到 `!manager.isConfigured` 时自动打开 Setup 窗口。

### US-2 管理多条隧道
作为开发者，我希望在主窗口里看到所有隧道的列表，每条隧道显示：名称、本地地址、外网访问地址、状态、启用开关，并能一键复制或打开外网地址。

> 对应实现：<kfile name="MainWindow.swift" path="Meilink/UI/Main/MainWindow.swift">MainWindow.swift</kfile> + <kfile name="TunnelListRow.swift" path="Meilink/UI/Main/TunnelListRow.swift">TunnelListRow.swift</kfile>

### US-3 增删改隧道
作为开发者，我希望添加 HTTP / HTTPS / TCP / UDP 四种类型的隧道，编辑时只改必要字段，删除时自动清理 frpc 上的代理。

> 对应实现：<kfile name="TunnelEditView.swift" path="Meilink/UI/Main/TunnelEditView.swift">TunnelEditView.swift</kfile> + `TunnelManager.addTunnel/updateTunnel/deleteTunnel/toggleTunnel`

### US-4 菜单栏快速控制
作为 macOS 用户，我希望点菜单栏图标弹出一个小面板，看到连接状态、启用的隧道列表、一键启停、重启、打开主窗口/设置/日志、退出应用。面板外的点击要自动关闭。

> 对应实现：<kfile name="AppRuntime.swift" path="Meilink/App/AppRuntime.swift">AppRuntime.swift</kfile> 的 `StatusBarController` + <kfile name="MenuBarView.swift" path="Meilink/UI/MenuBar/MenuBarView.swift">MenuBarView.swift</kfile>

### US-5 关窗口不退出
作为 macOS 用户，我希望关掉主窗口后应用仍然在菜单栏运行，frpc 进程不被杀掉；只有显式点"退出"才真正退出，退出时确保 frpc 完全终止。

> 对应实现：`MeilinkAppDelegate.applicationShouldTerminateAfterLastWindowClosed` 返回 `false` + `applicationShouldTerminate` 受 `allowQuit` 控制 + `applicationWillTerminate` 调 `killFrpcOnExit`。

### US-6 自动重连
作为长时间挂着的用户，我希望 frpc 异常退出或外网不可达时，应用自动检测并尝试重启 frpc + 恢复所有启用的隧道，不需要我手动干预。

> 对应实现：<kfile name="TunnelManager.swift" path="Meilink/Core/TunnelManager.swift">TunnelManager.swift</kfile> 的 `pollStatus` / `recordConnectivityFailure` / `recoverConnection` + `FrpcProcess.onTermination` 回调。

### US-7 远程可达性验证
作为用户，我希望应用定期真的去连一下外网入口（不只看 frpc 状态），发现连不上时及时报错并触发重连，避免"frpc 说 running 但外网访问不通"的假阳性。

> 对应实现：<kfile name="TunnelReachabilityProbe.swift" path="Meilink/Core/TunnelReachabilityProbe.swift">TunnelReachabilityProbe.swift</kfile> + `TunnelManager.shouldProbeReachability` / `probeReachability`。

### US-8 安全存储凭据
作为用户，我希望 frps Token 存在 Keychain 而不是明文配置文件，frpc.toml 文件权限 0600，Admin API 只监听 127.0.0.1。

> 对应实现：<kfile name="KeychainHelper.swift" path="Meilink/Storage/KeychainHelper.swift">KeychainHelper.swift</kfile> + <kfile name="ConfigGenerator.swift" path="Meilink/Core/ConfigGenerator.swift">ConfigGenerator.swift</kfile> 写文件后 `setAttributes posixPermissions: 0o600` + `webServer.addr = "127.0.0.1"`。

### US-9 开机自启
作为用户，我希望勾选"开机自启动"后，登录 macOS 就自动起 Meilink 并连接。

> 对应实现：<kfile name="AutoStartManager.swift" path="Meilink/Utils/AutoStartManager.swift">AutoStartManager.swift</kfile> 用 `SMAppService.mainApp` + `SettingsView` 的 Toggle + `AppSettings.launchAtLogin`。

### US-10 个性化菜单栏图标
作为用户，我希望从 5 种图标风格（门户 / 拓扑 / 穿透 / 信号 / 中继）里选一个，菜单栏图标立即更新。

> 对应实现：<kfile name="AppSettings.swift" path="Meilink/Models/AppSettings.swift">AppSettings.swift</kfile> 的 `MenuBarIconStyle` 枚举 + `SettingsView.updateMenuBarIconStyle` + `StatusBarController.menuBarImage`。

### US-11 日志可追溯
作为运维用户，我希望在日志窗口看到连接检测、自动重连、隧道增删改、frpc stdout/stderr 的事件，支持复制、导出、清空。

> 对应实现：<kfile name="LogWindowView.swift" path="Meilink/UI/Main/LogWindowView.swift">LogWindowView.swift</kfile> + `TunnelManager.events` / `addEvent` / `clearEvents`。

### US-12 一键部署服务端
作为运维用户，我希望在 VPS 上跑一个脚本或交互式程序就能部署 frps，支持多域名多 Token 隔离部署。

> 对应实现：<kfile name="deploy-frps.sh" path="deploy-frps.sh">deploy-frps.sh</kfile>（单实例 systemd）+ `cross-platform-client/cmd/meilink-setup`（多 profile，见 `Scripts/build-all.sh` 第 169-195 行的构建说明）。

## 3. 非目标（当前实现明确不做）

- **不做 frps 图形化管理**：Meilink 是 frpc 端管理工具，不管理 frps 的代理列表、不展示 frps 仪表盘。
- **不做多服务器同时连接**：`ServerConfig` 是单实例，一次只连一个 frps。多 profile 是服务端部署能力，不是客户端同时连。
- **不做 UDP 探活**：`TunnelReachabilityProbe.check` 对 `.udp` 直接返回 `.skipped`。
- **不做账号体系与多用户**：本地单用户，配置文件 + Keychain 存在当前用户目录下。
- **不做流量/带宽统计**：只展示连接状态与隧道状态，不统计流量。
- **不做 frpc 版本管理**：构建期下载固定 `v0.70.0`，运行期不升级 frpc。
- **不做 iOS / Android 客户端**。
- **不内置 frps**：客户端只内置 frpc；frps 在 VPS 上单独部署。

## 4. 典型使用场景

### 场景 A：本地 Web 开发对外回调
开发者在本地 8080 跑了一个 Web 服务，需要让支付平台的异步回调访问到。流程：

1. 部署 frps 到 VPS（`./deploy-frps.sh` 或 `meilink-setup setup`）。
2. DNS 加泛解析 `*.tunnel.example.com → VPS_IP`。
3. macOS 上启动 Meilink，在 Setup 窗口填入 VPS 地址、7000、Token、`tunnel.example.com`。
4. 添加一条 HTTP 隧道：本地 `127.0.0.1:8080`，子域名 `pay-callback`。
5. 外网通过 `http://pay-callback.tunnel.example.com:8080` 访问到本地服务。

### 场景 B：远程 SSH 到内网机器
内网机器跑 SSH（22 端口），VPS 暴露一个高位端口给外部。流程：

1. 添加一条 TCP 隧道：本地 `127.0.0.1:22`，远程端口留空（自动分配）或指定 2222。
2. 外网通过 `ssh -p 2222 user@vps_ip` 连到内网。

### 场景 C：长期挂着的 HTTPS 服务
开发者把本地 HTTPS 服务通过 Meilink 暴露，长期挂着。要求：

- 关闭主窗口后应用仍在菜单栏运行。
- frpc 异常退出时自动重启。
- 外网不可达时触发重连。
- 重新登录 macOS 后自动启动 Meilink。

对应 Meilink 的"关窗口不退出 / 自动重连 / 远程探活 / Login Items 自启"四项能力。

## 5. 隐含需求

以下需求没有显式 UI，但代码里有实现，属于隐含契约：

- **frpc.toml 必须可被 frpc v0.70.0 直接消费**：`ConfigGenerator.generate` 输出的 TOML 格式与 frp v0.70.0 的 schema 严格对齐（见 `05-data-contract.md`）。
- **配置文件改了之后必须重启 frpc 才生效**：frpc 不支持 hot reload 全部配置，所以 `SettingsView.saveConfiguration(restartAfterSave: true)` 走 `manager.restart()`。
- **隧道通过 Store API 动态管理**：frpc.toml 里只声明 server/transport/webServer/store，具体 proxy 通过 `/api/store/proxies` 增删改 + `/api/reload` 生效（见 `05-data-contract.md`）。
- **应用启动后自动连接**：`TunnelManager.init` 末尾 `DispatchQueue.main.asyncAfter(0.5)` 调 `startIfNeeded`，已配置就自动起。
- **退出时强杀 frpc**：`applicationWillTerminate` 调 `killFrpcOnExit`，先用 `stopImmediately(timeout: 2)`，还活着就 `kill -9`。
