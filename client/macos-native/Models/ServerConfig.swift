import Foundation

struct ServerConfig: Codable, Sendable {
    var serverAddr: String
    var serverPort: Int
    var authToken: String
    var subDomainHost: String
    var tlsEnabled: Bool
    var adminPort: Int
    var adminUser: String
    var adminPassword: String

    init(
        serverAddr: String = "",
        serverPort: Int = 7000,
        authToken: String = "",
        subDomainHost: String = "",
        tlsEnabled: Bool = true,
        adminPort: Int = 7400,
        adminUser: String = "admin",
        adminPassword: String = "admin"
    ) {
        self.serverAddr = serverAddr
        self.serverPort = serverPort
        self.authToken = authToken
        self.subDomainHost = subDomainHost
        self.tlsEnabled = tlsEnabled
        self.adminPort = adminPort
        self.adminUser = adminUser
        self.adminPassword = adminPassword
    }
}
