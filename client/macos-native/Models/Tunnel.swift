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

    /// 容错解码：跨平台 Go sidecar 写 tunnels.json 时不持久化运行期字段
    /// （status / errorMessage / remoteAddr），Swift 默认 Codable 合成会因
    /// `status` 缺失而整个解码失败 → loadTunnels() 返回空 → 主界面列表空。
    /// 这里手动解码，运行期字段缺失时用默认值，和 AppSettings 的容错模式一致
    /// （见 SDD 05-data-contract §2.1：运行期字段是 transient，由 pollStatus 覆盖）。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(TunnelType.self, forKey: .type)
        localPort = try c.decode(Int.self, forKey: .localPort)
        localIP = try c.decodeIfPresent(String.self, forKey: .localIP) ?? "127.0.0.1"
        subdomain = try c.decodeIfPresent(String.self, forKey: .subdomain)
        remotePort = try c.decodeIfPresent(Int.self, forKey: .remotePort)
        customDomains = try c.decodeIfPresent([String].self, forKey: .customDomains) ?? []
        httpUser = try c.decodeIfPresent(String.self, forKey: .httpUser)
        httpPassword = try c.decodeIfPresent(String.self, forKey: .httpPassword)
        hostHeaderRewrite = try c.decodeIfPresent(String.self, forKey: .hostHeaderRewrite)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        // Runtime fields — fall back to defaults when absent (not persisted by
        // the Go sidecar). pollStatus / recoverConnection overwrites them.
        status = try c.decodeIfPresent(TunnelStatus.self, forKey: .status) ?? .new
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        remoteAddr = try c.decodeIfPresent(String.self, forKey: .remoteAddr)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    func toProxyDefinition(serverConfig: ServerConfig? = nil) -> ProxyDefinition {
        let normalizedSubdomain = SubdomainNormalizer.normalize(
            subdomain,
            baseHost: serverConfig?.subDomainHost
        )

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
                    subdomain: normalizedSubdomain,
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
                    subdomain: normalizedSubdomain,
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
