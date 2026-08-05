# Meilink SDD · 00 · 项目总览

> 本文是 Meilink 软件设计文档（SDD）的入口。本文档由 `client/macos-native/`、`scripts/`、根目录配置文件反向推导得出，事实基线以 macOS 原生 Swift 实现为准。

## 1. 项目定位

Meilink 是一款基于 [frp](https://github.com/fatedier/frp) 的内网穿透管理工具。目标用户是需要在本地开发服务（HTTP/HTTPS/TCP/UDP）并对外发布可访问入口的开发者与运维人员。

核心价值：

- 把本机的 `127.0.0.1:<port>` 服务通过 VPS 上的 frps 暴露成 `https://<subdomain>.<basehost>` 或 `tcp://<vps>:<port>` 的外网入口。
- 在 macOS 上以菜单栏常驻方式运行，不占 Dock，不打扰用户，关窗口不退出。
- 提供 macOS 原生、跨平台桌面、Docker 三种客户端，覆盖 macOS / Windows / Linux。

## 2. 客户端形态

| 形态 | 路径 | 技术栈 | 平台 | 定位 |
|---|---|---|---|---|
| macOS 原生客户端 | `client/macos-native/` | Swift + AppKit/SwiftUI | macOS 13+ | 特色版本，菜单栏常驻、Keychain、Login Items |
| 跨平台桌面客户端 | `client/desktop/` | Tauri v2（Rust + Web 前端）+ Go sidecar | Windows / Linux / macOS | 推荐版本，交互与原生客户端对齐 |
| Docker 客户端 | `client/docker/` | Node.js + TypeScript（容器化 frpc） | 任意支持 Docker 的平台 | NAS / 无头服务器 |

SDD 的事实基线是 `client/macos-native/` 下的 Swift 实现。跨平台客户端必须与 Swift 实现在数据、状态、交互上对齐，详见 `docs/sdd/06-constraints.md` 的"跨平台兼容"一节。

## 3. 技术栈

### macOS 原生客户端（`client/macos-native/`）

- Swift 5.9，macOS 13.0+ 部署目标
- AppKit + SwiftUI 混合：`NSApplication` / `NSPanel` / `NSStatusItem` 承载壳，SwiftUI 承载内容
- `@MainActor` + `ObservableObject` + Combine 管理状态
- SwiftPM + XcodeGen 双轨构建（`Package.swift` / `project.yml`）
- ServiceManagement（`SMAppService`）实现开机自启
- Keychain 存敏感凭据（auth token）
- `Process` 管控 frpc 子进程
- `URLSession` 调用 frpc Admin API
- `Network.NWConnection` 做 TCP 探活
- frpc v0.70.0（通过 `scripts/assets/download-frpc.sh` 在构建期下载到 `.app/Contents/MacOS/frpc`）

### 跨平台桌面客户端（`client/desktop/`）

- Tauri v2（Rust 壳）+ Vite + 原生 HTML/CSS/ES modules 前端
- Go sidecar：复用 `client/desktop/sidecar/internal/*` 的业务逻辑，通过本地 HTTP API 服务给前端
- 与 macOS 原生客户端共享 `~/Library/Application Support/Meilink` 目录

### Docker 客户端（`client/docker/`）

- Node.js + TypeScript，容器化 frpc + Web 管理 UI
- 适合 NAS、家庭服务器、无头环境
- 与桌面客户端业务逻辑对齐（frpc 进程管理、隧道 CRUD、Admin API）

### 服务端

- frps v0.70.0（由 `server/bare-metal/deploy-frps.sh` 或 `server/setup/`（`meilink-setup`）Go 程序部署）
- 部署形态：systemd 单实例（`server/bare-metal/deploy-frps.sh`）或多 profile（`server/setup/`，每个 profile = `frps-<name>.service`）
- Docker 形态：`server/docker-compose/`（裸 frps）或 `server/docker-managed/`（frps + Web 管理页一体镜像）

## 4. 仓库目录结构

```
mei-link/
├── client/                      # 客户端（frpc）合集
│   ├── macos-native/            # macOS 原生客户端（Swift，事实基线）
│   │   ├── App/                  # 应用入口（MeilinkApp / AppRuntime）
│   │   ├── Core/                 # 隧道管理、frpc 进程、Admin API、配置生成、探活
│   │   ├── Models/               # 数据模型（Tunnel / ServerConfig / AppSettings / ProxyDefinition / TunnelDisplay）
│   │   ├── Storage/              # Keychain + JSON 持久化
│   │   ├── UI/                   # Main / MenuBar / Settings / Setup 四组窗口
│   │   ├── Utils/                # AutoStart / Logger / Network / SubdomainNormalizer / AppIconProvider
│   │   ├── Resources/            # 图标 PNG + frps.toml 示例
│   │   └── Info.plist
│   ├── desktop/                  # 跨平台桌面客户端（Tauri v2）
│   │   ├── sidecar/              # Go sidecar 源码（桌面客户端专属后端，非独立 CLI）
│   │   ├── src/                  # 前端（HTML/CSS/ES）
│   │   └── src-tauri/            # Rust 壳（托盘/窗口/生命周期）
│   └── docker/                   # Docker 客户端（容器化 frpc，Node/TS）
├── server/                       # 服务端（frps）实现合集
│   ├── docker-compose/           # 方案①：裸 frps（docker-compose.yml + frps.toml）
│   ├── docker-managed/           # 方案②：frps + Web 管理页一体镜像（自构建）
│   ├── setup/                    # 方案③：Go 多 profile 部署工具（meilink-setup）
│   └── bare-metal/               # 方案④：Shell 单实例一键部署（deploy-frps.sh）
├── scripts/                    # 构建与开发辅助脚本
├── docs/                        # 文档（sdd / rules / guides / archive）
├── Tests/                       # 空目录（保留给 SwiftPM）
├── release/                     # 发布产物输出（对齐 client/server 结构）
│   ├── client/                  #   客户端产物（macos-native/ + desktop/）
│   └── server/                  #   服务端产物（meilink-setup-*.tar.gz）
├── build/                       # 本地构建暂存（含预构建 Meilink.app）
├── Package.swift                # SwiftPM 入口
├── project.yml                  # XcodeGen 配置
└── README.md
```

## 5. 关键运行时入口

- 应用启动入口：<kfile name="MeilinkApp.swift" path="client/macos-native/App/MeilinkApp.swift">MeilinkApp.swift</kfile>
  - 设置 `activationPolicy = .accessory`（不显示在 Dock）
  - `disableAutomaticTermination` + `disableSuddenTermination`：防止系统在后台杀进程
  - `applicationShouldTerminateAfterLastWindowClosed` 返回 `false`：关窗口不退出
  - `applicationShouldHandleReopen`：Dock/Spotlight 再次唤起时显示主窗口
- 全局运行时：<kfile name="AppRuntime.swift" path="client/macos-native/App/AppRuntime.swift">AppRuntime.swift</kfile>
  - 单例 `AppRuntime.shared` 持有 `TunnelManager` / `AppWindowController` / `StatusBarController`
  - 所有窗口与菜单栏共享同一 `manager` 实例
- 退出控制：`MeilinkAppDelegate.allowQuit` 静态标志，只有用户显式"退出"时为 `true`，否则 `applicationShouldTerminate` 返回 `terminateCancel`

## 6. SDD 索引

- [01-requirements.md](./01-requirements.md) — 用户需求、典型场景、非目标
- [02-features.md](./02-features.md) — 功能清单
- [03-architecture.md](./03-architecture.md) — 技术架构、运行时对象图、状态机、自动恢复
- [04-ui-design.md](./04-ui-design.md) — UI 设计（窗口规格、组件、配色、文案、图标）
- [05-data-contract.md](./05-data-contract.md) — 持久化 schema、Admin API、Keychain、frpc.toml 生成规则
- [06-constraints.md](./06-constraints.md) — 平台、安全、生命周期、并发、跨平台兼容约束
- [07-build-release.md](./07-build-release.md) — 构建、发布、产物命名、版本号

## 7. Agent 规则索引

- 根目录 [AGENTS.md](../../AGENTS.md) — Agent 入口、上下文管理规则、通用工作流
- [../rules/modifying-tunnel.md](../rules/modifying-tunnel.md) — 修改 Tunnel 模型与代理定义
- [../rules/modifying-status-polling.md](../rules/modifying-status-polling.md) — 修改状态轮询 / 自动重连 / 探活
- [../rules/modifying-frpc-process.md](../rules/modifying-frpc-process.md) — 修改 frpc 进程管理
- [../rules/modifying-ui.md](../rules/modifying-ui.md) — 修改 UI（窗口规格、状态色、文案不变量）
- [../rules/adding-menubar-icon.md](../rules/adding-menubar-icon.md) — 新增菜单栏图标风格
- [../rules/cross-platform-compat.md](../rules/cross-platform-compat.md) — 跨平台兼容性约束
- [../rules/build-release.md](../rules/build-release.md) — 构建与发布流程
