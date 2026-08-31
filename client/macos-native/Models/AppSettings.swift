import Foundation

enum MenuBarIconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case portal
    case topology
    case arrowRing
    case waveform
    case relay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .portal: return "门户"
        case .topology: return "拓扑"
        case .arrowRing: return "穿透"
        case .waveform: return "信号"
        case .relay: return "中继"
        }
    }

    var imageName: String {
        switch self {
        case .portal: return "portal"
        case .topology: return "topology"
        case .arrowRing: return "arrow-ring"
        case .waveform: return "waveform"
        case .relay: return "relay"
        }
    }
}

struct AppSettings: Codable, Sendable {
    var autoStart: Bool
    var launchAtLogin: Bool
    var showInDock: Bool
    var statusPollingInterval: TimeInterval
    var remoteReachabilityInterval: TimeInterval
    var menuBarIconStyle: MenuBarIconStyle
    /// 自动重连：断连后每次探测/等待的间隔（秒）。默认 10，clamp [3, 300]。
    var reconnectInterval: TimeInterval
    /// 自动重连：重建连接连续失败多少次后升级为重启 frpc。默认 3，clamp [1, 30]。
    var maxReconnectAttempts: Int
    /// 自动重连：重启 frpc 连续失败多少次后放弃自动恢复。默认 3，clamp [1, 30]。
    var maxRestartAttempts: Int

    init(
        autoStart: Bool = true,
        launchAtLogin: Bool = false,
        showInDock: Bool = false,
        statusPollingInterval: TimeInterval = 3.0,
        remoteReachabilityInterval: TimeInterval = 60.0,
        menuBarIconStyle: MenuBarIconStyle = .portal,
        reconnectInterval: TimeInterval = 10.0,
        maxReconnectAttempts: Int = 3,
        maxRestartAttempts: Int = 3
    ) {
        self.autoStart = autoStart
        self.launchAtLogin = launchAtLogin
        self.showInDock = showInDock
        self.statusPollingInterval = statusPollingInterval
        self.remoteReachabilityInterval = remoteReachabilityInterval
        self.menuBarIconStyle = menuBarIconStyle
        self.reconnectInterval = reconnectInterval
        self.maxReconnectAttempts = maxReconnectAttempts
        self.maxRestartAttempts = maxRestartAttempts
    }

    enum CodingKeys: String, CodingKey {
        case autoStart
        case launchAtLogin
        case showInDock
        case statusPollingInterval
        case remoteReachabilityInterval
        case menuBarIconStyle
        case reconnectInterval
        case maxReconnectAttempts
        case maxRestartAttempts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        showInDock = try container.decodeIfPresent(Bool.self, forKey: .showInDock) ?? false
        statusPollingInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .statusPollingInterval) ?? 3.0
        remoteReachabilityInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .remoteReachabilityInterval) ?? 60.0
        menuBarIconStyle = try container.decodeIfPresent(MenuBarIconStyle.self, forKey: .menuBarIconStyle) ?? .portal
        reconnectInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .reconnectInterval) ?? 10.0
        maxReconnectAttempts = try container.decodeIfPresent(Int.self, forKey: .maxReconnectAttempts) ?? 3
        maxRestartAttempts = try container.decodeIfPresent(Int.self, forKey: .maxRestartAttempts) ?? 3
    }
}

struct EventLog: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let message: String
    let level: LogLevel

    enum LogLevel: String, Sendable {
        case info
        case warning
        case error
    }

    init(message: String, level: LogLevel = .info) {
        self.id = UUID()
        self.timestamp = Date()
        self.message = message
        self.level = level
    }
}
