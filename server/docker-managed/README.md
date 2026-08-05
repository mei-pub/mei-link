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
