# 域名目录拉取 + 隧道编辑「选基域 + 填前缀」交互设计

> 日期：2026-08-05
> 状态：待 review

## 1. 背景与问题

### 1.1 现状
- HTTP/HTTPS 隧道在 frp 里有两种访问域名模式：
  - **subdomain**：客户端填前缀（如 `admin`），frps 用 `subDomainHost` 拼成 `admin.meichuanxue.com`。需要服务端配置 `subDomainHost`（即管理页的「主域名」）。
  - **customDomains**：客户端填完整域名（如 `admin.meichuanxue.com`），不依赖 `subDomainHost`。服务端配「泛域名」登记即可。
- macOS 与 Tauri 客户端的隧道编辑 UI **只暴露了 subdomain 输入框**，`customDomains` 字段在模型/持久化/frpc payload 里都已就绪，但 UI 从未暴露。
- 用户在服务端配了「泛域名」`*.meichuanxue.com`（不是主域名），导致 subdomain 模式的隧道报 `subdomain is not supported because this feature is not enabled in server`，永远起不来。

### 1.2 用户期望的交互
用户不想理解 frp 的 subdomain / customDomain 区别。期望：**在客户端选一个基域 + 填前缀，得到 `前缀.基域`，客户端自动适配成正确的 frp 字段。** 域名列表由服务端管理页统一维护，客户端只拉取用于简化交互。

### 1.3 架构约束
- 客户端只连 frps（如 `aicun.cc:7758`），不连管理页（如 `:17500`）。
- frps 本身不暴露「支持的域名列表」API。
- 客户端 `ServerConfig` 现在只有 `subDomainHost`（单字符串），不知道服务端配了哪些域名、什么用途。
- 域名目录的 source of truth 在服务端 `server.json` 的 `domains` 数组，管理页维护。

## 2. 核心原则

**客户端不存域名列表。** 域名列表只在服务端管理页维护，客户端每次需要时实时拉取（`GET /api/domains`），仅用于隧道编辑时的下拉交互。隧道最终只存 frp 需要的结果字段（`subdomain` / `customDomains`），不存"选了哪个基域"。

这样保证：
- 域名目录单一数据源（服务端），不会客户端/服务端不同步。
- 服务端管理页加/删/改域名，客户端下次编辑隧道立即看到最新列表。

## 3. 数据流

```
服务端管理页（source of truth）
  └─ server.json 的 domains 数组
       ├─ { domain: "meichuanxue.com",     kind: "primary",  enabled: true }
       └─ { domain: "*.meichuanxue.com",   kind: "wildcard", enabled: true }

客户端隧道编辑页（每次打开实时拉取，不持久化）
  GET {managementURL}/api/domains   （带 Bearer token）
  → 下拉列出：meichuanxue.com / *.meichuanxue.com
  → 用户选基域 + 填前缀 "admin"
  → 实时预览：admin.meichuanxue.com
  → 保存时按 kind 算出 frp 字段：
       选 primary  → tunnel.subdomain = "admin",  tunnel.customDomains = []
       选 wildcard → tunnel.subdomain = nil,      tunnel.customDomains = ["admin.meichuanxue.com"]
  → 写入 tunnels.json 的仍只有 subdomain / customDomains（不存"基域"）
```

## 4. 改动清单

### 4.1 服务端（`server/docker-managed/`）

#### 新增端点 `GET /api/domains`（token 认证）
- 位置：`src/server.ts`，在 `/healthz` 之后、auth 中间件之前注册（像 `/healthz` 一样是元数据端点，但**加 Bearer token 认证**）。
- 认证：读环境变量 `MEILINK_DOMAIN_API_TOKEN`。请求需带 `Authorization: Bearer <token>`。token 未配置时端点禁用（返回 404）。token 不匹配返回 401。
  - 用独立 token（不是管理页登录账号密码），避免客户端持有管理页凭据。
  - 用户在管理页 / 环境变量配置这个 token，客户端 SetupView 填一次。
- 响应：
  ```json
  {
    "domains": [
      { "domain": "meichuanxue.com",   "kind": "primary",  "enabled": true },
      { "domain": "*.meichuanxue.com", "kind": "wildcard", "enabled": true }
    ]
  }
  ```
  只返回 `enabled: true` 的域名。
