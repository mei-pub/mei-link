# Agent Rule · 跨平台兼容性

> **何时触发**：当任务要求修改跨平台客户端（`cross-platform-client/`）、或修改 Swift 客户端但可能影响跨平台兼容性时。或当任务涉及持久化 schema、frpc 交互模式、状态机、UI 不变量等跨端共享契约时。

> **必读 SDD**：[../sdd/05-data-contract.md](../sdd/05-data-contract.md)（数据契约）、[../sdd/06-constraints.md](../sdd/06-constraints.md) §7（跨平台兼容约束）、[../sdd/04-ui-design.md](../sdd/04-ui-design.md)（UI 对齐基线）。

> **重要原则**：Swift 原生客户端（`Meilink/`）是 source of truth。跨平台客户端必须与 Swift 实现对齐，而不是反过来。

## 1. 涉及文件清单

### 1.1 Swift 原生客户端（source of truth）
- `Meilink/` 全部 — 详见 [../sdd/00-overview.md](../sdd/00-overview.md) §4

### 1.2 跨平台客户端（必须对齐）
- `cross-platform-client/cmd/meilink/` — CLI 入口
- `cross-platform-client/cmd/meilink-setup/` — 服务端部署
- `cross-platform-client/internal/config/` — 配置管理 + frpc.toml 生成
- `cross-platform-client/internal/frpc/` — frpc 进程管理 + Admin API + 自动下载
- `cross-platform-client/internal/tunnel/` — 隧道 CRUD
- `cross-platform-client/internal/web/` — Web UI + HTTP API
- `cross-platform-client/internal/service/` — systemd / Windows Service
- `cross-platform-client/desktop/src-tauri/` — Tauri Rust 壳
- `cross-platform-client/desktop/src/` — 前端 HTML/CSS/ES

### 1.3 对齐文档（已存在）
- `docs/superpowers/specs/2026-07-24-cross-platform-native-alignment-design.md`
- `docs/superpowers/plans/2026-07-24-cross-platform-native-alignment.md`
- `docs/superpowers/plans/2026-07-24-swift-to-tauri-alignment.md`

### 1.4 SDD 文档
- [../sdd/05-data-contract.md](../sdd/05-data-contract.md)（数据契约，跨端共享）
- [../sdd/06-constraints.md](../sdd/06-constraints.md) §7（跨平台兼容约束）
- [../sdd/04-ui-design.md](../sdd/04-ui-design.md)（UI 对齐基线）

## 2. 必读不变量

### 2.1 Swift 是 source of truth
- 行为、视觉、数据、状态、frpc 交互模式以 Swift 实现为准
- 跨平台客户端对齐 Swift，而不是反过来
- 若发现 Swift 实现有 bug 需要改，必须同时更新 SDD + 跨平台实现

### 2.2 数据互通（macOS 共享目录）
- macOS 上 Tauri 客户端与 Swift 客户端共享 `~/Library/Application Support/Meilink`
- Swift 写的 `config.json` / `tunnels.json` / `settings.json` 必须能被 Go 读取
- Go 写的也必须能被 Swift 读取
- **注意 `tunnels.json` 的特殊字段**：`status` / `errorMessage` / `remoteAddr` 是 Swift Codable 默认编码进去的运行期字段，Go 读取时不能据此判断状态（详见 [../sdd/05-data-contract.md](../sdd/05-data-contract.md) §2.1）

### 2.3 持久化 schema 对齐
| 文件 | Swift 类型 | Go 类型 | 对齐点 |
|---|---|---|---|
| `tunnels.json` | `[Tunnel]` | `[]Tunnel` | 字段名 camelCase + ISO8601 日期 |
| `config.json` | `ServerConfig` | `ServerConfig` | 同上 |
| `settings.json` | `AppSettings` | `Settings` | 同上 + 容错解码（字段缺失走默认） |

- JSON 编码：prettyPrinted + ISO8601 日期
- 字段命名：camelCase（Swift 默认）
- Go 端需要 `json:"fieldName"` tag 显式匹配 camelCase

