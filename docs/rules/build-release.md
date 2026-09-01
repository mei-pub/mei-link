# Agent Rule · 构建与发布

> **何时触发**：当任务要求构建客户端、生成发布产物、修改版本号、修改构建脚本、修改图标资源、或发布新版本时。

> **必读 SDD**：[../sdd/07-build-release.md](../sdd/07-build-release.md)（构建与发布基线）。

## 1. 涉及文件清单

### 1.1 构建脚本
- <kfile name="build-all.sh" path="scripts/build/build-all.sh">scripts/build/build-all.sh</kfile> — 全产物编排（Tauri 桌面 + setup 工具 + Swift 原生 DMG）
- <kfile name="build-desktop.sh" path="scripts/build/build-desktop.sh">scripts/build/build-desktop.sh</kfile> — Tauri 桌面客户端（含 Go sidecar 编译）
- <kfile name="build-frpc.sh" path="scripts/build/build-frpc.sh">scripts/build/build-frpc.sh</kfile> — frpc 源码编译
- <kfile name="download-frpc.sh" path="scripts/assets/download-frpc.sh">scripts/assets/download-frpc.sh</kfile> — frpc 预编译下载
- <kfile name="gen-icons.sh" path="scripts/assets/gen-icons.sh">scripts/assets/gen-icons.sh</kfile> — 图标派生（Windows ICO + Linux PNG）
- <kfile name="_pack_ico.py" path="scripts/assets/_pack_ico.py">scripts/assets/_pack_ico.py</kfile> — ICO 拼装
- <kfile name="setup-dev.sh" path="scripts/dev/setup-dev.sh">scripts/dev/setup-dev.sh</kfile> — 开发环境一键设置
- <kfile name="reset-menu-bar-cache.sh" path="scripts/dev/reset-menu-bar-cache.sh">scripts/dev/reset-menu-bar-cache.sh</kfile> — 菜单栏缓存清理

### 1.2 配置文件
- <kfile name="project.yml" path="project.yml">project.yml</kfile> — XcodeGen 配置
- <kfile name="Package.swift" path="Package.swift">Package.swift</kfile> — SwiftPM 配置
- <kfile name="Info.plist" path="client/macos-native/Info.plist">client/macos-native/Info.plist</kfile> — Bundle 信息
- <kfile name="docker-compose.yml" path="server/docker-compose/docker-compose.yml">server/docker-compose/docker-compose.yml</kfile> — frps Docker 部署（裸 frps）
- <kfile name="deploy-frps.sh" path="server/bare-metal/deploy-frps.sh">server/bare-metal/deploy-frps.sh</kfile> — frps 一键部署

### 1.3 资源
- `client/macos-native/Resources/AppIcon.png`（1254×1254，跨平台派生源）
- `client/macos-native/Resources/AppIcon.icns`（macOS .app）
- `client/macos-native/Resources/*.png`（菜单栏图标 + 备选图标）

### 1.4 产物输出（按 client/server 子目录组织）
- `release/client/macos-native/` — Swift 原生 DMG
- `release/client/desktop/` — Tauri 桌面客户端安装包（.dmg/.msi/.deb/.AppImage）
- `release/client/docker/` — Docker 客户端 OCI 离线包（`meilink-docker-client-<ver>.oci.tar`）
- `release/server/` — 服务端 setup 工具 tar.gz + Docker 服务端 OCI 离线包（`meilink-server-<ver>.oci.tar`）
- `build/Meilink.app` — 预构建 bundle（fallback）
- `release/RELEASE_NOTES.md` — 发布说明

> `release/` 下的产物（`.dmg`/`.tar.gz`/`.oci.tar`/`.msi`/`.zip`）已加入 `.gitignore`，**不入库**；仓库仅跟踪各目录 `.gitkeep` 占位文件与 `RELEASE_NOTES.md`。发布由 CI `publish-release` 统一清理 + 汇总，本地构建产物勿提交。

### 1.6 CI 工作流
- `client/docker/Dockerfile` — Docker 客户端镜像（Node 22 + frpc，:17420）
- `client/docker/docker-entrypoint.sh` — 客户端容器入口（root chown `/data` → su-exec 降权 meilink）
- `server/docker-managed/Dockerfile` — Docker 服务端一体镜像（frps + Web 管理页，:17500）
- `server/docker-managed/docker-entrypoint.sh` — 服务端容器入口（root chown `/data` → su-exec 降权 meilink）
- `.github/workflows/release.yml` — 发布 CI（5 个 job，含 `docker-images`）

