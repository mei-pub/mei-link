# Meilink SDD · 04 · UI 设计

> 本文记录 Meilink macOS 原生客户端的 UI 设计基线：窗口规格、各窗口结构、组件样式、配色、文案、图标。跨平台客户端必须与此对齐（允许细微渲染差异）。事实基线：`client/macos-native/UI/` 下的 SwiftUI 实现。

## 1. 窗口规格

| 窗口 | 视图 | Swift 尺寸（内容区） | Tauri 尺寸（含标题栏） | 最小尺寸 | styleMask | 标题 |
|---|---|---|---|---|---|---|
| 主窗口 | `MainWindow` | 1060×820 | 1060×820 | minWidth 980, minHeight 740 | titled+closable+miniaturizable+resizable | `Meilink` |
| 设置 | `SettingsView` | 760×460 | 760×737 | — | 同上 | `设置` |
| 首次配置 | `SetupView` | 560×640 | 560×597 | — | 同上 | `首次配置` |
| 隧道编辑 | `TunnelEditView` | 660×440 | 660×565 | minWidth 600, minHeight 505 | 同上 | `添加新隧道` / `编辑隧道` |
| 日志 | `LogWindowView` | 820×620 | 820×620 | minWidth 760, minHeight 560 | 同上 | `日志` |
| 菜单栏面板 | `MenuBarView` | 330×440 | 330×440 | — | borderless + nonactivatingPanel | — |

> **Swift vs Tauri 尺寸差异**：Swift `NSWindow` 的 `contentRect` 是内容区高度，用 `fixedSize(horizontal: false, vertical: true)` 让窗口垂直自适应内容。Tauri 窗口 `height` 是总高度（含 macOS 标题栏 28px），且需手动设成内容实际需要的高度（Swift 自适应，Tauri 不自适应）。Tauri 尺寸 = 实际内容高度 + 标题栏 28px。

引用：<kfile name="AppRuntime.swift" path="client/macos-native/App/AppRuntime.swift">AppRuntime.swift</kfile> 的 `AppWindowController`。

## 2. 全局视觉语言

### 2.1 配色
- 状态色（`TunnelStatus.tintColor`）：
  - running → `.green`
  - waitStart → `.yellow`
  - startError / checkFailed → `.red`
  - new / closed → `.gray`
- 应用级状态圆点：
  - `isConnected` → green
  - `isFrpcRunning && !isConnected` → yellow
  - 其余 → gray
- 日志级别色：
  - info → `.blue`，图标 `info.circle`
  - warning → `.orange`，图标 `exclamationmark.triangle`
  - error → `.red`，图标 `xmark.octagon`
- 卡片背景：`Color(nsColor: .controlBackgroundColor)` 或 `Color.secondary.opacity(0.07-0.08)`
- 主容器背景：`Color(nsColor: .windowBackgroundColor)`（TunnelEditView 显式设置）
- 弹出面板背景：`.regularMaterial`（毛玻璃）

### 2.2 圆角
- 卡片：`cornerRadius(10, style: .continuous)`
- 表单内卡片：`cornerRadius(10, style: .continuous)`
- 主窗口 appLogo：`RoundedRectangle(cornerRadius: 9, style: .continuous)`
- 隧道编辑 footer：`.regularMaterial` 背景
- 菜单栏 popover 内容：`RoundedRectangle(cornerRadius: 16, style: .continuous)` + `.shadow(black 0.22, radius 18, y 8)`

### 2.3 字体
- 标题：`.title2` bold（主窗口）、`.title3` semibold（日志）、`.title3` bold（DNS 引导）
- 副标题/说明：`.caption`，`.secondary`
- 表单项标题：`.subheadline`，`.primary`
- 列表行名称：`.body` medium（TunnelListRow）/ `.subheadline` semibold（MenuBarView）
- 类型标签：`.caption2` semibold，`.secondary`，大写
- 时间戳：`.system(.caption, design: .monospaced)`，`.secondary`

## 3. 主窗口（MainWindow）

### 3.1 结构
```
VStack
├── header（padding 20）
│   ├── HStack
│   │   ├── appLogo（42×42 圆角9）+ 标题/副标题
│   │   └── 状态指示（128×46）+ 连接/断开 + 重启 + 设置 按钮（104×46）
├── Divider
├── tunnelList
│   ├── 空状态：图标 + "还没有隧道" + 说明 + 添加按钮
│   └── List（Section + header）
└── Divider + footer（padding horizontal 20, vertical 12）
    ├── 添加隧道（124×32 bordered）
    ├── Spacer
    ├── "<启用>/<总数> 个隧道启用" caption
    ├── 查看日志（112×32 bordered）
    └── 清空日志（104×32 bordered）
```

### 3.2 Header 按钮规格
- 按钮 width 104，height 46
- 背景 `Color.secondary.opacity(0.08)`，`cornerRadius(8)`
- `.buttonStyle(.plain)`
- 文案：
  - `isFrpcRunning` → "断开" + `stop.fill`
  - 否则 → "连接" + `play.fill`
  - "重启" + `arrow.clockwise`
  - "设置" + `gear`
- `disabled(!manager.isConfigured)`

