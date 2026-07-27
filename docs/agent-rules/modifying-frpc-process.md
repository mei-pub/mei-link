# Agent Rule · 修改 frpc 进程管理

> **何时触发**：当任务涉及修改 `FrpcProcess`（启动/停止/强杀）、frpc 二进制查找、`Process` 配置、stdout/stderr 处理、`terminationHandler`、端口释放、或退出时的强杀逻辑时。

> **必读 SDD**：[../sdd/03-architecture.md](../sdd/03-architecture.md) §3.4 / §7（FrpcProcess 职责 + 并发模型）、[../sdd/06-constraints.md](../sdd/06-constraints.md) §3（生命周期约束）。

## 1. 涉及文件清单

### 1.1 Swift 原生客户端
- <kfile name="FrpcProcess.swift" path="Meilink/Core/FrpcProcess.swift">Meilink/Core/FrpcProcess.swift</kfile>
  - `start` / `stop` / `stopImmediately` / `findFrpcPath`
  - `onOutput` / `onTermination` / `onStarted` 回调
- <kfile name="TunnelManager.swift" path="Meilink/Core/TunnelManager.swift">Meilink/Core/TunnelManager.swift</kfile>
  - `init` 里设置 `frpcProcess.onTermination`
  - `start(force:)` / `stop()` / `stopImmediately()` / `restart()` / `killFrpcOnExit()`
  - `releasePort`（保留方法，当前未调用）
- <kfile name="ConfigGenerator.swift" path="Meilink/Core/ConfigGenerator.swift">Meilink/Core/ConfigGenerator.swift</kfile>
  - frpc.toml 生成 + 写文件 0600
- <kfile name="MeilinkApp.swift" path="Meilink/App/MeilinkApp.swift">Meilink/App/MeilinkApp.swift</kfile>
  - `applicationWillTerminate` 调 `killFrpcOnExit`
- <kfile name="project.yml" path="project.yml">project.yml</kfile>
  - `preBuildScripts` 调 `Scripts/download-frpc.sh`
- <kfile name="download-frpc.sh" path="Scripts/download-frpc.sh">Scripts/download-frpc.sh</kfile>
  - frpc 下载 + 版本号
- <kfile name="build-frpc.sh" path="Scripts/build-frpc.sh">Scripts/build-frpc.sh</kfile>
  - frpc 源码编译（可选）

### 1.2 跨平台客户端
- `cross-platform-client/internal/frpc/process.go`
- `cross-platform-client/internal/frpc/download.go`

### 1.3 SDD 文档
- [../sdd/03-architecture.md](../sdd/03-architecture.md) §3.4 / §7.4
- [../sdd/05-data-contract.md](../sdd/05-data-contract.md) §6（frpc.toml 生成规则）
- [../sdd/06-constraints.md](../sdd/06-constraints.md) §2.4 / §3.4 / §3.5

## 2. 必读不变量

### 2.1 frpc 二进制查找顺序
1. `Bundle.main.executableURL.deletingLastPathComponent()/frpc`（同目录，即 `.app/Contents/MacOS/frpc`）
2. `Bundle.main.path(forResource: "frpc", ofType: nil)`（Resources 目录 fallback）
3. 都找不到 → 抛 `FrpcProcessError.binaryNotFound`

**不能改成运行期下载**。frpc 二进制必须在构建期就准备好（`project.yml` 的 `preBuildScripts` 调 `Scripts/download-frpc.sh`）。

### 2.2 frpc 版本
- 硬编码：`v0.70.0`
- 三个文件必须同步：
  - `Scripts/download-frpc.sh` 第 4 行 `FRP_VERSION="${FRP_VERSION:-v0.70.0}"`
  - `Scripts/build-frpc.sh` 第 4 行
  - `deploy-frps.sh` 第 10 行

升级 frp 版本必须三处同步 + 实测 frpc.toml schema 兼容性。

### 2.3 进程停止逐级加强
`FrpcProcess.stopImmediately(timeout:)` 的顺序不能简化：