### 1.5 SDD 文档
- [../sdd/07-build-release.md](../sdd/07-build-release.md)（必须同步）

## 2. 必读不变量

### 2.1 frp 版本号六处同步
- `scripts/assets/download-frpc.sh` 第 4 行：`FRP_VERSION="${FRP_VERSION:-v0.70.0}"`
- `scripts/build/build-frpc.sh` 第 4 行
- `scripts/build/build-desktop.sh` 第 65 行 `FRP_VERSION`（桌面客户端内嵌 frpc）
- `server/bare-metal/deploy-frps.sh` 第 10 行
- `server/docker-managed/Dockerfile` 第 4 行 `ARG FRP_VERSION=0.70.0`
- `server/setup/main.go` 第 32 行 `defaultFrpVersion`

升级 frp 版本必须六处同步 + 实测 frpc.toml schema 兼容性。

### 2.2 版本号约定
- `Info.plist` 的 `CFBundleShortVersionString`：`1.0.0`（Swift 原生 .app 显示版本）
- `project.yml` 的 `CFBundleVersion`：`1.0`
- `scripts/build/build-all.sh` 第一个参数：默认 `1.1.0`（发布版本号）
- `scripts/build/build-desktop.sh` 内 `VERSION="1.1.0"`（第 189 行，`--copy` 分支内）

> **注意**：当前 `1.0.0`（Info.plist）与 `1.1.0`（发布脚本）不一致是历史遗留。新发布建议统一，但不要轻易改 `Info.plist`，会影响已部署的 Login Items 注册。

### 2.3 产物命名规则
- Swift 原生：`meilink-<version>-macos-native.dmg`
- Tauri 桌面：`meilink-desktop-<version>-<goos>-<goarch>.<ext>`
- 服务端工具：`meilink-setup-<version>-linux-<goarch>.tar.gz`
- Docker 客户端 OCI：`meilink-docker-client-<version>.oci.tar`
- Docker 服务端 OCI：`meilink-server-<version>.oci.tar`

### 2.9 Docker 镜像构建（CI `docker-images` job）
- 镜像名：`meilink-client`（`client/docker/`）/ `meilink-server`（`server/docker-managed/`）
- 推送到 `ghcr.io/<owner>/<image>:$version` + `:latest`
- 架构：`linux/amd64` + `linux/arm64`（Dockerfile 用 `ARG TARGETARCH` 选择 frpc/frps 二进制）
- 同时导出 OCI 离线包（`type=oci`）作 Release 附件，NAS 用 `docker load -i` 导入
- 版本 tag 与发布版本号一致；`latest` 始终指向最近一次发布
- frp 版本由 Dockerfile 的 `ARG FRP_VERSION` 控制，升级需六处同步（见 §2.1）
- **必须带 `org.opencontainers.image.source` label**（值 = 源仓库 URL，如 `https://github.com/<owner>/mei-link`）。GHCR 用它把 package 与仓库绑定，缺失时 GITHUB_TOKEN push 会报 `403 Forbidden`（可`HEAD`/`POST` blob 403）。Dockerfile + build-push-action `labels` 都要有

### 2.4 macOS 原生 .app bundle 结构
由 Xcode（`xcodegen generate` + `xcodebuild`）或 SwiftPM 回退流程产出，是标准 Swift macOS app bundle：

```
Meilink.app/
├── Contents/
│   ├── Info.plist
│   ├── MacOS/
│   │   ├── Meilink          (Swift 编译的单二进制)
│   │   └── frpc             (构建期由 download-frpc.sh 下载)
│   └── Resources/
│       ├── AppIcon.icns
│       └── *.png            (菜单栏图标)
```

- `CFBundleIdentifier = pub.mei.meilink`（不要改，会破坏 Login Items + Keychain）
- `LSMinimumSystemVersion = 13.0`
- **Info.plist 必须含 `CFBundleIconFile = AppIcon`**（否则 Finder/Dock 不显示图标；icns 已拷入 Resources 但未注册同样不显示）
- **Info.plist 必须含 `NSAppTransportSecurity.NSAllowsArbitraryLoads = true`**（managementURL 常为 http://host:port，ATS 默认拦明文 HTTP，导致 /api/domains 拉取失败）
- **CI 的 SwiftPM 打包路径（release.yml swift-native job）必须与 xcodebuild 路径保持同样的 Info.plist 字段 + 签名**（两处都可能落后）