### 3.3 隧道列表行（TunnelListRow）
列宽固定：
- 名称列：150（状态圆点 8×8 + 名称 medium）
- 本地列：120（类型大写 caption2 + `localIP:localPort` caption）
- 外网访问列：自适应（routeText + errorMessage 红字 或 shortRouteText secondary）
- 状态列：80（displayName + tintColor）
- 操作：复制（`doc.on.doc`）/ 打开（`arrow.up.right.square`）/ Toggle / Menu（`ellipsis.circle`）

## 4. 设置窗口（SettingsView）

### 4.1 结构
```
VStack
├── VStack（padding 16）
│   ├── serverCard（settingsSection "服务器配置"）
│   └── appCard（settingsSection "应用设置"）
├── saveError 提示行（caption red）
├── Divider
└── footer（padding 16）
    ├── 保存（`checkmark`）
    ├── 保存并重启（`arrow.clockwise`）
    ├── Spacer
    └── 关闭
```

### 4.2 settingsSection / settingsRow
- `settingsSection`：`headline` 标题 + `controlBackgroundColor` 卡片（padding 16, cornerRadius 10）
- `settingsRow`：左侧 96 宽标题（`.subheadline` primary） + 右侧内容，HStack spacing 14

### 4.3 服务器配置项
- 服务器地址：TextField 200 宽 + "测试连接"按钮 + 结果 Label
- 客户端端口：TextField 120 宽
- 管理端口：TextField 120 宽
- 认证 Token：TextField/SecureField 切换 + 眼睛按钮
- 子域名基域：TextField
- TLS 连接：Toggle + 说明文字"加密 frpc 到 frps 的控制连接，不等同于 HTTPS 隧道。"

### 4.4 应用设置项
- 开机自启动：Toggle + 说明 + `onChange` 即时调 `AutoStartManager`
- 菜单栏图标：5 个按钮横排（52 宽卡片，22×22 图标 + 9pt 名称），选中态 `Color.accentColor.opacity(0.12)` 背景，"重建图标"按钮
- 远程探测间隔：Stepper（30-600 step 15）+ 说明
- 退出程序：destructive 按钮"完全退出 Meilink" + `confirmationDialog`

## 5. 首次配置窗口（SetupView）

```
VStack（spacing 20, padding 24, width 480）
├── "欢迎使用 Meilink" title2 bold
├── "请配置你的 VPS 服务器信息" secondary
├── Form（grouped）
│   ├── Section "服务器信息"：地址 / 端口（80 宽）/ SecureField Token
│   ├── Section "子域名配置"：基域 TextField + DNS 泛解析提示 caption
│   └── Section：Toggle "启用 TLS 加密连接"
├── 测试结果行（check/xmark 图标 + 文案）
└── HStack：取消 / Spacer / 测试连接 / 保存
```

校验：`serverAddr` 非空才能测；`serverAddr/authToken/subDomainHost` 非空才能保存。

## 6. 隧道编辑窗口（TunnelEditView）

```
VStack
├── ScrollView
│   └── VStack（spacing 16, padding 20）
│       ├── formSection "基本信息"：名称 + 类型（segmented）
│       ├── formSection "本地配置"：本地端口（128）+ 本地地址
│       ├── formSection "远程配置"：
│       │   ├── HTTP/HTTPS → 子域名
│       │   └── TCP/UDP → 远程端口（160，留空自动分配）
│       └── formSection "状态"：启用 Toggle
└── footer（padding horizontal 28, vertical 16, .regularMaterial）
    ├── 取消（cancelAction）
    ├── Spacer
    └── 保存/创建（defaultAction）
```

- `formSection`：`headline` semibold + `Color.secondary.opacity(0.07)` 卡片（padding h16 v8, cornerRadius 10）
- `formRow`：92 宽标题 + 内容，固定 46 高，底部 Divider（左 padding 108）
- `canSave`：name 非空 + localPort 是数字 + 未在保存

## 7. 日志窗口（LogWindowView）

```
VStack
├── header（padding 18）：doc.text.magnifyingglass 图标 + "运行日志" title3 + "<n> 条事件..." caption + 复制全部 + 导出
├── Divider
├── content
│   ├── 空状态：tray 图标 + "暂无日志"
│   └── Table（events, selection）
│       ├── TableColumn "时间"（width 148, monospaced caption）
│       ├── TableColumn "级别"（width 92, Label + 颜色）
│       └── TableColumn "内容"（lineLimit 3, textSelection enabled）
│       └── contextMenu：复制选中 / 复制全部
└── Divider + footer（padding 14）：statusMessage + 复制选中 + 清空日志（destructive）
```

- 导出：`NSSavePanel`，默认文件名 `meilink-logs-<yyyyMMdd-HHmmss>.log`，`.plainText`
- 格式：`[yyyy-MM-dd HH:mm:ss] [级别] 消息`，按时间正序

## 8. 菜单栏面板（MenuBarView）

### 8.1 外壳（MenuBarPanelChrome）
```
VStack
├── HStack（width 330, height 12）
│   ├── Spacer（width = max(0, arrowOffset - 9)）
│   ├── Triangle（18×12，.regularMaterial）
│   └── Spacer
└── content（clipShape RoundedRectangle 16, shadow black0.22 r18 y8）
```

