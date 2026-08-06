# Meilink SDD · 07 · 构建与发布

> 本文记录 Meilink 的构建流程、产物命名规则、版本号约定、CI 提示。事实基线：`scripts/` + 根目录配置 + `release/` 目录现状。

## 1. 构建矩阵

| 产物 | 平台 | 构建脚本 | 产物格式 |
|---|---|---|---|
| macOS 原生客户端 | macOS 13+ | `xcodegen generate` + `xcodebuild` 或 `swift build` | `Meilink.app` → DMG |
| Tauri 桌面客户端 | macOS/Windows/Linux（各平台原生） | `scripts/build/build-desktop.sh` | DMG / MSI / DEB / AppImage |
| 服务端部署工具 | Linux（amd64 + arm64 交叉编译） | `scripts/build/build-all.sh` | tar.gz |
| Docker 客户端镜像 | linux/amd64 + linux/arm64 | `client/docker/Dockerfile` | GHCR 镜像 + OCI tar |
| Docker 服务端一体镜像 | linux/amd64 + linux/arm64 | `server/docker-managed/Dockerfile` | GHCR 镜像 + OCI tar |

> Docker 镜像由 CI（`.github/workflows/release.yml` 的 `docker-images` job）用 buildx 构建并推送到 GHCR（`ghcr.io/<owner>/meilink-client` / `meilink-server`），同时导出 OCI 离线包作为 Release 附件（NAS 等无法在线构建的环境用 `docker load -i` 导入）。本地构建见 [../guides/deploy-docker.md](../guides/deploy-docker.md)。

## 2. macOS 原生客户端构建

### 2.1 开发环境准备
```bash
bash scripts/dev/setup-dev.sh
```
- 检查 Swift
- 下载 frpc 到 `.build/.../frpc`（开发期）
- `swift build`

### 2.2 Xcode 工程（推荐用于发布）
```bash
brew install xcodegen
xcodegen generate       # 生成 Meilink.xcodeproj
open Meilink.xcodeproj  # 在 Xcode 中 Archive
```

### 2.3 SwiftPM（快速构建）
```bash
swift build
```
- 不含 frpc 二进制（需手动 `scripts/assets/download-frpc.sh`）
- 不含 AppIcon.icns 集成

### 2.4 frpc 集成
- `project.yml` 的 `preBuildScripts` 在每次构建前调 `scripts/assets/download-frpc.sh`
- frpc 下载到 `${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/MacOS/frpc`
- frp 版本：`v0.70.0`（硬编码在 `scripts/assets/download-frpc.sh`）
- 架构自动检测：`arm64` / `x86_64`

### 2.5 打包 DMG
- `scripts/build/build-all.sh` 第三段：
  1. 优先用 `xcodegen` + `xcodebuild` 生成 fresh `.app`
  2. 失败则回退到 `build/Meilink.app`（预构建 bundle）
  3. `make_dmg` 生成含 Applications 快捷方式的标准 DMG

## 3. 全产物编排（`scripts/build/build-all.sh`）

`build-all.sh` 是本地一键构建脚本，按三个阶段产出全部 release 产物到 `release/`（按 client/server 子目录组织）。CI（`.github/workflows/release.yml`）用矩阵 job 取代了它的角色，但本地仍可用。

### 3.1 入口
```bash
bash scripts/build/build-all.sh [version]    # 默认 1.1.0
```

### 3.2 三个阶段
1. **Tauri 桌面客户端**：委托 `scripts/build/build-desktop.sh --copy`（见 §4），产物到 `release/client/desktop/`
2. **服务端 setup 工具**：`build_setup` 函数交叉编译 `server/setup/`（linux amd64 + arm64），每个含 `meilink-setup` 二进制 + `README.txt`，打成 tar.gz 到 `release/server/`
3. **macOS 原生客户端 DMG**：见 §2.5，产物到 `release/client/macos-native/`

> 注：独立 Go CLI 客户端已不再作为产品形态发布（`cmd/meilink` 保留为桌面客户端的 sidecar 后端，不单独构建）。历史版本描述的"5 目标交叉编译 / `make_macos_app` / Linux tar.gz 桌面集成"流程已移除。

### 3.3 关键函数
- `make_dmg(app_path, dmg_path, volname)`：标准 DMG（含 Applications 快捷方式 + Gatekeeper 修复脚本）
- `build_setup(goarch)`：交叉编译 server setup 工具并打包

