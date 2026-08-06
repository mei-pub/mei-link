# Meilink 服务端 Docker 部署操作手册

> 本手册覆盖仓库现有的**两套** Docker 服务端部署方案，从选型、前置准备、配置、启动到运维排障一站式讲清。
>
> - 方案 A：**裸 frps**（`server/docker-compose/`，第三方镜像）
> - 方案 B：**一体镜像**（`server/docker-managed/`，frps + Web 管理页，仓库自构建）
>
> 仓库另有裸机 systemd 方案（`deploy-frps.sh` / `meilink-setup`），见 [../README.md](../README.md) 与 [../sdd/07-build-release.md](../sdd/07-build-release.md) §6.1 / §6.2，本手册不重复。

---

## 0. TL;DR — 我该选哪套？

| 维度 | 方案 A：裸 frps | 方案 B：一体镜像（推荐） |
|---|---|---|
| **适用场景** | 只要基础穿透、会写 TOML、不要管理页 | 要图形化管理、多域名/多隧道、新手友好 |
| **配置方式** | 手动编辑 `frps.toml` 挂载进容器 | 浏览器管理页 `:17500` 动态配置 |
| **镜像来源** | 第三方 `snowdreamtech/frps:latest`（版本不固定） | 本仓库自构建（frps v0.70.0 + Node 22 管理页） |
| **端口** | 7000 / 8080 / 8443 | 7000 / 8080 / 8443 / **17500（管理页）** |
| **改配置** | 改 toml → 重启容器 | 管理页操作，免重启 |
| **管理界面** | 无（除非自己开 dashboard） | 有（账号密码登录） |
| **上手成本** | 最低，一条 `docker compose up -d` | 需 `docker build` 一次镜像 |
| **frp 版本** | 由镜像决定（不固定） | 固定 v0.70.0（与客户端基线一致） |
| **数据持久化** | 仅配置文件挂载 | `/data` 卷（frps 配置 + 域名目录） |

**10 秒决策**：
- 我只有一个域名、几条隧道，会改配置文件 → **方案 A**
- 我要给团队/多机器用，想要 Web 管理页，不想碰 TOML → **方案 B**
- 我想要标准 80/443 访问（不带端口）→ **任选一套 + Nginx 反代**（见 §4）

---

## 1. 通用前置准备（两套共用）

### 1.1 服务器
- 一台公网 Linux VPS（amd64 或 arm64）
- 已安装 **Docker Engine** 与 **Docker Compose v2**（`docker compose` 子命令，非旧版 `docker-compose`）
  - 验证：`docker --version` ≥ 20.10，`docker compose version` ≥ 2.0

### 1.2 域名与 DNS
- 拥有一个域名及其 DNS 管理权限
- 添加**泛解析记录**：

  ```
  *.tunnel.yourdomain.com   A   <VPS 公网 IP>
  ```

  > `tunnel.yourdomain.com` 是示例，替换成你自己的子域。客户端填子域名 `photo` 时，访问地址就是 `photo.tunnel.yourdomain.com`。

### 1.3 防火墙 / 安全组
开放以下 TCP 端口（云厂商安全组 + 系统 firewall 都要放行）：

| 端口 | 用途 | 方案 A | 方案 B |
|---|---|:---:|:---:|
| 7000 | frps 客户端连接 | ✅ | ✅ |
| 8080 | HTTP vhost（子域名访问） | ✅ | ✅ |
| 8443 | HTTPS vhost（子域名访问） | ✅ | ✅ |
| 17500 | Web 管理页 | — | ✅（**建议不直接对公网开放**，见 §3.9） |

> ⚠️ **7000 是 frps 的客户端握手端口，必须对公网开放**，否则客户端连不上。8080/8443 也需要对公网开放才能直接用 `子域名:8080` 访问；若走 Nginx 反代到 80/443，则 8080/8443 可只绑 `127.0.0.1`。

### 1.4 认证 Token
自己生成一个高强度随机串作为 `auth.token`（客户端和服务端必须一致）。例如：

```bash
openssl rand -hex 32
```

---

## 2. 方案 A：裸 frps 部署（`server/docker-compose/`）

### 2.1 工作原理
用第三方预构建镜像 `snowdreamtech/frps:latest` 直接跑 frps，`server/docker-compose/` 下的两个文件配合使用：

