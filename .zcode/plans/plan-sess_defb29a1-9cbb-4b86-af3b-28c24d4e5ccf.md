# 跨平台客户端重构为 Tauri v2 原生 GUI 应用

## 问题与目标

当前 Go 客户端是"打开浏览器看网页"，与 macOS 原生客户端（菜单栏常驻 + popover 面板 + 多个原生窗口）的交互完全不同。用户要求：**交互形式、功能逻辑、交互路径必须和原生客户端完全一致**。

重构为 **Tauri v2（Rust 壳 + Web 前端 + Go sidecar）**，复刻原生客户端的完整交互：
- 系统托盘/菜单栏图标 + 点击弹出 popover 面板（330×440，含状态/隧道列表/控制按钮）
- 多个独立原生窗口（主窗口 1060×820、设置 760×880、配置向导 560×640、隧道编辑 660×840、日志 820×620）
- 退出语义（关窗口不退出，显式"退出"才退出，退出前停 frpc）
- 首次未配置自动弹配置向导

## 架构

```
┌─────────────────────────────────────────────┐
│  Tauri v2 应用（Rust 壳 + Web 前端）          │
│  ┌─────────────┐  ┌───────────────────────┐ │
│  │ Rust 壳      │  │ Web 前端 (HTML/JS/CSS) │ │
│  │ - 托盘图标    │  │ - popover 面板         │ │
│  │ - 窗口管理    │  │ - 主/设置/向导/编辑/日志 │ │
│  │ - sidecar管理 │  │   5 个窗口的 UI        │ │
│  └──────┬───────┘  └───────────┬───────────┘ │
│         │ spawn + HTTP         │ fetch HTTP   │
│         ▼                      ▼              │
│  ┌──────────────────────────────────────────┐│
│  │ Go sidecar（复用现有 internal/* 逻辑）     ││
│  │ - tunnel.Manager（状态轮询/探活/自动重连）  ││
│  │ - frpc 进程管理 + Admin API               ││
│  │ - 配置/隧道 CRUD                          ││
│  │ - HTTP API (127.0.0.1:随机端口)           ││
│  └──────────────────────────────────────────┘│
└─────────────────────────────────────────────┘
```

**数据流**：前端 `fetch` → Go sidecar HTTP API（127.0.0.1:随机端口）→ 业务逻辑。Rust 壳只管托盘/窗口/sidecar 生命周期。

## 目录结构

新建 `cross-platform-client/desktop/`（Tauri 项目），与现有 Go 代码并列：

```
cross-platform-client/
├── internal/           # Go 后端（保留，不动）
├── cmd/meilink/        # Go CLI（保留，作为 sidecar 入口）
├── desktop/            # 新增：Tauri v2 项目
│   ├── src-tauri/
│   │   ├── Cargo.toml
│   │   ├── tauri.conf.json
│   │   ├── capabilities/default.json
│   │   ├── src/
│   │   │   └── main.rs         # Rust 壳：托盘+窗口+sidecar
│   │   ├── icons/              # 应用图标
│   │   └── binaries/           # Go sidecar 二进制（构建时填入）
│   ├── src/                    # 前端源码
│   │   ├── popover.html        # 托盘 popover 面板
│   │   ├── main.html           # 主窗口
│   │   ├── settings.html       # 设置窗口
│   │   ├── setup.html          # 配置向导
│   │   ├── tunnel-edit.html    # 隧道编辑
│   │   └── logs.html           # 日志窗口
│   ├── styles/                 # 共享样式
│   ├── lib/                    # 共享 JS（API 客户端等）
│   ├── package.json
│   └── vite.config.js
├── go.mod
└── ...
```

## 实现步骤

### 第 1 步：搭建 Tauri v2 项目骨架
- `desktop/src-tauri/Cargo.toml`：依赖 `tauri`(v2,tray-icon,image-png 特性)、`tauri-plugin-positioner`、`tauri-plugin-shell`、`reqwest`(检测 sidecar 端口)
- `desktop/src-tauri/tauri.conf.json`：定义 6 个窗口（popover + 主 + 设置 + 向导 + 编辑 + 日志），各窗口的尺寸/标题/decorations 配置。popover 特殊配置：decorations:false、resizable:false、skipTaskbar:true、visible:false。macOS 设 LSUIElement:true（纯菜单栏应用，不显示 Dock 图标）
- `desktop/src-tauri/capabilities/default.json`：授权 shell:allow-spawn-sidecar、positioner、event 等权限

### 第 2 步：Rust 壳实现（`src/main.rs`）
**托盘 + popover**：
- 创建 TrayIcon，图标用 AppIcon
- `show_menu_on_left_click(false)`，左键点击时：用 positioner 把 popover 窗口定位到 `TrayCenter`，toggle show/hide
- popover 窗口失焦自动关闭（监听 `WindowEvent::Focused(false)`）
- 右键弹出原生菜单（打开主窗口/设置/退出）

**多窗口管理**：
- 启动时自动显示主窗口（延迟 300ms，对齐原生）
- 提供 Rust 命令 `open_window(name)` 供前端调用，打开/聚焦指定窗口
- 窗口单例复用（已存在则 focus）