### 2.10 macOS 签名（Developer ID）
- 证书：Developer ID Application（如 `Developer ID Application: Income Mei (8KV7MAV54M)`），本机 `security find-identity -v -p codesigning` 可查
- 签名命令（只签主 .app；frpc.exe 保持系统 linker-signed，macOS 15+ 链接器自动加 adhoc 签名，重签会报 `Operation not permitted`）：
  ```bash
  codesign --force --options runtime --sign "$IDENTITY" "$APP"
  codesign --verify --deep --strict "$APP"
  ```
- `--options runtime` = hardened runtime（公证必需）
- 无证书时回退 ad-hoc（`codesign --sign -`），仅消除"已损坏"错误，Gatekeeper 仍提示"未识别开发者"
- **CI runner 没有本机证书**：需把 Developer ID 证书导出 p12（base64）配到 GitHub secrets `CERTIFICATE_P12` + `CERTIFICATE_PASSWORD`，workflow 导入 keychain 后构建（见 release.yml 的 "Import Apple certificate" 步骤）
- 证书导出（本机钥匙串）：
  ```bash
  security export -k ~/Library/Keychains/login.keychain-db -t certs -f pkcs12 -P '<密码>' -o Meilink.p12
  base64 -i Meilink.p12 | pbcopy   # 粘贴到 secrets.CERTIFICATE_P12
  ```
- 未公证（notarize）的 Developer ID 包首次打开仍会被 Gatekeeper 拦（"无法验证开发者"→ 右键打开/系统设置→隐私与安全性→仍要打开）；公证需要 Apple ID 凭据，另配 secrets

### 2.5 DMG 结构
`make_dmg` 生成标准 DMG：
- 含 `.app` + `Applications` 快捷方式（拖拽安装）
- `hdiutil create -fs HFS+ -format UDZO`（压缩只读）

### 2.6 图标派生流程
`scripts/assets/gen-icons.sh`：
1. 输入：`client/macos-native/Resources/AppIcon.png`（1254×1254）
2. `sips -z <sz> <sz>` 派生 7 个尺寸（16/24/32/48/64/128/256）
3. `python3 _pack_ico.py` 拼成 `app.ico`（ICONDIR + ICONDIRENTRY + PNG 数据）
4. `rsrc -ico app.ico -arch amd64 -o resource_windows_amd64.syso`（go build 自动嵌入 exe）
5. 256.png 复制为 `meilink.png`（Linux 桌面图标）

### 2.7 frpc 集成（macOS 原生）
- `project.yml` 的 `preBuildScripts` 调 `scripts/assets/download-frpc.sh`
- frpc 下载到 `${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/MacOS/frpc`
- 架构自动检测：`arm64` / `x86_64`

### 2.8 平台限制（Tauri）
- Tauri 无法在同一主机交叉编译
- macOS 主机 → 只能构建 macOS
- Linux 主机 → 只能构建 Linux
- Windows 主机 → 只能构建 Windows
- 多平台发布必须在对应平台的 CI runner 上执行
- Windows 客户端仅构建 **amd64**（x86_64）单包，不按芯片拆分 arm64

## 3. 同步修改清单

### 3.1 升级 frp 版本
- [ ] `scripts/assets/download-frpc.sh`：改 `FRP_VERSION`
- [ ] `scripts/build/build-frpc.sh`：改 `FRP_VERSION`
- [ ] `scripts/build/build-desktop.sh`：改 `FRP_VERSION`（桌面客户端内嵌 frpc）
- [ ] `server/bare-metal/deploy-frps.sh`：改 `FRP_VERSION`
- [ ] `server/docker-managed/Dockerfile`：改 `ARG FRP_VERSION`
- [ ] `server/setup/main.go`：改 `defaultFrpVersion`
- [ ] 删除旧的 frpc 二进制（`.build/.../frpc` / `Meilink.xcodeproj/DerivedData/.../frpc`）
- [ ] 重新构建 + 实测 frpc.toml schema 兼容
- [ ] SDD：`05-data-contract.md` §6.1 + `06-constraints.md` §6.5 + `07-build-release.md` §2.4 / §6.1 同步
- [ ] 详见 [modifying-frpc-process.md](./modifying-frpc-process.md) §3.1

