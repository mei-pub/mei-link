# Agent Rule · 修改 Tunnel 模型与代理定义

> **何时触发**：当任务涉及修改 `Tunnel` 结构体字段、`TunnelType` 枚举、`ProxyDefinition` / `TCPProxyConfig` / `UDPProxyConfig` / `HTTPProxyConfig` / `HTTPSProxyConfig` 结构，或新增代理类型时。

> **必读 SDD**：[../sdd/05-data-contract.md](../sdd/05-data-contract.md)（数据契约）、[../sdd/03-architecture.md](../sdd/03-architecture.md)（架构）。

## 1. 涉及文件清单

修改 `Tunnel` 模型或代理定义时，必须同步检查以下文件：

### 1.1 Swift 原生客户端（`Meilink/`）
- <kfile name="Tunnel.swift" path="Meilink/Models/Tunnel.swift">Meilink/Models/Tunnel.swift</kfile> — `Tunnel` / `TunnelType` / `TunnelStatus` 定义 + `toProxyDefinition` 转换
- <kfile name="ProxyDefinition.swift" path="Meilink/Models/ProxyDefinition.swift">Meilink/Models/ProxyDefinition.swift</kfile> — frpc Store API 的 proxy payload
- <kfile name="TunnelDisplay.swift" path="Meilink/Models/TunnelDisplay.swift">Meilink/Models/TunnelDisplay.swift</kfile> — 路由文案 / 状态色 / openURL
- <kfile name="TunnelEditView.swift" path="Meilink/UI/Main/TunnelEditView.swift">Meilink/UI/Main/TunnelEditView.swift</kfile> — 编辑表单字段
- <kfile name="TunnelListRow.swift" path="Meilink/UI/Main/TunnelListRow.swift">Meilink/UI/Main/TunnelListRow.swift</kfile> — 列表行展示
- <kfile name="TunnelRowView.swift" path="Meilink/UI/MenuBar/TunnelRowView.swift">Meilink/UI/MenuBar/TunnelRowView.swift</kfile> — 菜单栏行展示
- <kfile name="TunnelManager.swift" path="Meilink/Core/TunnelManager.swift">Meilink/Core/TunnelManager.swift</kfile> — CRUD + 状态轮询
- <kfile name="FrpcAdminAPI.swift" path="Meilink/Core/FrpcAdminAPI.swift">Meilink/Core/FrpcAdminAPI.swift</kfile> — API 调用
- <kfile name="TunnelReachabilityProbe.swift" path="Meilink/Core/TunnelReachabilityProbe.swift">Meilink/Core/TunnelReachabilityProbe.swift</kfile> — 远程探活
- <kfile name="SubdomainNormalizer.swift" path="Meilink/Utils/SubdomainNormalizer.swift">Meilink/Utils/SubdomainNormalizer.swift</kfile> — 子域名归一化
- <kfile name="TunnelStore.swift" path="Meilink/Storage/TunnelStore.swift">Meilink/Storage/TunnelStore.swift</kfile> — 持久化

### 1.2 跨平台客户端（`cross-platform-client/`）
- `internal/config/config.go` — 配置 schema
- `internal/tunnel/manager.go` — 隧道管理
- `internal/frpc/` — frpc 进程管理 + Admin API
- `desktop/src/main.html` / `popover.html` / `tunnel-edit.html` — 前端 UI

### 1.3 SDD 文档
- [../sdd/05-data-contract.md](../sdd/05-data-contract.md) — 数据契约（必须同步更新 §2 / §7）
- [../sdd/04-ui-design.md](../sdd/04-ui-design.md) — UI 设计（若改了字段展示）
- [../sdd/02-features.md](../sdd/02-features.md) — 功能清单（若改了功能行为）

## 2. 必读不变量

### 2.1 `Tunnel` 持久化字段
- `id` / `name` / `type` / `localPort` / `localIP` / `subdomain` / `remotePort` / `customDomains` / `httpUser` / `httpPassword` / `hostHeaderRewrite` / `enabled` / `createdAt` / `updatedAt` 是持久化字段，会写进 `tunnels.json`
- `status` / `errorMessage` / `remoteAddr` 是运行期字段，由 `pollStatus` 实时填充，**不能**据持久化值判断状态（详见 [../sdd/05-data-contract.md](../sdd/05-data-contract.md) §2.1）
- 新增字段时必须给默认值 + 容错解码（参考 `AppSettings.init(from:)` 模式），否则旧 `tunnels.json` 加载会崩

### 2.2 `TunnelType` 枚举
- 当前 4 个值：`tcp` / `udp` / `http` / `https`
- rawValue 必须与 frpc Admin API 的 `status` 字段分组 key 一致（`getStatus` 返回 `[type.rawValue: [ProxyStatusResp]]`）
- 删除枚举值会破坏旧数据兼容性，新增枚举值必须同步所有 switch 分支

### 2.3 `TunnelStatus` 映射
- rawValue 必须与 frpc 的 phase 字符串完全一致：`"new"` / `"wait start"` / `"start error"` / `"running"` / `"check failed"` / `"closed"`
- `displayName` 不能改（跨平台对齐基线）：新建 / 连接中 / 启动失败 / 运行中 / 检查失败 / 已关闭
- `tintColor` 不能改：running→green / waitStart→yellow / startError/checkFailed→red / new/closed→gray

