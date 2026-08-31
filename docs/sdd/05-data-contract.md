# Meilink SDD · 05 · 数据契约

> 本文列出 Meilink 的所有持久化文件 schema、frpc Admin API 契约、Keychain 用法、frpc.toml 生成规则。这是跨平台客户端必须严格对齐的部分。

## 1. 持久化目录

### 1.1 macOS 原生客户端
- 目录：`~/Library/Application Support/Meilink/`
- 实现：<kfile name="TunnelStore.swift" path="client/macos-native/Storage/TunnelStore.swift">TunnelStore.swift</kfile>
- 创建：`init` 时 `createDirectory(withIntermediateDirectories: true)`
- 文件列表：
  | 文件 | 用途 | 读写 |
  |---|---|---|
  | `tunnels.json` | 隧道列表 | 应用读写；frpc 不读 |
  | `config.json` | 服务器配置 | 应用读写；frpc 不读 |
  | `settings.json` | 应用设置 | 应用读写；frpc 不读 |
  | `frpc.toml` | frpc 运行期配置 | 应用生成；frpc 读 |
  | `store.json` | frpc 自己持久化的 proxy 列表 | frpc 读写；应用不直接读 |

### 1.2 跨平台客户端
- macOS：同上，共享 `~/Library/Application Support/Meilink/`
- Windows / Linux：`~/.meilink/`（详见 `client/desktop/sidecar/internal/config/`，本次未深入）

## 2. `tunnels.json` Schema

类型：`[Tunnel]`（数组），JSON 编码 ISO8601 日期 + prettyPrinted。

### 2.1 `Tunnel` 字段
| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `id` | UUID | UUID() | 主键 |
| `name` | String | — | 隧道名（frpc proxy name） |
| `type` | TunnelType | — | `tcp` / `udp` / `http` / `https` |
| `localPort` | Int | — | 本地端口 |
| `localIP` | String | `127.0.0.1` | 本地地址 |
| `subdomain` | String? | nil | HTTP/HTTPS 子域名（已 normalize，不含 baseHost） |
| `remotePort` | Int? | nil | TCP/UDP 远程端口（nil = 自动分配） |
| `customDomains` | [String] | [] | HTTP/HTTPS 自定义域名（空数组时传 nil 给 frpc） |
| `httpUser` | String? | nil | HTTP Basic Auth user |
| `httpPassword` | String? | nil | HTTP Basic Auth password |
| `hostHeaderRewrite` | String? | nil | HTTP host header rewrite |
| `enabled` | Bool | true | 是否启用 |
| `status` | TunnelStatus | .new | 运行期状态，**不持久化** |
| `errorMessage` | String? | nil | 运行期错误，**不持久化** |
| `remoteAddr` | String? | nil | frpc 返回的远端地址，**运行期** |
| `createdAt` | Date | Date() | 创建时间 |
| `updatedAt` | Date | Date() | 更新时间 |

> **注意**：`status` / `errorMessage` / `remoteAddr` 是运行期字段，由 `pollStatus` 实时填充。Swift 实现里它们仍被编码进 `tunnels.json`（因为 `Codable` 默认全字段编码），但下次加载时不会据此判断状态——加载后 `status` 会被 `pollStatus` 覆盖。跨平台实现要兼容这种"持久化的 status 字段存在但不可信"的情况。

### 2.2 `TunnelType` 枚举值
- `tcp` / `udp` / `http` / `https`（`String` rawValue，`Codable` + `CaseIterable` + `Sendable`）

### 2.3 `TunnelStatus` 枚举值
- `new` / `waitStart` / `startError` / `running` / `checkFailed` / `closed`
- 从 frpc 的 phase 字符串映射：`"new"` / `"wait start"` / `"start error"` / `"running"` / `"check failed"` / `"closed"`

## 3. `config.json` Schema

类型：`ServerConfig`，ISO8601 日期（无日期字段）+ prettyPrinted。

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `serverAddr` | String | `""` | frps 地址 |
| `serverPort` | Int | 7000 | frps 客户端连接端口 |
| `authToken` | String | `""` | frps auth.token |
| `subDomainHost` | String | `""` | 子域名基域 |
| `tlsEnabled` | Bool | true | frpc 到 frps 是否启用 TLS |
| `adminPort` | Int | 7400 | frpc Admin API 端口 |
| `adminUser` | String | `admin` | Admin API Basic Auth user |
| `adminPassword` | String | `admin` | Admin API Basic Auth password |
| `managementURL` | String | `""` | 服务端管理页地址（如 `http://vps:17500`），用于拉取域名目录；与 frps 连接无关，留空则隧道编辑走手填模式 |
| `domainAPIToken` | String | `""` | 拉取 `GET /api/domains` 的 Bearer token（对应服务端 `MEILINK_DOMAIN_API_TOKEN`），与管理页登录账号独立 |

