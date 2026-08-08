# Meilink

内网穿透管理工具，基于 [frp](https://github.com/fatedier/frp) 构建。提供 macOS 原生、跨平台桌面（Tauri）、Docker 三种客户端形态，以及 Docker / 裸机多种服务端部署方案。

## 客户端 vs 服务端

> ⚠️ **Docker 客户端和 Docker 服务端是两回事**：客户端（`client/docker/`）在容器里跑 frpc，把本地服务暴露出去；服务端（`server/docker-managed/`）在容器里跑 frps，是公网中转枢纽。别混淆。

| | 客户端（frpc） | 服务端（frps） |
|---|---|---|
| 作用 | 跑在内网，把本地服务暴露到公网 | 跑在公网 VPS，转发流量 |
| 文档 | [`client/`](client/README.md) | [`server/`](server/README.md) |

## 客户端形态

| 形态 | 平台 | 说明 |
|---|---|---|
| macOS 原生客户端 | macOS 13+ | Swift + AppKit/SwiftUI 菜单栏应用，原生体验。详见 [`client/macos-native/`](client/macos-native/) |
| 跨平台桌面客户端（推荐） | Win / Linux / macOS | Tauri v2 + Go sidecar GUI，交互与原生端对齐。详见 [`client/desktop/`](client/desktop/) |
| Docker 客户端 | 任意 Docker 平台 | 容器化 frpc + Web 管理 UI，适合 NAS / 无头环境。详见 [`client/docker/`](client/docker/) |

## 服务端部署

| 方案 | 形态 | 说明 |
|---|---|---|
| ① Docker 一体镜像 | frps + Web 管理页 | 推荐，图形化管理多域名/多隧道。详见 [`server/docker-managed/`](server/docker-managed/) |
| ② Docker 裸 frps | 第三方镜像 + `frps.toml` | 轻量，只做基础穿透。详见 [`server/docker-compose/`](server/docker-compose/) |
| ③ 裸机 setup 工具 | Go 程序，systemd 多 profile | 不用 Docker，多域名各自隔离。详见 [`server/setup/`](server/setup/) |
| ④ 裸机 Shell 脚本 | `deploy-frps.sh` 单实例 | 最快跑起来。详见 [`server/bare-metal/`](server/bare-metal/) |

## 快速开始

- **VPS 部署 frps** → [`server/`](server/README.md)，完整手册见 [Docker 部署指南](docs/guides/deploy-docker.md)
- **Windows / Linux 用桌面客户端** → [`client/desktop/`](client/desktop/)，构建脚本见 [`scripts/build/build-desktop.sh`](scripts/build/build-desktop.sh)
- **macOS 用原生客户端** → [`client/macos-native/`](client/macos-native/)
- **NAS 用 Docker** → 客户端 [`client/docker/`](client/docker/) 与 服务端 [`server/docker-managed/`](server/docker-managed/)
- **发布产物与版本发布流程** → [docs/sdd/07-build-release.md](docs/sdd/07-build-release.md)

各端的安装、构建、环境变量等完整说明见对应目录的 README。

## 项目结构

```
mei-link/
├── client/                 # 客户端（frpc）合集
│   ├── macos-native/       #   macOS 原生客户端（Swift）
│   ├── desktop/            #   跨平台桌面客户端（Tauri v2 + Go sidecar）
│   └── docker/             #   Docker 客户端（Node/TS + frpc）
├── server/                 # 服务端（frps）合集
│   ├── docker-compose/     #   方案① 裸 frps（第三方镜像）
│   ├── docker-managed/     #   方案② frps + Web 管理页一体镜像
│   ├── setup/              #   方案③ Go 多 profile 部署工具
│   └── bare-metal/         #   方案④ Shell 一键部署
├── scripts/                # 开发辅助脚本（构建/发布）
├── release/                # 发布产物输出（CI 生成，不入库）
├── docs/                   # 设计文档（SDD + rules + 部署手册）
├── Package.swift           # SwiftPM 配置（仓库根）
└── project.yml             # XcodeGen 配置（仓库根）
```

## 系统要求

- macOS 原生客户端：macOS 13.0+；编译需 Xcode 15+
- 跨平台桌面客户端：Windows 10+ / Linux（systemd）/ macOS 13+；编译需 Node.js 22、Go 1.22、Rust
- Docker 客户端 / 服务端：任意支持 Docker 的平台（镜像支持 `linux/amd64` + `linux/arm64`）

## 安全说明

- 认证 Token 存于 macOS Keychain（原生端）或本地 JSON（权限 0600）
- frpc Admin API 仅监听 127.0.0.1
- TLS 默认启用；管理页请勿直接暴露公网

## 许可证

MIT License
