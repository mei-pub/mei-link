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
    private let remoteReachabilityInterval: TimeInterval = 60

    private let logger = Logger(subsystem: "com.meilink", category: "TunnelManager")

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
        }

        loadConfiguration()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor in
                await self?.startIfNeeded()
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
        await start()
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

    func restart() async {
        await stop()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await start()
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
            Task { @MainActor in
                await self?.pollStatus()
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
        return Date().timeIntervalSince(lastReachabilityProbeAt) >= remoteReachabilityInterval
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