### 2.4 状态机对齐
- `TunnelStatus` 6 个值 + 中文 displayName + tintColor 必须一致
- 应用级状态判定顺序：`isConnected` > `isFrpcRunning` > `isConfigured`
- 状态文案逐字对齐（中文）

### 2.5 frpc 交互模式对齐
- frpc.toml 生成规则一致（`webServer.addr = 127.0.0.1` / `[store]` 模式 / 0600 权限）
- Store API 调用路径一致（`/api/store/proxies` POST/PUT/DELETE + `/api/reload`）
- Admin API 解码 `convertFromSnakeCase`（Go 端用对应 snake_case tag）
- 自动恢复策略一致（连续 3 次失败 + 20s 冷却 + sleep 1s + start force）

### 2.6 UI 不变量对齐
- 窗口尺寸：见 [../sdd/04-ui-design.md](../sdd/04-ui-design.md) §1
- 状态色：见 [../sdd/04-ui-design.md](../sdd/04-ui-design.md) §2.1
- 状态文案：见 [../sdd/04-ui-design.md](../sdd/04-ui-design.md) §10
- macOS 行为：关窗口不退出 / 不显示 Dock / 点外部关面板 / 退出受 `allowQuit` 控制

### 2.7 跨平台默认目录
- macOS：`~/Library/Application Support/Meilink`（与 Swift 共享）
- Windows / Linux：`~/.meilink`
- 不能硬编码绝对路径，必须按平台判断

### 2.8 允许的差异
- 渲染细节（字体渲染、毛玻璃效果、阴影）
- 非 macOS 平台没有 Keychain 时的替代存储（0600 JSON）
- 非 macOS 平台没有 Login Items 时的替代（systemd / Windows Service）
- 非 macOS 平台的菜单栏图标实现差异（系统托盘）

## 3. 同步修改清单

### 3.1 修改 Swift 持久化 schema
- [ ] Swift：`Meilink/Models/` 改结构
- [ ] Go：`cross-platform-client/internal/config/config.go` 同步
- [ ] 验证 Swift 写的 JSON 能被 Go 读取（`go test ./internal/config/`）
- [ ] 验证 Go 写的 JSON 能被 Swift 读取（启动 Swift 客户端加载 Go 写的文件）
- [ ] SDD：`05-data-contract.md` 同步
- [ ] 若破坏兼容，必须在 SDD 标注"破坏性变更" + 提供迁移逻辑

### 3.2 修改 frpc 交互模式
- [ ] Swift：`Meilink/Core/` 改
- [ ] Go：`cross-platform-client/internal/frpc/` 同步
- [ ] 验证两端生成的 frpc.toml 字段一致
- [ ] 验证两端调用 Store API 的 payload 一致
- [ ] SDD：`05-data-contract.md` §6 / §7 同步

### 3.3 修改状态机或自动恢复
- [ ] Swift：`TunnelManager.swift` 改
- [ ] Go：`cross-platform-client/internal/tunnel/manager.go` 同步
- [ ] 验证两端的状态判定顺序一致
- [ ] 验证两端的恢复阈值一致
- [ ] SDD：`03-architecture.md` §4-§6 同步
- [ ] 详见 [modifying-status-polling.md](./modifying-status-polling.md)

### 3.4 修改 UI 不变量
- [ ] Swift：`Meilink/UI/` 改
- [ ] Tauri：`cross-platform-client/desktop/src/` + `desktop/src-tauri/` 同步
- [ ] 验证窗口尺寸、状态色、状态文案、macOS 行为一致
- [ ] SDD：`04-ui-design.md` 同步
- [ ] 详见 [modifying-ui.md](./modifying-ui.md)

### 3.5 修改默认目录
- [ ] Swift：`TunnelStore.swift` 的 `baseURL` 计算
- [ ] Go：`internal/config/config.go` 的目录判断
- [ ] 不能硬编码绝对路径
- [ ] 验证 macOS 共享目录 `~/Library/Application Support/Meilink` 两端一致
- [ ] SDD：`05-data-contract.md` §1 同步