**Sidecar 生命周期**：
- `setup` 里用 `tauri-plugin-shell` 的 `sidecar("meilink")` 启动 Go 二进制，传 `serve` 参数
- Go sidecar 启动后选随机端口起 HTTP server，把端口号写到临时文件（如 `~/.meilink/sidecar.port`）
- Rust 轮询读取端口文件 + 探测 HTTP 可用后，通过 `emit` 把 API base URL 通知前端
- 应用退出（`on_window_event Destroyed` 或 RunEvent::Exit）时 kill sidecar 子进程

**退出语义**：
- 关闭任意窗口不退出应用（配置 `closeRequested` 拦截，改为 hide）
- 只有"退出"按钮触发 Rust 命令 `quit_app`：先停 sidecar + frpc，再 `app.exit(0)`

### 第 3 步：Go sidecar 改造
现有 `internal/web/server.go` 已是 HTTP server，需要微调：
- 新增 `serve` 子命令到 `cmd/meilink/main.go`：自动选可用端口（`:0` 或随机），监听 `127.0.0.1`，把端口写入 `~/.meilink/sidecar.port`
- 保留所有现有 API（status/tunnels/server-config/events/settings/control）
- `serve` 模式下 autoStart 设为 false（由 Rust 壳控制生命周期，不自动启 frpc）
- 现有 CLI 命令（start/stop/setup/install-service）保留不变

### 第 4 步：前端实现（6 个窗口，逐个复刻原生 UI）
共享样式：对齐原生客户端的深色主题（--bg:#0f172a 等变量已在前几轮定义过）。共享 `lib/api.js` 封装 fetch 调用 + 端口发现。

**4a. popover 面板**（330×440，对齐 MenuBarView）：
- 状态头部卡片：状态圆点 + 标题（已连接/连接中/未连接/未配置）+ 副标题（服务器信息）+ 播放/停止按钮
- 隧道区：标题"N 个启用" + 每个启用隧道一行（状态点+名称+路由文本+复制/打开按钮），空态"暂无启用隧道+添加"
- 控制按钮区：主窗口/日志/服务器/重启/退出 五个按钮
- 首次未配置自动打开 setup 窗口

**4b. 主窗口**（1060×820，对齐 MainWindow）：
- Header：logo + 标题 + 服务器摘要 + 状态指示器 + 连接/重启/设置三按钮
- 隧道列表：表头（名称/本地/外网访问/状态）+ 每行（状态点+名称、类型+本地地址、路由文本+错误、状态名、复制/打开按钮、启用开关、编辑/删除菜单）
- Footer：添加隧道按钮 + X/Y启用计数 + 查看日志/清空日志

**4c. 配置向导 setup**（560×640，对齐 SetupView）：
- 服务器地址/端口/Token/子域名基域/TLS 开关 + DNS 提示文字 + 测试连接按钮 + 保存按钮

**4d. 隧道编辑 tunnel-edit**（660×840，对齐 TunnelEditView）：
- 名称 + 类型分段选择（TCP/UDP/HTTP/HTTPS）+ 本地端口 + 本地地址 + 字段联动（HTTP/HTTPS→子域名，TCP/UDP→远程端口）+ 启用开关 + 取消/保存

**4e. 设置 settings**（760×880，对齐 SettingsView）：
- 卡片1 服务器配置（地址/端口/Token 显隐切换/子域名/TLS/测试连接）
- 卡片2 应用设置（开机自启/菜单栏图标选择/远程探测间隔/退出按钮）
- 卡片3 最近事件 + 保存/保存并重启/关闭

**4f. 日志 logs**（820×620，对齐 LogWindowView）：
- 表格（时间/级别/内容）+ 复制全部/导出/清空 + 右键菜单

### 第 5 步：图标资源
- 用已有的 `Meilink/Resources/AppIcon.png`(1254×1254) 通过 `tauri icon` 命令生成全套 Tauri 图标（各尺寸 png + icns + ico）
- 放到 `desktop/src-tauri/icons/`

### 第 6 步：构建流程
更新 `Scripts/build-all.sh`：
1. 先 Go 交叉编译 sidecar 二进制，按 target triple 后缀命名放到 `desktop/src-tauri/binaries/`
2. `cd desktop && npm install && npx tauri build` 生成各平台安装包
3. 由于交叉编译限制，本机（macOS arm64）只能构建 macOS 版本；Windows/Linux 需在对应平台或 CI 上构建
4. 产物：macOS → `.dmg`，Windows → `.msi`/`.exe`，Linux → `.deb`/`.AppImage`

### 第 7 步：验证与文档
- 本机构建 macOS 版，验证 popover + 各窗口功能完整
- 更新 RELEASE_NOTES.md

## 关键风险与约束

1. **本机无完整 Xcode**：Tauri macOS 构建可能失败（需要 Xcode 而非 CLT）。若失败，代码完整实现但标注需要在有 Xcode 的环境构建，或用 CI。
2. **Linux/Windows 包需对应平台构建**：交叉编译受限，会在构建脚本中说明并提供 GitHub Actions 配置建议。
3. **Rust/Cargo 是 Homebrew 版**：rustup 未配置，可能需要先 `rustup default stable`。Tauri CLI 通过 npm 局部安装（`npx tauri`）。

## 不做的事
- 不修改现有 Go 后端逻辑（`internal/*`），只新增 `serve` 子命令
- 不修改 macOS 原生 Swift 客户端
- 保留现有 CLI 模式（`meilink start` 等）作为无 GUI 备用方案
- 服务端程序 `meilink-setup` 不受影响