> **注意**：`authToken` 同时被写入 Keychain（见 §5）。`config.json` 里的 token 与 Keychain 里的 token 是同一份，但跨平台实现要能从 `config.json` 直接读到 token（因为不是所有平台都有 Keychain）。

## 4. `settings.json` Schema

类型：`AppSettings`，自定义 `init(from:)` 容错解码（字段缺失走默认）。

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `autoStart` | Bool | true | 应用启动后是否自动连接 |
| `launchAtLogin` | Bool | false | 登录后是否自动启动 Meilink |
| `showInDock` | Bool | false | 是否显示 Dock（当前未真正生效） |
| `statusPollingInterval` | TimeInterval | 3.0 | 状态轮询间隔（运行时 clamp 3-30） |
| `remoteReachabilityInterval` | TimeInterval | 60.0 | 远程探活间隔（运行时 clamp 30-600） |
| `reconnectInterval` | TimeInterval | 10.0 | 自动重连：断连后的探测/重试间隔，也是两次重启的最小间隔（clamp 3-300） |
| `maxReconnectAttempts` | Int | 3 | 自动重连：重建连接连续失败 N 次后升级为重启 frpc（clamp 1-30） |
| `maxRestartAttempts` | Int | 3 | 自动重连：重启 frpc 连续失败 N 次后放弃自动恢复（clamp 1-30） |
| `menuBarIconStyle` | MenuBarIconStyle | .portal | 菜单栏图标风格 |

### 4.1 `MenuBarIconStyle` 枚举值
- `portal` / `topology` / `arrowRing` / `waveform` / `relay`（String rawValue，CaseIterable，Identifiable）

## 5. Keychain 契约

- service: `pub.mei.meilink`
- account: `auth-token`（当前仅此一个 key）
- accessible: `kSecAttrAccessibleWhenUnlocked`
- 写入：先 `SecItemDelete` 再 `SecItemAdd`（覆盖式）
- 实现：<kfile name="KeychainHelper.swift" path="client/macos-native/Storage/KeychainHelper.swift">KeychainHelper.swift</kfile>

> 跨平台无 Keychain 时，token 直接从 `config.json` 读，文件权限 0600。

## 6. frpc.toml 生成规则

实现：<kfile name="ConfigGenerator.swift" path="client/macos-native/Core/ConfigGenerator.swift">ConfigGenerator.swift</kfile>。

### 6.1 模板（frp v0.70.0 schema）
```toml
serverAddr = "<serverAddr>"
serverPort = <serverPort>

auth.method = "token"
auth.token = "<authToken>"

transport.tls.enable = <tlsEnabled>
transport.poolCount = 5
transport.tcpMux = true
transport.tcpMuxKeepaliveInterval = 30

webServer.addr = "127.0.0.1"
webServer.port = <adminPort>
webServer.user = "<adminUser>"
webServer.password = "<adminPassword>"

[store]
path = "<Application Support>/Meilink/store.json"

# Proxies are managed dynamically via Store API
```

### 6.2 关键不变量
- `webServer.addr` 永远是 `127.0.0.1`（Admin API 不对外）
- `[store]` 让 frpc 自己持久化 proxy，应用启动后通过 Store API 恢复
- TOML 格式：顶层 key=value，仅 `[store]` 是 section
- 文件权限 0600（`ConfigGenerator.writeToFile` 显式设置）

### 6.3 不在 frpc.toml 里
- 具体 proxy 配置（tcp/udp/http/https）通过 Store API 动态增删，不写在 toml 里
- `transport.poolCount / tcpMux / tcpMuxKeepaliveInterval` 是硬编码默认值，不通过 UI 暴露

## 7. Proxy 增删改（Store API）

实现：<kfile name="FrpcAdminAPI.swift" path="client/macos-native/Core/FrpcAdminAPI.swift">FrpcAdminAPI.swift</kfile> + <kfile name="Tunnel.swift" path="client/macos-native/Models/Tunnel.swift">Tunnel.swift</kfile> 的 `toProxyDefinition`。

### 7.1 `ProxyDefinition` 结构
```swift
struct ProxyDefinition: Codable {
    let name: String
    let type: String  // "tcp" / "udp" / "http" / "https"
    var tcp: TCPProxyConfig?
    var udp: UDPProxyConfig?
    var http: HTTPProxyConfig?
    var https: HTTPSProxyConfig?
}
```

### 7.2 各类型 config
- `TCPProxyConfig` / `UDPProxyConfig`：`localIP` / `localPort` / `remotePort`
- `HTTPProxyConfig`：`localIP` / `localPort` / `subdomain` / `customDomains` / `locations` / `httpUser` / `httpPassword` / `hostHeaderRewrite` / `requestHeaders` / `responseHeaders`
- `HTTPSProxyConfig`：`localIP` / `localPort` / `subdomain` / `customDomains`
- `HeaderOperations`：`set: [String: String]?`