```
server/docker-compose/
├── docker-compose.yml   # 编排：镜像、端口、卷挂载
└── frps.toml            # frps 配置（挂载进容器 /etc/frps/frps.toml）
```
> 两个文件都从仓库根目录迁入了 `server/docker-compose/`。下文命令默认在该目录内执行。

### 2.2 配置步骤

**① 编辑 `frps.toml`，必改两处占位符**：

```toml
bindPort = 7000
vhostHTTPPort = 8080
vhostHTTPSPort = 8443

subDomainHost = "tunnel.yourdomain.com"   # ← 改成你的真实域名
auth.method = "token"
auth.token = "your-secret-token-here"      # ← 改成你的高强度 Token
```

> 📌 **校验规则**（与 `deploy-frps.sh` 的 `validate_config_values` 一致）：
> - `subDomainHost` 不能保留默认值 `tunnel.yourdomain.com`
> - `auth.token` 不能保留默认值 `your-secret-token-here`
> - `bindPort` / `vhostHTTPPort` / `vhostHTTPSPort` 三个必须存在
>
> 不改占位符，虽然 Docker 直接起容器不会拦你，但客户端会连不上、或被扫描爆破。务必改。

**② （可选）开启 frps 原生 Dashboard**

参照 `client/macos-native/Resources/frps.toml.example`，在 `frps.toml` 末尾追加：

```toml
webServer.addr = "127.0.0.1"   # ⚠️ 必须 127.0.0.1，不能写 0.0.0.0（Admin API 不能对外）
webServer.port = 7500
webServer.user = "admin"
webServer.password = "改成强密码"
```

> ⚠️ **安全红线**：`webServer.addr` 一定写 `127.0.0.1`。frps Dashboard 是管理面，对公网开放等于把隧道管理权交出去。如需远程访问，走 SSH 隧道或 Nginx 反代加鉴权（见 §4.2）。
>
> 如开启 Dashboard，记得在 `docker-compose.yml` 的 `ports` 里加一条 `"127.0.0.1:7500:7500"`（只绑本机）。

### 2.3 启动 / 停止 / 更新

```bash
# 启动（后台）
docker compose up -d

# 查看状态
docker compose ps

# 实时日志
docker compose logs -f frps

# 停止并删除容器（配置文件和镜像保留）
docker compose down

# 更新镜像到最新版
docker compose pull
docker compose up -d
```

### 2.4 版本固定建议
默认 `image: snowdreamtech/frps:latest` 会跟随第三方最新 tag，**版本不可控、可能与客户端 frpc 版本不匹配**。

【建议】固定到具体版本，与客户端基线（frp v0.70.0）对齐：

```yaml
image: snowdreamtech/frps:0.70.0   # 而非 :latest
```

