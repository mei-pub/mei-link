# 客户端 UI 对齐 + 退出清理 + 服务端管理界面重构设计

> 日期：2026-08-05
> 状态：待 review

## 1. 背景

三个独立问题合并处理：
1. **原生端按钮布局与跨平台端对齐**：原生端 SettingsView 有「保存」「保存并重启」两个按钮，跨平台端已是「保存 + 确认弹框」。原生端要对齐成单按钮 + 确认弹框。
2. **ESC 关闭窗口**：原生端 SetupView/SettingsView/TunnelEditView 和跨平台端 settings/tunnel-edit 都不支持 ESC 关闭（原生是 NSWindow，cancelAction 对非 sheet 不可靠；跨平台无 keydown 监听）。
3. **退出清理彻底**：原生端 MenuBar 退出路径跳过 manager.stop()；跨平台端 Unix 下 quit_app 若 HTTP stop 失败，frpc 进程可能成为孤儿（无 POSIX 进程组 kill 兜底）。
4. **服务端管理界面重构**：现在太简陋（单页配置 + 状态侧栏），改为 Tab 三页：系统设置 / 域名接入管理 / 隧道状态与管理。隧道状态需启用 frps dashboard + 新增代理端点。

## 2. 客户端按钮对齐（原生端）

### 2.1 现状
- 跨平台端 `settings.html:142-151`：单「保存」按钮 + `customConfirm("保存后是否立即重启 frpc 隧道？")`，选项「保存并重启」/「仅保存」。
- 原生端 `SettingsView.swift:214-227`：「保存」（`restartAfterSave: false`）+「保存并重启」（`restartAfterSave: true`）两个独立按钮。

### 2.2 改动（原生端 SettingsView）
- 删除「保存并重启」按钮（`SettingsView.swift:222-227`）。
- 「保存」按钮点击 → 先调 `saveConfiguration(restartAfterSave: false)` 写配置，然后弹 `.confirmationDialog("保存后是否立即重启 frpc 隧道？")`：
  - 「保存并重启」（destructive/默认）→ `Task { await manager.restart() }` 再 close。
  - 「仅保存」→ 直接 close。
- 文案与跨平台端 `customConfirm` 完全一致：「保存后是否立即重启 frpc 隧道？」+「保存并重启」/「仅保存」。
- 复用现有 `showRestartConfirmation` 状态变量模式（参考已有的 `showQuitConfirmation` at SettingsView.swift:53）。

跨平台端不改（已是对齐的目标形态）。

## 3. ESC 关闭窗口

### 3.1 原生端
**问题**：所有窗口都是 NSWindow（非 sheet），`.keyboardShortcut(.cancelAction)` 对 NSWindow 不可靠，ESC 不关闭。

**方案**：在 `AppWindowController`（AppRuntime.swift）的窗口创建处，给每个目标窗口的 contentView 加一个本地 NSEvent 监听，捕获 Escape 调 `window.close()`。

具体：在 `showWindow` 工厂方法（AppRuntime.swift:394-409 附近，`makeKeyAndOrderFront` 后）安装 `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`，过滤 keyCode 53（Escape），调 `window.close()` 并 return nil（吞掉事件）。窗口关闭时在 `windowWillClose` 移除 monitor（用 NSWindow delegate 或存储 monitor token）。

目标窗口：SetupView、SettingsView、TunnelEditView（用户明确要求的三个）。主窗口/日志窗口不加（保持现有行为）。

**附带修复 SetupView dismiss bug**：SetupView 用 `@Environment(\.dismiss)`（SetupView.swift:82,154）在 NSWindow 上下文无效。给 SetupView 加 `onClose: (() -> Void)?`（像 SettingsView/TunnelEditView 那样），AppRuntime 在创建 setupWindow 时注入 `onClose = { self.setupWindow?.close() }`。取消/保存按钮改调 `close()`。

### 3.2 跨平台端
**问题**：settings.html、tunnel-edit.html 无 keydown 监听，ESC 不关闭。

**方案**：在两个 HTML 文件的 `<script>` 顶部加：
```js
document.addEventListener("keydown", (e) => { if (e.key === "Escape") closeWindow(); });
```
`closeWindow()`（api.js:283）已存在，hide 窗口。无需 Rust 改动（hide-on-close 已是行为）。

setup.html、logs.html 顺手也加（一致性），但用户明确要求的是设置/添加隧道/修改隧道。

## 4. 退出清理彻底

### 4.1 原生端
**问题**：MenuBarView 退出路径（MenuBarView.swift:195-198）只设 allowQuit + terminate，跳过 `manager.stop()`，依赖 `applicationWillTerminate` 的 `killFrpcOnExit`（已能 kill -9 兜底，但跳过优雅停止）。

**方案**：统一退出路径。提取一个 `performQuit()` 方法（放 MeilinkAppDelegate 或 AppRuntime），做完整序列：
1. `manager.stop()`（优雅停 timer + frpc.stop）
2. `allowQuit = true`
3. `NSApplication.shared.terminate(nil)`（触发 applicationWillTerminate → killFrpcOnExit 兜底）