### 3.2 改发布版本号
- [ ] `scripts/build/build-all.sh`：改默认 `VERSION`（第 15 行）
- [ ] `scripts/build/build-desktop.sh`：改 `VERSION`（第 189 行，`--copy` 分支内）
- [ ] 考虑是否同步 `Info.plist` 的 `CFBundleShortVersionString`（建议同步，但注意 Login Items 兼容）
- [ ] `release/RELEASE_NOTES.md`：更新发布说明
- [ ] SDD：`07-build-release.md` §5.3 同步

### 3.3 改图标
- [ ] `client/macos-native/Resources/AppIcon.png`：换 1254×1254 源
- [ ] `client/macos-native/Resources/AppIcon.icns`：换 macOS .app 图标
- [ ] 重跑 `scripts/assets/gen-icons.sh`（派生 Windows ICO + Linux PNG）
- [ ] `Meilink.xcodeproj`：确认 Assets.xcassets 引用正确
- [ ] 跨平台：`client/desktop/src/public/icons/app-icon.png` 同步
- [ ] SDD：`04-ui-design.md` §12 同步

### 3.4 改产物命名
- [ ] `scripts/build/build-all.sh`：改 `archive` 命名逻辑
- [ ] `scripts/build/build-desktop.sh`：改 `out` 命名逻辑
- [ ] SDD：`07-build-release.md` §5.2 同步
- [ ] `release/RELEASE_NOTES.md`：标注命名变更

### 3.5 改 macOS 原生 .app bundle 结构
- [ ] `project.yml` / `Package.swift`：调整 sources / Info.plist 配置
- [ ] 不能改 `CFBundleIdentifier`（会破坏 Login Items + Keychain）
- [ ] SDD：`07-build-release.md` §2.4 同步

### 3.6 改构建流程
- [ ] 改 `scripts/build/build-all.sh` / `build-desktop.sh`
- [ ] 验证 `release/` 产物完整
- [ ] 更新 `RELEASE_NOTES.md`
- [ ] SDD：`07-build-release.md` 同步

## 4. 反例

### 3.7 改签名 / 图标注册
- [ ] Info.plist 生成处（project.yml / CI swift-native job / build-all.sh fallback）确认含 `CFBundleIconFile` + `NSAppTransportSecurity`
- [ ] 签名命令统一走 `CODESIGN_IDENTITY` 自动检测（`security find-identity ... Developer ID Application`），无证书回退 ad-hoc
- [ ] `build-desktop.sh` / `build-all.sh`：Developer ID 签名主 .app（frpc.exe 不单独重签，保持 linker-signed）
- [ ] CI：release.yml 两个 macOS job 的 "Import Apple certificate" 步骤（依赖 secrets `CERTIFICATE_P12` / `CERTIFICATE_PASSWORD`）
- [ ] 验证：`codesign --verify --deep --strict` + `codesign -dv`（TeamIdentifier 正确）
- [ ] SDD：`07-build-release.md` 同步

### 4.1 反例：frp 版本六处不同步
```bash
# ❌ 错误：只改 download-frpc.sh，不改其余五处
# scripts/assets/download-frpc.sh:      FRP_VERSION="v0.71.0"
# scripts/build/build-frpc.sh:          FRP_VERSION="v0.70.0"  # 还旧
# scripts/build/build-desktop.sh:       FRP_VERSION="v0.70.0"  # 还旧（桌面客户端会带错版本 frpc）
# server/bare-metal/deploy-frps.sh:     FRP_VERSION="v0.70.0"  # 还旧
# server/docker-managed/Dockerfile:     ARG FRP_VERSION=0.70.0  # 还旧
# server/setup/main.go:                 defaultFrpVersion = "v0.70.0"  # 还旧
# 客户端用 0.71，服务端用 0.70，可能不兼容

# ✅ 正确：六处同步
# 六个文件都改成 v0.71.0
```

### 4.2 反例：改 CFBundleIdentifier
```xml
<!-- ❌ 错误：改 bundle ID 会破坏 Login Items + Keychain -->
<key>CFBundleIdentifier</key><string>pub.mei.meilink.new</string>

<!-- ✅ 正确：保持 pub.mei.meilink -->
<key>CFBundleIdentifier</key><string>pub.mei.meilink</string>
```

### 4.3 反例：忘了重跑 gen-icons
```bash
# ❌ 错误：改了 AppIcon.png 但没重跑 gen-icons.sh
# Windows exe 还用旧图标，Linux .desktop 还用旧 PNG

# ✅ 正确：改源图标后必跑
bash scripts/assets/gen-icons.sh
```