- 整体 330×440，top 对齐
- 箭头 offset = `clamp(buttonFrame.midX - originX, 24, panelSize.width - 24)`

### 8.2 内容（MenuBarView）
```
VStack（spacing 14, padding 14, width 330, .regularMaterial）
├── statusHeader（padding 12, controlBackgroundColor, cornerRadius 10）
│   ├── 状态圆点 + 标题/副标题 + 启停按钮（26×26 bordered small）
├── activeTunnels
│   ├── "隧道" caption + "<n> 个启用"
│   ├── 空状态：tray + "暂无启用隧道" + "添加" borderless
│   └── 每条：卡片（controlBackgroundColor, cornerRadius 10）
│       ├── 名称 + 状态
│       ├── 类型图标 + routeText
│       └── 复制 / 打开 按钮（bordered small）
└── controlButtons
    ├── HStack：主窗口 / 日志
    └── HStack：设置 / 重启 / 退出
```

### 8.3 文案
- statusTitle：`isConnected` → "已连接" / `isFrpcRunning` → "连接中" / `isConfigured` → "未连接" / 否则 "未配置"
- serverSubtitle：`<addr>:<port> · <subDomainHost>` 或 "请先完成服务器配置"
- 控制按钮：主窗口（`rectangle.stack`）/ 日志（`doc.text.magnifyingglass`）/ 设置（`gear`）/ 重启（`arrow.clockwise`）/ 退出（`power`）

## 9. 菜单栏图标

### 9.1 5 种风格
| style | rawValue | imageName | displayName |
|---|---|---|---|
| portal | portal | `portal` | 门户 |
| topology | topology | `topology` | 拓扑 |
| arrowRing | arrowRing | `arrow-ring` | 穿透 |
| waveform | waveform | `waveform` | 信号 |
| relay | relay | `relay` | 中继 |

### 9.2 加载
- 路径：`Bundle.main.path(forResource: imageName, ofType: "png")`
- 尺寸：18×18
- `isTemplate = true`（跟随系统深浅色 + 用户强调色）
- fallback：`AppIconProvider.image`（应用图标）

### 9.3 PNG 资源
位于 `client/macos-native/Resources/`，每个风格对应一个 18×18 左右的 template PNG。

## 10. 状态文案汇总

### 10.1 隧道状态
- new → "新建"
- waitStart → "连接中"
- startError → "启动失败"
- running → "运行中"
- checkFailed → "检查失败"
- closed → "已关闭"

### 10.2 应用级状态
- "已连接" / "连接中" / "未连接" / "未配置"

### 10.3 日志级别
- info → "信息"
- warning → "警告"
- error → "错误"

### 10.4 空状态
- 主窗口隧道空："还没有隧道" + "添加一个 HTTP、HTTPS、TCP 或 UDP 隧道，把本机服务发布出去。"
- 菜单栏隧道空："暂无启用隧道" + "添加"
- 日志空："暂无日志" + "连接检测、自动重连和配置变更会显示在这里。"

## 11. 交互不变量（跨平台必须对齐）

1. 关窗口不退出（`applicationShouldTerminateAfterLastWindowClosed = false`）
2. macOS 不显示 Dock（`LSUIElement = true` / `activationPolicy = .accessory`）
3. 菜单栏面板点外部自动关（local + global mouse monitor）
4. 菜单栏面板按 statusBar level 显示，跨 Space（`canJoinAllSpaces + transient`）
5. 重新打开应用（Dock/Spotlight）→ 显示主窗口
6. 只有显式"退出"才真正退出（`allowQuit` 标志）
7. 退出时强杀 frpc（`killFrpcOnExit`）
8. 应用启动 0.5s 后自动 `startIfNeeded`
9. 启动后 0.3s 自动显示主窗口
10. 未配置时自动打开 Setup 窗口

## 12. 图标资源

### 12.1 应用图标
- `client/macos-native/Resources/AppIcon.icns`（1.7MB，macOS .app 用）
- `client/macos-native/Resources/AppIcon.png`（1.39MB，1254×1254，构建脚本派生 Windows ICO / Linux PNG 的源）
- `client/macos-native/Resources/app-icon.png`（小尺寸占位）
- `Assets.xcassets`（Xcode 集成用）

### 12.2 菜单栏 PNG
- `portal.png` / `topology.png` / `arrow-ring.png` / `waveform.png` / `relay.png`（5 个风格）
- `link.png` / `link-chain.png` / `link-badge-plus.png`（备选）
- `globe.png` / `node.png` / `signal.png` / `bridge.png` / `pipeline.png` / `play.png` / `stop.png` / `tunnel.png`（扩展备选）

### 12.3 跨平台派生
- `scripts/assets/gen-icons.sh` 从 `AppIcon.png` 派生，输出到 `client/desktop/sidecar/`：
  - Windows `app.ico` + `resource_windows_amd64.syso`（Windows 资源对象，供桌面客户端 Windows 构建使用）
  - Linux `meilink.png`（256×256）
