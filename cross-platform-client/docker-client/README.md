# Meilink Docker Client

Browser-managed Meilink client for NAS devices. The container runs one Node.js
process plus `frpc`; it does not use the desktop Go sidecar.

## Start

```bash
export MEILINK_ADMIN_PASSWORD='use-a-long-random-password'
docker compose -f docker-compose.client.yml up -d --build
```

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

