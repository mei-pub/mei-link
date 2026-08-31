# Agent Rule · 修改状态轮询 / 自动重连 / 探活

> **何时触发**：当任务涉及修改 `TunnelManager.pollStatus` / `recordConnectivityFailure` / `recoverConnection` / `TunnelReachabilityProbe` / 状态轮询 Timer / 自动恢复阈值 / frpc 异常退出回调时。

> **必读 SDD**：[../sdd/03-architecture.md](../sdd/03-architecture.md)（架构 + 状态机 + 自动恢复）、[../sdd/06-constraints.md](../sdd/06-constraints.md)（并发约束）。

## 1. 涉及文件清单

### 1.1 Swift 原生客户端
- <kfile name="TunnelManager.swift" path="client/macos-native/Core/TunnelManager.swift">client/macos-native/Core/TunnelManager.swift</kfile>
  - `startStatusPolling` / `pollStatus` / `shouldProbeReachability` / `probeReachability`
  - `recordConnectivityFailure` / `recoverConnection`
  - `waitForAdminAPI` / `waitForAdminAPIAsync`
  - 硬编码常量：`maxConsecutiveFailuresBeforeRecovery = 3` / `recoveryCooldown = 20`
- <kfile name="TunnelReachabilityProbe.swift" path="client/macos-native/Core/TunnelReachabilityProbe.swift">client/macos-native/Core/TunnelReachabilityProbe.swift</kfile>
  - `check` / `checkTCP` / `LockedFlag`
- <kfile name="FrpcProcess.swift" path="client/macos-native/Core/FrpcProcess.swift">client/macos-native/Core/FrpcProcess.swift</kfile>
  - `onTermination` 回调（frpc 异常退出触发恢复）
- <kfile name="AppSettings.swift" path="client/macos-native/Models/AppSettings.swift">client/macos-native/Models/AppSettings.swift</kfile>
  - `statusPollingInterval` / `remoteReachabilityInterval`

### 1.2 跨平台客户端
- `client/desktop/sidecar/internal/tunnel/manager.go`
- `client/desktop/sidecar/internal/frpc/admin_api.go`
- `client/docker/src/reconnect.ts` — Docker 客户端可配置两段式重连状态机（重建连接 → 重启 frpc → 放弃）
- `client/docker/src/manager.ts` — watchdog 接线（`armReconnect` / `disarmReconnect` / `startFrpc` 退出回调 kick / 探活 / 重启）
- `client/docker/src/frpc-log.ts` — `isFrpcConnectionFailure`（匹配 frp v0.70 `connect to server error`）

### 1.3 SDD 文档
- [../sdd/03-architecture.md](../sdd/03-architecture.md) §4-§6（状态机 / 连接状态判定 / 自动恢复策略）
- [../sdd/06-constraints.md](../sdd/06-constraints.md) §4（并发约束）

## 2. 必读不变量

### 2.1 恢复阈值（两段式，可配置）
三端一致的**可配置两段式重连**（macOS 原生 / 桌面 / Docker）：
- **第 1 段（重建连接）**：断连后 frpc 进程存活时其在后台自行重连，客户端按 `reconnectInterval` 周期探测计数（`consecutiveFailures`），连续失败达到 `maxReconnectAttempts`（默认 3）→ `recoverConnection`（重启）
- **第 2 段（重启 frpc）**：重启失败累计 `restartFailures` 达到 `maxRestartAttempts`（默认 3）→ 放弃（`reconnectFailed`），需手动"连接"或等连接自行恢复后自动解除
- 进程意外退出（`onTermination` 非 0 且非主动）直接进重启（sleep 2s 防抖）；手动"断开"不触发恢复
- 重启最小间隔 = `reconnectInterval`（替代原 20s 冷却）；被间隔挡下时**只重排轮询定时器、不做立即探测**（避免探测→拦截级联）
- 断连期间轮询间隔改用 `reconnectInterval`；健康时用 `statusPollingInterval`

| 参数 | 默认 | clamp | 位置 |
|---|---|---|---|
| `reconnectInterval` | 10s | [3, 300] | `AppSettings` / Go `AppSettings` / docker `ServerConfig` |
| `maxReconnectAttempts` | 3 | [1, 30] | 同上（Swift `recordConnectivityFailure` / Go `recordConnectivityFailure` / docker `ReconnectController`） |
| `maxRestartAttempts` | 3 | [1, 30] | 同上（Swift/Go `recoverConnection` / docker `ReconnectController`） |
| `statusPollingInterval` clamp | 3.0 | [3, 30] | `startStatusPolling` |
| `remoteReachabilityInterval` clamp | 60.0 | [30, 600] | `shouldProbeReachability` |
| frpc 异常退出后 sleep | 2 秒 | — | `FrpcProcess.onTermination` |
| 恢复前 sleep | 1 秒 | — | `recoverConnection` |
| `waitForAdminAPI` 超时 | 5 秒 | — | `start()` |
| `waitForAdminAPIAsync` 超时 | 15 秒 | — | `restart()` |
| 探活 TCP 超时 | 4 秒 | — | `TunnelReachabilityProbe` |
| Admin API 请求超时 | 10 秒 | — | `FrpcAdminAPI` |

