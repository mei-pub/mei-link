import Foundation

enum StorageError: Error, LocalizedError {
    case directoryCreationFailed
    case saveFailed(Error)
    case loadFailed(Error)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed: return "无法创建存储目录"
        case .saveFailed(let err): return "保存失败: \(err.localizedDescription)"
        case .loadFailed(let err): return "加载失败: \(err.localizedDescription)"
        }
    }
}

struct TunnelStore {
    private let baseURL: URL
    private let tunnelsFile = "tunnels.json"
    private let configFile = "config.json"
    private let settingsFile = "settings.json"

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        baseURL = paths[0].appendingPathComponent("Meilink")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    // MARK: - Tunnels

    func saveTunnels(_ tunnels: [Tunnel]) throws {
        let data = try encoder.encode(tunnels)
        try data.write(to: baseURL.appendingPathComponent(tunnelsFile))
    }

    func loadTunnels() -> [Tunnel] {
        let url = baseURL.appendingPathComponent(tunnelsFile)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([Tunnel].self, from: data)) ?? []
    }

    // MARK: - Server Config

    func saveServerConfig(_ config: ServerConfig) throws {
        let data = try encoder.encode(config)
        try data.write(to: baseURL.appendingPathComponent(configFile))
    }

    func loadServerConfig() -> ServerConfig? {
        let url = baseURL.appendingPathComponent(configFile)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ServerConfig.self, from: data)
    }

    // MARK: - Settings

    func saveSettings(_ settings: AppSettings) throws {
        let data = try encoder.encode(settings)
        try data.write(to: baseURL.appendingPathComponent(settingsFile))
    }

    func loadSettings() -> AppSettings {
        let url = baseURL.appendingPathComponent(settingsFile)
        guard let data = try? Data(contentsOf: url) else { return AppSettings() }
        return (try? decoder.decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    // MARK: - Config Path

    var configDirectory: URL { baseURL }

    var frpcConfigPath: String {
        baseURL.appendingPathComponent("frpc.toml").path
    }

    var storePath: String {
        baseURL.appendingPathComponent("store.json").path
    }
}
