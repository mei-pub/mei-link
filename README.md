# Meilink

内网穿透管理工具，基于 [frp](https://github.com/fatedier/frp) 构建。

## 客户端版本

Meilink 提供以下客户端实现：

### 1. macOS 原生客户端（特色版本）

基于 **Swift + AppKit/SwiftUI** 的菜单栏应用，仅提供 macOS 平台支持。

- 常驻菜单栏，不占 Dock 空间
- 原生系统图标、Keychain 存储、Login Items 自启动
- 实时隧道状态监控与自动重连
- 要求 macOS 13.0+

详见 `client/macos-native/` 目录。

### 2. 跨平台桌面客户端（Tauri v2，推荐）

基于 **Tauri v2（Rust + Web 前端）+ Go 后端** 的跨平台原生 GUI 客户端，支持 **Windows、Linux、macOS**。

**交互与 macOS 原生客户端完全对齐**：
- 系统托盘/菜单栏图标 + 点击弹出 popover 面板（状态、隧道列表、控制按钮）
- 多个独立原生窗口（主窗口、设置、配置向导、隧道编辑、日志）
- 关窗口不退出，显式"退出"才退出
- 实时状态轮询、远程探活、自动重连

**技术架构**：Rust 壳（托盘/窗口/生命周期）+ Go sidecar（HTTP API，复用全部业务逻辑）+ Web 前端（原生窗口式 UI）。

```bash
# 构建（需 Node.js + Rust/Cargo + Go）
cd client/desktop
npm install
bash ../../scripts/build/build-desktop.sh --copy   # 构建 + 复制 DMG 到 release/client/desktop/
```

详见 `client/desktop/` 目录。

### 3. Docker 客户端（容器化 frpc）

基于 **Node.js + TypeScript** 的容器化 frpc 客户端，在 Docker 里跑 frpc，提供 Web 管理 UI。适合 NAS、家庭服务器、不想装原生客户端的场景。

> ⚠️ Docker 客户端（跑 frpc，把本地服务暴露出去）和 [服务端 Docker](server/)（跑 frps，公网中转）是**两回事**，别混淆。

详见 `client/docker/` 目录。

## 快速开始

### VPS 部署 frps

在你的 VPS 上部署 frps 服务端。参考配置：

```toml
# frps.toml
bindPort = 7000
vhostHTTPPort = 8080
vhostHTTPSPort = 8443
subDomainHost = "tunnel.yourdomain.com"
auth.method = "token"
auth.token = "YOUR_SECRET_TOKEN"
```

仓库内的部署方式：

**方式一：Shell 脚本（传统方式）**

```bash
cd server/bare-metal
bash deploy-frps.sh           # 安装或更新 frps，并启动服务
bash deploy-frps.sh start     # 启动服务
bash deploy-frps.sh stop      # 停止服务
bash deploy-frps.sh restart   # 重启服务
bash deploy-frps.sh status    # 查看状态
```

**方式二：引导式 Go 程序（推荐，支持多域名/多 token）**

```bash
# 从 release 目录直接使用预编译二进制
tar xzf release/server/meilink-setup-1.1.0-linux-amd64.tar.gz
cd meilink-setup-1.1.0-linux-amd64
sudo ./meilink-setup            # 交互式菜单

# 或自行从源码编译
cd server/setup
go build -o meilink-setup .
sudo ./meilink-setup
```

该程序支持**多 profile 管理**——每个 profile = 一个域名 + 一个 token + 一个独立的
frps systemd 服务（`frps-<name>.service`），方便多台机器各自穿透：

```bash
sudo ./meilink-setup setup              # 首次初始化（安装 frps + 创建第一个 profile）
sudo ./meilink-setup add                # 添加新 profile（域名+token）
sudo ./meilink-setup list               # 列出所有 profile
sudo ./meilink-setup start [name]       # 启动指定/所有实例
sudo ./meilink-setup stop|restart|status [name]
sudo ./meilink-setup upgrade            # 升级 frps 并重启所有实例
```

每个实例自动分配端口（bindPort 从 7000 递增），`systemctl enable --now` 确保服务器
重启后自动恢复。

### Docker 部署

```bash
docker compose up -d
```

仓库提供两套 Docker 服务端方案：`server/docker-compose/`（裸 frps，第三方镜像）和
`server/docker-managed/`（frps + Web 管理页一体镜像，自构建）。完整的选型、
配置、启动、反代与运维操作见 [docs/guides/deploy-docker.md](docs/guides/deploy-docker.md)。

### DNS 配置

在域名管理处添加泛解析记录：

```
*.tunnel.yourdomain.com  →  A  →  VPS_IP_ADDRESS
```

### macOS 原生客户端

```bash
# 使用 xcodegen 生成 Xcode 项目
brew install xcodegen
xcodegen generate

# 或直接使用 Swift Package Manager
swift build
```

### 跨平台桌面客户端（Tauri）

```bash
# 构建（需 Node.js + Rust/Cargo + Go）
cd client/desktop
npm install
bash ../../scripts/build/build-desktop.sh --copy   # 构建 + 复制产物到 release/client/desktop/
```

## 项目结构

```
mei-link/
├── client/                     # 客户端（frpc）合集
│   ├── macos-native/           # macOS 原生客户端（Swift AppKit）
│   │   ├── App/                # 应用入口
│   │   ├── Core/               # 隧道管理、frpc 进程控制
│   │   ├── Models/             # 数据模型
│   │   ├── Storage/            # Keychain + JSON 持久化
│   │   ├── UI/                 # Menu Bar、设置、向导
│   │   └── Utils/              # 网络、日志等工具
│   ├── desktop/                # 跨平台桌面客户端（Tauri v2，Win/Linux/macOS）
│   │   ├── sidecar/            # Go sidecar 源码（桌面客户端专属后端，非独立 CLI）
│   │   ├── src/                # 前端（HTML/CSS/ES）
│   │   └── src-tauri/          # Rust 壳（托盘/窗口/生命周期）
│   └── docker/                 # Docker 客户端（容器化 frpc + Web 管理，Node/TS）
│
├── server/                     # 服务端（frps）实现合集
│   ├── docker-compose/         # 方案①：裸 frps（第三方镜像 + 手写 toml）
│   ├── docker-managed/         # 方案②：frps + Web 管理页一体镜像（自构建）
│   ├── setup/                  # 方案③：Go 多 profile 部署工具（meilink-setup）
│   └── bare-metal/             # 方案④：Shell 单实例一键部署
│
├── scripts/                    # 开发辅助脚本
├── release/                    # 发布产物输出（对齐 client/server 结构）
│   ├── client/                 #   客户端产物（macos-native/ + desktop/）
│   └── server/                 #   服务端产物（meilink-setup-*.tar.gz）
├── docs/                       # 设计文档（SDD + rules + 部署手册）
├── Package.swift               # SwiftPM 配置（仓库根）
└── project.yml                 # XcodeGen 配置（仓库根）
```

## 系统要求

### macOS 原生客户端
- macOS 13.0 或更高版本
- Xcode 15.0 或更高版本（用于编译）

### 跨平台 Go 客户端
- Go 1.22 或更高版本（用于编译）
- 支持 Windows 10+、Linux（systemd）、macOS 13+

## 安全说明

- 认证 Token 存储在 macOS Keychain（原生客户端）或本地 JSON 文件（Go 客户端，权限 0600）
- frpc Admin API 仅监听 127.0.0.1
- TLS 默认启用
- 配置文件权限设为 0600

## 许可证

MIT License