> 具体可用的 tag 列表见 [Docker Hub - snowdreamtech/frps](https://hub.docker.com/r/snowdreamtech/frps/tags)。若该镜像未提供 `0.70.0` tag，建议改用方案 B（仓库自构建，版本与客户端严格一致）。

### 2.5 客户端连接信息（部署完成后告诉客户端）
- **服务器地址**：`<VPS 公网 IP>` 或你的域名
- **bindPort**：`7000`
- **Token**：你在 `frps.toml` 里设的 `auth.token`
- **子域名基域**：`tunnel.yourdomain.com`（客户端填的 `subdomain` 会拼成 `<subdomain>.tunnel.yourdomain.com`）
- **HTTP 访问**：`http://<subdomain>.tunnel.yourdomain.com:8080`
- **HTTPS 访问**：`https://<subdomain>.tunnel.yourdomain.com:8443`

### 2.6 常见问题
| 现象 | 排查 |
|---|---|
| 客户端连不上 | 检查 7000 端口是否在安全组放行；`telnet VPS_IP 7000` |
| 子域名访问 404 | `subDomainHost` 未改占位符；DNS 泛解析未生效（`dig photo.tunnel.yourdomain.com`） |
| 容器启动即退出 | `docker compose logs frps` 看报错，多半是 `frps.toml` 语法错或端口被占用 |
| 端口被占用 | `ss -tlnp \| grep -E '7000\|8080\|8443'` 找占用的宿主进程，或改 compose 的端口映射 |
| Dashboard 打不开 | `webServer.addr` 写成了 `0.0.0.0` 但未在 `ports` 映射；或写错地址 |

---

## 3. 方案 B：一体镜像部署（`server/docker-managed/`，推荐）

### 3.1 工作原理
一个镜像内同时运行 **frps** 和 **Node.js 管理页**：

- frps 二进制在构建时从 GitHub release 下载（v0.70.0，带 SHA256 校验），放进 `/usr/local/bin/frps`
- 管理页是 Node 22 直接跑 TypeScript（`src/server.ts`），默认端口 `17500`
- frps 配置由管理页动态生成、写入 `/data` 卷，**无需手写 toml**
- **管理页账号密码只从环境变量读取，不写入数据卷**——改密码 = 改环境变量 + 重启容器

源码位置：`server/docker-managed/`

### 3.2 构建镜像

```bash
cd server/docker-managed
docker build -t meilink-server:latest .
```

> 每次 GitHub Release 也会推送多架构镜像到 GHCR（`ghcr.io/<owner>/meilink-server:<version>|latest`，`linux/amd64` + `linux/arm64`），并附带 OCI 离线包 `meilink-server-<ver>.oci.tar`（`docker load -i` 导入，适合 NAS 离线部署）。用预构建镜像可跳过本地 `docker build`。
>
> **国内加速**：可选任一方式：
> - 阿里云 ACR（CI 配了 ACR secrets 时）：`docker pull registry.cn-hangzhou.aliyuncs.com/meilink/meilink-server:<version>`（国内直连最快）
> - 加速站（镜像需在 GHCR 设为 public）：`docker pull ghcr.nju.edu.cn/<owner>/meilink-server:<version>`（首次回源慢，CI 发布时已 best-effort 预热）
> - 离线导入：`docker load -i meilink-server-<ver>.oci.tar` 免网络
>
> 阿里云 `*.mirror.aliyuncs.com` 镜像加速器只对 Docker Hub 生效，对 ghcr.io 无加速效果。

- 支持 `amd64` 与 `arm64`（构建时按宿主架构自动选 frps 二进制，其他架构会报 `Unsupported architecture` 退出）
- 构建过程会校验 frps 压缩包的 SHA256，校验失败自动中止
- 无需 `npm install`（零运行时依赖，靠 Node 22 原生跑 TS）

> 若需交叉编译到别的架构，用 `docker buildx`：
> ```bash
> docker buildx build --platform linux/arm64 -t meilink-server:arm64 . --load
> ```

### 3.3 部署 — 三种方式任选

#### (a) `docker run` 一条命令

```bash
docker run -d \
  --name meilink-server \
  --restart unless-stopped \
  -p 7000:7000 \
  -p 8080:8080 \
  -p 8443:8443 \
  -p 127.0.0.1:17500:17500 \
  -v /opt/meilink-server/data:/data \
  -e MEILINK_ADMIN_USER=admin \
  -e MEILINK_ADMIN_PASSWORD='replace-with-a-strong-password' \
  -e MEILINK_FRPS_TOKEN='replace-with-a-long-frp-token' \
  -e MEILINK_PRIMARY_DOMAIN='tunnel.yourdomain.com' \
  meilink-server:latest
```

> 上面把 `17500` 绑到 `127.0.0.1`（只本机访问），需要远程管理时走 Nginx 反代（§4.2）。如果你确定要临时对公网开放（**不推荐**），把 `127.0.0.1:17500:17500` 改成 `17500:17500`。

#### (b) Docker Compose（推荐，易维护）

`server/docker-managed/` 目录自带 `docker-compose.yml`，直接使用：

```bash
cd server/docker-managed
# 编辑 docker-compose.yml，修改环境变量
docker compose up -d
```
      MEILINK_PRIMARY_DOMAIN: "tunnel.yourdomain.com"
      # 以下为可选项，不填用默认值
      # MEILINK_WEB_PORT: 17500
      # MEILINK_FRPS_BIND_PORT: 7000
      # MEILINK_FRPS_HTTP_PORT: 8080
      # MEILINK_FRPS_HTTPS_PORT: 8443
    volumes:
      - ./data:/data               # 持久化 frps 配置 + 域名目录
```

启动：

```bash
docker compose up -d
docker compose logs -f meilink-server
```

#### (c) NAS 图形化部署（Synology Container Manager 等）
1. 在 Container Manager → 映像 → 新增，从本机 Docker 构建（需先把 `server/docker-managed/` 目录上传到 NAS）或导入已构建好的镜像
2. 容器创建时配置：
   - **端口**：本地 7000/8080/8443 → 容器同号；本地 `127.0.0.1:17500`（或仅内网 IP）→ 容器 17500
   - **存储空间**：`/volume1/docker/meilink-server` → `/data`（卷挂载）
   - **环境变量**：填 `MEILINK_ADMIN_USER` / `MEILINK_ADMIN_PASSWORD` / `MEILINK_FRPS_TOKEN` / `MEILINK_PRIMARY_DOMAIN`
   - **重启策略**：除非手动停止

### 3.4 环境变量完整说明

| 变量 | 必填 | 默认 | 说明 |
|---|:---:|---|---|
| `MEILINK_ADMIN_USER` | ✅ | — | 管理页登录用户名 |
| `MEILINK_ADMIN_PASSWORD` | ✅ | — | 管理页登录密码（强密码） |
| `MEILINK_FRPS_TOKEN` | 建议 | — | 首次启动写入的 frps Token；也可登录管理页后改 |
| `MEILINK_PRIMARY_DOMAIN` | 否 | — | 首次启动的主域名（即 frps `subDomainHost`） |
| `MEILINK_WEB_PORT` | 否 | `17500` | 管理页端口（一般不用改，改了要同步改端口映射） |
| `MEILINK_FRPS_BIND_PORT` | 否 | `7000` | 客户端连接端口 |
| `MEILINK_FRPS_HTTP_PORT` | 否 | `8080` | HTTP vhost 端口 |
| `MEILINK_FRPS_HTTPS_PORT` | 否 | `8443` | HTTPS vhost 端口 |

> 📌 `MEILINK_ADMIN_USER` / `MEILINK_ADMIN_PASSWORD` 只在环境变量里，**不会落盘到 `/data`**。改密码 = 改 compose 里的 `environment` + `docker compose up -d` 重建容器。

### 3.5 首次配置流程
1. 浏览器访问 `http://<VPS_IP>:17500`（若按 §3.3 绑了 `127.0.0.1`，先 SSH 端口转发：`ssh -L 17500:127.0.0.1:17500 user@vps`，再访问 `http://localhost:17500`）
2. 用环境变量里的 `MEILINK_ADMIN_USER` / `MEILINK_ADMIN_PASSWORD` 登录
3. 在页面维护：
   - frps 端口（确认默认 7000/8080/8443，或按需改）
   - 主域名（`subDomainHost`，如 `tunnel.yourdomain.com`）
   - Token（`MEILINK_FRPS_TOKEN`，客户端要填同一个）
   - 域名目录（额外域名 / 泛域名，见 §3.6）
4. 保存后管理页自动生成 `frps.toml` 写入 `/data`，并 (re)start frps 子进程——**无需重启容器**

### 3.6 域名模型与规则（重要）
frps 只支持**一个** `subDomainHost`（主域名）。管理页支持三类域名：

| 类型 | 示例 | DNS 配置 | 客户端填法 |
|---|---|---|---|
| **主域名**（subDomainHost） | `tunnel.example.com` | `*.tunnel.example.com → A → VPS_IP` | 子域名 `photo` → 访问 `photo.tunnel.example.com` |
| **额外域名** | `photo.example.com` | `photo.example.com → A → VPS_IP` | HTTP/HTTPS 隧道「自定义域名」填完整域名 |
| **泛域名** | `*.apps.example.com` | `*.apps.example.com → A → VPS_IP` | 「自定义域名」填该泛域名，整个泛域路由到同一隧道 |

> ⚠️ **不能把主域名的泛域（如 `*.tunnel.example.com`）再当作自定义泛域名添加**——会和主域名重叠，管理页会拒绝。额外域名/泛域名必须用**不同的域名空间**（如主域名用 `tunnel.example.com`，泛域名用 `*.apps.example.com`）。

### 3.7 健康检查
镜像内置健康检查：

```
HEALTHCHECK CMD node -e "fetch('http://127.0.0.1:17500/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
```

判读容器状态：

```bash
docker ps
# STATUS 列显示 (healthy) / (unhealthy) / (health: starting)
```

- `healthy`：管理页正常响应
- `unhealthy`：管理页没起来，`docker logs meilink-server` 看报错

### 3.8 升级流程
`/data` 卷保存了所有 frps 配置和域名目录，升级只动镜像、不动数据：

```bash
# 1. 拉最新代码后重建镜像
cd server/docker-managed
git pull
docker build -t meilink-server:latest .

# 2. 用 compose 重启（会自动用新镜像）
cd <你的 compose 文件所在目录>
docker compose up -d

# 3. 确认数据还在
docker compose logs meilink-server | head -50
```

> 升级 frp 主版本前，先确认客户端 frpc 版本兼容（基线 v0.70.0，见 §7.2）。

### 3.9 安全建议（17500 管理页）
管理页是**整个服务端的控制面**，泄露账号 = 别人能改你的所有隧道。务必：

1. **不要直接对公网开放 17500**——按 §3.3 绑 `127.0.0.1:17500:17500`
2. 远程管理用 **SSH 端口转发**：`ssh -L 17500:127.0.0.1:17500 user@vps`
3. 或用 **Nginx 反代 + HTTPS + Basic Auth + IP 白名单**（见 §4.2）
4. `MEILINK_ADMIN_PASSWORD` 用强密码（≥ 16 位随机）
5. 如果不慎公网开放过，改密码后检查 `/data` 里的 frps 配置有无被篡改

---

## 4. 进阶配置（两套通用）

### 4.1 Nginx 反代：标准 80/443 访问子域名
默认子域名访问要带端口（`:8080` / `:8443`）。用 Nginx 反代到 80/443 即可不带端口访问：

```nginx
# HTTP：80 → frps vhostHTTPPort 8080
server {
    listen 80;
    server_name *.tunnel.yourdomain.com;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        # WebSocket / 长连接支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
    }
}

# HTTPS：443 → frps vhostHTTPSPort 8443（或终止 TLS 后转 8080 走 HTTP）
server {
    listen 443 ssl http2;
    server_name *.tunnel.yourdomain.com;

    ssl_certificate     /etc/letsencrypt/live/tunnel.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/tunnel.yourdomain.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;   # 终止 TLS 后转 HTTP vhost
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
    }
}
```

> 走反代后，8080/8443 可在 compose 里改成只绑 `127.0.0.1`，不暴露公网：
> ```yaml
> ports:
>   - "7000:7000"
>   - "127.0.0.1:8080:8080"
>   - "127.0.0.1:8443:8443"
> ```

### 4.2 Nginx 反代管理页（方案 B）+ Basic Auth
让管理页走 HTTPS 并加一层 Basic Auth：

```bash
# 1. 生成 htpasswd 文件
sudo htpasswd -c /etc/nginx/.htpasswd meilink-admin

# 2. Nginx 配置（用你自己的管理域名，如 admin.yourdomain.com）
```

```nginx
server {
    listen 443 ssl http2;
    server_name admin.yourdomain.com;

    ssl_certificate     /etc/letsencrypt/live/admin.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/admin.yourdomain.com/privkey.pem;

    auth_basic           "Meilink Admin";
    auth_basic_user_file /etc/nginx/.htpasswd;

    # 可选：IP 白名单
    # allow 1.2.3.4;
    # deny  all;

    location / {
        proxy_pass http://127.0.0.1:17500;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

访问 `https://admin.yourdomain.com` → 先过 Basic Auth → 再到管理页登录。

### 4.3 多实例 / 多域名
| 需求 | 方案 A | 方案 B | 裸机 |
|---|---|---|---|
| 多个域名各跑一套 frps | 改 `subDomainHost` + 不同端口，起多个 compose 服务 | 管理页直接加「域名目录」，**一个实例即可** | `meilink-setup add` 加 profile，自动分配端口 |
| 物理隔离（不同 Token/不同 frps 进程） | 多容器 | 多容器（compose 起多个 service） | `meilink-setup` 多 profile |

### 4.4 TLS 证书（Let's Encrypt）
```bash
# 安装 certbot
sudo apt install -y certbot python3-certbot-nginx

# 申请泛域名证书（需 DNS 验证）
sudo certbot certonly --manual --preferred-challenges dns \
  -d "*.tunnel.yourdomain.com" -d "tunnel.yourdomain.com"

# 续期（cron 自动）
sudo certbot renew --dry-run
```

> 泛域名证书必须用 `--preferred-challenges dns`。部分域名商支持 API 自动写 TXT 记录，可配 `certbot-dns-*` 插件实现自动续期。

### 4.5 持久化与备份（方案 B）
方案 B 的所有动态数据都在 `/data` 卷，备份这一份就够了：

```bash
# 备份
docker run --rm -v <你的data卷或目录>:/data -v $(pwd):/backup alpine \
  tar czf /backup/meilink-data-$(date +%F).tar.gz /data

# 恢复
docker run --rm -v <你的data卷或目录>:/data -v $(pwd):/backup alpine \
  tar xzf /backup/meilink-data-YYYY-MM-DD.tar.gz -C /
```

---

## 5. 运维速查

### 5.1 日常命令
```bash
# 看状态
docker compose ps

# 看日志（实时跟随）
docker compose logs -f frps              # 方案 A
docker compose logs -f meilink-server    # 方案 B

# 重启
docker compose restart

# 进容器排查
docker compose exec frps sh              # 方案 A（alpine）
docker compose exec meilink-server sh    # 方案 B
```

### 5.2 重启策略对照
| 策略 | 行为 |
|---|---|
| `restart: always` | 任何退出都重启，**包括手动 stop 后重启 Docker daemon 时也会拉起**（方案 A 默认） |
| `restart: unless-stopped` | 除非手动 stop，否则都重启；手动 stop 后重启 daemon **不会**拉起（方案 B 默认） |
| `restart: on-failure` | 仅非 0 退出码才重启 |

> 生产环境推荐 `unless-stopped`：维护时手动 stop 不会被 daemon 重启打断。

### 5.3 端口占用排查
```bash
# 宿主机端口监听
ss -tlnp | grep -E '7000|8080|8443|17500'

# 容器端口映射
docker ps --format "table {{.Names}}\t{{.Ports}}"

# 谁占了 8080
sudo lsof -i :8080
```

### 5.4 连通性自测
```bash
# 客户端能否到 frps 的 7000
telnet VPS_IP 7000
# 或
nc -zv VPS_IP 7000

# frps 的 HTTP vhost 是否通（手动塞 Host 头模拟子域名）
curl -H "Host: photo.tunnel.yourdomain.com" http://VPS_IP:8080

# 方案 B 管理页健康检查
curl http://127.0.0.1:17500/healthz
```

### 5.5 客户端侧 frpc.toml 最小示例
```toml
serverAddr = "VPS_IP"
serverPort = 7000
auth.method = "token"
auth.token = "和你 frps 里设的一样的 Token"

[[proxies]]
name = "my-web"
type = "http"
localPort = 8080
customDomains = ["photo.tunnel.yourdomain.com"]
# 或用 subdomain（需 frps 配了 subDomainHost）
# subdomain = "photo"
```

> 实际客户端推荐用 Meilink GUI（macOS 原生 / 跨平台桌面），图形化配置；CLI 场景才手写 toml。

---

## 6. 方案对比与选型建议（总结）

### 6.1 三种服务端部署方式全景
| 维度 | 方案 A：裸 frps Docker | 方案 B：一体镜像 Docker | 裸机 systemd |
|---|---|---|---|
| 位置 | `server/docker-compose/` | `server/docker-managed/` | `server/bare-metal/` / `server/setup/` |
| 管理界面 | 无 | Web 管理页 :17500 | 无（CLI 菜单） |
| 多域名 | 多容器 | 单实例加域名目录 | meilink-setup 多 profile |
| 版本控制 | 第三方镜像，不固定 | 固定 v0.70.0 | 固定 v0.70.0 |
| 隔离性 | 进程/网络隔离 | 进程/网络隔离 | 裸进程 |
| 适合 | 老手、最小依赖 | 团队、新手、要管理页 | 不用 Docker 的服务器 |

### 6.2 FAQ
- **Q：方案 A 和方案 B 能在同一台机器上共存吗？**
  A：能，但端口要错开（比如方案 B 用默认 7000，方案 A 改成 17000），否则冲突。一般没必要共存。

- **Q：客户端用哪个 frp 版本？**
  A：必须与服务端主版本一致。仓库基线是 **v0.70.0**（见 §7.2）。方案 A 用 `:latest` 有版本漂移风险，生产环境强烈建议固定版本或用方案 B。

- **Q：想从方案 A 迁到方案 B 怎么办？**
  A：`docker compose down` 停掉方案 A，按 §3 重新部署方案 B，把原 `frps.toml` 里的 `subDomainHost` / Token 在管理页重新填一遍（客户端配置不用改，只要端口和 Token 一致）。

- **Q：为什么不要把 7000 端口改掉？**
  A：能改，但 `serverPort` 在客户端和服务端必须一致。改了之后客户端连接处也要同步改。默认 7000 是 frp 社区约定，扫描流量可接受。

- **Q：Docker 部署 vs 裸机部署怎么选？**
  A：服务器已经在跑 Docker / 想要环境隔离 / 想要管理页 → Docker（方案 B）。服务器资源紧张 / 不会 Docker / 只想最快跑起来 → 裸机 `deploy-frps.sh` 或 `meilink-setup`。

---

## 7. 附录

### 7.1 端口速查表
| 端口 | 含义 | 来源 |
|---|---|---|
| 7000 | frps `bindPort`（客户端连接） | 所有方案一致 |
| 8080 | frps `vhostHTTPPort`（HTTP 子域名访问） | 所有方案一致 |
| 8443 | frps `vhostHTTPSPort`（HTTPS 子域名访问） | 所有方案一致 |
| 17500 | 方案 B 管理页（`MEILINK_WEB_PORT`） | server-docker 默认 |
| 7500 | frps 原生 Dashboard（`webServer.port`，需手动开启） | `frps.toml.example` |
| 17420 | 客户端 Admin API（仅本机，不在本手册范围） | docker-client |

### 7.2 frp 版本基线
仓库内 frp 版本统一为 **v0.70.0**，分布在：

| 文件 | 位置 |
|---|---|
| `scripts/assets/download-frpc.sh` | 第 4 行 `FRP_VERSION` |
| `scripts/build/build-frpc.sh` | 第 4 行 `FRP_VERSION` |
| `scripts/build/build-desktop.sh` | 第 65 行 `FRP_VERSION`（桌面客户端内嵌 frpc） |
| `server/bare-metal/deploy-frps.sh` | 第 10 行 `FRP_VERSION`（硬编码） |
| `server/docker-managed/Dockerfile` | 第 4 行 `ARG FRP_VERSION=0.70.0` |
| `server/setup/main.go` | 第 32 行 `defaultFrpVersion` |

> 📌 升级 frp 时，**以上六处必须同步修改**。方案 A 用第三方镜像，版本独立于这六处——升级方案 A 要单独固定镜像 tag。

### 7.3 客户端配置参考
- macOS 原生客户端：`client/macos-native/`（详见 [../README.md](../README.md)）
- 跨平台桌面客户端（Tauri）：`client/desktop/`
- Docker 客户端（容器化 frpc）：`client/docker/`

### 7.4 相关文件索引
| 文件 | 说明 |
|---|---|
| [`../server/docker-compose/docker-compose.yml`](../server/docker-compose/docker-compose.yml) | 方案 A 编排文件 |
| [`../server/docker-compose/frps.toml`](../server/docker-compose/frps.toml) | 方案 A 的 frps 配置（含占位符） |
| [`../server/docker-managed/Dockerfile`](../server/docker-managed/Dockerfile) | 方案 B 镜像构建 |
| [`../server/docker-managed/README.md`](../server/docker-managed/README.md) | 方案 B 简版说明 |
| [`../client/macos-native/Resources/frps.toml.example`](../client/macos-native/Resources/frps.toml.example) | 带 Dashboard 的 frps 配置示例 |
| [`../server/bare-metal/deploy-frps.sh`](../server/bare-metal/deploy-frps.sh) | 裸机单实例部署脚本 |
| [`../server/setup/main.go`](../server/setup/main.go) | 裸机多 profile 部署工具 |
| [`../server/README.md`](../server/README.md) | 服务端 4 套方案总览 |
| [`../sdd/07-build-release.md`](../sdd/07-build-release.md) §6 | 构建发布 SDD 的服务端部署章节 |
