# Meilink

macOS 内网穿透管理工具，基于 [frp](https://github.com/fatedier/frp) 构建。

## 功能特性

- **Menu Bar 应用**：常驻菜单栏，不占 Dock 空间
- **全协议支持**：HTTP、HTTPS、TCP、UDP 隧道
- **子域名映射**：将子域名映射到本地端口
- **动态管理**：通过 frpc Admin API 动态增删隧道，无需重启
- **开机自启动**：支持 macOS Login Items
- **实时状态**：监控隧道连接状态
- **安全存储**：Token 存储在 macOS Keychain

## 系统要求

- macOS 13.0 或更高版本
- Xcode 15.0 或更高版本（用于编译）

## 快速开始

### 1. VPS 部署 frps

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

### 2. DNS 配置

在域名管理处添加泛解析记录：

```
*.tunnel.yourdomain.com  →  A  →  VPS_IP_ADDRESS
```

### 3. 编译应用

```bash
# 使用 xcodegen 生成 Xcode 项目
brew install xcodegen
xcodegen generate

# 或直接使用 Swift Package Manager
swift build
```

### 4. 首次配置

1. 启动 Meilink
2. 在配置向导中输入 VPS 地址、端口、Token
3. 输入子域名基域（如 `tunnel.yourdomain.com`）
4. 点击"测试连接"验证配置
5. 保存配置

### 5. 添加隧道

- 点击菜单栏图标
- 选择"添加隧道"
- 填写隧道名称、类型、本地端口、子域名
- 保存后隧道自动生效

## 项目结构

```
Meilink/
├── App/
│   └── MeilinkApp.swift          # 应用入口
├── UI/
│   ├── MenuBar/                  # 菜单栏视图
│   ├── Setup/                    # 配置向导
│   ├── Main/                     # 主窗口
│   └── Settings/                 # 设置页面
├── Core/
│   ├── TunnelManager.swift       # 隧道管理核心
│   ├── FrpcProcess.swift         # frpc 进程管理
│   ├── FrpcAdminAPI.swift        # Admin API 客户端
│   └── ConfigGenerator.swift     # TOML 配置生成
├── Models/                       # 数据模型
├── Storage/                      # 持久化存储
└── Utils/                        # 工具类
```

## frpc 二进制

应用会自动从 GitHub Releases 下载 frpc 二进制。你也可以手动编译：

```bash
# 编译 universal binary
Scripts/build-frpc.sh
```

## 安全说明

- 认证 Token 存储在 macOS Keychain
- frpc Admin API 仅监听 127.0.0.1
- TLS 默认启用
- 配置文件权限设为 0600

## 许可证

MIT License