> 三端默认值一致（10 / 3 / 3）。Docker 端实现为独立状态机 `client/docker/src/reconnect.ts`
> （先验证），Swift / Go 端逻辑见 `recoverConnection` / `recordConnectivityFailure`。

### 2.2 重入保护标志
- `isPollingStatus`：`pollStatus` 重入直接 return
- `isRecovering`：`recoverConnection` 重入直接 return
- `LockedFlag`（探活）：continuation 只 resume 一次

**不能去掉这些保护**。`pollStatus` 会被 Timer 周期触发 + `startStatusPolling` 启动时立即触发，可能撞一起；`recoverConnection` 会被 `recordConnectivityFailure` + frpc 退出回调同时触发。

### 2.3 状态判定顺序
`pollStatus` 的判定顺序不能变：

1. `adminAPI` 已初始化（否则 `recordConnectivityFailure("Admin API 未初始化")`）
2. `frpcProcess.isRunning`（否则 `isFrpcRunning = false` + `recordConnectivityFailure("frpc 进程已退出")`）
3. `adminAPI.getStatus()` 成功（否则 `recordConnectivityFailure("状态检测失败: ...")`）
4. 每条 tunnel 匹配到 status + `status == running` + `errorMessage == nil`（否则 `recordConnectivityFailure("隧道状态异常: ...")`）
5. 到探活时机 + 所有 tunnel `reachable`（否则 `recordConnectivityFailure("外网探活失败: ...")`）
6. 全部通过 → `consecutiveFailures = 0` + `isFrpcRunning = true` + `isConnected = true`

**不能跳过任何一层**，否则会出现"frpc 说 running 但外网不通"的假阳性。

### 2.4 探活类型差异
- HTTP → 远端 host:80
- HTTPS → 远端 host:443
- TCP → 远端 `tunnel.remotePort`
- UDP → `.skipped`（TCP 无法探活 UDP）

**不能对 UDP 强行探活**，TCP 探活 UDP 端口永远失败，会触发误恢复。

### 2.5 恢复路径两条
1. **轮询触发**：`pollStatus` 失败累计 `maxReconnectAttempts` 次 → `recoverConnection`
2. **进程退出触发**：`FrpcProcess.onTermination` 非 0 且非主动退出 → sleep 2s → `recoverConnection`（进程已死，"重建连接"无意义，直接重启）

两条路径都受 `isRecovering` 重入保护 + `reconnectInterval` 重启最小间隔保护。
若已 `reconnectFailed`（放弃），两条路径都不再触发恢复。

### 2.6 恢复流程
`recoverConnection` 的顺序不能变：

1. 检查 `isRecovering`（重入保护）
2. 检查 `reconnectFailed`（已放弃则不再恢复）
3. 检查重启最小间隔（距上次重启 < `reconnectInterval` → 只 `startStatusPolling(immediatePoll: false)` 重排轮询后返回）
4. `isRecovering = true` + `lastRestartAt = Date()`
5. 记 warning 日志
6. 停 `statusTimer`
7. `frpcProcess.stopImmediately()`
8. `isFrpcRunning = false` + `isConnected = false`
9. sleep 1s
10. `consecutiveFailures = 0` + `restartFailures += 1`
11. `start(force: true)`（Swift 返回 Bool；Go `Start()` 返回 error）
    - 成功 → `restartFailures = 0` + 记"frpc 重启成功"
    - 失败 → 记"第 N/maxRestartAttempts 次重启失败"；`restartFailures >= maxRestartAttempts` → `reconnectFailed = true` + `isReconnecting = false` + 记"自动重连已放弃"；随后 `startStatusPolling()` 保持轮询
12. `isRecovering = false`

## 3. 同步修改清单

### 3.1 改阈值
- [ ] `AppSettings.swift` / Go `config.go` / docker `config.ts`：改默认值（三端一致：`reconnectInterval` 10 / `maxReconnectAttempts` 3 / `maxRestartAttempts` 3）
- [ ] 三端使用点 clamp（Swift `TunnelManager` / Go `manager.go` / docker `normalizedConfig`）
- [ ] SDD：`03-architecture.md` §6 / `06-constraints.md` §4.3 同步

### 3.2 改轮询间隔
- [ ] `AppSettings.swift`：改 `statusPollingInterval` / `remoteReachabilityInterval` 默认值
- [ ] `TunnelManager.swift`：改 clamp 范围（`startStatusPolling` / `shouldProbeReachability`）
- [ ] `SettingsView.swift`：改 Stepper 范围（30-600 step 15）
- [ ] 跨平台：`config.go` + `settings.html` 同步
- [ ] SDD：`05-data-contract.md` §4 + `06-constraints.md` §4.3 同步

### 3.3 改探活逻辑
- [ ] `TunnelReachabilityProbe.swift`：改 `check` / `checkTCP`
- [ ] 注意 `LockedFlag` 的 continuation 只 resume 一次
- [ ] 若新增协议（如 UDP 探活），必须用 `NWConnection` with `.udp`，且不能阻塞主线程
- [ ] 跨平台：`admin.go` 或独立探活模块同步
- [ ] SDD：`03-architecture.md` §3.9 / `06-constraints.md` §4.2 同步

