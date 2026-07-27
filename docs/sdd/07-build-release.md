# Meilink SDD · 07 · 构建与发布

> 本文记录 Meilink 的构建流程、产物命名规则、版本号约定、CI 提示。事实基线：`Scripts/` + 根目录配置 + `release/` 目录现状。

## 1. 构建矩阵

| 产物 | 平台 | 构建脚本 | 产物格式 |
|---|---|---|---|
| macOS 原生客户端 | macOS 13+ | `xcodegen generate` + `xcodebuild` 或 `swift build` | `Meilink.app` → DMG |
| 跨平台 Go 客户端 | Linux/Darwin/Windows | `Scripts/build-all.sh` | tar.gz / DMG / zip |
| 服务端部署工具 | Linux | `Scripts/build-all.sh` | tar.gz |
| Tauri 桌面客户端 | 当前平台 | `Scripts/build-desktop.sh` | DMG / MSI / DEB / AppImage |

## 2. macOS 原生客户端构建

### 2.1 开发环境准备
```bash
bash Scripts/setup-dev.sh
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
- 不含 frpc 二进制（需手动 `Scripts/download-frpc.sh`）
- 不含 AppIcon.icns 集成

### 2.4 frpc 集成
- `project.yml` 的 `preBuildScripts` 在每次构建前调 `Scripts/download-frpc.sh`
- frpc 下载到 `${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/MacOS/frpc`
- frp 版本：`v0.70.0`（硬编码在 `Scripts/download-frpc.sh`）
- 架构自动检测：`arm64` / `x86_64`

### 2.5 打包 DMG
- `Scripts/build-all.sh` 第三段：
  1. 优先用 `xcodegen` + `xcodebuild` 生成 fresh `.app`
  2. 失败则回退到 `build/Meilink.app`（预构建 bundle）
  3. `make_dmg` 生成含 Applications 快捷方式的标准 DMG

## 3. 跨平台 Go 客户端构建（`Scripts/build-all.sh`）

### 3.1 入口
```bash
bash Scripts/build-all.sh [version]    # 默认 1.1.0
```

### 3.2 流程
1. **图标生成**（仅 macOS 主机）：`Scripts/gen-icons.sh`
   - 输入：`Meilink/Resources/AppIcon.png`
   - 输出：`cross-platform-client/app.ico` / `resource_windows_amd64.syso` / `meilink.png`
   - 工具：`sips`（裁剪 PNG）+ `python3 _pack_ico.py`（拼 ICO）+ `rsrc`（编译 .syso）
2. **Go 客户端交叉编译**：5 个目标
   - `linux/amd64` / `linux/arm64`：tar.gz（含 README + 桌面集成）
   - `darwin/amd64` / `darwin/arm64`：DMG（Go 二进制包成 .app + Applications 快捷方式）
   - `windows/amd64`：单 exe（嵌入 .syso 图标，console subsystem 保留以支持 CLI 子命令）
3. **服务端 setup 工具**：`linux/amd64` + `linux/arm64`，tar.gz
4. **macOS 原生客户端 DMG**：见 §2.5
5. **清理**：删除临时 .syso / .ico / .png（防 commit 污染）

### 3.3 关键函数
- `make_macos_app(bin, appdir)`：把 Go 二进制包成 `.app` bundle
  - `Contents/MacOS/Meilink` = 启动脚本（`cross-platform-client/assets/meilink-launcher-macos.sh`）
  - `Contents/MacOS/meilink-bin` = 真正的 Go 二进制
  - `Contents/Resources/AppIcon.icns`
  - `Contents/Info.plist`（bundleId = `vip.rego.meilink.go`）
- `make_dmg(app_path, dmg_path, volname)`：标准 DMG（含 Applications 快捷方式）

### 3.4 Linux 桌面集成
tar.gz 内含：
- `meilink` 二进制
- `README.md`（来自 `cross-platform-client/assets/USER_README.md`）
- `meilink.png`（256×256）
- `meilink.desktop`（GNOME/KDE 桌面入口）
- `meilink-webui`（启动 Web UI 的脚本）
- `install.sh`（安装脚本）

## 4. Tauri 桌面客户端构建（`Scripts/build-desktop.sh`）

### 4.1 入口
```bash
bash Scripts/build-desktop.sh [--copy]
```

### 4.2 流程
1. **Go sidecar 交叉编译**：按 target-triple 命名
   - `darwin-arm64` → `meilink-aarch64-apple-darwin`
   - `darwin-amd64` → `meilink-x86_64-apple-darwin`
   - `linux-amd64` → `meilink-x86_64-unknown-linux-gnu`
   - `linux-arm64` → `meilink-aarch64-unknown-linux-gnu`
   - `windows-amd64` → `meilink-x86_64-pc-windows-msvc.exe`
   - 输出到 `cross-platform-client/desktop/src-tauri/binaries/`
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

### 5.1 release/ 目录现状（v1.1.0）
```
meilink-1.1.0-darwin-amd64.dmg          # Go 客户端 macOS amd64
meilink-1.1.0-darwin-arm64.dmg          # Go 客户端 macOS arm64
meilink-1.1.0-linux-amd64.tar.gz        # Go 客户端 Linux amd64
meilink-1.1.0-linux-arm64.tar.gz        # Go 客户端 linux arm64
meilink-1.1.0-windows-amd64.zip         # Go 客户端 Windows amd64
meilink-1.1.0-macOS-native.dmg          # Swift 原生客户端
meilink-desktop-1.1.0-darwin-arm64.dmg  # Tauri 桌面客户端
meilink-setup-1.1.0-linux-amd64.tar.gz  # 服务端 setup 工具
meilink-setup-1.1.0-linux-arm64.tar.gz  # 服务端 setup 工具
RELEASE_NOTES.md
```

### 5.2 命名约定
- Go 客户端：`meilink-<version>-<goos>-<goarch>.<ext>`
- Swift 原生：`meilink-<version>-macOS-native.dmg`
- Tauri 桌面：`meilink-desktop-<version>-<goos>-<goarch>.<ext>`
- 服务端工具：`meilink-setup-<version>-linux-<goarch>.tar.gz`

### 5.3 版本号来源
- `Scripts/build-all.sh` 第一个参数，默认 `1.1.0`
- Tauri 桌面：`Scripts/build-desktop.sh` 内硬编码 `VERSION="1.1.0"`（第 71 行）
- Swift 原生：`Info.plist` 的 `CFBundleShortVersionString = 1.0.0`（与发布版本不一致，历史遗留）

## 6. frps 服务端部署

### 6.1 Shell 脚本部署（单实例）
```bash
./deploy-frps.sh              # 默认 deploy：下载 frp + 安装 + 启动
./deploy-frps.sh start
./deploy-frps.sh stop
./deploy-frps.sh restart
./deploy-frps.sh status
./deploy-frps.sh help
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
- 实现位于 `cross-platform-client/cmd/meilink-setup`（本次未深入读源码）

### 6.3 Docker 部署
```bash
docker compose up -d
```
- 镜像：`snowdreamtech/frps:latest`
- 端口：7000 / 8080 / 8443
- 挂载：`./frps.toml:/etc/frps/frps.toml`

## 7. 开发辅助脚本

### 7.1 `Scripts/build-frpc.sh`
- 从源码构建 frpc universal binary（arm64 + amd64 → lipo）
- 用于需要自定义 frpc 的场景
- 默认 `Scripts/download-frpc.sh` 下载预编译二进制足够

### 7.2 `Scripts/gen-icons.sh`
- 从 `AppIcon.png` 派生 Windows ICO + .syso + Linux PNG
- 依赖：`sips`（macOS 自带）+ `python3` + `rsrc`（go install）
- 输出：`cross-platform-client/app.ico` / `resource_windows_amd64.syso` / `meilink.png`

### 7.3 `Scripts/reset-menu-bar-cache.sh`
- 清理 macOS 系统对菜单栏图标的缓存
- 当菜单栏图标位置错乱时运行
- 清理 `com.meilink.app` / `vip.rego.meilink` 两个 domain 的 `NSStatusItem Visible*` keys

### 7.4 `Scripts/setup-dev.sh`
- 一键设置开发环境：检查 Swift + 下载 frpc + `swift build`

## 8. CI 提示（未实现，建议）

基于当前 `Scripts/` 与 `docs/superpowers/plans/` 的对齐文档，建议的 CI 流程：

### 8.1 macOS runner
- `bash Scripts/build-all.sh <version>`（需 Xcode + Go + xcodegen）
- 产出：所有 tar.gz / DMG / zip / setup 工具

### 8.2 Linux runner
- `cd cross-platform-client && go build .`（CLI 客户端）
- `bash Scripts/build-desktop.sh --copy`（Tauri Linux 桌面客户端）
- 产出：`meilink-<ver>-linux-*.tar.gz` / `meilink-desktop-<ver>-linux-*.deb` / `meilink-setup-<ver>-linux-*.tar.gz`

### 8.3 Windows runner
- `cd cross-platform-client && GOOS=windows GOARCH=amd64 go build .`
- `bash Scripts/build-desktop.sh --copy`（Tauri Windows 桌面客户端）
- 产出：`meilink-<ver>-windows-amd64.zip` / `meilink-desktop-<ver>-windows-*.msi`

### 8.4 测试
- `swift build`（SwiftPM 编译验证）
- `swift test`（当前 `Tests/` 为空，需补测试）
- `go test ./...`（跨平台客户端 Go 测试，见 `docs/superpowers/plans/`）
- `cargo test`（Tauri Rust 测试）
- `npm run build`（前端构建验证）

## 9. 发布检查清单

发布前必须确认：

- [ ] frp 版本号在 `Scripts/download-frpc.sh` / `Scripts/build-frpc.sh` / `deploy-frps.sh` 三处一致
- [ ] `Meilink/Resources/AppIcon.png` 与 `AppIcon.icns` 已更新（若改了图标）
- [ ] `Scripts/gen-icons.sh` 已重跑（若改了源图标）
- [ ] `release/` 目录里旧的产物已清理或归档
- [ ] `RELEASE_NOTES.md` 已更新
- [ ] `CFBundleShortVersionString`（Info.plist）与 `build-all.sh` 的 `VERSION` 对齐（目前 1.0.0 vs 1.1.0 不一致，建议统一）
- [ ] macOS 原生客户端在 `xcodegen generate` + `xcodebuild` 后能正常启动
- [ ] 跨平台客户端在 macOS / Linux / Windows 各自 runner 上能构建
- [ ] 服务端 setup 工具能正常部署 frps
- [ ] 验证升级路径：旧版本配置能被新版本读取
