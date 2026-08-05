import Foundation
import Combine

@MainActor
class TunnelManager: ObservableObject {
    @Published var tunnels: [Tunnel] = []
    @Published var isConnected = false
    @Published var isFrpcRunning = false
    @Published var serverConfig: ServerConfig?
    @Published var events: [EventLog] = []
    @Published var isConfigured = false
    @Published var appSettings = AppSettings()

    private let frpcProcess = FrpcProcess()
    private var adminAPI: FrpcAdminAPI?
    private let configGenerator = ConfigGenerator()
    private let store = TunnelStore()
    private let reachabilityProbe = TunnelReachabilityProbe()
    private var statusTimer: Timer?
    private var isPollingStatus = false
    private var isRecovering = false
    private var consecutiveFailures = 0
    private var lastRecoveryAt: Date?
    private var lastReachabilityProbeAt: Date?

    private let maxConsecutiveFailuresBeforeRecovery = 3
    private let recoveryCooldown: TimeInterval = 20

    private let logger = Logger(subsystem: "pub.mei.meilink", category: "TunnelManager")

    init() {
        frpcProcess.onOutput = { [weak self] line in
            self?.addEvent("frpc: \(line)")
        }
        frpcProcess.onTermination = { [weak self] status in
            guard let self else { return }
            self.isFrpcRunning = false
            self.isConnected = false
            self.statusTimer?.invalidate()
            self.statusTimer = nil
            for idx in self.tunnels.indices {
                if self.tunnels[idx].enabled {
                    self.tunnels[idx].status = .closed
                    self.tunnels[idx].errorMessage = "frpc 进程已退出，状态码: \(status)"
                }
            }
            self.addEvent("frpc 进程已退出，状态码: \(status)", level: status == 0 ? .info : .error)

            // 自动重启：如果 frpc 非正常退出，尝试自动重启
            if status != 0 {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await self.recoverConnection(reason: "frpc 异常退出，正在自动重启")
                }
            }
        }