## 4. Tauri 桌面客户端构建（`scripts/build/build-desktop.sh`）

### 4.1 入口
```bash
bash scripts/build/build-desktop.sh [--copy]
```

### 4.2 流程
1. **Go sidecar 交叉编译**：按 target-triple 命名
   - `darwin-arm64` → `meilink-aarch64-apple-darwin`
   - `darwin-amd64` → `meilink-x86_64-apple-darwin`
   - `linux-amd64` → `meilink-x86_64-unknown-linux-gnu`
   - `linux-arm64` → `meilink-aarch64-unknown-linux-gnu`
   - `windows-amd64` → `meilink-x86_64-pc-windows-msvc.exe`
   - 输出到 `client/desktop/src-tauri/binaries/`
2. **前端构建**：`npm install` + `npx vite build`
3. **Tauri 构建**：`npx tauri build`（Rust 编译 + 打包）
4. **复制产物**（`--copy`）：
   - macOS → `meilink-desktop-<ver>-darwin-<arch>.dmg`
   - Windows → 原 MSI 名
   - Linux → 原 DEB / AppImage

### 4.3 平台限制
- Tauri 无法在同一主机交叉编译
- macOS 主机 → 只能构建 macOS
- Linux 主机 → 只能构建 Linux
- Windows 主机 → 只能构建 Windows
- 多平台发布必须在对应平台的 CI runner 上执行

## 5. 产物命名规则

### 5.1 release/ 目录结构（对齐 client/server 源码结构）
```
release/
├── RELEASE_NOTES.md
├── client/                                  # 客户端产物
│   ├── macos-native/                        #   macOS 原生客户端
│   │   └── meilink-<ver>-macos-native.dmg
│   ├── desktop/                             #   Tauri 桌面客户端
│   │   ├── meilink-desktop-<ver>-darwin-<arch>.dmg
│   │   ├── meilink-desktop-<ver>-linux-<arch>.deb
│   │   ├── meilink-desktop-<ver>-linux-<arch>.AppImage
│   │   └── meilink-desktop-<ver>-windows-<arch>.msi
│   └── docker/                              #   Docker 客户端 OCI 离线包
│       └── meilink-docker-client-<ver>.oci.tar
└── server/                                  # 服务端产物
    ├── meilink-setup-<ver>-linux-amd64.tar.gz
    ├── meilink-setup-<ver>-linux-arm64.tar.gz
    └── meilink-server-<ver>.oci.tar         #   Docker 服务端一体镜像 OCI 离线包
```

### 5.2 命名约定
- Swift 原生：`meilink-<version>-macos-native.dmg`
- Tauri 桌面：`meilink-desktop-<version>-<goos>-<goarch>.<ext>`
- 服务端工具：`meilink-setup-<version>-linux-<goarch>.tar.gz`
- Docker 客户端 OCI：`meilink-docker-client-<version>.oci.tar`
- Docker 服务端 OCI：`meilink-server-<version>.oci.tar`
- GHCR 镜像：`ghcr.io/<owner>/meilink-client:<version>|latest` / `ghcr.io/<owner>/meilink-server:<version>|latest`

### 5.3 版本号来源
- `scripts/build/build-all.sh` 第一个参数，默认 `1.1.0`
- Tauri 桌面：`scripts/build/build-desktop.sh` 内硬编码 `VERSION="1.1.0"`（第 189 行，`--copy` 分支内）
- Swift 原生：`Info.plist` 的 `CFBundleShortVersionString = 1.0.0`（与发布版本不一致，历史遗留）

## 6. frps 服务端部署

### 6.1 Shell 脚本部署（单实例）
```bash
bash server/bare-metal/deploy-frps.sh              # 默认 deploy：下载 frp + 安装 + 启动
bash server/bare-metal/deploy-frps.sh start
bash server/bare-metal/deploy-frps.sh stop
bash server/bare-metal/deploy-frps.sh restart
bash server/bare-metal/deploy-frps.sh status
bash server/bare-metal/deploy-frps.sh help
```
- frp 版本：`v0.70.0`（硬编码）
- frps 安装路径：`/usr/local/bin/frps`
- 配置路径：`/etc/frps/frps.toml`（0600 权限）
- systemd 服务：`/etc/systemd/system/frps.service`
- 校验：`bindPort` / `vhostHTTPPort` / `vhostHTTPSPort` 必填；`subDomainHost` 不能是 `tunnel.yourdomain.com`；`auth.token` 不能是 `your-secret-token-here`

