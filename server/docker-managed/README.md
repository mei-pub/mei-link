# Meilink Server Docker

一个镜像同时运行 frps 和 Meilink 服务端管理页。管理页账号、密码只从 Docker 环境变量读取，不写入数据卷。

## 快速开始

```bash
# 构建镜像 + 启动
docker compose up -d

# 查看日志
docker compose logs -f meilink-server
```

首次启动后浏览器打开 `http://服务器IP:17500`（若 17500 绑了 127.0.0.1，先用 SSH 端口转发：`ssh -L 17500:127.0.0.1:17500 user@vps`），使用环境变量中的账号密码登录，并在页面维护 frps 端口和域名目录。

## 网络模式：bridge vs host（重要）

默认 `docker-compose.yml` 用 bridge 网络 + 端口映射。**管理页修改 frps 端口（bindPort / vhostHTTPPort / vhostHTTPSPort）后，bridge 模式下需要重建容器才对外生效**，因为 `ports` 映射是启动时写死的。

| 场景 | 推荐模式 | 文件 |
|---|---|---|
| 端口基本不变，要端口隔离、管理页绑本机 | bridge（默认） | `docker-compose.yml` |
| 经常在管理页改端口、希望改完立即生效 | host 网络 | `docker-compose.host.yml` |

**host 模式的代价**（详见 `docker-compose.host.yml` 顶部注释）：
- 端口隔离消失：管理页 17500 默认对公网开放。**务必用强密码**（`openssl rand -base64 24`），必要时用 ufw/iptables 加 IP 白名单。
- 必须手动放行防火墙 / 云厂商安全组的端口（host 模式不会自动放行）。
- 宿主机 7000/8080/8443/17500 不能被其他进程占用。

启用 host 模式：
```bash
docker compose -f docker-compose.host.yml up -d
```

## 特权端口（80/443）

镜像已对 `/usr/local/bin/frps` 设置 `cap_net_bind_service=+ep`（file capability）。frps 虽以非 root 的 `meilink` 用户运行，但能绑定 < 1024 的特权端口。

- **host 模式**：管理页直接把 HTTP 端口填 `80`、HTTPS 填 `443`，保存即生效，无需 Nginx 或其他前置反代。
- **bridge 模式**：frps 能 bind 容器内的 80，但默认 `docker-compose.yml` 只映射了 `8080:8080`。要对外用 80，需把映射改成 `80:80`（此时宿主机 80 不能被其他进程占用），或改用 host 模式。
- **升级须知**：此修复**之前**构建的旧镜像没有 setcap，必须重建镜像才生效，仅 `restart` / `up -d`（不重建）无效：
  ```bash
  docker compose -f docker-compose.host.yml build && docker compose -f docker-compose.host.yml up -d
  ```
- 若你在 compose 显式写了 `cap_drop: [ALL]`，或 NAS 平台默认 drop 了 `NET_BIND_SERVICE`，file capability 会失效。本仓库两份 compose 均无 `cap_drop`，默认不受影响。

## NAS / Docker 直接运行（不依赖 compose）

```bash
docker run -d --name meilink-server --restart unless-stopped \
  -p 7000:7000 -p 8080:8080 -p 8443:8443 -p 17500:17500 \
  -v /volume1/docker/meilink-server:/data \
  -e MEILINK_ADMIN_USER=admin \
  -e MEILINK_ADMIN_PASSWORD='replace-with-a-strong-password' \
  -e MEILINK_FRPS_TOKEN='replace-with-a-long-frp-token' \
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
