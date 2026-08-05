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

### 1.3 SDD 文档
- [../sdd/03-architecture.md](../sdd/03-architecture.md) §4-§6（状态机 / 连接状态判定 / 自动恢复策略）
- [../sdd/06-constraints.md](../sdd/06-constraints.md) §4（并发约束）

## 2. 必读不变量

### 2.1 硬编码阈值（不能随意改）
| 常量 | 值 | 位置 | 说明 |
|---|---|---|---|
| `maxConsecutiveFailuresBeforeRecovery` | 3 | `TunnelManager` | 连续 3 次失败才触发恢复 |
| `recoveryCooldown` | 20 秒 | `TunnelManager` | 距上次恢复不足 20s 跳过 |
| `statusPollingInterval` clamp | [3, 30] | `startStatusPolling` | 即使设置成 1 也按 3 跑 |
| `remoteReachabilityInterval` clamp | [30, 600] | `shouldProbeReachability` | 设置范围外会被 clamp |
| frpc 异常退出后 sleep | 2 秒 | `FrpcProcess.onTermination` | 防抖 |
| 恢复前 sleep | 1 秒 | `recoverConnection` | 给进程退出留时间 |
| `waitForAdminAPI` 超时 | 5 秒 | `start()` | 启动路径 |
| `waitForAdminAPIAsync` 超时 | 15 秒 | `restart()` | 重启路径 |
| 探活 TCP 超时 | 4 秒 | `TunnelReachabilityProbe` | NWConnection 超时 |
| Admin API 请求超时 | 10 秒 | `FrpcAdminAPI` | `URLSessionConfiguration.timeoutIntervalForRequest` |

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
1. **轮询触发**：`pollStatus` 失败累计 3 次 → `recoverConnection`
2. **进程退出触发**：`FrpcProcess.onTermination` 非 0 退出 → sleep 2s → `recoverConnection`

两条路径都受 `isRecovering` + `recoveryCooldown` 保护。

### 2.6 恢复流程
`recoverConnection` 的顺序不能变：

1. 检查 `isRecovering`（重入保护）
2. 检查 `recoveryCooldown`（20s 冷却）
3. `isRecovering = true` + `lastRecoveryAt = Date()`
4. 记 warning 日志
5. 停 `statusTimer`
6. `frpcProcess.stopImmediately()`
7. `isFrpcRunning = false` + `isConnected = false`
8. sleep 1s
9. `consecutiveFailures = 0`
10. `start(force: true)`
11. `isRecovering = false`

## 3. 同步修改清单

### 3.1 改阈值
- [ ] `TunnelManager.swift`：改常量值
- [ ] 跨平台：`manager.go` 同步
- [ ] SDD：`03-architecture.md` §3.3 / `06-constraints.md` §4.3 同步

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
- [ ] `TunnelManager.swift`：`recoverConnection` / `recordConnectivityFailure`
- [ ] 不能去掉 `isRecovering` / `recoveryCooldown` 保护
- [ ] 不能去掉 sleep 1s（frpc 退出需要时间）
- [ ] 跨平台：`manager.go` 同步
- [ ] SDD：`03-architecture.md` §6 同步

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

### 4.4 反例：恢复不加冷却
```swift
// ❌ 错误：每次失败都恢复，会陷入恢复风暴
private func recordConnectivityFailure(reason: String) async {
    consecutiveFailures += 1
    await recoverConnection(reason: reason)  // 没 cooldown
}

// ✅ 正确：累计 3 次且过冷却才恢复
guard consecutiveFailures >= maxConsecutiveFailuresBeforeRecovery else { return }
if let lastRecoveryAt, Date().timeIntervalSince(lastRecoveryAt) < recoveryCooldown { return }
await recoverConnection(reason: reason)
```

### 4.5 反例：恢复不 sleep
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

1. `swift build` 编译通过
2. 启动应用 + 配置 + 添加隧道 → 状态轮询正常，`isConnected` 变 true
3. 手动 kill frpc 进程（`pkill -f frpc`）→ 2s 后自动恢复，日志显示"连接连续异常，正在自动重连"
4. 拔网线 / 改 hosts 让外网不可达 → 3 次失败后触发恢复
5. 30s 内连续 kill frpc 多次 → 只触发一次恢复（冷却生效）
6. 短时间内多次重启 → 不出现恢复风暴
7. UDP 隧道不会被探活（不会被标 checkFailed）
8. 跨平台客户端行为一致
