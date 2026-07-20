import Foundation

enum TunnelType: String, Codable, CaseIterable, Sendable {
    case tcp
    case udp
    case http
    case https
}

enum TunnelStatus: String, Codable, Sendable {
    case new
    case waitStart
    case startError
    case running
    case checkFailed
    case closed

    init(frpcPhase: String) {
        switch frpcPhase {
        case "new": self = .new
        case "wait start": self = .waitStart
        case "start error": self = .startError
        case "running": self = .running
        case "check failed": self = .checkFailed
        case "closed": self = .closed
        default: self = .new
        }
    }

    var displayName: String {
        switch self {
        case .new: return "新建"
        case .waitStart: return "连接中"
        case .startError: return "启动失败"
        case .running: return "运行中"
        case .checkFailed: return "检查失败"
        case .closed: return "已关闭"
        }
    }
}

struct Tunnel: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var type: TunnelType
    var localPort: Int
    var localIP: String
    var subdomain: String?
    var remotePort: Int?
    var customDomains: [String]
    var httpUser: String?
    var httpPassword: String?
    var hostHeaderRewrite: String?
    var enabled: Bool
    var status: TunnelStatus
    var errorMessage: String?
    var remoteAddr: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        type: TunnelType,
        localPort: Int,
        localIP: String = "127.0.0.1",
        subdomain: String? = nil,
        remotePort: Int? = nil,
        customDomains: [String] = [],
        httpUser: String? = nil,
        httpPassword: String? = nil,
        hostHeaderRewrite: String? = nil,
        enabled: Bool = true,
        status: TunnelStatus = .new,
        errorMessage: String? = nil,
        remoteAddr: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.localPort = localPort
        self.localIP = localIP
        self.subdomain = subdomain
        self.remotePort = remotePort
        self.customDomains = customDomains
        self.httpUser = httpUser
        self.httpPassword = httpPassword
        self.hostHeaderRewrite = hostHeaderRewrite
        self.enabled = enabled
        self.status = status
        self.errorMessage = errorMessage
        self.remoteAddr = remoteAddr
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func toProxyDefinition() -> ProxyDefinition {
        switch type {
        case .tcp:
            return ProxyDefinition(
                name: name,
                type: "tcp",
                tcp: TCPProxyConfig(
                    localIP: localIP,
                    localPort: localPort,
                    remotePort: remotePort ?? 0
                )
            )
        case .udp:
            return ProxyDefinition(
                name: name,
                type: "udp",
                udp: UDPProxyConfig(
                    localIP: localIP,
                    localPort: localPort,
                    remotePort: remotePort ?? 0
                )
            )
        case .http:
            return ProxyDefinition(
                name: name,
                type: "http",
                http: HTTPProxyConfig(
                    localIP: localIP,
                    localPort: localPort,
                    subdomain: subdomain,
                    customDomains: customDomains.isEmpty ? nil : customDomains,
                    locations: ["/"],
                    httpUser: httpUser,
                    httpPassword: httpPassword,
                    hostHeaderRewrite: hostHeaderRewrite
                )
            )
        case .https:
            return ProxyDefinition(
                name: name,
                type: "https",
                https: HTTPSProxyConfig(
                    localIP: localIP,
                    localPort: localPort,
                    subdomain: subdomain,
                    customDomains: customDomains.isEmpty ? nil : customDomains
                )
            )
        }
    }

    func updatedStatus(from resp: ProxyStatusResp) -> Tunnel {
        var copy = self
        copy.status = TunnelStatus(frpcPhase: resp.status)
        copy.errorMessage = resp.err.isEmpty ? nil : resp.err
        copy.remoteAddr = resp.remoteAddr.isEmpty ? nil : resp.remoteAddr
        return copy
    }
}