        loadConfiguration()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            // Bind self to a local constant before entering the concurrent Task
            // (Swift 5.10 release-mode concurrency checking rejects capturing
            // optional self? in a concurrently-executing closure).
            guard let self = self else { return }
            Task { @MainActor in
                await self.startIfNeeded()
            }
        }
    }

    func loadConfiguration() {
        appSettings = store.loadSettings()
        if let config = store.loadServerConfig() {
            serverConfig = config
            tunnels = store.loadTunnels()
            isConfigured = true
        }
    }

    func saveAppSettings(_ settings: AppSettings) throws {
        try store.saveSettings(settings)
        appSettings = settings
    }

    func rebuildMenuBarIcon() {
        addEvent("菜单栏图标已重建")
    }

    func saveConfiguration(_ config: ServerConfig) throws {
        try store.saveServerConfig(config)
        serverConfig = config
        isConfigured = true

        try KeychainHelper.save("auth-token", value: config.authToken)
    }

    func start() async {
        await start(force: false)
    }

    private func start(force: Bool) async {
        if isFrpcRunning, frpcProcess.isRunning, !force {
            return
        }

        if !frpcProcess.isRunning {
            isFrpcRunning = false
            isConnected = false
        }

        guard let config = serverConfig else {
            addEvent("未配置服务器", level: .error)
            return
        }

        addEvent("正在启动隧道管理器...")

        let toml = configGenerator.generate(serverConfig: config)
        do {
            let configPath = try configGenerator.writeToFile(toml)
            try frpcProcess.start(configPath: configPath)
            isFrpcRunning = true
            isConnected = false
        } catch {
            addEvent("启动 frpc 失败: \(error.localizedDescription)", level: .error)
            return
        }

        adminAPI = FrpcAdminAPI(
            port: config.adminPort,
            user: config.adminUser,
            password: config.adminPassword
        )

        do {
            try await waitForAdminAPI(timeout: 5.0)
        } catch {
            addEvent("Admin API 未就绪，启动未完成: \(error.localizedDescription)", level: .error)
            frpcProcess.stopImmediately()
            isFrpcRunning = false
            isConnected = false
            return
        }

        var restoredProxy = false
        var restoreFailures: [String] = []
        for tunnel in tunnels where tunnel.enabled {
            do {
                try await adminAPI?.createProxy(tunnel.toProxyDefinition(serverConfig: config))
                restoredProxy = true
            } catch {
                restoreFailures.append(tunnel.name)
                addEvent("恢复隧道 \"\(tunnel.name)\" 失败: \(error.localizedDescription)", level: .warning)
            }
        }

        if restoredProxy {
            do {
                try await adminAPI?.reload()
            } catch {
                addEvent("重载隧道配置失败: \(error.localizedDescription)", level: .warning)
            }
        }

        if !restoreFailures.isEmpty {
            isConnected = false
            addEvent("部分隧道恢复失败，等待自动重连: \(restoreFailures.joined(separator: ", "))", level: .warning)
        }

        startStatusPolling()
        addEvent("隧道管理器已启动，正在检测外部可达性")
    }

    func startIfNeeded() async {
        guard isConfigured, !isFrpcRunning else { return }
        addEvent("应用启动，执行深度重启流程", level: .info)
        await restart()
    }

    func stop() async {
        statusTimer?.invalidate()
        statusTimer = nil

        frpcProcess.stop()
        isFrpcRunning = false
        isConnected = false

        for idx in tunnels.indices {
            tunnels[idx].status = .closed
        }

        addEvent("隧道管理器已停止")
    }

    func stopImmediately() {
        statusTimer?.invalidate()
        statusTimer = nil

        frpcProcess.stopImmediately()
        isFrpcRunning = false
        isConnected = false
    }

    /// 强制终止 frpc 进程（应用退出时调用，确保 frpc 完全退出）
    func killFrpcOnExit() {
        if frpcProcess.isRunning, let pid = frpcProcess.processID {
            frpcProcess.stopImmediately(timeout: 2.0)
            if frpcProcess.isRunning {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/kill")
                task.arguments = ["-9", "\(pid)"]
                try? task.run()
                task.waitUntilExit()
            }
        }
    }

    /// 强制释放指定端口（杀死占用该端口的进程）
    private func releasePort(_ port: Int) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-ti", ":\(port)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = nil
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else { return }
        for pidStr in output.components(separatedBy: "\n") {
            let pid = pidStr.trimmingCharacters(in: .whitespaces)
            guard !pid.isEmpty else { continue }
            addEvent("释放端口 \(port): 杀死进程 \(pid)", level: .warning)
            let killTask = Process()
            killTask.executableURL = URL(fileURLWithPath: "/usr/bin/kill")
            killTask.arguments = ["-9", pid]
            try? killTask.run()
            killTask.waitUntilExit()
        }
    }

    func restart() async {
        addEvent("开始深度重启...", level: .info)

        // 第1层：停止状态轮询
        statusTimer?.invalidate()
        statusTimer = nil

        // 第2层：停止 frpc 进程（逐级加强）
        if frpcProcess.isRunning {
            frpcProcess.stopImmediately(timeout: 3.0)
            try? await Task.sleep(nanoseconds: 500_000_000)

            // 如果 frpc 仍未退出，用 kill -9 强制终止
            if frpcProcess.isRunning, let pid = frpcProcess.processID {
                addEvent("frpc 进程未能退出，尝试强制终止", level: .warning)
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/kill")
                task.arguments = ["-9", "\(pid)"]
                try? task.run()
                task.waitUntilExit()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        isFrpcRunning = false
        isConnected = false

        // 第3层：重新生成配置并启动 frpc（callback 驱动）
        guard let config = serverConfig else {
            addEvent("未配置服务器，重启失败", level: .error)
            return
        }

        let toml = configGenerator.generate(serverConfig: config)
        do {
            let configPath = try configGenerator.writeToFile(toml)
            try frpcProcess.start(configPath: configPath)
        } catch {
            addEvent("重启 frpc 失败: \(error.localizedDescription)", level: .error)
            return
        }
        isFrpcRunning = true
        isConnected = false

        // 第4层：等待 Admin API 就绪（异步 callback）
        adminAPI = FrpcAdminAPI(port: config.adminPort, user: config.adminUser, password: config.adminPassword)
        waitForAdminAPIAsync(timeout: 15.0) { [weak self] success in
            guard let self else { return }
            guard success else {
                self.addEvent("Admin API 未就绪，重启未完成", level: .error)
                return
            }

            // 第5层：恢复所有启用的隧道
            Task { @MainActor in
                var restoredProxy = false
                var restoreFailures: [String] = []
                for tunnel in self.tunnels where tunnel.enabled {
                    do {
                        try await self.adminAPI?.createProxy(tunnel.toProxyDefinition(serverConfig: config))
                        restoredProxy = true
                    } catch {
                        restoreFailures.append(tunnel.name)
                        self.addEvent("恢复隧道 \"\(tunnel.name)\" 失败: \(error.localizedDescription)", level: .warning)
                    }
                }

                if restoredProxy {
                    do {
                        try await self.adminAPI?.reload()
                    } catch {
                        self.addEvent("重载隧道配置失败: \(error.localizedDescription)", level: .warning)
                    }
                }

                if !restoreFailures.isEmpty {
                    self.isConnected = false
                    self.addEvent("部分隧道恢复失败，等待自动重连: \(restoreFailures.joined(separator: ", "))", level: .warning)
                }

                self.startStatusPolling()
                self.addEvent("深度重启完成", level: .info)
            }
        }
    }

    // MARK: - Tunnel CRUD

    func addTunnel(_ tunnel: Tunnel) async throws {
        guard serverConfig != nil else { throw MeilinkError.notConfigured }

        tunnels.append(tunnel)
        try store.saveTunnels(tunnels)

        do {
            try await adminAPI?.createProxy(tunnel.toProxyDefinition(serverConfig: serverConfig))
            try await adminAPI?.reload()
            addEvent("隧道 \"\(tunnel.name)\" 已创建")
        } catch {
            addEvent("创建隧道 \"\(tunnel.name)\" 失败: \(error.localizedDescription)", level: .error)
            throw error
        }
    }

    func updateTunnel(_ tunnel: Tunnel) async throws {
        guard serverConfig != nil else { throw MeilinkError.notConfigured }

        if let idx = tunnels.firstIndex(where: { $0.id == tunnel.id }) {
            tunnels[idx] = tunnel
            try store.saveTunnels(tunnels)
        }

        do {
            try await adminAPI?.updateProxy(name: tunnel.name, definition: tunnel.toProxyDefinition(serverConfig: serverConfig))
            try await adminAPI?.reload()
            addEvent("隧道 \"\(tunnel.name)\" 已更新")
        } catch {
            addEvent("更新隧道 \"\(tunnel.name)\" 失败: \(error.localizedDescription)", level: .error)
            throw error
        }
    }

    func deleteTunnel(id: UUID) async throws {
        guard let tunnel = tunnels.first(where: { $0.id == id }) else { return }

        do {
            try await adminAPI?.deleteProxy(name: tunnel.name)
            try await adminAPI?.reload()
        } catch {
            logger.warning("删除代理 API 调用失败: \(error)")
        }

        tunnels.removeAll { $0.id == id }
        try store.saveTunnels(tunnels)
        addEvent("隧道 \"\(tunnel.name)\" 已删除")
    }

    func toggleTunnel(id: UUID, enabled: Bool) async throws {
        guard var tunnel = tunnels.first(where: { $0.id == id }) else { return }

        tunnel.enabled = enabled
        if enabled {
            tunnel.status = .waitStart
            tunnel.errorMessage = nil
            do {
                try await adminAPI?.createProxy(tunnel.toProxyDefinition(serverConfig: serverConfig))
                try await adminAPI?.reload()
                addEvent("隧道 \"\(tunnel.name)\" 已启用")
            } catch {
                addEvent("启用隧道 \"\(tunnel.name)\" 失败: \(error.localizedDescription)", level: .error)
                throw error
            }
        } else {
            tunnel.status = .closed
            tunnel.errorMessage = nil
            try? await adminAPI?.deleteProxy(name: tunnel.name)
            try? await adminAPI?.reload()
            addEvent("隧道 \"\(tunnel.name)\" 已禁用")
        }

        if let idx = tunnels.firstIndex(where: { $0.id == id }) {
            tunnels[idx] = tunnel
            try store.saveTunnels(tunnels)
        }
    }

    // MARK: - Status Polling

    private func startStatusPolling() {
        statusTimer?.invalidate()
        lastReachabilityProbeAt = nil
        let pollingInterval = min(max(appSettings.statusPollingInterval, 3), 30)
        statusTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            // Bind self to a local constant before entering the concurrent Task
            // to avoid "reference to captured var 'self' in concurrently-executing
            // code" under Swift 5.10 release-mode concurrency checking.
            guard let self = self else { return }
            Task { @MainActor in
                await self.pollStatus()
            }
        }
        Task { @MainActor in
            await pollStatus()
        }
    }

    private func pollStatus() async {
        guard !isPollingStatus else { return }
        isPollingStatus = true
        defer { isPollingStatus = false }

        guard let adminAPI else {
            await recordConnectivityFailure(reason: "Admin API 未初始化")
            return
        }

        guard frpcProcess.isRunning else {
            isFrpcRunning = false
            await recordConnectivityFailure(reason: "frpc 进程已退出")
            return
        }

        do {
            let statusResponse = try await adminAPI.getStatus()

            for idx in tunnels.indices {
                let tunnel = tunnels[idx]
                if let proxyStatuses = statusResponse[tunnel.type.rawValue],
                   let status = proxyStatuses.first(where: { $0.name == tunnel.name }) {
                    tunnels[idx] = tunnel.updatedStatus(from: status)
                } else if tunnel.enabled {
                    tunnels[idx].status = .checkFailed
                    tunnels[idx].errorMessage = "frpc 未返回该隧道状态"
                }
            }

            let enabledTunnels = tunnels.filter(\.enabled)
            let unhealthyTunnels = enabledTunnels.filter { tunnel in
                tunnel.status != .running || tunnel.errorMessage != nil
            }

            if !unhealthyTunnels.isEmpty {
                let names = unhealthyTunnels.map(\.name).joined(separator: ", ")
                await recordConnectivityFailure(reason: "隧道状态异常: \(names)")
                return
            }

            if shouldProbeReachability() {
                let unreachableTunnels = await probeReachability(for: enabledTunnels)
                lastReachabilityProbeAt = Date()
                if !unreachableTunnels.isEmpty {
                    await recordConnectivityFailure(reason: "外网探活失败: \(unreachableTunnels.joined(separator: ", "))")
                    return
                }
            }

            consecutiveFailures = 0
            isFrpcRunning = true
            isConnected = true
        } catch {
            await recordConnectivityFailure(reason: "状态检测失败: \(error.localizedDescription)")
        }
    }

    private func shouldProbeReachability() -> Bool {
        guard let lastReachabilityProbeAt else { return true }
        let interval = min(max(appSettings.remoteReachabilityInterval, 30), 600)
        return Date().timeIntervalSince(lastReachabilityProbeAt) >= interval
    }

    private func probeReachability(for tunnels: [Tunnel]) async -> [String] {
        var failed: [String] = []
        for tunnel in tunnels {
            let result = await reachabilityProbe.check(tunnel: tunnel, serverConfig: serverConfig)
            switch result {
            case .reachable, .skipped:
                continue
            case .unreachable(let reason):
                if let idx = self.tunnels.firstIndex(where: { $0.id == tunnel.id }) {
                    self.tunnels[idx].status = .checkFailed
                    self.tunnels[idx].errorMessage = reason
                }
                failed.append(tunnel.name)
            }
        }
        return failed
    }

    private func recordConnectivityFailure(reason: String) async {
        consecutiveFailures += 1
        isConnected = false

        if consecutiveFailures == 1 {
            addEvent("连接检测失败: \(reason)", level: .warning)
        }

        guard consecutiveFailures >= maxConsecutiveFailuresBeforeRecovery else { return }
        await recoverConnection(reason: reason)
    }

    private func recoverConnection(reason: String) async {
        guard !isRecovering else { return }

        if let lastRecoveryAt,
           Date().timeIntervalSince(lastRecoveryAt) < recoveryCooldown {
            return
        }

        isRecovering = true
        lastRecoveryAt = Date()
        addEvent("连接连续异常，正在自动重连: \(reason)", level: .warning)

        statusTimer?.invalidate()
        statusTimer = nil

        frpcProcess.stopImmediately()
        isFrpcRunning = false
        isConnected = false

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        consecutiveFailures = 0
        await start(force: true)
        isRecovering = false
    }

    private func waitForAdminAPI(timeout: TimeInterval) async throws {
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            if let api = adminAPI, try await api.healthCheck() {
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw MeilinkError.adminAPINotReady
    }

    /// 异步等待 Admin API 就绪，通过 callback 通知结果（不阻塞调用线程）
    private func waitForAdminAPIAsync(timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        Task { [weak self] in
            guard let self else { return completion(false) }
            let startTime = Date()
            while Date().timeIntervalSince(startTime) < timeout {
                if let api = self.adminAPI, (try? await api.healthCheck()) == true {
                    completion(true)
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            completion(false)
        }
    }

    // MARK: - Events

    func addEvent(_ message: String, level: EventLog.LogLevel = .info) {
        let event = EventLog(message: message, level: level)
        events.insert(event, at: 0)
        if events.count > 100 {
            events = Array(events.prefix(100))
        }
        logger.info("[\(level.rawValue)] \(message)")
    }

    func clearEvents() {
        events.removeAll()
    }
}

enum MeilinkError: Error, LocalizedError {
    case notConfigured
    case adminAPINotReady

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "尚未配置服务器"
        case .adminAPINotReady: return "Admin API 未就绪"
        }
    }
}