MenuBarView 退出、SettingsView 完全退出、Cmd+Q 都调 `performQuit()`。这样三条路径行为一致，frpc 必被清理（stop → terminate → kill -9 三级）。

**Cmd+Q**：目前 `applicationShouldTerminate` 在 allowQuit=false 时取消，Cmd+Q 静默无效。改为：Cmd+Q 时也走 `performQuit()`（在 applicationShouldTerminate 里同步触发，或加主菜单 Quit 项指向 performQuit）。简化：让 applicationShouldTerminate 直接执行清理并返回 .terminateNow（不再 require allowQuit）。这样 Cmd+Q 也能干净退出。

### 4.2 跨平台端
**问题**：`quit_app`（lib.rs:137-157）在 Unix 下若 HTTP `/api/control/stop`（1.2s 超时）失败，`child.kill()` 只 SIGKILL sidecar，frpc 因无进程组绑定可能成孤儿（Windows 有 taskkill /T，Unix 无对应）。

**方案**：在 `stop_sidecar_tree`（lib.rs:31-40）加 Unix 分支，用 POSIX 进程组 kill 兜底。具体：
- sidecar 启动时（lib.rs 启动 sidecar 处）设 `setpgid(0,0)` 让 sidecar 成为进程组首（或 Rust 端 spawn 时设 process group）。但 sidecar 由 tauri-plugin-shell 启动，难直接设 pgid。
- 替代方案：`quit_app` 里记录 sidecar pid，Unix 下用 `nix::sys::signal::kill(Pgid::from_raw(pid), Signal::SIGTERM)` + 超时后 SIGKILL，杀整个进程组（sidecar + frpc 同组）。需 sidecar 启动时确认自己和 frpc 同一进程组（process_other.go 的 applyPlatformAttrs 是 no-op，frpc 继承 sidecar 的 pgid，天然同组——前提是 sidecar 自己是个 pgid 首，或与父进程同组）。
- 更稳妥：sidecar 启动后报告自己的 pgid（或 Rust 端 spawn 时通过 Command::process_group(0) 让 Tauri 给 sidecar 新建进程组）。Tauri 的 `tauri-plugin-shell` 不一定暴露 process_group，需核实。

**最小可行**：先在 `quit_app` 加：HTTP stop 后，Unix 下额外用 `kill -TERM <negative_pid>`（杀进程组）+ 0.5s 后 `kill -KILL <negative_pid>` 兜底。pid 取 sidecar 的 pid，假设 frpc 与 sidecar 同组（当前 process_other.go 不改 pgid，成立）。若 sidecar 非 pgid 首，退化为只杀 sidecar（与现状一致，不退化）。同时改 process_other.go 让 frpc spawn 时显式继承（已是默认），并在 sidecar main.go 启动时 `syscall.Setpgid(0,0)` 让 sidecar 成为 pgid 首——这样 frpc 与 sidecar 确定同组。

**验证**：退出后 `pgrep -f "frpc|meilink-desktop"` 应无输出。

## 5. 服务端管理界面重构

### 5.1 后端：启用 frps dashboard + 代理端点

#### 5.1.1 frps.toml 启用 dashboard
改 `config.ts`：
- `ServerConfig` 加可选字段：`dashboardPort`（默认 0=禁用）、`dashboardUser`、`dashboardPassword`。或固定启用，固定地址 `127.0.0.1`（只本机，不对外），随机/固定端口（如 7500），固定凭据。
- `renderFrpsToml` 输出 `webServer.addr = "127.0.0.1"`、`webServer.port = <固定>`、`webServer.user/password`。dashboard 只绑 127.0.0.1，外部访问不到（安全）。
- 凭据用环境变量 `MEILINK_DASHBOARD_USER/PASSWORD` 或固定值（dashboard 只本机访问，风险低；但代理端点会用它，所以需要可靠凭据）。

#### 5.1.2 新增代理端点（server.ts）
新增需登录认证的端点，服务端用 dashboard 凭据请求 frps 的 dashboard API，转发给前端：

| 端点 | 转发到 frps | 用途 |
|---|---|---|
| `GET /api/frps/serverinfo` | `GET /api/serverinfo` | 服务器信息（版本、proxyTypeCount、clientCounts、流量等） |
| `GET /api/frps/proxies` | `GET /api/proxy/{http,tcp,https,udp}` | 所有类型代理列表（合并） |

实现：服务端用 Node `fetch` 请求 `http://127.0.0.1:<dashboardPort>/api/...`，带 Basic Auth（dashboardUser:dashboardPassword）。失败（dashboard 未就绪/未启用）返回 `{error, proxies: []}`，前端友好降级。

dashboard API 已实测（frp v0.70.0）：`/api/serverinfo` 200、`/api/proxy/{http,tcp,https,udp}` 200、需 Basic Auth、`/healthz` 200。

