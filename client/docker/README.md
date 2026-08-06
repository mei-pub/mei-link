# Meilink Docker Client

Browser-managed Meilink client for NAS devices. The container runs one Node.js
process plus `frpc`; it does not use the desktop Go sidecar.

## Start

```bash
export MEILINK_ADMIN_PASSWORD='use-a-long-random-password'
docker compose -f docker-compose.client.yml up -d --build
```

## Prebuilt image (GitHub Releases)

Every release pushes a multi-arch (`linux/amd64` + `linux/arm64`) image to GHCR:

```bash
export MEILINK_ADMIN_PASSWORD='use-a-long-random-password'
docker pull ghcr.io/<owner>/meilink-client:latest
docker compose -f docker-compose.client.yml up -d
# 或直接 run（--no-build 且 compose 里 image 指向 ghcr 标签时）：
docker run -d --name meilink-client \
  -p 17420:17420 \
  -e MEILINK_ADMIN_PASSWORD="$MEILINK_ADMIN_PASSWORD" \
  -v /path/on/nas/meilink-data:/data \
  --restart unless-stopped \
  ghcr.io/<owner>/meilink-client:latest
```

> 仓库名以小写为准：`ghcr.io/<owner>/meilink-client:<version>|latest`。

### 国内加速

- **阿里云 ACR**（若 CI 配置了 `ALIYUN_ACR_USERNAME` / `ALIYUN_ACR_PASSWORD` secrets 与 `ACR_REGISTRY` / `ACR_NAMESPACE` variables）：发布时会同步推送 `$ACR_REGISTRY/$ACR_NAMESPACE/meilink-client:<version>`，国内直连最快。
- **GHCR 加速站**（镜像需 public）：把 `ghcr.io` 换成加速站前缀，如 `ghcr.nju.edu.cn/<owner>/meilink-client:<version>`。首次拉取加速站会回源 ghcr.io（较慢），之后缓存命中就快；发布时 CI 也会 best-effort 预热。
- 离线导入：Release 附带的 `meilink-docker-client-<ver>.oci.tar`，`docker load -i` 免网络。

> 阿里云 `*.mirror.aliyuncs.com` 镜像加速器只对 Docker Hub 生效，对 ghcr.io 无效。

## Offline image deployment

Use the release OCI archive when the NAS cannot build images itself. It contains
both `linux/amd64` and `linux/arm64` variants:

```bash
docker load -i meilink-docker-client-1.1.0.oci.tar
export MEILINK_ADMIN_PASSWORD='use-a-long-random-password'
docker compose -f docker-compose.client.yml up -d --no-build
```

### NAS UI / docker run (without Compose)

Import `meilink-docker-client-1.1.0-amd64.tar` for Intel/AMD NAS devices, or
`meilink-docker-client-1.1.0-arm64.tar` for ARM64 NAS devices. In the NAS
container UI, create a container from the imported image and set:

| Setting | Value |
|---|---|
| Container port | `17420/TCP` |
| Host port | `17420` (or any unused host port) |
| Environment | `MEILINK_ADMIN_PASSWORD=<strong password>` |
| Volume | A persistent host folder mounted at `/data` |
| Restart policy | `unless-stopped` |

Equivalent command-line deployment:

```bash
docker run -d --name meilink-client \
  -p 17420:17420 \
  -e MEILINK_ADMIN_PASSWORD='use-a-long-random-password' \
  -v /path/on/nas/meilink-data:/data \
  --restart unless-stopped \
  meilink-client:latest
```

Open `http://NAS-IP:17420`, log in as `admin`, then save the frps connection
settings before starting tunnels. Persistent configuration is in `./data`.

## Security

Do not publish the management port directly to the Internet. Put it behind a
TLS reverse proxy or restrict it to the trusted LAN/VPN. The frpc Admin API is
bound only to the container loopback address and is not a published port.

## Environment

| Variable | Default | Meaning |
|---|---:|---|
| `MEILINK_ADMIN_USER` | `admin` | Initial login account |
| `MEILINK_ADMIN_PASSWORD` | required | Initial login password |
| `MEILINK_WEB_PORT` | `17420` | Browser management port |
| `MEILINK_DATA_DIR` | `/data` | Persistent data directory |

