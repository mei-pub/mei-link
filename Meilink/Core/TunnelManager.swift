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

    private let frpcProcess = FrpcProcess()
    private var adminAPI: FrpcAdminAPI?
    private let configGenerator = ConfigGenerator()
    private let store = TunnelStore()
    private var statusTimer: Timer?

    private let logger = Logger(subsystem: "com.meilink", category: "TunnelManager")

    init() {
        loadConfiguration()
    }

    func loadConfiguration() {
        if let config = store.loadServerConfig() {
            serverConfig = config
            tunnels = store.loadTunnels()
            isConfigured = true
        }
    }

    func saveConfiguration(_ config: ServerConfig) throws {
        try store.saveServerConfig(config)
        serverConfig = config
        isConfigured = true

        try KeychainHelper.save("auth-token", value: config.authToken)
    }

    func start() async {
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
            addEvent("Admin API 未就绪，frpc 可能正在重连", level: .warning)
        }

        for tunnel in tunnels where tunnel.enabled {
            do {
                try await adminAPI?.createProxy(tunnel.toProxyDefinition(serverConfig: config))
            } catch {
                addEvent("恢复隧道 \"\(tunnel.name)\" 失败: \(error.localizedDescription)", level: .warning)
            }
        }

        startStatusPolling()
        addEvent("隧道管理器已启动")
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
            do {
                try await adminAPI?.createProxy(tunnel.toProxyDefinition(serverConfig: serverConfig))
                addEvent("隧道 \"\(tunnel.name)\" 已启用")
            } catch {
                addEvent("启用隧道 \"\(tunnel.name)\" 失败: \(error.localizedDescription)", level: .error)
                throw error
            }
        } else {
            try? await adminAPI?.deleteProxy(name: tunnel.name)
            addEvent("隧道 \"\(tunnel.name)\" 已禁用")
        }

        if let idx = tunnels.firstIndex(where: { $0.id == id }) {
            tunnels[idx] = tunnel
            try store.saveTunnels(tunnels)
        }
    }

    // MARK: - Status Polling

    private func startStatusPolling() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollStatus()
            }
        }
    }

    private func pollStatus() async {
        guard adminAPI != nil else { return }

        do {
            let statusResponse = try await adminAPI?.getStatus()

            for idx in tunnels.indices {
                let tunnel = tunnels[idx]
                if let proxyStatuses = statusResponse?[tunnel.type.rawValue],
                   let status = proxyStatuses.first(where: { $0.name == tunnel.name }) {
                    tunnels[idx] = tunnel.updatedStatus(from: status)
                }
            }

            isConnected = true
        } catch {
            isConnected = false
        }
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
