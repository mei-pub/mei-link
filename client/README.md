# Meilink 客户端

本目录汇集 Meilink 的**客户端（frpc）**全部实现。客户端跑在内网机器上，把本地服务通过 frp 服务端暴露到公网。

> ⚠️ **先搞清「客户端」与「服务端」**
> - **客户端（本目录）** = 跑在内网机器上的 frpc，把本地服务暴露出去。
> - **服务端** = 跑在公网 VPS 上的 frps，是流量中转枢纽，见 [`../server/`](../server/)。
>
> 「Docker 客户端」（本目录的 `docker/`）和「Docker 服务端」（`../server/docker-*`）是**两回事**：客户端在容器里跑 frpc，服务端在容器里跑 frps，不要混淆。

---

## 客户端形态

| 形态 | 目录 | 技术栈 | 平台 | 适合 |
|---|---|---|---|---|
| **macOS 原生客户端**（特色版本） | [`macos-native/`](macos-native/) | Swift + AppKit/SwiftUI | macOS 13+ | macOS 用户，想要菜单栏原生体验 |
| **跨平台桌面客户端**（推荐） | [`desktop/`](desktop/) | Tauri v2（Rust 壳 + Web 前端）+ Go sidecar | Win/Linux/macOS | 跨平台用户，交互与 macOS 原生端对齐 |
| **Docker 客户端** | [`docker/`](docker/) | Node.js + TypeScript（容器化 frpc） | 任意支持 Docker 的平台 | NAS、家庭服务器、无头环境 |

三端共用同一套**数据契约**（隧道定义、frpc.toml schema、状态机、UI 不变量），跨端行为对齐。基线和共享契约见 [`../docs/sdd/05-data-contract.md`](../docs/sdd/05-data-contract.md) 与 [`../docs/rules/cross-platform-compat.md`](../docs/rules/cross-platform-compat.md)。

---

## 选哪个？

- **macOS 用户，想要最原生的菜单栏体验** → [`macos-native/`](macos-native/)
- **Windows / Linux 用户，或想要 GUI** → [`desktop/`](desktop/)（推荐）
- **NAS / 服务器 / 想用 Docker 跑 frpc** → [`docker/`](docker/)

---

## 目录结构

```
client/
├── README.md            # 本文件（客户端总览）
├── macos-native/        # macOS 原生客户端（Swift + AppKit/SwiftUI）
│   ├── App/             # 应用入口（MeilinkApp + AppRuntime）
│   ├── Core/            # 隧道管理、frpc 进程、Admin API、配置生成、探活
│   ├── Models/          # Tunnel / ServerConfig / AppSettings / ProxyDefinition
│   ├── Storage/         # Keychain + JSON 持久化
│   ├── UI/              # Main / MenuBar / Settings / Setup 四组窗口
│   ├── Utils/           # AutoStart / Logger / Network 等
│   └── Resources/       # 图标 + frps.toml 示例
│
├── desktop/             # 跨平台桌面客户端（Tauri v2）
│   ├── sidecar/         # Go sidecar 源码（桌面客户端专属后端，非独立 CLI）
│   │   ├── main.go      # sidecar 编译入口（package main）
│   │   ├── go.mod       # Go module: github.com/meilink/desktop-sidecar
│   │   ├── cmd/meilink/ # sidecar CLI 逻辑（由 Tauri 以 serve 子命令拉起）
│   │   ├── internal/    # 共享业务（config/frpc/tunnel/web/service）
│   │   └── assets/      # 静态资源
│   ├── src/             # 前端（原生窗口式 UI：HTML/CSS/ES）
│   ├── src-tauri/       # Rust 壳（托盘/窗口/生命周期 + 启动 sidecar）
│   ├── package.json     # 前端依赖（Vite）
│   └── vite.config.js
│
└── docker/              # Docker 客户端（容器化 frpc + Web 管理）
    ├── Dockerfile
    ├── src/             # Node.js/TS 服务（frpc 进程管理 + Web API）
    ├── web/             # 前端
    └── package.json
```

---

## 快速开始

### macOS 原生客户端
```bash
# 仓库根执行（Package.swift 在仓库根）
swift build                    # SwiftPM
# 或
xcodegen generate && xcodebuild -project Meilink.xcodeproj -scheme Meilink -configuration Release build
```
详见 [`macos-native/`](macos-native/) 与 [`../docs/sdd/04-ui-design.md`](../docs/sdd/04-ui-design.md)。

### 跨平台桌面客户端（推荐）
```bash
cd desktop
npm install
bash ../../scripts/build/build-desktop.sh --copy   # 构建前端 + Go sidecar + Rust 壳
```
详见 [`desktop/`](desktop/) 与 [`../scripts/build/build-desktop.sh`](../scripts/build/build-desktop.sh)。

### Docker 客户端
```bash
cd docker
docker build -t meilink-client .
# 环境变量与端口配置见 docker/docker-compose.client.yml
```
详见 [`docker/`](docker/)。

---

## 关于 Go sidecar（重要）

桌面客户端的 [`desktop/sidecar/`](desktop/sidecar/) 是一段 Go 代码，它**不是独立 CLI 产品**，而是桌面客户端的专属后端：

- 桌面 App 启动时，Rust 壳（`desktop/src-tauri/`）用 `Command::sidecar("meilink")` 拉起这段 Go 二进制
- 全部隧道/配置/状态 REST API 和 frpc 进程管理都在 sidecar 里
- 前端（`desktop/src/`）只是 HTTP 客户端，调用 sidecar 暴露的接口

构建链：`scripts/build/build-desktop.sh` 第一步 `go build .`（在 `desktop/sidecar/`）生成二进制到 `desktop/src-tauri/binaries/`，然后 Tauri 打包。

> macOS 原生客户端和 Docker 客户端**不使用**这个 sidecar——前者用 Swift 直接实现业务逻辑，后者用 Node.js/TS 实现。

---

## 相关文档
- 服务端实现：[`../server/`](../server/)、[`../server/README.md`](../server/README.md)
- Docker 服务端部署手册：[`../docs/guides/deploy-docker.md`](../docs/guides/deploy-docker.md)
- 跨端兼容契约：[`../docs/rules/cross-platform-compat.md`](../docs/rules/cross-platform-compat.md)
- 项目总览（Agent 入口）：[`../AGENTS.md`](../AGENTS.md)
