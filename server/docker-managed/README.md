# Meilink Server Docker

一个镜像同时运行 frps 和 Meilink 服务端管理页。管理页账号、密码只从 Docker 环境变量读取，不写入数据卷。

## 快速开始

```bash
# 构建镜像 + 启动
docker compose up -d

# 查看日志
docker compose logs -f meilink-server
```

## 预构建镜像（GitHub Releases）

每次发布都会推送多架构（`linux/amd64` + `linux/arm64`）镜像到 GHCR：

```bash
docker pull ghcr.io/<owner>/meilink-server:latest
docker run -d --name meilink-server --restart unless-stopped \
  --network host \
  -v /volume1/docker/meilink-server:/data \
  -e MEILINK_ADMIN_USER=admin \
  -e MEILINK_ADMIN_PASSWORD='replace-with-a-strong-password' \
  -e MEILINK_FRPS_TOKEN='replace-with-a-long-frp-token' \
  -e MEILINK_DOMAIN_API_TOKEN='replace-with-a-bootstrap-token' \
  ghcr.io/<owner>/meilink-server:latest
```

> 仓库名以小写为准：`ghcr.io/<owner>/meilink-server:<version>|latest`。

首次启动后浏览器打开 `http://服务器IP:17500`（若 17500 绑了 127.0.0.1，先用 SSH 端口转发：`ssh -L 17500:127.0.0.1:17500 user@vps`），使用环境变量中的账号密码登录，并在页面维护 frps 端口和域名目录。

## 网络模式：host

默认使用 host 网络模式：容器直接复用宿主机网络栈，管理页修改 frps 端口后立即生效，无需重建容器。frps 监听的 7000/8080/8443 和管理页 17500 直接暴露在宿主机上。

**安全注意事项**：
- 端口隔离消失：管理页 17500 默认对公网开放。**务必用强密码**（`openssl rand -base64 24`），必要时用 ufw/iptables 加 IP 白名单。
- 必须手动放行防火墙 / 云厂商安全组的端口（host 模式不会自动放行）。
- 宿主机 7000/8080/8443/17500 不能被其他进程占用。

```bash
docker compose up -d          # 构建镜像 + 启动
docker compose build && docker compose up -d   # 改完代码或环境变量后重建
```

## 特权端口（80/443）

镜像已对 `/usr/local/bin/frps` 设置 `cap_net_bind_service=+ep`（file capability）。frps 虽以非 root 的 `meilink` 用户运行，但能绑定 < 1024 的特权端口。

- **host 模式**：管理页直接把 HTTP 端口填 `80`、HTTPS 填 `443`，保存即生效，无需 Nginx 或其他前置反代。
- **升级须知**：此修复**之前**构建的旧镜像没有 setcap，必须重建镜像才生效，仅 `restart` / `up -d`（不重建）无效：
  ```bash
  docker compose build && docker compose up -d
  ```
- 若你在 compose 显式写了 `cap_drop: [ALL]`，或 NAS 平台默认 drop 了 `NET_BIND_SERVICE`，file capability 会失效。默认 compose 无 `cap_drop`，不受影响。

## NAS / Docker 直接运行（不依赖 compose）

```bash
docker run -d --name meilink-server --restart unless-stopped \
  --network host \
  -v /volume1/docker/meilink-server:/data \
  -e MEILINK_ADMIN_USER=admin \
  -e MEILINK_ADMIN_PASSWORD='replace-with-a-strong-password' \
  -e MEILINK_FRPS_TOKEN='replace-with-a-long-frp-token' \
  -e MEILINK_DOMAIN_API_TOKEN='replace-with-a-bootstrap-token' \
  meilink-server:latest
```

## 域名与泛域名

- **主域名**：例如 `tunnel.example.com`。管理页会写入 frps 的 `subDomainHost`；在 DNS 将 `*.tunnel.example.com` 解析到服务器。客户端填写子域名 `photo`，访问地址为 `photo.tunnel.example.com`。
- **额外域名**：例如 `photo.example.com`。在 DNS 解析到服务器；客户端在 HTTP/HTTPS 隧道的“自定义域名”中填写该完整域名。
- **泛域名**：例如 `*.apps.example.com`。在 DNS 添加同名泛解析记录；客户端可将该泛域名作为自定义域名，用于将该泛域名下的请求路由至同一 HTTP/HTTPS 隧道。

frp 只支持一个 `subDomainHost`。因此，不能把 `*.tunnel.example.com` 再作为自定义泛域名添加；管理页会拒绝这种与主域名重叠的配置。额外域名和泛域名需要使用不同的域名空间，例如主域名为 `tunnel.example.com` 时，可用 `*.apps.example.com`。

## 环境变量

| 变量 | 必填 | 用途 |
|---|---:|---|
| `MEILINK_ADMIN_USER` | 是 | 管理页登录用户名 |
| `MEILINK_ADMIN_PASSWORD` | 是 | 管理页登录密码 |
| `MEILINK_FRPS_TOKEN` | 建议 | 首次启动时的 frps Token；也可在管理页面首次保存 |
| `MEILINK_WEB_PORT` | 否 | 管理页端口，默认 `17500` |
| `MEILINK_FRPS_BIND_PORT` | 否 | 客户端连接端口，默认 `7000` |
| `MEILINK_FRPS_HTTP_PORT` | 否 | HTTP vhost 端口，默认 `8080` |
| `MEILINK_FRPS_HTTPS_PORT` | 否 | HTTPS vhost 端口，默认 `8443` |
| `MEILINK_PRIMARY_DOMAIN` | 否 | 首次启动时的主域名 |
| `MEILINK_DOMAIN_API_TOKEN` | **推荐** | 配置后启用 `GET /api/bootstrap` + `GET /api/domains`。客户端 SetupView 只需填「管理页地址 + 这个 Token」即可自动拉取 frps 地址/端口/Token/子域名基域。客户端用 Bearer token 访问，独立于管理页登录账号 |
| `MEILINK_DASHBOARD_USER` | 否 | frps 内置 dashboard 用户名，默认 `admin`（仅容器内 127.0.0.1，外部访问不到；管理页「隧道状态」Tab 用它拉代理列表）|
| `MEILINK_DASHBOARD_PASSWORD` | 否 | frps 内置 dashboard 密码，默认 `admin` |
| `MEILINK_DASHBOARD_PORT` | 否 | frps dashboard 端口，默认 `7500` |
