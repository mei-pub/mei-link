# Agent Rule · 修改 UI

> **何时触发**：当任务涉及修改任何 SwiftUI 视图（MainWindow / SettingsView / SetupView / TunnelEditView / LogWindowView / MenuBarView / TunnelListRow / TunnelRowView）、窗口尺寸、状态色、状态文案、菜单栏面板行为、应用生命周期行为时。

> **必读 SDD**：[../sdd/04-ui-design.md](../sdd/04-ui-design.md)（UI 设计基线）、[../sdd/06-constraints.md](../sdd/06-constraints.md) §5（UI 不变量）。

## 1. 涉及文件清单

### 1.1 Swift 原生客户端（`Meilink/UI/`）
- <kfile name="MainWindow.swift" path="Meilink/UI/Main/MainWindow.swift">Meilink/UI/Main/MainWindow.swift</kfile> — 主窗口
- <kfile name="TunnelListRow.swift" path="Meilink/UI/Main/TunnelListRow.swift">Meilink/UI/Main/TunnelListRow.swift</kfile> — 隧道列表行
- <kfile name="TunnelEditView.swift" path="Meilink/UI/Main/TunnelEditView.swift">Meilink/UI/Main/TunnelEditView.swift</kfile> — 隧道编辑
- <kfile name="LogWindowView.swift" path="Meilink/UI/Main/LogWindowView.swift">Meilink/UI/Main/LogWindowView.swift</kfile> — 日志窗口
- <kfile name="EventLogView.swift" path="Meilink/UI/Main/EventLogView.swift">Meilink/UI/Main/EventLogView.swift</kfile> — 事件日志（内联版）
- <kfile name="SettingsView.swift" path="Meilink/UI/Settings/SettingsView.swift">Meilink/UI/Settings/SettingsView.swift</kfile> — 设置面板
- <kfile name="SetupView.swift" path="Meilink/UI/Setup/SetupView.swift">Meilink/UI/Setup/SetupView.swift</kfile> — 首次配置
- <kfile name="DNSGuideView.swift" path="Meilink/UI/Setup/DNSGuideView.swift">Meilink/UI/Setup/DNSGuideView.swift</kfile> — DNS 引导
- <kfile name="MenuBarView.swift" path="Meilink/UI/MenuBar/MenuBarView.swift">Meilink/UI/MenuBar/MenuBarView.swift</kfile> — 菜单栏面板内容
- <kfile name="MenuBarStatusItem.swift" path="Meilink/UI/MenuBar/MenuBarStatusItem.swift">Meilink/UI/MenuBar/MenuBarStatusItem.swift</kfile> — 菜单栏状态项
- <kfile name="TunnelRowView.swift" path="Meilink/UI/MenuBar/TunnelRowView.swift">Meilink/UI/MenuBar/TunnelRowView.swift</kfile> — 菜单栏隧道行

### 1.2 窗口控制器
- <kfile name="AppRuntime.swift" path="Meilink/App/AppRuntime.swift">Meilink/App/AppRuntime.swift</kfile>
  - `AppWindowController`：5 个窗口的尺寸 + 标题
  - `StatusBarController`：菜单栏 + popover 安装 / 位置 / 自动关闭
  - `MenuBarPanelChrome`：箭头 + 圆角 + 阴影
- <kfile name="MeilinkApp.swift" path="Meilink/App/MeilinkApp.swift">Meilink/App/MeilinkApp.swift</kfile>
  - `applicationShouldTerminateAfterLastWindowClosed = false`
  - `applicationShouldHandleReopen` 显示主窗口
  - `applicationShouldTerminate` 受 `allowQuit` 控制
  - `setActivationPolicy(.accessory)`

### 1.3 跨平台客户端
- `cross-platform-client/desktop/src/*.html` — 前端页面
- `cross-platform-client/desktop/src/styles/app.css` — 样式
- `cross-platform-client/desktop/src-tauri/src/lib.rs` — Rust 壳（窗口 + 托盘 + popover）
- `cross-platform-client/desktop/src-tauri/tauri.conf.json` — 窗口配置

### 1.4 SDD 文档
- [../sdd/04-ui-design.md](../sdd/04-ui-design.md)（必须同步）
- [../sdd/06-constraints.md](../sdd/06-constraints.md) §5（UI 不变量）