1. `outputPipe.readabilityHandler = nil` / `errorPipe.readabilityHandler = nil`（先关 handler，防 stop 后还回调）
2. `process.terminate()`
3. 等 `timeout` 秒（`while process.isRunning && now - start < timeout`）
4. `process.interrupt()` → sleep 0.5s
5. `process.interrupt()` 再次 → sleep 0.5s
6. `kill -9 <pid>` → sleep 0.5s

**不能省略 `kill -9` 兜底**。frpc 偶尔会卡在清理阶段，不 kill 会导致端口被占用、下次启动失败。

### 2.4 退出时的强杀
`TunnelManager.killFrpcOnExit` 在 `applicationWillTerminate` 调用：

1. `frpcProcess.stopImmediately(timeout: 2.0)`
2. 若还活着，`kill -9 <pid>`

**不能省略这层兜底**。即使是正常退出，也要确保 frpc 完全终止，否则用户下次启动会因端口占用失败。

### 2.5 stdout/stderr 处理
- `Pipe.readabilityHandler` 异步按行回调
- `handleOutput` 按换行切分 + trim + 过滤空行
- 每行通过 `DispatchQueue.main.async` 派回主线程 → `onOutput` → `addEvent("frpc: <line>")`

**不能阻塞主线程**。Pipe 的 readabilityHandler 在后台队列触发，必须 main.async 派回。

### 2.6 `terminationHandler`
- 在 `DispatchQueue.main.async` 里派发 `onTermination`
- `TunnelManager.init` 设置的回调：
  - `isFrpcRunning = false` / `isConnected = false`
  - 停 `statusTimer`
  - 所有 enabled tunnel 置 `closed` + `errorMessage = "frpc 进程已退出，状态码: ..."`
  - 记日志（status == 0 → info，否则 error）
  - **若 status != 0**：sleep 2s → `recoverConnection`

**不能去掉 `status != 0` 判断**。正常停止（status == 0）不应触发恢复。

### 2.7 frpc.toml 文件权限
- `ConfigGenerator.writeToFile` 写文件后 `setAttributes posixPermissions: 0o600`
- **不能改成更宽松的权限**，文件里含 auth token + admin password。

### 2.8 `webServer.addr`
- `ConfigGenerator.generate` 永远输出 `webServer.addr = "127.0.0.1"`
- **不能改成 `0.0.0.0` 或对外地址**，Admin API 不能暴露。

## 3. 同步修改清单

### 3.1 改 frpc 版本
- [ ] `Scripts/download-frpc.sh`：改 `FRP_VERSION`
- [ ] `Scripts/build-frpc.sh`：改 `FRP_VERSION`
- [ ] `deploy-frps.sh`：改 `FRP_VERSION`
- [ ] 删除旧的 frpc 二进制（`rm Meilink.xcodeproj/DerivedData/.../frpc` 或 `rm .build/.../frpc`）
- [ ] 重新构建 + 实测 frpc.toml schema 兼容（特别是 `transport.*` / `webServer.*` / `[store]` 字段）
- [ ] SDD：`05-data-contract.md` §6.1 / `06-constraints.md` §6.5 / `07-build-release.md` §2.4 同步

### 3.2 改进程停止策略
- [ ] `FrpcProcess.swift`：`stopImmediately`
- [ ] 不能去掉 `readabilityHandler = nil`（否则 stop 后还回调会崩）
- [ ] 不能去掉 `kill -9` 兜底
- [ ] `TunnelManager.restart`：若改了 `stopImmediately` 的 timeout，同步检查后续 `kill -9` 兜底逻辑
- [ ] 跨平台：`process.go` 同步
- [ ] SDD：`03-architecture.md` §7.4 同步

### 3.3 改 frpc 二进制查找
- [ ] `FrpcProcess.swift`：`findFrpcPath`
- [ ] 若加新路径，必须 fallback 到现有两个路径
- [ ] 跨平台：`process.go` 同步
- [ ] SDD：`06-constraints.md` §2.4 同步