## 4. 反例

### 4.1 反例：Go 端用 snake_case 字段
```go
// ❌ 错误：Go 默认 json tag 用 snake_case，但 Swift 写的是 camelCase
type Tunnel struct {
    LocalPort int `json:"local_port"`
    // ...
}
// Swift 写的 tunnels.json 里是 "localPort"，Go 读不到

// ✅ 正确：显式 camelCase tag
type Tunnel struct {
    LocalPort int `json:"localPort"`
    // ...
}
```

### 4.2 反例：Go 端据持久化 status 判断状态
```go
// ❌ 错误：status 是运行期字段，持久化值可能过期
if tunnel.Status == "running" { ... }

// ✅ 正确：状态来自实时轮询 frpc Admin API
status := pollStatusFromAdminAPI(tunnel)
```

### 4.3 反例：跨平台窗口尺寸不一致
```swift
// Swift 改成 800×500
settingsWindow = showWindow(..., size: NSSize(width: 800, height: 500)) { ... }
```
```json
// tauri.conf.json 还是 760×460
{
  "width": 760,
  "height": 460
}
```
```go
// ❌ 错误：两端不一致

// ✅ 正确：同步改
// tauri.conf.json: 800×500
// 04-ui-design.md §1 同步
```

### 4.4 反例：改 Swift 默认目录
```swift
// ❌ 错误：改 Swift 默认目录但不同步 Go
baseURL = paths[0].appendingPathComponent("MeilinkApp")
// Go 还在用 "Meilink"，两端互读不了

// ✅ 正确：保持 ~/Library/Application Support/Meilink，两端共享
baseURL = paths[0].appendingPathComponent("Meilink")
```

### 4.5 反例：跨平台改 frpc.toml schema
```go
// ❌ 错误：Go 端单独改 frpc.toml 生成，不与 Swift 对齐
lines = append(lines, "transport.tls.enable = false")  // 强制关 TLS

// ✅ 正确：两端一致，TLS 由用户配置决定
lines = append(lines, fmt.Sprintf("transport.tls.enable = %v", config.TLSEnabled))
```

### 4.6 反例：忽略对齐文档
```
# ❌ 错误：不看 docs/superpowers/ 下的对齐文档，凭感觉改跨平台
# ✅ 正确：先读 docs/superpowers/specs/ + plans/，再改
```

## 5. 验证步骤

### 5.1 数据互通验证
1. Swift 客户端创建几条隧道 + 配置服务器
2. 退出 Swift 客户端
3. 在 macOS 上启动 Tauri 客户端（共享目录）
4. 验证 Tauri 能读到 Swift 创建的隧道 + 配置
5. 在 Tauri 里改一条隧道
6. 切回 Swift 客户端，验证能读到 Tauri 的修改

### 5.2 行为对齐验证
1. 两端的窗口尺寸一致（[../sdd/04-ui-design.md](../sdd/04-ui-design.md) §1）
2. 两端的状态文案 + 状态色一致
3. macOS 上两端都不显示 Dock
4. macOS 上两端关窗口都不退出
5. 菜单栏/托盘点击弹出面板，点外部自动关

### 5.3 frpc 交互验证
1. 两端生成的 frpc.toml 字段一致（diff 对比）
2. 两端调用 Store API 的 payload 一致
3. frpc 异常退出时两端都自动恢复
4. 外网不可达时两端都触发重连

### 5.4 测试命令
```bash
# Swift
swift build
swift test  # 当前 Tests/ 为空，需补

# Go
cd cross-platform-client
go test ./...

# Tauri
cd cross-platform-client/desktop
npm run build
cd src-tauri && cargo test
```

### 5.5 SDD 同步验证
- 改了共享契约后，相关 SDD 章节（`05-data-contract.md` / `06-constraints.md` §7 / `04-ui-design.md`）已同步
- 改了 Swift 实现后，相关 agent-rules（`modifying-tunnel.md` / `modifying-status-polling.md` / `modifying-frpc-process.md` / `modifying-ui.md`）已同步