### 3.4 改恢复策略
- [ ] `TunnelManager.swift` / Go `manager.go` / docker `reconnect.ts`：`recoverConnection` / `recordConnectivityFailure`（三端逻辑一致）
- [ ] 不能去掉 `isRecovering` 重入保护
- [ ] 不能去掉 sleep 1s（frpc 退出需要时间）
- [ ] 被 `reconnectInterval` 最小间隔挡下时**只重排轮询、不做立即探测**（`startStatusPolling(immediatePoll: false)` / `startStatusPollingWithPoll(false)`），避免探测→拦截级联
- [ ] 新增/修改"重连中/重连失败"状态发布（Swift `@Published` / Go getter + `/api/status` / docker `/api/status`）
- [ ] SDD：`03-architecture.md` §6 / `06-constraints.md` §4.3 + §5 同步

### 3.5 改 frpc 退出回调
- [ ] `FrpcProcess.swift`：`onTermination` 回调
- [ ] `TunnelManager.swift`：`init` 里设置的 `frpcProcess.onTermination` 闭包
- [ ] 不能去掉"非 0 退出才恢复"的判断（0 退出是正常停止，不需要恢复）
- [ ] 不能去掉 sleep 2s 防抖

## 4. 反例

### 4.1 反例：去掉重入保护
```swift
// ❌ 错误：去掉 isPollingStatus
private func pollStatus() async {
    // 多个 Timer 触发会同时进来，状态乱掉
}

// ✅ 正确：保留重入保护
private func pollStatus() async {
    guard !isPollingStatus else { return }
    isPollingStatus = true
    defer { isPollingStatus = false }
    // ...
}
```

### 4.2 反例：跳过外网探活
```swift
// ❌ 错误：只看 frpc status，不探活外网
if allTunnelsRunning { isConnected = true }

// ✅ 正确：frpc status running 不代表外网可达，必须探活
if shouldProbeReachability() {
    let unreachable = await probeReachability(for: enabledTunnels)
    if !unreachable.isEmpty { await recordConnectivityFailure(...); return }
}
```

### 4.3 反例：UDP 强行 TCP 探活
```swift
// ❌ 错误：UDP 端口 TCP 永远连不上
case .udp:
    return await checkTCP(host: endpoint.host, port: endpoint.port)

// ✅ 正确：UDP 跳过
case .udp:
    return .skipped
```

### 4.4 反例：恢复不计数 / 不设间隔
```swift
// ❌ 错误：每次失败都恢复，或重启失败不计数，会陷入恢复风暴
private func recordConnectivityFailure(reason: String) async {
    consecutiveFailures += 1
    await recoverConnection(reason: reason)  // 无阈值、无重启失败计数
}

// ✅ 正确：累计 maxReconnectAttempts 次才重启；重启失败累计 maxRestartAttempts 次后放弃
guard consecutiveFailures >= maxReconnectAttempts else { return }
await recoverConnection(reason: reason)
// recoverConnection 内：restartFailures += 1；>= maxRestartAttempts → reconnectFailed = true
```

### 4.5 反例：重启间隔拦截分支做立即探测
```swift
// ❌ 错误：被 reconnectInterval 最小间隔挡下时 startStatusPolling() 会立即探测，
// 探测又触发恢复→拦截→再探测……形成快速级联
if withinReconnectInterval { startStatusPolling(); return }

// ✅ 正确：只重排定时器，不做立即探测，等定时器自然触发
if withinReconnectInterval { startStatusPolling(immediatePoll: false); return }
```

### 4.6 反例：恢复不 sleep
```swift
// ❌ 错误：stopImmediately 后立即 start，frpc 端口可能还没释放
frpcProcess.stopImmediately()
await start(force: true)

// ✅ 正确：sleep 1s 给进程退出留时间
frpcProcess.stopImmediately()
try? await Task.sleep(nanoseconds: 1_000_000_000)
await start(force: true)
```

## 5. 验证步骤

1. `swift build` 编译通过 / `go test ./...` / docker `npm test` 通过
2. 启动应用 + 配置 + 添加隧道 → 状态轮询正常，`isConnected` 变 true
3. 手动 kill frpc 进程（`pkill -f frpc`）→ 2s 后自动重启，日志显示"正在重启 frpc"，状态短暂进入"重连中"后恢复"已连接"
4. 拔网线 / 改 hosts 让外网不可达 → `maxReconnectAttempts` 次失败后触发重启
5. 服务器持续不可达 → 重启失败累计 `maxRestartAttempts` 次 → 状态"重连失败"，日志显示"自动重连已放弃"
6. 手动点"连接" → 清除"重连失败"，恢复正常轮询
7. 重启失败后立即再次 kill frpc → 被 `reconnectInterval` 最小间隔挡下，不出现快速重启风暴
8. UDP 隧道不会被探活（不会被标 checkFailed）
9. 三端（macOS 原生 / 桌面 / Docker）行为一致：阈值默认值、状态文案、放弃机制