### 3.4 改 stdout/stderr 处理
- [ ] `FrpcProcess.swift`：`handleOutput`
- [ ] 不能阻塞主线程
- [ ] 每行 trim + 过滤空行（避免 frpc 的空行刷屏 events）
- [ ] SDD：`03-architecture.md` §3.4 同步

### 3.5 改退出强杀
- [ ] `TunnelManager.swift`：`killFrpcOnExit`
- [ ] `MeilinkApp.swift`：`applicationWillTerminate`
- [ ] 不能省略 `kill -9` 兜底
- [ ] SDD：`06-constraints.md` §3.2 / §3.4 同步

### 3.6 改端口释放（releasePort）
- [ ] `TunnelManager.swift`：`releasePort`
- [ ] 当前未在任何主路径调用，若启用，必须先 `lsof -ti :<port>` 找 pid + 谨慎 `kill -9`
- [ ] 不能误杀其他进程（lsof 输出多个 pid 时要逐个判断）
- [ ] SDD：`06-constraints.md` §3.5 同步

## 4. 反例

### 4.1 反例：进程停止只用 terminate
```swift
// ❌ 错误：terminate 后不等退出就返回，frpc 可能还在跑
process.terminate()

// ✅ 正确：terminate + 等退出 + interrupt + kill -9 兜底
process.terminate()
let start = Date()
while process.isRunning && Date().timeIntervalSince(start) < timeout {
    Thread.sleep(forTimeInterval: 0.05)
}
if process.isRunning {
    process.interrupt()
    Thread.sleep(forTimeInterval: 0.5)
    if process.isRunning {
        // kill -9 兜底
    }
}
```

### 4.2 反例：改 webServer.addr 对外
```swift
// ❌ 错误：Admin API 暴露给外网
lines.append("webServer.addr = \"0.0.0.0\"")

// ✅ 正确：永远 127.0.0.1
lines.append("webServer.addr = \"127.0.0.1\"")
```

### 4.3 反例：frpc.toml 不设权限
```swift
// ❌ 错误：默认权限，其他用户可读
try content.write(toFile: configPath, atomically: true, encoding: .utf8)

// ✅ 正确：0600
try content.write(toFile: configPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath)
```

### 4.4 反例：terminationHandler 在后台线程更新状态
```swift
// ❌ 错误：@MainActor 属性在后台线程修改
process?.terminationHandler = { process in
    self.isFrpcRunning = false  // 后台线程改 @MainActor 属性
}

// ✅ 正确：派回主线程
process?.terminationHandler = { [weak self] process in
    DispatchQueue.main.async {
        self?.onTermination?(process.terminationStatus)
    }
}
```

### 4.5 反例：frpc 异常退出立即恢复
```swift
// ❌ 错误：没 sleep 2s 防抖，可能恢复风暴
self?.onTermination = { status in
    if status != 0 {
        Task { await self.recoverConnection(reason: "...") }
    }
}

// ✅ 正确：sleep 2s 给系统稳定
if status != 0 {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await self.recoverConnection(reason: "frpc 异常退出，正在自动重启")
    }
}
```

### 4.6 反例：退出时不强杀 frpc
```swift
// ❌ 错误：依赖 frpc 自己退出，可能泄漏
func applicationWillTerminate(_ notification: Notification) {
    // 不做任何事
}

// ✅ 正确：killFrpcOnExit 确保完全终止
func applicationWillTerminate(_ notification: Notification) {
    runtime.manager.killFrpcOnExit()
}
```

## 5. 验证步骤

1. `swift build` 编译通过
2. 启动应用 → frpc 进程在跑（`pgrep -f frpc`）
3. 关主窗口 → frpc 仍跑
4. 显式退出 → frpc 完全消失（`pgrep -f frpc` 无输出）
5. 退出后立即重启应用 → 不报端口占用
6. `kill -9 <frpc_pid>` 模拟异常 → 2s 后自动恢复
7. `pkill frpc` 模拟批量退出 → 不会触发多次恢复
8. 修改 frpc.toml 里的 adminPort → 重启后能连上新端口
9. 跨平台客户端行为一致