### 7.3 `Tunnel.toProxyDefinition` 规则
- HTTP：`locations = ["/"]`，`customDomains` 空数组传 nil，subdomain 经 `SubdomainNormalizer.normalize` 处理
- HTTPS：同上但无 `locations` / `httpUser` / `httpPassword`
- TCP/UDP：`remotePort ?? 0`（0 表示自动分配）

### 7.4 `SubdomainNormalizer.normalize` 规则
- 输入 `value` 与 `baseHost`
- trim 空白，空则返回 nil
- 若 `baseHost` 为空，直接返回 trim 后的 `value`
- 若 `value` 以 `.<baseHost>` 结尾，去掉该后缀返回前缀（前缀为空则返回 nil）
- 否则原样返回 `value`

## 8. frpc Admin API 端点

baseURL: `http://127.0.0.1:<adminPort>`，Basic Auth。

### 8.1 端点列表
| Method | Path | 用途 | 实现 |
|---|---|---|---|
| GET | `/healthz` | 健康检查，返回 200 即就绪 | `healthCheck()` |
| GET | `/api/status` | 拉所有 proxy 状态，返回 `{type: [{name, status, err, ...}]}` | `getStatus()` |
| POST | `/api/stop` | 停止 frpc | `stop()` |
| POST | `/api/reload` | 重载配置 | `reload()` |
| GET | `/api/store/proxies` | 列出所有 proxy | `listProxies()` |
| POST | `/api/store/proxies` | 创建 proxy，body 是 `ProxyDefinition` | `createProxy()` |
| PUT | `/api/store/proxies/<name>` | 更新 proxy | `updateProxy()` |
| DELETE | `/api/store/proxies/<name>` | 删除 proxy | `deleteProxy()` |

### 8.2 解码约定
- `decoder.keyDecodingStrategy = .convertFromSnakeCase`：frpc Admin API 返回 snake_case，Swift 模型用 camelCase
- `StatusResponse = [String: [ProxyStatusResp]]`：按 proxy 类型分组的字典

### 8.3 `ProxyStatusResp` 字段
| 字段 | 类型 | 说明 |
|---|---|---|
| `name` | String | proxy 名 |
| `type` | String | proxy 类型 |
| `status` | String | frpc phase（`new` / `wait start` / `start error` / `running` / `check failed` / `closed`） |
| `err` | String | 错误信息 |
| `localAddr` | String | 本地地址 |
| `plugin` | String | 插件名 |
| `remoteAddr` | String | 远端地址 |
| `source` | String? | 来源（可选） |

### 8.4 错误模型
`FrpcError` 枚举：
- `adminAPINotReady` / `createFailed(Int)` / `updateFailed` / `deleteFailed` / `stopFailed` / `reloadFailed` / `networkError(Error)`

### 8.5 超时
- `URLSessionConfiguration.default.timeoutIntervalForRequest = 10` 秒

## 8A. 跨平台 Go sidecar HTTP API

跨平台桌面客户端的 Tauri 壳通过本地 HTTP API 调用 Go sidecar（`client/desktop/sidecar/internal/web/server.go`）。baseURL 通过 `sidecar.port` 文件动态发现。Swift 原生客户端**不**使用这套 API（它直接调 frpc Admin API + 持久化文件），但跨平台客户端的 API 契约需要与 Swift 行为对齐。

### 8A.1 端点列表
| Method | Path | 用途 |
|---|---|---|
| GET | `/api/status` | 返回 `{configured, running, connected, pid}` |
| GET / POST | `/api/server-config` | 读取 / 保存 `ServerConfig` |
| POST | `/api/test-connection` | body `{addr, port}`，返回 `{ok, err?}`，TCP 5s 探活（对齐 Swift `NetworkHelper.testConnection`） |
| GET / POST | `/api/autostart` | 读取 `{enabled, available}` / POST `{enabled}` 注册或注销开机自启 |
| GET / POST / PUT / DELETE | `/api/tunnels` | 隧道 CRUD |
| POST | `/api/tunnels/<id>/toggle` | body `{enabled}` 切换启用 |
| POST | `/api/control/{start,stop,restart}` | 控制 frpc 生命周期 |
| GET / DELETE | `/api/events` | 读取 / 清空事件日志 |
| GET / POST | `/api/settings` | 读取 / 保存 `AppSettings` |
| GET | `/api/domains` | 代理拉取服务端管理页域名目录（用 `ServerConfig.managementURL` + `domainAPIToken`）。返回 `{domains: [...], error?: "..."}`，失败时 domains 为空、error 非空，前端据此 fallback 到手填 |

