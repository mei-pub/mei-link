# Meilink Docker Client

Browser-managed Meilink client for NAS devices. The container runs one Node.js
process plus `frpc`; it does not use the desktop Go sidecar.

## Start

```bash
export MEILINK_ADMIN_PASSWORD='use-a-long-random-password'
docker compose -f docker-compose.client.yml up -d --build
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