### 2.4 `toProxyDefinition` 转换规则
- HTTP：`locations = ["/"]`，`customDomains` 空数组时传 nil 给 frpc，subdomain 经 `SubdomainNormalizer.normalize`
- HTTPS：无 `locations` / `httpUser` / `httpPassword`
- TCP/UDP：`remotePort ?? 0`（0 = frpc 自动分配）
- subdomain 必须经 `SubdomainNormalizer.normalize(subdomain, baseHost: serverConfig?.subDomainHost)` 处理，避免用户填了完整域名导致 frpc 拼出 `foo.bar.tunnel.example.com.tunnel.example.com`

## 3. 同步修改清单

### 3.1 新增 `Tunnel` 字段
- [ ] `Tunnel.swift`：加字段 + init 默认值
- [ ] `Tunnel.swift`：若需要，更新 `toProxyDefinition`
- [ ] `TunnelEditView.swift`：加表单字段 + `saveTunnel` 写入 + `canSave` 校验
- [ ] `TunnelListRow.swift`：若需展示，加列
- [ ] `TunnelRowView.swift`：菜单栏展示（若需要）
- [ ] `TunnelDisplay.swift`：路由文案（若涉及）
- [ ] `TunnelStore.swift`：编解码（通常 Codable 自动处理，但容错解码需手动加）
- [ ] 跨平台：`config.go` / `manager.go` / `tunnel-edit.html` 同步
- [ ] SDD：`05-data-contract.md` §2.1 表格加行

### 3.2 新增 `TunnelType`
- [ ] `Tunnel.swift`：`TunnelType` 加枚举值
- [ ] `Tunnel.swift`：`toProxyDefinition` 加 switch 分支 + 新的 `*ProxyConfig` 结构
- [ ] `ProxyDefinition.swift`：加对应 config 结构
- [ ] `TunnelEditView.swift`：Picker 自动多一个选项，但远程配置区域可能需要新分支
- [ ] `TunnelDisplay.swift`：`routeText` / `shortRouteText` / `openURL` 加分支
- [ ] `TunnelReachabilityProbe.swift`：`check` 加 switch 分支（默认 `.skipped`）
- [ ] `TunnelRowView.swift`：`description` 加分支
- [ ] 跨平台：`config.go` / `manager.go` / 前端 `STATUS_LABELS` 等同步
- [ ] SDD：`05-data-contract.md` §2.2 / §7 同步

### 3.3 新增 `TunnelStatus`
- [ ] `Tunnel.swift`：枚举加值 + `init(frpcPhase:)` 映射 + `displayName`
- [ ] `TunnelDisplay.swift`：`tintColor` 加分支
- [ ] `TunnelRowView.swift`：`statusColor` 加分支
- [ ] 跨平台：`STATUS_LABELS` / `STATUS_COLORS` 同步
- [ ] SDD：`05-data-contract.md` §2.3 / [../sdd/04-ui-design.md](../sdd/04-ui-design.md) §10.1 同步

### 3.4 修改 `ProxyDefinition` 结构
- [ ] `ProxyDefinition.swift`：改结构
- [ ] `Tunnel.swift`：`toProxyDefinition` 同步
- [ ] `FrpcAdminAPI.swift`：若有特殊编解码需求，调整
- [ ] 跨平台：`frpc/admin.go` 等同步
- [ ] 验证：frpc v0.70.0 Store API 接受新 payload（看 frp 源码或实测）

## 4. 反例

### 4.1 反例：直接读持久化的 `status` 字段判断状态
```swift
// ❌ 错误：status 是运行期字段，持久化值可能过期
if tunnel.status == .running { ... }

// ✅ 正确：状态来自 pollStatus 实时刷新，UI 通过 @Published tunnels 自动响应
// 不需要主动判断，观察 manager.tunnels 即可
```

### 4.2 反例：新增 TunnelType 不更新所有 switch
```swift
// ❌ 错误：加了 .stcp 类型但没更新 toProxyDefinition
// ✅ 正确：按 §3.2 清单逐项更新
```

### 4.3 反例：subdomain 不 normalize
```swift
// ❌ 错误：用户可能填了 "admin.tunnel.example.com"
let proxy = HTTPProxyConfig(subdomain: tunnel.subdomain, ...)

// ✅ 正确：经 SubdomainNormalizer 处理
let normalized = SubdomainNormalizer.normalize(tunnel.subdomain, baseHost: serverConfig?.subDomainHost)
let proxy = HTTPProxyConfig(subdomain: normalized, ...)
```

### 4.4 反例：新增字段不给默认值
```swift
// ❌ 错误：旧 tunnels.json 没这字段，加载会崩
var newField: String

// ✅ 正确：给默认值 + 容错解码
var newField: String = ""
// 或在 init(from decoder:) 里：
newField = try container.decodeIfPresent(String.self, forKey: .newField) ?? ""
```

## 5. 验证步骤

1. `swift build` 编译通过
2. 启动应用，添加 / 编辑 / 删除隧道正常
3. 退出应用，删除 `~/Library/Application Support/Meilink/tunnels.json`，重新启动应用不崩（验证默认值）
4. 用旧 `tunnels.json`（缺新字段）启动应用不崩（验证容错解码）
5. frpc Admin API 能接受新 payload（`/api/store/proxies` POST 返回 2xx）
6. 跨平台客户端能读到新字段（若跨端同步）
