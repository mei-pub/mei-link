# Agent Rule · 新增菜单栏图标风格

> **何时触发**：当任务要求在 `portal / topology / arrow-ring / waveform / relay` 五种风格之外新增第 6 种菜单栏图标风格时。

> **必读 SDD**：[../sdd/04-ui-design.md](../sdd/04-ui-design.md) §9（菜单栏图标）、[../sdd/05-data-contract.md](../sdd/05-data-contract.md) §4.1（MenuBarIconStyle 枚举）。

## 1. 涉及文件清单

### 1.1 Swift 原生客户端
- <kfile name="AppSettings.swift" path="Meilink/Models/AppSettings.swift">Meilink/Models/AppSettings.swift</kfile>
  - `MenuBarIconStyle` 枚举：加 case + `displayName` + `imageName`
- <kfile name="AppRuntime.swift" path="Meilink/App/AppRuntime.swift">Meilink/App/AppRuntime.swift</kfile>
  - `StatusBarController.menuBarImage`：从 `Bundle.main` 加载 PNG
- <kfile name="SettingsView.swift" path="Meilink/UI/Settings/SettingsView.swift">Meilink/UI/Settings/SettingsView.swift</kfile>
  - "菜单栏图标"行：5 个按钮横排，加新按钮
- <kfile name="MenuBarStatusItem.swift" path="Meilink/UI/MenuBar/MenuBarStatusItem.swift">Meilink/UI/MenuBar/MenuBarStatusItem.swift</kfile>
  - `style` 字段类型是 `MenuBarIconStyle`，自动支持新值

### 1.2 资源
- `Meilink/Resources/<imageName>.png` — 必须新增
  - 尺寸：18×18 左右
  - 格式：PNG，`isTemplate = true`（跟随系统深浅色 + 强调色）
  - 设计：黑色线条 + 透明背景，避免彩色

### 1.3 跨平台客户端
- `cross-platform-client/desktop/src-tauri/src/lib.rs` — 系统托盘图标加载
- `cross-platform-client/desktop/src/settings.html` — 设置页图标选择器
- `cross-platform-client/desktop/src/public/icons/` — 跨平台 PNG 资源

### 1.4 SDD 文档
- [../sdd/04-ui-design.md](../sdd/04-ui-design.md) §9（菜单栏图标）
- [../sdd/05-data-contract.md](../sdd/05-data-contract.md) §4.1（MenuBarIconStyle）

## 2. 必读不变量

### 2.1 PNG 资源规格
- 尺寸：18×18 像素（运行期 `image.size = NSSize(width: 18, height: 18)`）
- `isTemplate = true`：跟随系统深浅色 + 用户强调色
- 黑色线条 + 透明背景：template 图标默认按系统前景色渲染
- 避免彩色：彩色 template 图标在深色模式会看不清

### 2.2 `MenuBarIconStyle` 枚举约束
- `String` rawValue + `Codable` + `CaseIterable` + `Identifiable` + `Sendable`
- `id` = rawValue
- `displayName`：中文名（2-3 字）
- `imageName`：与 PNG 文件名（不带扩展名）一致

### 2.3 SettingsView 布局约束
- 5 个按钮横排，每个 52 宽（22×22 图标 + 9pt 名称）
- 选中态：`Color.accentColor.opacity(0.12)` 背景 + 8 圆角
- 加第 6 个会换行（HStack spacing 8），需要测试布局不溢出

### 2.4 默认值
- `MenuBarIconStyle.portal` 是默认值（`AppSettings.menuBarIconStyle = .portal`）
- 新增风格不能改默认值（会破坏老用户设置）

## 3. 实施步骤

### 3.1 准备 PNG 资源
1. 设计 18×18 黑色线条图标，透明背景
2. 导出为 PNG，命名 `<imageName>.png`（如 `network.png`）
3. 放到 `Meilink/Resources/`
4. 跨平台同步：复制到 `cross-platform-client/desktop/src/public/icons/`

### 3.2 修改 `MenuBarIconStyle` 枚举
<kfile name="AppSettings.swift" path="Meilink/Models/AppSettings.swift">Meilink/Models/AppSettings.swift</kfile>：

```swift
enum MenuBarIconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case portal
    case topology
    case arrowRing
    case waveform
    case relay
    case network  // 新增

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .portal: return "门户"
        case .topology: return "拓扑"
        case .arrowRing: return "穿透"
        case .waveform: return "信号"
        case .relay: return "中继"
        case .network: return "网络"  // 新增
        }
    }

    var imageName: String {
        switch self {
        case .portal: return "portal"
        case .topology: return "topology"
        case .arrowRing: return "arrow-ring"
        case .waveform: return "waveform"
        case .relay: return "relay"
        case .network: return "network"  // 新增
        }
    }
}
```

