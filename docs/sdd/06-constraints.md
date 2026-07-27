# Meilink SDD · 06 · 关键约束

> 本文列出 Meilink 实现中不可违反的约束。修改代码前必读，避免破坏隐式契约。事实基线：`Meilink/` 下的 Swift 实现 + `Scripts/` + 根目录配置。

## 1. 平台约束

### 1.1 macOS 原生客户端
- **最低系统**：macOS 13.0（`project.yml` / `Info.plist` / `Package.swift` 三处对齐）
- **Xcode**：15.0+
- **Swift**：5.9
- **LSUIElement**：必须为 `true`（不显示 Dock，菜单栏常驻）
- **activationPolicy**：`.accessory`（与 LSUIElement 等效，双重保险）
- **disableAutomaticTermination / disableSuddenTermination**：应用启动时调用，防止后台被杀
- **Hardened Runtime**：`ENABLE_HARDENED_RUNTIME = true`（project.yml）
- **Code Sign**：`CODE_SIGN_STYLE = Automatic`
- **Bundle ID**：`vip.rego.meilink`（不能改，会破坏 Keychain 已存数据 + Login Items 注册）

### 1.2 跨平台客户端
- macOS：共享 `~/Library/Application Support/Meilink`，与原生客户端互通
- Windows / Linux：默认 `~/.meilink`
- Go 1.22+
- Tauri v2 + Rust + Web 前端

## 2. 安全约束

### 2.1 凭据存储
- `authToken` 必须存 Keychain（macOS）或 0600 权限 JSON 文件（跨平台）
- `frpc.toml` 文件权限必须 0600（`ConfigGenerator.writeToFile` 显式 `setAttributes`）
- `config.json` / `tunnels.json` / `settings.json` 当前未显式设权限，依赖 Application Support 目录默认权限
- Admin API Basic Auth 默认 `admin/admin`，用户可在设置里改

### 2.2 网络监听
- frpc Admin API (`webServer.addr`) **必须** `127.0.0.1`，不能对外
- 远程探活只对 frpc 返回的 `remoteAddr` 发起 TCP 连接，不接受用户输入的任意 URL
- `NetworkHelper.testConnection` 只对用户填的 `serverAddr:serverPort` 发起 TCP 握手，不传任何凭据

### 2.3 TLS
- `tlsEnabled` 默认 `true`（`ServerConfig.init` 默认值 + `SettingsView` / `SetupView` 默认 Toggle on）
- 注意 UI 文案明确："加密 frpc 到 frps 的控制连接，不等同于 HTTPS 隧道"

### 2.4 frpc 二进制完整性
- frpc 二进制由 `Scripts/download-frpc.sh` 在构建期从 GitHub release 下载（v0.70.0）
- 运行期不下载、不升级 frpc
- 二进制查找顺序：`Bundle.main.executableURL.deletingLastPathComponent()/frpc` → `Bundle.main.path(forResource: "frpc")`

## 3. 生命周期约束

### 3.1 关窗口不退出
- `applicationShouldTerminateAfterLastWindowClosed` 必须返回 `false`
- 关掉所有窗口后：frpc 仍跑、菜单栏仍在、状态轮询继续
- 重新打开（Dock/Spotlight 唤起）→ `applicationShouldHandleReopen` 显示主窗口

### 3.2 退出受 `allowQuit` 控制
- `MeilinkAppDelegate.allowQuit` 默认 `false`
- `applicationShouldTerminate` 据此返回 `terminateNow` 或 `terminateCancel`
- 只有以下路径设 `allowQuit = true`：
  - 设置面板"完全退出 Meilink"按钮（确认对话框后）
  - 菜单栏面板"退出"按钮
- 退出前必须：
  - `manager.stop()`（停止 frpc + 状态轮询）
  - `applicationWillTerminate` 调 `killFrpcOnExit`（强杀兜底）

### 3.3 启动后自动连接
- `TunnelManager.init` 末尾 `DispatchQueue.main.asyncAfter(0.5)` 调 `startIfNeeded`
- `startIfNeeded` 仅在 `isConfigured && !isFrpcRunning` 时执行 `restart`
- 启动后 0.3s 自动 `showMainWindow`（`MeilinkAppDelegate.start`）

