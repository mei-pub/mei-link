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
    /// 服务端管理页地址（如 http://aicun.cc:17500），用于拉取域名目录，简化隧道编辑。
    /// 留空则隧道编辑走手填模式。与 frps 连接无关。
    var managementURL: String
    /// 拉取 GET /api/domains 用的 Bearer token（对应服务端 MEILINK_DOMAIN_API_TOKEN）。
    /// 与管理页登录账号密码独立。留空则不拉取。
    var domainAPIToken: String

    init(
        serverAddr: String = "",
        serverPort: Int = 7000,
        authToken: String = "",
        subDomainHost: String = "",
        tlsEnabled: Bool = true,
        adminPort: Int = 7400,
        adminUser: String = "admin",
        adminPassword: String = "admin",
        managementURL: String = "",
        domainAPIToken: String = ""
    ) {
        self.serverAddr = serverAddr
        self.serverPort = serverPort
        self.authToken = authToken
        self.subDomainHost = subDomainHost
        self.tlsEnabled = tlsEnabled
        self.adminPort = adminPort
        self.adminUser = adminUser
        self.adminPassword = adminPassword
        self.managementURL = managementURL
        self.domainAPIToken = domainAPIToken
    }

    private enum CodingKeys: String, CodingKey {
        case serverAddr, serverPort, authToken, subDomainHost, tlsEnabled, adminPort, adminUser, adminPassword
        case managementURL, domainAPIToken
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverAddr = try c.decodeIfPresent(String.self, forKey: .serverAddr) ?? ""
        serverPort = try c.decodeIfPresent(Int.self, forKey: .serverPort) ?? 7000
        authToken = try c.decodeIfPresent(String.self, forKey: .authToken) ?? ""
        subDomainHost = try c.decodeIfPresent(String.self, forKey: .subDomainHost) ?? ""
        tlsEnabled = try c.decodeIfPresent(Bool.self, forKey: .tlsEnabled) ?? true
        adminPort = try c.decodeIfPresent(Int.self, forKey: .adminPort) ?? 7400
        adminUser = try c.decodeIfPresent(String.self, forKey: .adminUser) ?? "admin"
        adminPassword = try c.decodeIfPresent(String.self, forKey: .adminPassword) ?? "admin"
        managementURL = try c.decodeIfPresent(String.self, forKey: .managementURL) ?? ""
        domainAPIToken = try c.decodeIfPresent(String.self, forKey: .domainAPIToken) ?? ""
    }
}