### 3.3 验证 SettingsView 自动适配
<kfile name="SettingsView.swift" path="Meilink/UI/Settings/SettingsView.swift">Meilink/UI/Settings/SettingsView.swift</kfile> 的"菜单栏图标"行用 `ForEach(MenuBarIconStyle.allCases)`，会自动多一个按钮，但需要：

- [ ] 验证 6 个按钮横排不溢出（窗口宽 760，按钮区宽约 6×52 = 312 + spacing，应该够）
- [ ] 验证换行布局（若 HStack 自动换行，需检查对齐）
- [ ] 若溢出，考虑改为 `LazyVGrid` 或缩小按钮宽度

### 3.4 验证 `StatusBarController.menuBarImage` 自动适配
<kfile name="AppRuntime.swift" path="Meilink/App/AppRuntime.swift">Meilink/App/AppRuntime.swift</kfile> 的 `menuBarImage` 通过 `status.imageName` 加载 PNG，自动支持新值：

```swift
let name = status.imageName
if let path = Bundle.main.path(forResource: name, ofType: "png"),
   let image = NSImage(contentsOfFile: path) {
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = true
    return image
}
return resizedApplicationIcon()  // fallback
```

- [ ] 确认 PNG 已被 Xcode 打进 bundle（`project.yml` 的 `sources: [Meilink]` 自动包含 Resources，通常无需手动配置）
- [ ] 若用 SwiftPM，确认 `Package.swift` 的 `exclude: ["Info.plist", "Resources"]` 不会排除新 PNG（当前 exclude 整个 Resources 目录，但资源通过 bundle 加载，需要单独处理）

> **注意**：当前 `Package.swift` `exclude: ["Info.plist", "Resources"]` 会导致 SwiftPM 构建时不包含 Resources。SwiftPM 用户需要手动把 PNG 复制到 `.build/.../Meilink_Resources/` 或改用 Xcode 构建。详见 [../sdd/07-build-release.md](../sdd/07-build-release.md) §2.3。

### 3.5 跨平台同步
- [ ] `cross-platform-client/desktop/src-tauri/src/lib.rs`：托盘图标加载逻辑支持新 imageName
- [ ] `cross-platform-client/desktop/src/settings.html`：图标选择器加新选项
- [ ] 跨平台 PNG 资源同步

### 3.6 同步 SDD
- [ ] [../sdd/04-ui-design.md](../sdd/04-ui-design.md) §9.1 表格加行
- [ ] [../sdd/05-data-contract.md](../sdd/05-data-contract.md) §4.1 枚举值列表加值
- [ ] [../sdd/04-ui-design.md](../sdd/04-ui-design.md) §12.2 PNG 资源列表加文件名

## 4. 反例

### 4.1 反例：彩色 PNG
```swift
// ❌ 错误：彩色图标在深色模式看不清
image.isTemplate = false

// ✅ 正确：template 图标
image.isTemplate = true
// PNG 用黑色线条 + 透明背景
```

### 4.2 反例：尺寸不对
```swift
// ❌ 错误：22×22 在菜单栏显得太大
image.size = NSSize(width: 22, height: 22)

// ✅ 正确：18×18 与其他风格一致
image.size = NSSize(width: 18, height: 18)
```

### 4.3 反例：改默认值
```swift
// ❌ 错误：改默认值会破坏老用户设置
var menuBarIconStyle: MenuBarIconStyle = .network

// ✅ 正确：保持 .portal 为默认
var menuBarIconStyle: MenuBarIconStyle = .portal
```

### 4.4 反例：imageName 与文件名不一致
```swift
// ❌ 错误：imageName 是 "net"，文件名是 "network.png"
case .network: return "net"
// Meilink/Resources/network.png 不会被加载

// ✅ 正确：imageName 与文件名（不含扩展名）一致
case .network: return "network"
// Meilink/Resources/network.png 加载成功
```

### 4.5 反例：忘记加 `case` 到 switch
```swift
// ❌ 错误：只加 case 没加 switch 分支，Swift 编译会报错（好处是编译器强制）
// 但若用 if-else 链可能漏掉

// ✅ 正确：switch 全覆盖，Swift 强制 exhaustive
```

## 5. 验证步骤

1. `swift build` 编译通过（Swift switch exhaustive 会强制覆盖新 case）
2. 启动应用 → 菜单栏图标是当前选中风格
3. 打开设置 → "菜单栏图标"行显示 6 个按钮（含新增）
4. 点新风格按钮 → 菜单栏图标立即切换
5. 退出应用重启 → 设置保留（`settings.json` 里 `menuBarIconStyle = "network"`）
6. 深色模式 + 浅色模式都正常显示（template 生效）
7. PNG 加载失败时 fallback 到 AppIcon（不崩）
8. 跨平台客户端同步显示新风格
9. `Scripts/reset-menu-bar-cache.sh` 后菜单栏图标位置正常（若图标错位）
10. SDD 文档已同步
