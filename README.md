# Meilink

内网穿透管理工具，基于 [frp](https://github.com/fatedier/frp) 构建。

## 客户端版本

Meilink 提供三种客户端实现：

### 1. macOS 原生客户端（特色版本）

基于 **Swift + AppKit/SwiftUI** 的菜单栏应用，仅提供 macOS 平台支持。

- 常驻菜单栏，不占 Dock 空间
- 原生系统图标、Keychain 存储、Login Items 自启动
- 实时隧道状态监控与自动重连
- 要求 macOS 13.0+

详见 `Meilink/` 目录。

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
cd cross-platform-client/desktop
npm install
bash ../../Scripts/build-desktop.sh --copy   # 构建 + 复制 DMG 到 release/
```

详见 `cross-platform-client/desktop/` 目录。

### 3. 跨平台 CLI 客户端（Go，轻量备选）

基于 **Go** 的命令行客户端，支持 **Windows、Linux、macOS**。无 GUI，适合服务器/无头环境。

- 前台运行 + Web UI（浏览器管理）
- 自动下载对应平台的 frpc 二进制
- 支持 systemd / Windows Service 注册

详见 `cross-platform-client/` 目录。

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
./deploy-frps.sh           # 安装或更新 frps，并启动服务
./deploy-frps.sh start     # 启动服务
./deploy-frps.sh stop      # 停止服务
./deploy-frps.sh restart   # 重启服务
./deploy-frps.sh status    # 查看状态
```

**方式二：引导式 Go 程序（推荐，支持多域名/多 token）**

```bash
# 从 release 目录直接使用预编译二进制
tar xzf release/meilink-setup-1.1.0-linux-amd64.tar.gz
cd meilink-setup-1.1.0-linux-amd64
sudo ./meilink-setup            # 交互式菜单

# 或自行从源码编译
cd cross-platform-client
go build -o meilink-setup ./cmd/meilink-setup
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

### 跨平台 Go 客户端

```bash
cd cross-platform-client

# 当前平台（入口是根包 main.go，导入 cmd/meilink）
go build -o meilink .

# 交叉编译
GOOS=windows GOARCH=amd64 go build -o meilink-windows-amd64.exe .
GOOS=linux   GOARCH=arm64 go build -o meilink-linux-arm64    .
GOOS=darwin  GOARCH=arm64 go build -o meilink-darwin-arm64   .

# 交互式配置
./meilink setup

# 启动客户端
./meilink start --listen :7400

# 访问 Web UI
open http://localhost:7400
```

## 项目结构

```
mei-link/
├── Meilink/                    # macOS 原生客户端（Swift AppKit）
│   ├── App/                    # 应用入口
│   ├── Core/                   # 隧道管理、frpc 进程控制
│   ├── Models/                 # 数据模型
│   ├── Storage/                # Keychain + JSON 持久化
│   ├── UI/                     # Menu Bar、设置、向导
│   └── Utils/                  # 网络、日志等工具
│
├── cross-platform-client/      # 跨平台 Go 客户端（新增）
│   ├── cmd/
│   │   ├── meilink/            # 主程序 CLI 入口
│   │   └── meilink-setup/      # VPS 部署引导程序
│   ├── internal/
│   │   ├── config/             # 配置管理 + frpc.toml 生成
│   │   ├── frpc/               # frpc 进程管理 + 自动下载 + Admin API
│   │   ├── tunnel/             # 隧道 CRUD 管理
│   │   ├── web/                # Web UI 服务 + HTML 模板
│   │   └── service/            # 系统服务注册
│   ├── assets/                 # 静态资源
│   ├── build.sh                # 构建脚本
│   └── README.md
│
├── Scripts/                    # 开发辅助脚本
├── deploy-frps.sh              # 传统 frps 部署脚本
├── docker-compose.yml          # Docker 部署配置
└── frps.toml                   # frps 示例配置
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