## 2. 必读不变量

### 2.1 窗口尺寸（跨平台对齐基线，不能改）
| 窗口 | 尺寸 |
|---|---|
| 主窗口 | 1060×820（min 980×740） |
| 设置 | 760×460 |
| 首次配置 | 560×640 |
| 隧道编辑 | 660×440 |
| 日志 | 820×620（min 760×560） |
| 菜单栏面板 | 330×440 |

尺寸定义在 `AppWindowController.showWindow` / `showPanel`。

### 2.2 状态色映射（不能改）
- running → green
- waitStart → yellow
- startError / checkFailed → red
- new / closed → gray
- 应用级：isConnected → green / isFrpcRunning → yellow / 其余 → gray

定义在 `TunnelStatus.tintColor` + 各 View 的 `statusColor`。

### 2.3 状态文案（不能改，跨平台逐字对齐）
- 隧道：新建 / 连接中 / 启动失败 / 运行中 / 检查失败 / 已关闭
- 应用：已连接 / 连接中 / 未连接 / 未配置
- 日志级别：信息 / 警告 / 错误

定义在 `TunnelStatus.displayName` + 各 View 的 `statusTitle`。

### 2.4 应用级状态判定逻辑
```swift
var statusText: String {
    if manager.isConnected { return "已连接" }
    if manager.isFrpcRunning { return "连接中" }
    if manager.isConfigured { return "未连接" }
    return "未配置"
}
```

判定顺序不能变。`isConnected` 优先于 `isFrpcRunning` 优先于 `isConfigured`。

### 2.5 生命周期行为（不能改）
1. `applicationShouldTerminateAfterLastWindowClosed` 返回 `false`（关窗口不退出）
2. `setActivationPolicy(.accessory)`（不显示 Dock）
3. `applicationShouldHandleReopen` 显示主窗口（Dock/Spotlight 唤起）
4. `applicationShouldTerminate` 受 `allowQuit` 控制（只有显式"退出"才退出）
5. 启动后 0.3s 自动 `showMainWindow`
6. `MenuBarView.onAppear` 检测 `!isConfigured` 自动打开 Setup

### 2.6 菜单栏面板行为（不能改）
- borderless + nonactivatingPanel
- level = statusBar
- collectionBehavior = canJoinAllSpaces + transient + ignoresCycle
- 点面板外自动关（local + global mouse monitor）
- 箭头对齐按钮中心，offset clamp `[24, panelWidth - 24]`
- 默认下方，空间不够翻转上方
- `isReleasedWhenClosed = false`

### 2.7 应用图标
- `Meilink/Resources/AppIcon.icns`（macOS .app）
- `Meilink/Resources/AppIcon.png`（1254×1254，跨平台派生源）
- 修改源图标后必须重跑 `Scripts/gen-icons.sh`

## 3. 同步修改清单

### 3.1 改窗口尺寸
- [ ] `AppRuntime.swift`：`AppWindowController.showXxxWindow` 的 `size` 参数
- [ ] 对应 View 的 `.frame(minWidth:, minHeight:)` 或 `.frame(width:)`
- [ ] 跨平台：`tauri.conf.json` 的窗口尺寸 + `lib.rs` 的 popover 尺寸同步
- [ ] SDD：`04-ui-design.md` §1 表格同步

### 3.2 改状态色
- [ ] `TunnelDisplay.swift`：`TunnelStatus.tintColor`
- [ ] `TunnelRowView.swift`：`statusColor`
- [ ] `MainWindow.swift` / `MenuBarView.swift`：应用级状态圆点
- [ ] 跨平台：`app.css` 的状态色变量同步
- [ ] SDD：`04-ui-design.md` §2.1 + `06-constraints.md` §5.1 同步

### 3.3 改状态文案
- [ ] `Tunnel.swift`：`TunnelStatus.displayName`
- [ ] 各 View 的 `statusTitle` / `statusText`
- [ ] 跨平台：`STATUS_LABELS` 常量同步
- [ ] SDD：`04-ui-design.md` §10 + `06-constraints.md` §5.2 同步

