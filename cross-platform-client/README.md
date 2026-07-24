# Meilink Cross-Platform Client

基于 Go 的跨平台 frp 内网穿透客户端，支持 **Windows、Linux、macOS**。

> 注意：本项目与现有的 macOS Swift AppKit 客户端（`Meilink/` 目录）独立。Swift 版本是特色版本，提供原生菜单栏体验；Go 版本是跨平台补充方案。

## 功能特性

- **跨平台**：Windows / Linux / macOS 统一客户端
- **Web 管理界面**：内嵌 Web UI，浏览器即可管理隧道
- **自动下载 frpc**：首次运行自动获取对应平台的 frpc 二进制
- **隧道 CRUD**：通过 REST API 动态增删改查隧道
- **系统服务注册**：支持 Windows Service / systemd 安装
- **与现有 macOS 客户端共用 frps.toml 配置格式**

## 快速开始

### 编译

```bash
# 当前平台
go build -o meilink ./cmd/meilink

# 交叉编译
GOOS=windows GOARCH=amd64 go build -o meilink-windows-amd64.exe ./cmd/meilink
GOOS=linux   GOARCH=arm64 go build -o meilink-linux-arm64    ./cmd/meilink
GOOS=darwin  GOARCH=arm64 go build -o meilink-darwin-arm64   ./cmd/meilink
```

### 使用

```bash
# 交互式配置
./meilink setup

# 启动客户端
./meilink start --listen :7400

# 停止客户端
./meilink stop

# 查看状态
./meilink status
```

启动后访问 http://localhost:7400 打开 Web 管理界面。

## 项目结构

```
cross-platform-client/
├── cmd/
│   ├── meilink/            # 主程序入口
│   └── meilink-setup/      # 引导式部署工具
├── internal/
│   ├── config/             # 配置管理 + frpc.toml 生成
│   ├── frpc/               # frpc 进程管理 + 自动下载 + Admin API
│   ├── tunnel/             # 隧道 CRUD 管理
│   ├── web/                # Web UI 服务 + HTML 模板
│   └── service/            # 系统服务注册（systemd / Windows Service）
├── assets/                 # 静态资源
├── build.sh                # 构建脚本
├── go.mod
└── README.md
```

## 数据目录

macOS 桌面版与原生 Swift 客户端共享数据目录：

```
~/Library/Application Support/Meilink/
```

Windows / Linux 默认存储在 `~/.meilink/`：

```
~/.meilink/
├── config.json          # 服务器配置
├── tunnels.json         # 隧道定义
├── settings.json        # 应用设置
├── frpc.toml            # 生成的 frpc 配置
├── store.json           # frpc 代理存储
└── frpc.log             # frpc 日志
```

## API 参考

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/status` | GET | 获取运行状态 |
| `/api/server-config` | GET/POST | 获取/保存服务器配置 |
| `/api/tunnels` | GET | 获取所有隧道 |
| `/api/tunnels` | POST | 创建隧道 |
| `/api/tunnels` | PUT | 更新隧道 |
| `/api/tunnels?id=<id>` | DELETE | 删除隧道 |