### 6.2 meilink-setup 多 profile 部署
```bash
sudo ./meilink-setup setup              # 首次初始化
sudo ./meilink-setup add                # 添加新 profile
sudo ./meilink-setup list
sudo ./meilink-setup start [name]
sudo ./meilink-setup stop|restart|status [name]
sudo ./meilink-setup upgrade            # 升级 frps + 重启所有实例
```
- 每个 profile = 一个域名 + 一个 token + 一个独立的 `frps-<name>.service`
- 端口从 7000 递增
- `systemctl enable --now` 确保开机自启
- 实现位于 `server/setup`（本次未深入读源码）

### 6.3 Docker 部署
```bash
docker compose up -d
```
- 镜像：`snowdreamtech/frps:latest`
- 端口：7000 / 8080 / 8443
- 挂载：`./frps.toml:/etc/frps/frps.toml`

> 另有 `server/docker-managed/` 自构建的「frps + Web 管理页」一体镜像方案。
> 两套 Docker 方案的完整部署手册见 [../guides/deploy-docker.md](../guides/deploy-docker.md)。
>
> docker-managed 镜像对 `/usr/local/bin/frps` 设置了 `cap_net_bind_service=+ep`（file capability），frps 以非 root 用户 `meilink` 运行但可绑定 < 1024 的特权端口（80/443）。host 网络模式下管理页直接填 80 即生效；bridge 模式下还需在 compose 映射对应端口。修改此机制需同步 `server/docker-managed/Dockerfile`（setcap）与 README「特权端口」小节。

## 7. 开发辅助脚本

### 7.1 `scripts/build/build-frpc.sh`
- 从源码构建 frpc universal binary（arm64 + amd64 → lipo）
- 用于需要自定义 frpc 的场景
- 默认 `scripts/assets/download-frpc.sh` 下载预编译二进制足够

### 7.2 `scripts/assets/gen-icons.sh`
- 从 `AppIcon.png` 派生 Windows ICO + .syso + Linux PNG
- 依赖：`sips`（macOS 自带）+ `python3` + `rsrc`（go install）
- 输出：`client/desktop/sidecar/app.ico` / `resource_windows_amd64.syso` / `meilink.png`

### 7.3 `scripts/dev/reset-menu-bar-cache.sh`
- 清理 macOS 系统对菜单栏图标的缓存
- 当菜单栏图标位置错乱时运行
- 清理 `pub.mei.meilink.app` / `pub.mei.meilink` 两个 domain 的 `NSStatusItem Visible*` keys

### 7.4 `scripts/dev/setup-dev.sh`
- 一键设置开发环境：检查 Swift + 下载 frpc + `swift build`

## 8. CI 流程（已实现，`.github/workflows/release.yml`）

触发方式：推送 `v*` tag 或 `workflow_dispatch`（可手动填版本号）。由 5 个 job 组成，最后 `publish-release` 汇总产物到 GitHub Release：

### 8.1 `tauri-desktop` — Tauri 桌面客户端
- 矩阵：macos-14 / windows-latest / ubuntu-22.04
- `bash scripts/build/build-desktop.sh --copy <version>`
- 产出：`meilink-desktop-<ver>-<goos>-<goarch>.<ext>`（DMG / MSI / DEB / AppImage）

### 8.2 `swift-native` — macOS 原生客户端
- runner：macos-14，`swift build -c release` + SwiftPM 回退打包 DMG
- 产出：`meilink-<ver>-macos-native.dmg`

### 8.3 `server-setup` — 服务端 setup 工具
- runner：ubuntu-22.04，交叉编译 linux amd64 + arm64
- 产出：`meilink-setup-<ver>-linux-<arch>.tar.gz`

