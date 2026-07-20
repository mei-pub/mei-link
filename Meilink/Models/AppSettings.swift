import Foundation

struct AppSettings: Codable, Sendable {
    var autoStart: Bool
    var launchAtLogin: Bool
    var showInDock: Bool
    var statusPollingInterval: TimeInterval

    init(
        autoStart: Bool = true,
        launchAtLogin: Bool = false,
        showInDock: Bool = false,
        statusPollingInterval: TimeInterval = 3.0
    ) {
        self.autoStart = autoStart
        self.launchAtLogin = launchAtLogin
        self.showInDock = showInDock
        self.statusPollingInterval = statusPollingInterval
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