### 3.4 frpc 进程停止逐级加强
- `FrpcProcess.stopImmediately`：terminate → 等 timeout → interrupt → sleep 0.5 → interrupt → sleep 0.5 → kill -9
- `TunnelManager.restart`：在 `stopImmediately(timeout: 3)` 之外再补 `kill -9` 兜底
- `killFrpcOnExit`：`stopImmediately(timeout: 2)` + 兜底 `kill -9`
- **不能省略 kill -9 兜底**：frpc 偶尔会卡在清理阶段，不 kill 会导致端口被占用、下次启动失败

### 3.5 端口释放
- `TunnelManager.releasePort` 使用 `lsof -ti :<port>` 找占用进程 + `kill -9`
- 当前实现里有此方法但未在任何主路径调用（保留给未来需要时使用）

## 4. 并发约束

### 4.1 MainActor 边界
- `TunnelManager` / `AppRuntime` / `StatusBarController` / `AppWindowController` 全部 `@MainActor`
- `@Published` 属性的读写必须在主线程
- `FrpcProcess` / `FrpcAdminAPI` / `TunnelReachabilityProbe` 非 MainActor，回调必须 `DispatchQueue.main.async` 派回

### 4.2 重入保护
- `isPollingStatus`：`pollStatus` 重入直接 return（防 Timer 触发 + 立即触发撞一起）
- `isRecovering`：`recoverConnection` 重入直接 return
- `LockedFlag`（探活）：continuation 只 resume 一次，防 NWConnection stateUpdateHandler 与超时定时器同时触发

### 4.3 自动恢复阈值（硬编码）
- `maxConsecutiveFailuresBeforeRecovery = 3`：连续 3 次失败才触发恢复
- `recoveryCooldown = 20` 秒：距上次恢复不足 20s 跳过
- `statusPollingInterval` 运行时 clamp `[3, 30]`（即使设置成 1 也按 3 跑）
- `remoteReachabilityInterval` 运行时 clamp `[30, 600]`
- frpc 非 0 退出后 sleep 2s 再恢复（防抖）
- 恢复前 sleep 1s（给进程退出留时间）

### 4.4 异步等 Admin API
- `start()` 用 `waitForAdminAPI`（async/await，5s 超时，500ms 间隔）
- `restart()` 用 `waitForAdminAPIAsync`（回调式，15s 超时）— restart 可能从非 async 上下文触发，回调式避免阻塞
- **超时即视为启动失败**：start 路径 `frpcProcess.stopImmediately()` + 置 `isFrpcRunning = false`；restart 路径仅记日志（因为 frpc 已在跑，后续轮询会自愈）

## 5. UI 不变量

### 5.1 状态色映射（不能改）
- running → green
- waitStart → yellow
- startError / checkFailed → red
- new / closed → gray
- 应用级：isConnected → green / isFrpcRunning → yellow / 其余 → gray

### 5.2 状态文案（不能改）
- 隧道：新建 / 连接中 / 启动失败 / 运行中 / 检查失败 / 已关闭
- 应用：已连接 / 连接中 / 未连接 / 未配置

### 5.3 窗口尺寸（跨平台对齐基线）
- 主窗口 1060×820（min 980×740）
- 设置 760×460
- 首次配置 560×640
- 隧道编辑 660×440
- 日志 820×620（min 760×560）
- 菜单栏面板 330×440

### 5.4 菜单栏图标 5 种风格
- portal / topology / arrow-ring / waveform / relay
- PNG 资源必须放在 `Meilink/Resources/<imageName>.png`
- 18×18 + `isTemplate = true`
- fallback 是 AppIcon

### 5.5 菜单栏面板行为
- borderless + nonactivatingPanel
- level = statusBar
- collectionBehavior = canJoinAllSpaces + transient + ignoresCycle
- 点面板外自动关（local + global mouse monitor）
- 箭头对齐按钮中心，offset clamp `[24, panelWidth - 24]`
- 默认下方，空间不够翻转上方

## 6. 数据契约不变量

### 6.1 持久化文件
- 目录：`~/Library/Application Support/Meilink/`（macOS）
- 文件：`tunnels.json` / `config.json` / `settings.json` / `frpc.toml`（运行期）/ `store.json`（frpc 写）
- 编码：JSONEncoder ISO8601 + prettyPrinted，JSONDecoder ISO8601
- 容错：load 失败返回默认值，不抛错
- 详见 `05-data-contract.md`

### 6.2 Keychain
- service = `com.meilink`（不能改，会破坏已存 token）
- account = `auth-token`
- accessible = `kSecAttrAccessibleWhenUnlocked`
- 覆盖式写入（先 delete 再 add）