### 3.4 改菜单栏面板行为
- [ ] `AppRuntime.swift`：`StatusBarController.showPanel` / `installEventMonitors` / `MenuBarPanelChrome`
- [ ] 不能去掉点外部自动关（local + global mouse monitor）
- [ ] 不能去掉 `isReleasedWhenClosed = false`
- [ ] 不能改 level / collectionBehavior
- [ ] 跨平台：`lib.rs` 的 popover 几何 + 自动关闭同步
- [ ] SDD：`04-ui-design.md` §8 + `06-constraints.md` §5.5 同步

### 3.5 改生命周期行为
- [ ] `MeilinkApp.swift`：`applicationShouldTerminateAfterLastWindowClosed` / `applicationShouldHandleReopen` / `applicationShouldTerminate` / `setActivationPolicy`
- [ ] `project.yml` + `Info.plist`：`LSUIElement = true`
- [ ] 不能改 `disableAutomaticTermination` / `disableSuddenTermination`
- [ ] 跨平台：`lib.rs` 的 activation policy + `tauri.conf.json` 同步
- [ ] SDD：`06-constraints.md` §1.1 / §3 同步

### 3.6 改应用图标
- [ ] `Meilink/Resources/AppIcon.png`（1254×1254 源）
- [ ] `Meilink/Resources/AppIcon.icns`（macOS .app）
- [ ] 重跑 `Scripts/gen-icons.sh`（派生 Windows ICO + Linux PNG）
- [ ] SDD：`04-ui-design.md` §12 同步

### 3.7 新增菜单栏图标风格
- 见 [adding-menubar-icon.md](./adding-menubar-icon.md)

## 4. 反例

### 4.1 反例：关窗口退出
```swift
// ❌ 错误：关掉主窗口就退出应用
func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
}

// ✅ 正确：关窗口不退出
func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
}
```

### 4.2 反例：显示 Dock
```swift
// ❌ 错误：regular 策略会显示 Dock
app.setActivationPolicy(.regular)

// ✅ 正确：accessory 不显示 Dock
app.setActivationPolicy(.accessory)
```

### 4.3 反例：改状态文案不一致
```swift
// ❌ 错误：Swift 用"运行中"，跨平台用"已连接"
Text("已连接")  // 应该是"运行中"

// ✅ 正确：按 04-ui-design.md §10 的文案
Text(tunnel.status.displayName)  // "运行中"
```

### 4.4 反例：菜单栏面板点外部不关
```swift
// ❌ 错误：去掉 event monitor，面板只能手动点关闭按钮
private func showPanel(...) {
    // 不安装 monitor
}

// ✅ 正确：local + global monitor
installEventMonitors(for: panel)
```

### 4.5 反例：状态判定顺序错
```swift
// ❌ 错误：isFrpcRunning 优先于 isConnected，会显示"连接中"而非"已连接"
var statusText: String {
    if manager.isFrpcRunning { return "连接中" }
    if manager.isConnected { return "已连接" }
    // ...
}

// ✅ 正确：isConnected 优先
var statusText: String {
    if manager.isConnected { return "已连接" }
    if manager.isFrpcRunning { return "连接中" }
    // ...
}
```

### 4.6 反例：改窗口尺寸但不改跨平台
```swift
// ❌ 错误：只改 Swift 的窗口尺寸，跨平台 Tauri 不同步
settingsWindow = showWindow(..., size: NSSize(width: 800, height: 500)) { ... }
// tauri.conf.json 还是 760×460

// ✅ 正确：同步改两边 + SDD
settingsWindow = showWindow(..., size: NSSize(width: 800, height: 500)) { ... }
// tauri.conf.json 也改成 800×500
// 04-ui-design.md §1 表格同步
```

## 5. 验证步骤

1. `swift build` 编译通过
2. 启动应用 → 不显示 Dock（LSUIElement 生效）
3. 关主窗口 → 应用不退出，菜单栏仍在
4. Dock/Spotlight 唤起 → 主窗口重新显示
5. 点菜单栏图标 → 面板弹出，箭头对齐按钮
6. 点面板外 → 面板自动关
7. 状态文案 / 颜色与 [../sdd/04-ui-design.md](../sdd/04-ui-design.md) §10 / §2.1 一致
8. 跨客户端（如已构建 Tauri 版本）行为一致
9. 隧道状态变化时菜单栏图标颜色跟着变（green/yellow/gray）
10. 退出时通过显式"退出"按钮，不能通过关窗口
