# Docker Web Client Design

## Goal

Provide a NAS-friendly Meilink client that is managed in a browser, uses only
TypeScript/Node.js besides `frpc`, and follows the macOS native client as the
behavioral and visual source of truth.

## Scope

- A single Node.js process serves the Web UI and API, owns `frpc`, and manages
  configuration, state polling, reachability checks, events, and recovery.
- `frpc` is the only bundled external executable.
- The Web UI reuses the cross-platform desktop CSS, icon assets, labels, page
  hierarchy, tunnel list, settings and log interaction patterns.
- Docker deployment persists all mutable data in `/data` and exposes one
  configurable management port.

## Runtime

```text
Browser -> Node HTTP server -> TypeScript tunnel manager -> frpc
                   |                    |
                   |                    +-> frpc Admin API on 127.0.0.1
                   +-> embedded static Web assets
```

The Node process binds its management server to `0.0.0.0` in Docker. `frpc`
Admin API remains fixed to `127.0.0.1` and is never published by Docker.

## Data and frpc contract

- Persist `config.json`, `tunnels.json`, `settings.json`, `events.json`,
  `frpc.toml`, and `store.json` under `/data`.
- Use camelCase JSON compatible with the macOS models where applicable.
- Generate frpc v0.70.0 TOML matching the native ConfigGenerator: token auth,
  TLS option, pool count 5, tcp mux, local Admin API, and Store API proxies.
- TOML values must use escaped basic strings so Linux paths and future special
  characters remain valid.
- Tunnel phases and labels remain: new, wait start, start error, running,
  check failed, closed. Recovery is after 3 failures with a 20-second cooldown.

## Authentication

- First start requires `MEILINK_ADMIN_PASSWORD`; optional
  `MEILINK_ADMIN_USER` defaults to `admin`.
- Persist only a bcrypt password hash in `/data/auth.json`.
- Login creates an HttpOnly, Secure-when-HTTPS, SameSite=Lax cookie session.
- All API routes except login/health require a session and reject cross-origin
  browser calls; no permissive CORS in Docker mode.

## Image and deployment

- Multi-stage Dockerfile builds the TypeScript application and copies the
  official, checksum-verified platform `frpc` binary into the final Node image.
- `docker-compose.client.yml` maps `${MEILINK_WEB_PORT:-17420}:17420` and
  mounts `./data:/data`.
- Container health check calls the local authenticated-independent `/healthz`.
- Documentation covers NAS volume permissions, reverse-proxy TLS, and the
  requirement to keep the management port private or protected by TLS.

## Verification

- Unit tests cover TOML escaping, process start/stop, recovery thresholds and
  authentication session checks.
- Browser tests cover first-run login, configuration, tunnel CRUD, controls and
  log rendering.
- Docker smoke test starts the container with a mounted temporary data volume,
  logs in, saves configuration, and verifies no frpc Admin port is published.