### 6.3 frpc.toml 模板
- `webServer.addr` 永远 `127.0.0.1`
- `[store] path` 指向 `store.json`
- proxy 不写在 toml 里，通过 Store API 动态管理
- 文件权限 0600

### 6.4 Admin API 解码
- `decoder.keyDecodingStrategy = .convertFromSnakeCase`
- 超时 10s
- Basic Auth

### 6.5 frp 版本
- v0.70.0（`Scripts/download-frpc.sh` / `Scripts/build-frpc.sh` / `deploy-frps.sh` 三处硬编码）
- 升级 frp 版本必须三处同步修改 + 验证 frpc.toml schema 兼容性

## 7. 跨平台兼容约束

### 7.1 Swift 是 source of truth
- macOS 原生 Swift 客户端 (`Meilink/`) 是行为、视觉、数据、状态的事实基线
- 跨平台客户端（Tauri/Go）必须与 Swift 实现对齐
- 对齐范围：持久化 schema、状态机、frpc 交互模式、UI 信息架构、状态文案、窗口尺寸、菜单栏行为、自动恢复策略

### 7.2 数据互通
- macOS 上 Tauri 客户端与 Swift 客户端共享 `~/Library/Application Support/Meilink`
- Swift 写的 `config.json` / `tunnels.json` / `settings.json` 必须能被 Go 读取
- Go 写的也必须能被 Swift 读取
- **注意**：`tunnels.json` 里的 `status` / `errorMessage` / `remoteAddr` 字段是 Swift Codable 默认编码进去的运行期字段，Go 读取时不能据此判断状态（详见 `05-data-contract.md` §2.1）

### 7.3 不变量对齐
- 状态文案必须逐字对齐（中文）
- 状态色映射必须一致
- 窗口尺寸必须一致
- 关窗口不退出 / macOS 不显示 Dock / 点外部关面板 等 macOS 行为必须一致
- frpc.toml 生成规则必须一致（`webServer.addr = 127.0.0.1` / `[store]` 模式 / 0600 权限）

### 7.4 允许的差异
- 渲染细节（字体渲染、毛玻璃效果、阴影）
- 非 macOS 平台没有 Keychain 时的替代存储（0600 JSON）
- 非 macOS 平台没有 Login Items 时的替代（systemd / Windows Service）
- 非 macOS 平台的菜单栏图标实现差异（系统托盘）

### 7.5 跨平台默认目录
- macOS：`~/Library/Application Support/Meilink`
- Windows / Linux：`~/.meilink`
- 不能硬编码绝对路径，必须按平台判断

## 8. 构建约束

### 8.1 frpc 二进制集成
- macOS 原生客户端：`project.yml` 的 `preBuildScripts` 调 `Scripts/download-frpc.sh`，把 frpc 下载到 `.app/Contents/MacOS/frpc`
- 跨平台 Go 客户端：运行期自动下载对应平台 frpc
- Tauri 桌面客户端：Go sidecar 内嵌 frpc 下载逻辑

### 8.2 图标资源
- 源：`Meilink/Resources/AppIcon.png`（1254×1254）
- `Scripts/gen-icons.sh` 派生 Windows ICO + .syso + Linux PNG
- `Meilink/Resources/AppIcon.icns` 直接复用
- 修改源图标后必须重跑 `gen-icons.sh`

### 8.3 版本号
- `CFBundleShortVersionString`（Info.plist + project.yml）：`1.0.0`
- 发布版本号（`Scripts/build-all.sh` 第一个参数）：默认 `1.1.0`
- 两者不一致是历史遗留，新的发布流程以 `build-all.sh` 的 `VERSION` 为准

详见 `07-build-release.md`。

## 9. 不可降级的体验约束

以下约束来自用户预期，违反会显著伤害体验：

1. **关窗口后必须仍能从菜单栏恢复主窗口**
2. **退出时必须确保 frpc 完全终止**（否则端口泄漏、下次启动失败）
3. **frpc 异常退出必须自动恢复**（不能让用户手动重启）
4. **外网不可达必须能检测到**（不能只看 frpc status）
5. **Token 必须安全存储**（不能明文写到普通文件）
6. **未配置时必须引导用户**（自动打开 Setup 窗口）
7. **菜单栏图标必须跟随系统深浅色**（`isTemplate = true`）
8. **面板点外部必须自动关**（macOS 用户预期）