#### 5.1.3 不暴露 dashboard 端口
docker-compose.yml 不映射 dashboard 端口（7500 仅容器内 127.0.0.1）。安全靠"只绑本机 + 不映射"。

### 5.2 前端：Tab 三页

#### 布局
登录后主页面：顶部 topbar（品牌 + frps 状态 + 重启/退出按钮，保持现有）。下方 Tab 切换三个页面。

```
┌─────────────────────────────────────────┐
│ topbar: Meilink Server · 状态 · 重启/退出 │
├─────────────────────────────────────────┤
│ [系统设置] [域名接入管理] [隧道状态]      │ ← Tab
├─────────────────────────────────────────┤
│                                         │
│         当前 Tab 内容                    │
│                                         │
└─────────────────────────────────────────┘
```

#### Tab 1: 系统设置
- frps 端口：bindPort / vhostHTTPPort / vhostHTTPSPort（现有 ports 表单）+ 特权端口提示（现有 portNotice）
- FRP Token（现有 authToken）
- 保存并应用按钮（复用现有 POST /api/config）
- 把现有的"服务端配置"卡片整体移到这个 Tab

#### Tab 2: 域名接入管理
- 现有的"域名与泛域名"区块（domain table + 添加域名 + 用途 select + 启用 checkbox）整体移到这个 Tab
- 增加说明卡片：解释主域名/泛域名/额外域名的区别和 DNS 配置要求（从现有 guide 提炼）
- 域名修改后保存（仍走 POST /api/config 整体保存）

#### Tab 3: 隧道状态
- **frps 进程状态**：运行中/PID/最后错误（现有 frpsState 指标）
- **服务器信息**：从 `/api/frps/serverinfo` 拉，显示 frp 版本、proxyTypeCount、clientCounts、运行时长、流量统计（格式化 bytes）
- **连接的代理列表**：从 `/api/frps/proxies` 拉，按类型分组（HTTP/TCP/HTTPS/UDP）显示表格：名称、状态、远程地址、客户端。自动刷新（每 5s 轮询）
- **运行日志**：现有 events 日志框移到这里（从右侧栏移到隧道状态 Tab 底部）
- dashboard 不可用时显示降级提示

#### 交互
- Tab 切换纯前端（JS 切 div 显示），不重新加载页面
- 每个进入 Tab 时刷新对应数据；隧道状态 Tab 开启 5s 轮询，离开 Tab 暂停轮询
- 保存操作（系统设置/域名管理）只在各自 Tab 内，保存后刷新

## 6. 文件清单

### 原生端
- `SettingsView.swift`：合并保存按钮 + 确认弹框
- `SetupView.swift`：加 onClose，修复 dismiss bug
- `MenuBarView.swift`：退出调统一 performQuit
- `MeilinkApp.swift`：performQuit 实现 + Cmd+Q 处理
- `AppRuntime.swift`：窗口 ESC 监听 + onClose 注入

### 跨平台端
- `src/settings.html`、`src/tunnel-edit.html`、`src/setup.html`、`src/logs.html`：加 ESC keydown
- `src-tauri/src/lib.rs`：quit_app 加 Unix 进程组 kill 兜底
- `sidecar/cmd/meilink/main.go`：启动时 Setpgid 确定进程组

### 服务端
- `server/docker-managed/src/config.ts`：ServerConfig 加 dashboard 字段 + renderFrpsToml 输出 webServer
- `server/docker-managed/src/manager.ts`：dashboard 配置传递
- `server/docker-managed/src/server.ts`：新增 /api/frps/serverinfo + /api/frps/proxies
- `server/docker-managed/web/index.html`：重构为 Tab 三页布局
- `server/docker-managed/web/app.js`：Tab 切换 + 隧道状态轮询 + 代理端点消费

## 7. 验证

### 原生端
1. swift build 通过
2. 设置窗口：保存按钮单按钮，点击弹确认框，两个选项都对
3. ESC 关闭设置/首次配置/添加隧道/修改隧道窗口
4. MenuBar 退出、设置完全退出、Cmd+Q 三路径都清理 frpc（pgrep 无残留）
5. SetupView 取消/保存按钮能关窗（修复 dismiss bug）

### 跨平台端
1. go build 通过
2. ESC 关闭设置/隧道编辑窗口
3. 退出后无 frpc/sidecar 残留（pgrep）

### 服务端
1. frps.toml 含 webServer.* 配置
2. /api/frps/serverinfo + /api/frps/proxies 返回数据（有客户端连接时）
3. 三个 Tab 切换正常，隧道状态 Tab 显示代理列表 + 5s 刷新
4. dashboard 未就绪时降级提示
5. 系统设置/域名管理保存仍正常

## 8. 不做（YAGNI）
- ❌ 不改窗口尺寸/状态色/状态文案（跨端契约）
- ❌ 不给 frps dashboard 对外暴露端口（仅容器内 127.0.0.1）
- ❌ 不做域名 per-row CRUD 端点（仍整体保存，够用）
- ❌ 不做服务端隧道启停控制（frps 不支持停单个 proxy；只能看）