- CORS：客户端跨域请求需加 `Access-Control-Allow-Origin`（限制来源）。因客户端是原生 app 发 HTTP，不走浏览器 CORS，实际不需要；但为保险加 `Access-Control-Allow-Headers: Authorization`。
- 不复用 `EnvironmentAuth`（那是登录会话），单独写一个常量时间比较的 token 校验。

#### 文档
- `server/docker-managed/README.md` 环境变量表加 `MEILINK_DOMAIN_API_TOKEN`（可选，配置后客户端可拉取域名列表）。

### 4.2 macOS 客户端（`client/macos-native/`）

#### 4.2.1 `ServerConfig` 加字段
```swift
var managementURL: String    // 如 "http://aicun.cc:17500"，空则不拉取
var domainAPIToken: String   // 拉取 /api/domains 用的 Bearer token，空则不拉取
```
默认空字符串。旧 server.json 容错解码（`decodeIfPresent`）。

#### 4.2.2 `SetupView` 加两个输入框
- 「管理页地址」：如 `http://aicun.cc:17500`
- 「域名拉取 Token」：对应 `MEILINK_DOMAIN_API_TOKEN`
- 都选填。不填则隧道编辑页 fallback 到手填模式。

#### 4.2.3 新增 `DomainDirectory`（域名拉取服务）
```swift
struct DomainEntry: Codable, Identifiable {
    let domain: String
    let kind: String      // "primary" | "wildcard"
    let enabled: Bool
    var id: String { domain }
}

enum DomainDirectory {
    /// 从服务端管理页拉取域名列表。失败抛错。
    static func fetch(managementURL: String, token: String) async throws -> [DomainEntry]
}
```
- URL 拼接：`{managementURL}/api/domains`，去掉重复斜杠。
- Header：`Authorization: Bearer {token}`。
- 超时：5 秒。
- 不缓存（每次实时拉）。

#### 4.2.4 `TunnelEditView` 改造（核心 UI 变化）
原来的「子域名」单输入框（仅 HTTP/HTTPS）改为：

**拉取成功时（有 managementURL + token 且请求成功）：**
- 「基域」下拉（Picker）：列出拉到的域名，显示 `meichuanxue.com` / `*.meichuanxue.com`，并标注类型（主/泛）。
- 「前缀」输入框：如 `admin`。
- 实时预览：`admin.meichuanxue.com`。
- 保存时按所选基域 kind 算出 subdomain / customDomains。

**fallback 时（没配 managementURL/token，或拉取失败）：**
- 显示原来的「子域名」单输入框（填 `admin`）。
- 保存时按原逻辑：subdomain = 填的值。
- 额外加一个「自定义域名」输入框（逗号分隔多个），存入 customDomains——补全这个一直缺失的 UI 入口。即使没拉取，用户也能手动填完整域名。

**编辑已有隧道时的回填逻辑：**
- 若隧道有 `subdomain`：fallback 模式直接填进子域名框；拉取模式下，若 subdomain + 某个主域名基域能拼出，自动选中该基域 + 前缀，否则进 fallback 显示。
- 若隧道有 `customDomains`：fallback 模式填进自定义域名框；拉取模式下，若某个 customDomain 去掉前缀后匹配某个泛域名基域，自动选中该基域 + 前缀，否则进 fallback 显示。

#### 4.2.5 `TunnelDisplay` 显示逻辑微调
`hostName(serverConfig:)` 现在只算 subdomain。改为：
1. 若有 customDomains 且非空，返回 customDomains.first。
2. 否则按原逻辑算 subdomain 拼接。
（保证用 customDomain 模式的隧道，列表/菜单栏能正确显示访问地址。）

#### 4.2.6 不改动的部分
- `Tunnel` 模型字段不变（subdomain / customDomains 都已存在）。
- `toProxyDefinition` 不变（已正确处理两个字段）。
- `ProxyDefinition` 不变。
- 持久化 schema 不变（ tunnels.json 还是 subdomain + customDomains）。

### 4.3 跨平台桌面客户端（`client/desktop/`）

按 rules §1.2 跨端对齐，同步改动：

