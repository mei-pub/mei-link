import Foundation

enum MenuBarIconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case link
    case appIcon
    case text

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .link: return "链路图标"
        case .appIcon: return "应用图标"
        case .text: return "状态图标"
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

    init(
        autoStart: Bool = true,
        launchAtLogin: Bool = false,
        showInDock: Bool = false,
        statusPollingInterval: TimeInterval = 3.0,
        remoteReachabilityInterval: TimeInterval = 60.0,
        menuBarIconStyle: MenuBarIconStyle = .appIcon
    ) {
        self.autoStart = autoStart
        self.launchAtLogin = launchAtLogin
        self.showInDock = showInDock
        self.statusPollingInterval = statusPollingInterval
        self.remoteReachabilityInterval = remoteReachabilityInterval
        self.menuBarIconStyle = menuBarIconStyle
    }

    enum CodingKeys: String, CodingKey {
        case autoStart
        case launchAtLogin
        case showInDock
        case statusPollingInterval
        case remoteReachabilityInterval
        case menuBarIconStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        showInDock = try container.decodeIfPresent(Bool.self, forKey: .showInDock) ?? false
        statusPollingInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .statusPollingInterval) ?? 3.0
        remoteReachabilityInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .remoteReachabilityInterval) ?? 60.0
        menuBarIconStyle = try container.decodeIfPresent(MenuBarIconStyle.self, forKey: .menuBarIconStyle) ?? .appIcon
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
