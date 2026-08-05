# Meilink 服务端

本目录汇集 Meilink 的**服务端（frps）**全部实现。frps 跑在公网 VPS 上，负责接收客户端连接并把流量转发到内网。

> ⚠️ **先搞清「服务端」与「客户端」**
> - **服务端（本目录）** = 部署在公网 VPS 上的 frps，是流量中转枢纽。
> - **客户端** = 跑在内网机器上的 frpc，把本地服务暴露出去。客户端实现在仓库别处：macOS 原生客户端（`../client/macos-native/`）、跨平台桌面客户端（`../client/desktop/`）、Docker 客户端（`../client/docker/`）。
>
> **「Docker 服务端」和「Docker 客户端」是两回事**：本目录的 `docker-compose/` 和 `docker-managed/` 是服务端（跑 frps）；`client/docker/` 是客户端（跑 frpc），不要混淆。

---

## 方案总览

| 方案 | 目录 | 形态 | 管理界面 | 适合 |
|---|---|---|---|---|
| ① 裸 frps（Docker） | [`docker-compose/`](docker-compose/) | 第三方镜像 `snowdreamtech/frps` + 手写 `frps.toml` | 无 | 只要基础穿透、会写 TOML |
| ② frps + 管理页（Docker） | [`docker-managed/`](docker-managed/) | 仓库自构建一体镜像（frps + Node Web 管理页） | Web 管理页 `:17500` | 要图形化管理、多域名/多隧道、新手友好 |
| ③ 裸机 setup 工具 | [`setup/`](setup/) | Go 程序 `meilink-setup`，systemd 多 profile | 交互式 CLI 菜单 | 不用 Docker、要多域名隔离的 Linux 服务器 |
| ④ 裸机 Shell 一键脚本 | [`bare-metal/`](bare-metal/) | `deploy-frps.sh`，systemd 单实例 | 无 | 最快跑起来、单域名 |

**端口约定**（所有方案一致）：`7000` 客户端连接、`8080` HTTP vhost、`8443` HTTPS vhost。方案 ② 额外有 `17500` 管理页。

**frp 版本基线**：v0.70.0（与全部客户端对齐，详见 [`../AGENTS.md`](../AGENTS.md) §7.1）。

---

## 选哪个？

- **只想要最简单、一个域名几条隧道** → 方案 ①（`docker compose up -d`）或方案 ④（一行 `deploy-frps.sh`）
- **想要 Web 管理页、多域名多隧道、不想碰 TOML** → 方案 ②（推荐）
- **服务器不装 Docker、要多域名各自隔离的 systemd 服务** → 方案 ③（`meilink-setup`）
- **想要标准 80/443 访问（不带端口）** → 任选一套 + Nginx 反代（见 Docker 手册 §4）

---

## 文档

- **Docker 部署完整手册**（方案 ① + ②，含 Nginx 反代、TLS、备份、运维排障）：[`../docs/guides/deploy-docker.md`](../docs/guides/deploy-docker.md)
- **构建发布 SDD**（含服务端部署章节）：[`../docs/sdd/07-build-release.md`](../docs/sdd/07-build-release.md) §6

---

## 各方案快速开始

### ① docker-compose（裸 frps）
```bash
cd docker-compose
# 编辑 frps.toml：必改 subDomainHost 和 auth.token 两处占位符
docker compose up -d
```
详见 [`docker-compose/`](docker-compose/) 与 [Docker 手册 §2](../docs/guides/deploy-docker.md#2-方案-a裸-frps-部署根目录-docker-composeyml)。

### ② docker-managed（frps + Web 管理页，推荐）
```bash
cd docker-managed
docker build -t meilink-server:latest .
docker run -d --name meilink-server --restart unless-stopped \
  -p 7000:7000 -p 8080:8080 -p 8443:8443 -p 127.0.0.1:17500:17500 \
  -v /opt/meilink-server/data:/data \
  -e MEILINK_ADMIN_USER=admin \
  -e MEILINK_ADMIN_PASSWORD='强密码' \
  -e MEILINK_FRPS_TOKEN='长随机串' \
  meilink-server:latest
# 浏览器访问 http://VPS_IP:17500（或 SSH 端口转发后访问 localhost:17500）
```
详见 [`docker-managed/README.md`](docker-managed/README.md) 与 [Docker 手册 §3](../docs/guides/deploy-docker.md#3-方案-b一体镜像部署server-docker推荐)。

### ③ setup（裸机多 profile）
从 release 取预编译二进制：
```bash
tar xzf release/meilink-setup-1.1.0-linux-amd64.tar.gz
cd meilink-setup-1.1.0-linux-amd64
sudo ./meilink-setup            # 交互式菜单
sudo ./meilink-setup setup      # 首次初始化（装 frps + 创建第一个 profile）
sudo ./meilink-setup add        # 添加新 profile（域名+token）
sudo ./meilink-setup list
sudo ./meilink-setup start|stop|restart|status [name]
sudo ./meilink-setup upgrade    # 升级 frps 并重启所有实例
```
或从源码构建：`cd setup && go build -o meilink-setup .`。每个 profile 自动分配端口（bindPort 从 7000 递增），独立的 `frps-<name>.service`，开机自启。

### ④ bare-metal（裸机单实例 Shell）
```bash
cd bare-metal
# 先编辑同目录或在仓库根参考 frps.toml 写好配置
sudo bash deploy-frps.sh           # 安装 frps + 启动 systemd 服务
sudo bash deploy-frps.sh status
sudo bash deploy-frps.sh restart
```
脚本会校验 `frps.toml` 的占位符（`subDomainHost` 不能是 `tunnel.yourdomain.com`，`auth.token` 不能是 `your-secret-token-here`）。

---

## 目录结构
```
server/
├── README.md            # 本文件
├── docker-compose/      # 方案 ①：裸 frps（第三方镜像 + 手写 toml）
│   ├── docker-compose.yml
│   └── frps.toml
├── docker-managed/      # 方案 ②：frps + Web 管理页一体镜像（自构建）
│   ├── Dockerfile
│   ├── package.json
│   ├── README.md
│   ├── src/
│   ├── web/
│   └── test/
├── setup/               # 方案 ③：Go 多 profile 部署工具（meilink-setup）
│   ├── main.go
│   ├── go.mod
│   └── go.sum
└── bare-metal/          # 方案 ④：Shell 单实例一键部署
    └── deploy-frps.sh
```