### 4.4 反例：在同一主机交叉编译 Tauri
```bash
# ❌ 错误：在 macOS 上想一次性构建 Windows + Linux + macOS
bash scripts/build/build-desktop.sh --copy
# 只会产出 macOS DMG

# ✅ 正确：对应平台 CI runner 上构建
# macOS runner → DMG
# Linux runner → DEB / AppImage
# Windows runner → MSI
```

### 4.5 反例：发布前不清理 release/
```bash
# ❌ 错误：旧产物与新产物混在一起
ls release/client/macos-native/
# meilink-1.1.0-macos-native.dmg
# meilink-1.2.0-macos-native.dmg  # 新旧混在一起

# ✅ 正确：发布前清理或归档旧版本（release/ 按子目录组织，对齐 client/server 源码结构）
rm release/client/macos-native/meilink-1.1.0-*
# 或
mkdir release/archive && mv release/client/macos-native/meilink-1.1.0-* release/archive/
```

> 自 v1.2.0 起，CI `publish-release` 会在上传前自动清理 `release/` 下陈旧产物（`*.dmg`/`*.tar.gz`/`*.oci.tar`/`*.msi`/`*.zip`），且产物已加入 `.gitignore` 不入库。本地构建仍建议按上述方法维护 `release/`。

### 4.6 反例：改 frpc 集成不验证
```yaml
# ❌ 错误：改了 project.yml 的 preBuildScripts 但没验证 frpc 下载
preBuildScripts:
  - name: Download frpc
    script: |
      bash "${SRCROOT}/scripts/assets/download-frpc.sh"
# 不验证就构建，可能 .app 里没 frpc

# ✅ 正确：构建后验证 frpc 在 .app/Contents/MacOS/frpc
ls Meilink.app/Contents/MacOS/frpc
```

## 5. 验证步骤

### 5.1 macOS 原生客户端
1. `xcodegen generate`
2. `xcodebuild -project Meilink.xcodeproj -scheme Meilink -configuration Release build`
3. 验证 `Meilink.app/Contents/MacOS/frpc` 存在 + 可执行
4. 验证 `Meilink.app/Contents/Resources/AppIcon.icns` 存在
5. 启动 `Meilink.app`，不显示 Dock，菜单栏出现图标

### 5.2 服务端 setup 工具 + macOS 原生客户端
1. `bash scripts/build/build-all.sh <version>`
2. 验证 `release/` 下产物完整（按 client/server 子目录组织）：
   - `release/server/meilink-setup-<ver>-linux-amd64.tar.gz`
   - `release/server/meilink-setup-<ver>-linux-arm64.tar.gz`
   - `release/client/macos-native/meilink-<ver>-macos-native.dmg`
3. 解压 setup tar.gz 验证含 `meilink-setup` + `README.txt`
4. 挂载 macOS DMG 验证含 `.app` + `Applications` 快捷方式

### 5.3 Tauri 桌面客户端
1. `bash scripts/build/build-desktop.sh --copy`
2. 验证 `release/client/desktop/` 下产物：
   - macOS：`meilink-desktop-<ver>-darwin-<arch>.dmg`
   - Linux：`.deb` / `.AppImage`
   - Windows：`.msi`
3. 启动应用验证 sidecar 正常 + 前端正常

### 5.4 服务端部署
1. 在 VPS 上 `bash server/bare-metal/deploy-frps.sh`
2. `sudo systemctl status frps` 验证 running
3. 或 `sudo ./meilink-setup setup` 走多 profile 流程（setup 工具源码在 `server/setup/`）

### 5.5 发布检查清单
- [ ] frp 版本三处同步
- [ ] 图标已更新 + `gen-icons.sh` 已重跑
- [ ] `release/` 旧产物已清理（CI `publish-release` 会自动清理；本地构建手动清理）
- [ ] `RELEASE_NOTES.md` 已更新
- [ ] macOS 原生客户端启动正常
- [ ] 跨平台客户端在对应平台 runner 上构建成功
- [ ] 服务端 setup 工具能正常部署
- [ ] `docker-images` CI job 已推送 GHCR（`meilink-client` / `meilink-server`，含 `:latest`）
- [ ] OCI 离线包已随 Release 附出且可 `docker load -i` 导入（amd64 + arm64）
- [ ] 升级路径：旧版本配置能被新版本读取
- [ ] SDD `07-build-release.md` 已同步