### 8.4 `docker-images` — Docker 镜像
- runner：ubuntu-22.04，`setup-qemu` + `setup-buildx`，登录 GHCR
- 矩阵：`client/docker` → `meilink-client`；`server/docker-managed` → `meilink-server`
- 构建 `linux/amd64 + linux/arm64` 多架构镜像，推送 `ghcr.io/<owner>/<image>:<version>` + `:latest`
- **可选 ACR**：若配置了 secrets `ALIYUN_ACR_USERNAME` + `ALIYUN_ACR_PASSWORD`，额外推送 `registry.cn-hangzhou.aliyuncs.com/meilink/<image>:<version>` + `:latest`（阿里云个人版免费，国内直连最快）
- 同时导出 OCI 离线包（`type=oci`）作为 Release 附件：`meilink-docker-client-<ver>.oci.tar` / `meilink-server-<ver>.oci.tar`
- 需要 GHCR 权限：`permissions.packages: write`（用 `GITHUB_TOKEN`，无需额外 secrets）
- **必须带 `org.opencontainers.image.source` label**（Dockerfile 里写死 + build-push-action `labels` 双保险）。GHCR 靠它把 package 与源仓库绑定；缺失时 package 会处于"未关联"状态，导致 GITHUB_TOKEN push 时报 `403 Forbidden`（`HEAD request ... 403`）。已在 `client/docker/Dockerfile` 与 `server/docker-managed/Dockerfile` 顶部写入 `https://github.com/tomtrije/mei-link`
- **国内加速**：镜像需在 GHCR 设为 public（否则加速站回源 401）。`server` 实例额外执行 best-effort 预热（`continue-on-error`），docker pull 各加速站触发回源缓存；`warm-cache.yml` 可随时手动触发。注意阿里云 `*.mirror.aliyuncs.com` 是 Docker daemon registry mirror，只对 Docker Hub 生效，**对 ghcr.io 无效**（ACR 是独立免费仓库，不受此限制）

### 8.6 `warm-cache.yml` — 加速站预热（手动）
- 触发：`workflow_dispatch`，输入版本号
- runner：ubuntu-22.04，`continue-on-error`，docker pull `ghcr.nju.edu.cn` / `ghcr.m.daocloud.io` / `ghcr.dockerproxy.net` 下的 client + server 镜像
- 用途：不影响发布，镜像改 public 或新版本发布后，随时手动触发加速站回源缓存，国内拉取更快

### 8.5 `publish-release` — 汇总发布
- `needs` 依赖上述 4 个 job，按产物名前缀分发到 `release/` 子目录后 `action-gh-release` 建 Release
- `download-artifact` 用 `pattern: "!*.dockerbuild"` 排除 build-push-action 自动上传的构建记录产物（否则全量下载会因 dockerbuild 元数据解压失败）；`docker-images` 侧同时设 `DOCKER_BUILD_RECORD_UPLOAD=false` 直接禁止上传

## 9. 发布检查清单

发布前必须确认：

- [ ] frp 版本号在六处一致：`scripts/assets/download-frpc.sh` / `scripts/build/build-frpc.sh` / `scripts/build/build-desktop.sh` / `server/bare-metal/deploy-frps.sh` / `server/docker-managed/Dockerfile` / `server/setup/main.go`
- [ ] `client/macos-native/Resources/AppIcon.png` 与 `AppIcon.icns` 已更新（若改了图标）
- [ ] `scripts/assets/gen-icons.sh` 已重跑（若改了源图标）
- [ ] `release/` 目录里旧的产物已清理或归档
- [ ] `RELEASE_NOTES.md` 已更新
- [ ] `CFBundleShortVersionString`（Info.plist）与 `build-all.sh` 的 `VERSION` 对齐（目前 1.0.0 vs 1.1.0 不一致，建议统一）
- [ ] macOS 原生客户端在 `xcodegen generate` + `xcodebuild` 后能正常启动
- [ ] 跨平台客户端在 macOS / Linux / Windows 各自 runner 上能构建
- [ ] 服务端 setup 工具能正常部署 frps
- [ ] Docker 镜像 CI（`docker-images` job）已推送 GHCR：`ghcr.io/<owner>/meilink-client:<ver>` / `ghcr.io/<owner>/meilink-server:<ver>` + `:latest`
- [ ] Docker 镜像能正常启动：客户端管理页 `:17420`、服务端管理页 `:17500`（含 frps 7000/8080/8443）
- [ ] 验证 OCI 离线包可 `docker load -i` 导入（amd64 + arm64 双架构）
- [ ] 验证升级路径：旧版本配置能被新版本读取
