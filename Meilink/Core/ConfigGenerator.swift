import Foundation

struct ConfigGenerator {
    private let store: TunnelStore

    init(store: TunnelStore = TunnelStore()) {
        self.store = store
    }

    func generate(serverConfig: ServerConfig) -> String {
        var lines: [String] = []

        lines.append("serverAddr = \"\(serverConfig.serverAddr)\"")
        lines.append("serverPort = \(serverConfig.serverPort)")
        lines.append("")
        lines.append("auth.method = \"token\"")
        lines.append("auth.token = \"\(serverConfig.authToken)\"")
        lines.append("")
        lines.append("transport.tls.enable = \(serverConfig.tlsEnabled)")
        lines.append("transport.poolCount = 5")
        lines.append("transport.tcpMux = true")
        lines.append("transport.tcpMuxKeepaliveInterval = 30")
        lines.append("")
        lines.append("webServer.addr = \"127.0.0.1\"")
        lines.append("webServer.port = \(serverConfig.adminPort)")
        lines.append("webServer.user = \"\(serverConfig.adminUser)\"")
        lines.append("webServer.password = \"\(serverConfig.adminPassword)\"")
        lines.append("")
        lines.append("[store]")
        lines.append("path = \"\(store.storePath)\"")
        lines.append("")
        lines.append("# Proxies are managed dynamically via Store API")

        return lines.joined(separator: "\n")
    }

    @discardableResult
    func writeToFile(_ content: String) throws -> String {
        let configPath = store.frpcConfigPath
        try content.write(toFile: configPath, atomically: true, encoding: .utf8)

        let fileManager = FileManager.default
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configPath
        )

        return configPath
    }
}
