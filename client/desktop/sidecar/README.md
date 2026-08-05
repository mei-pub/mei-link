# Meilink Desktop Sidecar

跨平台桌面客户端（[`../`](../)）的 **Go sidecar 后端**。

> ⚠️ 这段代码**不是独立 CLI 产品**。它是桌面客户端的专属后端，由 Tauri Rust 壳以 `serve` 子命令拉起，提供全部 REST API 和 frpc 进程管理。直接 `go build` 它会产出 archive（`cmd/meilink/` 是 `package meilink`，真正的 `func main` 在本目录根的 `main.go`，专供 sidecar 编译链）。
>
> macOS 原生客户端和 Docker 客户端**不使用**本 sidecar。

## 它做什么

桌面 App（[`../src-tauri/`](../src-tauri/) 的 Rust 壳）启动时：

1. Rust 端用 `Command::sidecar("meilink")` 拉起本目录编译出的 Go 二进制
2. sidecar 跑 `serve` 子命令，监听 `127.0.0.1:0`，把端口写入 `<data_dir>/sidecar.port`
3. 前端 JS（[`../src/lib/api.js`](../src/lib/api.js)）通过该端口调用 sidecar 的 REST API
4. 全部隧道 / 配置 / 状态 / frpc 进程管理都在 sidecar 内（`internal/`）

构建链：[`../../../scripts/build/build-desktop.sh`](../../../scripts/build/build-desktop.sh) 第一步 `go build .`（本目录）生成 `../src-tauri/binaries/meilink-<target-triple>`，然后 Tauri 打包。

## 目录结构

```
sidecar/
├── main.go                 # sidecar 编译入口（package main，import cmd/meilink）
├── go.mod / go.sum         # Go module: github.com/meilink/desktop-sidecar
├── cmd/
│   └── meilink/            # sidecar CLI 逻辑（package meilink，由 Tauri 以 serve 子命令拉起）
├── internal/               # sidecar 共享业务
│   ├── config/             # 配置管理 + frpc.toml 生成
│   ├── frpc/               # frpc 进程管理 + 自动下载 + Admin API + 远程探活
│   ├── tunnel/             # 隧道 CRUD
│   ├── web/                # HTTP API + Web UI
│   ├── service/            # 系统服务注册（systemd / Windows Service）
│   └── autostart/          # 开机自启（平台分文件）
└── assets/                 # 静态资源（desktop icon、launcher 脚本等）
```

## 单独编译（一般不用手动）

桌面客户端构建脚本会自动编译 sidecar。如需单独验证可编译：

```bash
go build .   # 本目录根包（main.go → import cmd/meilink），产出 sidecar 二进制
```

交叉编译由 `scripts/build/build-desktop.sh` 处理（按 `GOOS/GOARCH` 决定 target-triple，产物命名 `meilink-<triple>[.exe]`）。

## 数据目录（运行时，非源码）

桌面客户端与 macOS 原生 Swift 客户端共享：
```
~/Library/Application Support/Meilink/   # macOS
~/.meilink/                              # Windows / Linux
```

## REST API

桌面/Docker 客户端前端调用的接口（由本 sidecar 提供）：

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/status` | GET | 获取运行状态 |
| `/api/server-config` | GET/POST | 获取/保存服务器配置 |
| `/api/tunnels` | GET | 获取所有隧道 |
| `/api/tunnels` | POST | 创建隧道 |
| `/api/tunnels` | PUT | 更新隧道 |
| `/api/tunnels?id=<id>` | DELETE | 删除隧道 |

## 相关
- 桌面客户端总览：[`../`](../)（Tauri 壳 + 前端）
- 客户端合集总览：[`../../`](../../)
- 服务端：[`../../../server/`](../../../server/)
- 构建脚本：[`../../../scripts/build/build-desktop.sh`](../../../scripts/build/build-desktop.sh)
