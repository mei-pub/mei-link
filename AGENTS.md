# AGENTS.md

> 这是 Meilink 仓库的 Agent 入口。**任何 Agent 在动这个仓库之前必读本文**。本文解决一个核心痛点：上下文容易溢出导致执行结果总不对。下面给出按需加载策略，让你只读必要的上下文就能完成任务。

## 1. 项目速览

Meilink 是基于 [frp](https://github.com/fatedier/frp) 的内网穿透管理工具，两种客户端形态 + 服务端部署工具：

| 形态 | 路径 | 技术栈 | 平台 |
|---|---|---|---|
| macOS 原生客户端（特色版本） | `Meilink/` | Swift + AppKit/SwiftUI | macOS 13+ |
| 跨平台桌面客户端（推荐） | `cross-platform-client/desktop/` | Tauri v2 + Go sidecar + Web 前端 | Win/Linux/macOS |
| 服务端部署工具 | `cross-platform-client/cmd/meilink-setup/` + `deploy-frps.sh` | Go + Shell | Linux |

**事实基线**：macOS 原生 Swift 客户端（`Meilink/`）是行为、视觉、数据、状态、frpc 交互的 source of truth。跨平台客户端必须与 Swift 实现对齐。

详见 [docs/sdd/00-overview.md](docs/sdd/00-overview.md)。

## 2. 上下文管理规则（核心痛点解决方案）

### 2.1 按需加载，不要全量读码

修改某模块前**只读对应的 SDD + 对应 agent-rules**，不要全量加载 `docs/sdd/` 或全量读 `Meilink/`。索引见 §4 / §5。

### 2.2 不重复读已读文件

已经读过的文件**不要再次 `read_file`**。用以下工具精准定位：
- `grep_search` — 搜关键词
- `view_file_outline` — 看文件结构
- `view_code_item` — 看具体函数/类
- `list_files` — 看目录结构

### 2.3 先查规则再改代码

修改前先查 `docs/agent-rules/` 是否有对应专题规则。规则文件包含"何时触发 / 必读不变量 / 同步修改清单 / 反例 / 验证步骤"。

### 2.4 跳过 cross-platform-client（除非必要）

本次基线是 Swift 实现。只有以下情况才读 `cross-platform-client/`：
- 任务明确要求修改跨平台客户端
- 任务涉及跨端兼容性（持久化 schema / frpc 交互 / 状态机 / UI 不变量）
- SDD 或 agent-rules 明确要求跨端同步

否则只读 `Meilink/` + `Scripts/` + 根目录配置。

### 2.5 大文件先 outline

超过 300 行的文件先 `view_file_outline` 看结构，再决定读哪一段。Meilink 里超过 300 行的文件：
- `Meilink/Core/TunnelManager.swift`（592 行）
- `Meilink/App/AppRuntime.swift`（426 行）
- `Meilink/UI/Settings/SettingsView.swift`（401 行）
- `Meilink/UI/Main/LogWindowView.swift`（213 行）
- `Meilink/UI/Main/MainWindow.swift`（216 行）
- `Meilink/UI/MenuBar/MenuBarView.swift`（231 行）
- `Scripts/build-all.sh`（273 行）
- `deploy-frps.sh`（259 行）

### 2.6 修改前先核 schema

涉及 `Tunnel` / `ServerConfig` / `AppSettings` / `ProxyDefinition` 修改时，必须同步检查 [docs/sdd/05-data-contract.md](docs/sdd/05-data-contract.md) 列出的所有下游引用点。详见 [docs/agent-rules/modifying-tunnel.md](docs/agent-rules/modifying-tunnel.md)。

### 2.7 任务对应必读

| 任务类型 | 必读 SDD | 必读 agent-rules |
|---|---|---|
| 改 Tunnel 模型 / 代理定义 | `05-data-contract.md` | `modifying-tunnel.md` |
| 改状态轮询 / 自动重连 / 探活 | `03-architecture.md` + `06-constraints.md` | `modifying-status-polling.md` |
| 改 frpc 进程管理 | `03-architecture.md` + `06-constraints.md` | `modifying-frpc-process.md` |
| 改 UI / 窗口 / 状态色 / 文案 | `04-ui-design.md` + `06-constraints.md` | `modifying-ui.md` |
| 新增菜单栏图标风格 | `04-ui-design.md` | `adding-menubar-icon.md` |
| 改跨平台兼容性 | `05-data-contract.md` + `06-constraints.md` + `04-ui-design.md` | `cross-platform-compat.md` |
| 构建 / 发布 / 改版本号 | `07-build-release.md` | `build-release.md` |
| 新需求 / 不确定改哪 | `00-overview.md` + `02-features.md` | — |

### 2.8 不要做的事

- ❌ 不要 `read_file` 整个 `Meilink/` 目录下所有文件
- ❌ 不要 `read_file` 整个 `cross-platform-client/`（除非跨端任务）
- ❌ 不要在没读 agent-rules 的情况下改代码
- ❌ 不要改 `CFBundleIdentifier`（会破坏 Login Items + Keychain）
- ❌ 不要改状态文案 / 状态色 / 窗口尺寸（跨平台对齐基线，详见 `06-constraints.md` §5）
- ❌ 不要改 frp 版本号而不三处同步（`download-frpc.sh` / `build-frpc.sh` / `deploy-frps.sh`）
- ❌ 不要去掉 frpc 停止的 `kill -9` 兜底
- ❌ 不要去掉自动恢复的 `isRecovering` / `recoveryCooldown` 保护
- ❌ 不要在 `webServer.addr` 写 `0.0.0.0`（Admin API 不能对外）
- ❌ 不要在 `frpc.toml` 里写 proxy 配置（通过 Store API 动态管理）

## 3. 通用工作流

接任务后按以下步骤执行：

### Step 1 · 判断任务类型
读任务描述，对照 §2.7 表格确定任务类型。

### Step 2 · 加载必要上下文
按 §2.7 表格读对应 SDD + agent-rules。**不要全量加载**。

### Step 3 · 用 plan 工具记录
复杂任务（3+ 步骤）用 `write_todo` 建任务清单，避免跑偏。

### Step 4 · 代码定位
用 `grep_search` / `view_file_outline` / `view_code_item` 精准定位要改的代码，不要 `read_file` 整个文件。

### Step 5 · 按 agent-rules 同步修改清单执行
agent-rules 的"同步修改清单"是 checklist，逐项勾选。

### Step 6 · 验证
按 agent-rules 的"验证步骤"执行。能 `swift build` 编译通过是最低要求。

### Step 7 · 同步 SDD
改了共享契约（schema / frpc 交互 / 状态机 / UI 不变量 / 构建流程）必须同步对应 SDD。

### Step 8 · 自检
检查是否引入 lint error / 编译错误。若引入，立即修复。

## 4. SDD 索引

| 文件 | 内容 |
|---|---|
| [docs/sdd/00-overview.md](docs/sdd/00-overview.md) | 项目定位、技术栈、目录结构、运行时入口、SDD 索引 |
| [docs/sdd/01-requirements.md](docs/sdd/01-requirements.md) | 用户需求、用户故事、非目标、典型场景、隐含需求 |
| [docs/sdd/02-features.md](docs/sdd/02-features.md) | 功能清单（F1-F10，每条含入口 + 实现位置 + 流程） |
| [docs/sdd/03-architecture.md](docs/sdd/03-architecture.md) | 运行时拓扑、启动序列、核心对象职责、状态机、自动恢复、并发模型 |
| [docs/sdd/04-ui-design.md](docs/sdd/04-ui-design.md) | 窗口规格、视觉语言、各窗口结构、菜单栏面板、状态文案、图标 |
| [docs/sdd/05-data-contract.md](docs/sdd/05-data-contract.md) | 持久化 schema、Keychain、frpc.toml 生成、Admin API 端点、端口契约 |
| [docs/sdd/06-constraints.md](docs/sdd/06-constraints.md) | 平台、安全、生命周期、并发、UI 不变量、跨平台兼容约束 |
| [docs/sdd/07-build-release.md](docs/sdd/07-build-release.md) | 构建矩阵、产物命名、版本号、CI 提示、发布检查清单 |

## 5. Agent 规则索引

| 文件 | 何时触发 |
|---|---|
| [docs/agent-rules/modifying-tunnel.md](docs/agent-rules/modifying-tunnel.md) | 修改 `Tunnel` / `TunnelType` / `ProxyDefinition` 结构或新增代理类型 |
| [docs/agent-rules/modifying-status-polling.md](docs/agent-rules/modifying-status-polling.md) | 修改状态轮询 / 自动重连 / 探活 / 阈值 / frpc 退出回调 |
| [docs/agent-rules/modifying-frpc-process.md](docs/agent-rules/modifying-frpc-process.md) | 修改 frpc 进程管理 / 二进制查找 / 停止策略 / 退出强杀 |
| [docs/agent-rules/modifying-ui.md](docs/agent-rules/modifying-ui.md) | 修改任何 SwiftUI 视图 / 窗口尺寸 / 状态色 / 状态文案 / 生命周期行为 |
| [docs/agent-rules/adding-menubar-icon.md](docs/agent-rules/adding-menubar-icon.md) | 新增第 6 种菜单栏图标风格 |
| [docs/agent-rules/cross-platform-compat.md](docs/agent-rules/cross-platform-compat.md) | 修改跨平台客户端或涉及跨端共享契约 |
| [docs/agent-rules/build-release.md](docs/agent-rules/build-release.md) | 构建、发布、改版本号、改图标、改构建脚本 |

## 6. 项目目录结构速查

```
mei-link/
├── AGENTS.md                   # ← 你在这里
├── docs/
│   ├── sdd/                    # 软件设计文档（8 个文件）
│   ├── agent-rules/            # Agent 专题规则（7 个文件）
│   └── superpowers/            # 旧的对齐文档（保留）
├── Meilink/                    # macOS 原生客户端（Swift）
│   ├── App/                    # MeilinkApp + AppRuntime（单例 + 窗口 + 菜单栏）
│   ├── Core/                   # TunnelManager + FrpcProcess + AdminAPI + ConfigGenerator + Probe
│   ├── Models/                 # Tunnel / ServerConfig / AppSettings / ProxyDefinition / TunnelDisplay
│   ├── Storage/                # TunnelStore + KeychainHelper
│   ├── UI/                     # Main / MenuBar / Settings / Setup 四组窗口
│   ├── Utils/                  # AutoStart / Logger / Network / SubdomainNormalizer / AppIconProvider
│   └── Resources/              # 图标 + frps.toml 示例
├── cross-platform-client/      # 跨平台客户端（Tauri 桌面 + Go sidecar + setup 工具，跳过除非跨端任务）
├── Scripts/                    # 构建脚本（build-all / build-desktop / download-frpc / gen-icons 等）
├── release/                    # 发布产物输出
├── build/                      # 本地构建暂存
├── Package.swift               # SwiftPM
├── project.yml                 # XcodeGen
├── deploy-frps.sh              # frps 一键部署
├── docker-compose.yml          # frps Docker 部署
└── frps.toml                   # frps 示例配置
```

## 7. 快速参考

### 7.1 关键常量
| 常量 | 值 | 位置 |
|---|---|---|
| frp 版本 | v0.70.0 | `Scripts/download-frpc.sh` / `build-frpc.sh` / `deploy-frps.sh` |
| 发布版本 | 1.1.0 | `Scripts/build-all.sh` 默认参数 |
| macOS 最低系统 | 13.0 | `project.yml` / `Info.plist` / `Package.swift` |
| Swift 版本 | 5.9 | `project.yml` |
| Bundle ID | `vip.rego.meilink` | `Info.plist` / `project.yml` |
| 持久化目录 | `~/Library/Application Support/Meilink` | `TunnelStore.swift` |
| Keychain service | `com.meilink` | `KeychainHelper.swift` |
| 自动恢复阈值 | 3 次失败 | `TunnelManager.maxConsecutiveFailuresBeforeRecovery` |
| 恢复冷却 | 20 秒 | `TunnelManager.recoveryCooldown` |
| 状态轮询 clamp | [3, 30] | `TunnelManager.startStatusPolling` |
| 远程探活 clamp | [30, 600] | `TunnelManager.shouldProbeReachability` |

### 7.2 状态文案
- 隧道：新建 / 连接中 / 启动失败 / 运行中 / 检查失败 / 已关闭
- 应用：已连接 / 连接中 / 未连接 / 未配置

### 7.3 状态色
- running → green / waitStart → yellow / startError / checkFailed → red / new / closed → gray

### 7.4 窗口尺寸
- 主窗口 1060×820 / 设置 760×460 / 首次配置 560×640 / 隧道编辑 660×440 / 日志 820×620 / 菜单栏面板 330×440

### 7.5 关键端点
- frps bindPort: 7000（客户端连接）
- frpc Admin API: 7400（本地管理）
- frps vhostHTTPPort: 8080 / vhostHTTPSPort: 8443

### 7.6 构建命令速查
```bash
# 开发环境
bash Scripts/setup-dev.sh

# macOS 原生客户端
xcodegen generate
xcodebuild -project Meilink.xcodeproj -scheme Meilink -configuration Release build
# 或
swift build

# 跨平台全产物
bash Scripts/build-all.sh [version]

# Tauri 桌面客户端
bash Scripts/build-desktop.sh [--copy]

# frps 服务端部署
./deploy-frps.sh
# 或
sudo ./meilink-setup setup
```

## 8. 当前已知遗留问题

以下是当前实现里已识别但未修复的问题，**不要在新任务里"顺手修复"**，除非任务明确要求：

1. **`Info.plist` 的 `CFBundleShortVersionString = 1.0.0` 与发布版本 `1.1.0` 不一致**：历史遗留，改 `Info.plist` 会影响 Login Items 注册，需评估后再统一。
2. **`AppSettings.showInDock` 字段未真正生效**：`SettingsView` 没暴露此选项，`MeilinkApp` 也没读它。保留占位。
3. **`Package.swift` exclude `Resources` 目录**：SwiftPM 构建时不包含 PNG 资源，菜单栏图标在 SwiftPM 构建下会 fallback 到 AppIcon。建议用 Xcode 构建。
4. **`releasePort` 方法保留但未调用**：`TunnelManager.releasePort` 实现完整但未在任何主路径调用，保留给未来需要。
5. **`DNSGuideView` 未挂到任何按钮**：组件已实现，但 SetupView/SettingsView 都没引用它。
6. **`Tests/` 目录为空**：SwiftPM 测试目录保留，但当前无测试。详见 [docs/sdd/07-build-release.md](docs/sdd/07-build-release.md) §8.4。
7. **`FrpcProcess.stop` 的 interrupt 调用嵌套层级错位**：`stopImmediately` 第 138-151 行的 `if process.isRunning` 嵌套缩进看起来异常（可能是历史合并错误），但功能正常。改之前先实测。

## 9. 反馈

发现 SDD / agent-rules 有遗漏、错误、或不够用的情况，请直接更新对应文档，并在 commit message 里标注"docs: update SDD/agent-rules for <scenario>"。