#### 4.3.1 sidecar Go
- `internal/config/config.go`：`ServerConfig` 加 `ManagementURL` / `DomainAPIToken` 字段。
- `internal/tunnel/manager.go` 或新增 `internal/tunnel/domains.go`：实现 `FetchDomains`（调管理页）。
- sidecar 暴露给前端的 API：新增 `GET /api/domains`（sidecar 本地，代理到管理页的拉取），前端 tunnel-edit.html 调它。

#### 4.3.2 前端
- `src/settings.html`：加管理页地址 + token 输入框。
- `src/tunnel-edit.html`：子域名输入框改为「基域下拉 + 前缀」（拉取成功时）/「子域名 + 自定义域名」（fallback 时），逻辑与 macOS 对齐。

## 5. 认证与安全

- `GET /api/domains` 用独立 Bearer token（`MEILINK_DOMAIN_API_TOKEN`），不复用管理页登录账号密码。
- token 在服务端环境变量配置，客户端 SetupView 填一次存进 ServerConfig（持久化在客户端 `server.json`，与现有的 authToken 同等敏感度，靠文件权限 0600 保护）。
- token 校验用常量时间比较（`crypto.timingSafeEqual`），防时序攻击。
- 域名列表本身不含 token/密码，泄漏影响小；加 token 主要防止枚举和未授权拉取。

## 6. 错误处理与降级

| 情况 | 行为 |
|---|---|
| 没配 managementURL / token | 隧道编辑页 fallback 到手填模式（子域名 + 自定义域名框） |
| 拉取超时 / 网络错误 | fallback 到手填模式，顶部提示「无法连接管理页，手动填写」 |
| 拉取返回空列表 | fallback 到手填模式 |
| 服务端没配 MEILINK_DOMAIN_API_TOKEN（端点禁用） | 客户端收到 404，fallback 到手填模式 |
| token 不匹配（401） | fallback + 提示「token 错误」 |

核心原则：**拉取失败绝不阻塞隧道编辑**，永远能 fallback 到手填。

## 7. 兼容性

- 旧 `server.json`（无 managementURL/domainAPIToken）：加载不崩，字段默认空，走 fallback。
- 旧 `tunnels.json`（有 subdomain，无 customDomains）：加载不崩，编辑时按回填逻辑处理。
- frp payload 不变（subdomain + customDomains 早已支持）。
- 服务端 `MEILINK_DOMAIN_API_TOKEN` 可选，不配则端点禁用，现有部署不受影响。

## 8. 验证步骤

### 8.1 服务端
1. 配置 `MEILINK_DOMAIN_API_TOKEN=xxx`，`GET /api/domains` 无 token → 401；带正确 token → 200 + 域名列表。
2. 不配 token，端点 → 404。
3. 只返回 enabled 域名。

### 8.2 macOS 客户端
1. `swift build` 通过。
2. SetupView 配 managementURL + token，保存。
3. 新建 HTTP 隧道，基域下拉显示服务端域名，填前缀 admin，预览 admin.meichuanxue.com，保存。
4. tunnels.json 里：选主域名 → subdomain=admin；选泛域名 → customDomains=["admin.meichuanxue.com"]。
5. 列表/菜单栏访问地址正确显示。
6. 关掉 managementURL（设空），编辑页 fallback 到手填模式，仍能保存。
7. 拉取失败（错地址）→ fallback + 提示。

### 8.3 跨平台客户端
1. `go build` 通过。
2. 同样的端到端流程。

### 8.4 端到端
1. 服务端配主域名 meichuanxue.com，客户端选该基域 + 前缀 admin → 隧道运行中，访问 admin.meichuanxue.com 成功。
2. 服务端改配泛域名 *.meichuanxue.com（删主域名），客户端选该基域 + 前缀 admin → 隧道运行中，访问 admin.meichuanxue.com 成功。

## 9. 不做的事（YAGNI）

- ❌ 客户端不持久化域名列表（每次实时拉）。
- ❌ 客户端不维护/编辑域名列表（那是管理页的事）。
- ❌ Tunnel 模型不新增"基域"字段（只存最终 subdomain/customDomains）。
- ❌ 不改 frpc payload（早已支持）。
- ❌ 不做域名列表缓存（简单优先，每次实时拉）。
- ❌ 不做 WebSocket 推送域名变更（轮询/实时拉足够）。
