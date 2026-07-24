# Meilink 跨平台客户端

基于 Go 的 frp 内网穿透客户端，提供 Web 管理界面。

## 快速开始

```bash
# 1. 交互式配置服务器信息
./meilink setup

# 2. 启动（前台运行，浏览器访问 Web UI）
./meilink start

# 3. 打开管理界面
#    http://localhost:7400
```

## 常用命令

| 命令 | 说明 |
|------|------|
| `./meilink setup` | 交互式配置服务器地址、端口、Token 等 |
| `./meilink start` | 前台启动（Ctrl+C 停止） |
| `./meilink stop` | 停止正在运行的实例（服务优先，PID 兜底） |
| `./meilink status` | 查看运行状态、隧道数量 |
| `./meilink restart` | 重启 |
| `sudo ./meilink install-service` | 注册为系统服务（开机自启） |
| `sudo ./meilink uninstall-service` | 卸载系统服务 |

## 数据目录

默认 `~/.meilink/`：

```
~/.meilink/
├── server_config.json   # 服务器配置
├── tunnels.json         # 隧道定义
├── settings.json        # 应用设置
├── frpc                 # 自动下载的 frpc 二进制
└── frpc.log             # frpc 运行日志
```

## Web UI 功能

- 实时隧道状态（运行中 / 连接中 / 启动失败 / 检查失败 / 已关闭）
- 隧道增删改查（TCP / UDP / HTTP / HTTPS）
- 启用 / 禁用开关
- 启动 / 停止 / 重启控制
- 事件日志（info / warning / error）
- 设置（轮询间隔、远程探活间隔）

## 作为系统服务运行

```bash
# 注册并开机自启
sudo ./meilink install-service

# 服务管理（systemd）
sudo systemctl status meilink
sudo systemctl restart meilink
sudo journalctl -u meilink -f

# 卸载
sudo ./meilink uninstall-service
```

## 系统要求

无需额外依赖，单二进制运行。首次启动会自动下载对应平台的 frpc 二进制。