### 8A.2 `/api/test-connection` 契约
- body: `{"addr": "tunnel.example.com", "port": 7000}`
- 返回: `{"ok": true}` 或 `{"ok": false, "err": "dial tcp ...: connection refused"}`
- 实现：`frpc.TestConnection` 用 `net.DialTimeout("tcp", host:port, 5s)`
- 不传凭据，只测 TCP 可达

### 8A.3 `/api/autostart` 契约
- GET 返回 `{"enabled": bool, "available": bool}`：`available` 报告当前平台是否支持
- POST body `{"enabled": true}` 注册，`{"enabled": false}` 注销
- 平台实现：
  - macOS：写 `~/Library/LaunchAgents/pub.mei.meilink.client.plist` + `launchctl load/unload`
  - Linux：写 `~/.config/systemd/user/meilink-client.service` + `systemctl --user enable/disable`
  - Windows：注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 写 `Meilink` 值
  - 其他平台：返回 501
- 与 Swift `AutoStartManager`（`SMAppService.mainApp`）的差异：macOS 上 Swift 用 `SMAppService`，Go 用 LaunchAgent plist——两者机制不同但效果一致（登录后自启）。Swift 客户端不会读 Go 写的 plist，反之亦然，但两者各自独立工作。

## 9. frps 服务端配置契约

### 9.1 `frps.toml` 必填字段（`server/bare-metal/deploy-frps.sh` 校验）
- `bindPort` — 客户端连接端口
- `vhostHTTPPort` — HTTP 子域名访问端口
- `vhostHTTPSPort` — HTTPS 子域名访问端口
- `subDomainHost` — 子域名基域（不能是默认占位 `tunnel.yourdomain.com`）
- `auth.token` — 认证 token（不能是默认占位 `your-secret-token-here`）

### 9.2 可选字段
- `webServer.addr` / `webServer.port` / `webServer.user` / `webServer.password` — frps Dashboard

### 9.3 示例
见 <kfile name="frps.toml" path="server/docker-compose/frps.toml">server/docker-compose/frps.toml</kfile> 与 <kfile name="frps.toml.example" path="client/macos-native/Resources/frps.toml.example">frps.toml.example</kfile>。

## 10. DNS 契约

- 用户需在域名管理处加 A 记录泛解析：`*.<subDomainHost>` → VPS IP
- 客户端不验证 DNS，只显示引导文案（`DNSGuideView`）
- `NetworkHelper.validateSubDomainHost`：`parts.count >= 2 && parts.allSatisfy { !$0.isEmpty }`（非空两段以上）

## 11. 端口契约

| 端口 | 默认 | 配置项 | 说明 |
|---|---|---|---|
| 7000 | frps bindPort | `ServerConfig.serverPort` | frpc → frps 控制连接 |
| 7400 | frpc Admin API | `ServerConfig.adminPort` | 应用 → frpc 本地管理 |
| 8080 | frps vhostHTTPPort | frps 端配置 | HTTP 子域名访问 |
| 8443 | frps vhostHTTPSPort | frps 端配置 | HTTPS 子域名访问 |

> 客户端不直接访问 8080/8443，只通过 frps 转发；远程探活时 HTTP 探 80、HTTPS 探 443（见 `02-features.md` F4.2）。

## 12. 事件日志契约

### 12.1 `EventLog` 结构
- `id: UUID`，`timestamp: Date`，`message: String`，`level: LogLevel`
- `LogLevel`: `info` / `warning` / `error`

### 12.2 容量与顺序
- `TunnelManager.events` 是 `[EventLog]`，新事件 `insert(at: 0)`（倒序，最新在前）
- 容量 100，超出 `events.prefix(100)` 截断

### 12.3 来源
- 应用内部：`addEvent(message, level)` 显式调用
- frpc 输出：`FrpcProcess.onOutput` 每行作为 `frpc: <line>` 事件

## 13. 版本与构建标识

- `CFBundleShortVersionString`: `1.0.0`（Info.plist + project.yml）
- `CFBundleVersion`: `1.0`
- `CFBundleIdentifier`: `pub.mei.meilink`（Swift 原生；Tauri 桌面客户端的 bundleId 见 `client/desktop/src-tauri/tauri.conf.json`）
- frp 版本：`v0.70.0`（硬编码在六处：`scripts/assets/download-frpc.sh` / `scripts/build/build-frpc.sh` / `scripts/build/build-desktop.sh` / `server/bare-metal/deploy-frps.sh` / `server/docker-managed/Dockerfile` / `server/setup/main.go`）
- 发布版本号：`1.1.0`（`scripts/build/build-all.sh` 默认参数，可覆盖）
