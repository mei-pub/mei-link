import Foundation

/// 服务端域名目录里的一条记录。镜像服务端 config.ts 的 ManagedDomain（只读子集）。
struct DomainEntry: Codable, Identifiable, Hashable, Sendable {
    /// 域名，泛域名以 "*." 开头（如 "*.meichuanxue.com"），主域名是裸域名（如 "meichuanxue.com"）。
    let domain: String
    /// "primary"（主域名，对应 frps subDomainHost）或 "wildcard"（泛域名，对应 customDomain 模式）。
    let kind: String
    var id: String { domain }

    var isWildcard: Bool { kind == "wildcard" }
    /// 泛域名去掉 "*." 前缀的主机部分（用于拼前缀）；主域名则直接返回自身。
    var hostPart: String { domain.hasPrefix("*.") ? String(domain.dropFirst(2)) : domain }

    /// 把用户填的前缀拼成最终访问域名。
    /// - 主域名：admin + meichuanxue.com → admin.meichuanxue.com
    /// - 泛域名：admin + *.meichuanxue.com → admin.meichuanxue.com（替换 * 占位）
    func combined(prefix: String) -> String {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? hostPart : "\(trimmed).\(hostPart)"
    }
}

/// 从服务端管理页拉取域名目录。客户端不持久化，每次实时拉。
/// 失败时抛错，调用方（TunnelEditView）fallback 到手填模式。
enum DomainDirectory {
    struct Response: Codable { let domains: [DomainEntry] }

    static func fetch(managementURL: String, token: String) async throws -> [DomainEntry] {
        try await fetchDomains(from: managementURL, token: token, path: "/api/domains").domains
    }

    /// 一次性拉取客户端启动所需的全部信息（frps 地址/端口/token/子域名基域/域名目录）。
    /// 让 SetupView 只需填「管理页地址 + token」两个字段。
    static func fetchBootstrap(managementURL: String, token: String) async throws -> BootstrapInfo {
        let base = normalizeBase(managementURL)
        guard !base.isEmpty, !token.isEmpty else { throw DomainDirectoryError.notConfigured }
        guard let url = URL(string: "\(base)/api/bootstrap") else { throw DomainDirectoryError.invalidURL }
        return try await fetchAndDecode(BootstrapInfo.self, url: url, token: token)
    }

    private static func fetchDomains(from managementURL: String, token: String, path: String) async throws -> Response {
        let base = normalizeBase(managementURL)
        guard !base.isEmpty, !token.isEmpty else { throw DomainDirectoryError.notConfigured }
        guard let url = URL(string: "\(base)\(path)") else { throw DomainDirectoryError.invalidURL }
        return try await fetchAndDecode(Response.self, url: url, token: token)
    }

    private static func normalizeBase(_ managementURL: String) -> String {
        // 只去掉结尾的斜杠，保留 http:// 里的斜杠。
        // 注意：不能用 replacingOccurrences(of:"/")，那会删掉 http:// 的斜杠彻底破坏 URL。
        var base = managementURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    private static func fetchAndDecode<T: Decodable>(_ type: T.Type, url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DomainDirectoryError.invalidResponse }
        if http.statusCode == 404 { throw DomainDirectoryError.endpointDisabled }
        if http.statusCode == 401 { throw DomainDirectoryError.unauthorized }
        guard http.statusCode == 200 else { throw DomainDirectoryError.httpError(http.statusCode) }
        return try JSONDecoder().decode(type, from: data)
    }
}

/// 客户端启动信息：从服务端 /api/bootstrap 拉取，用于自动填充 ServerConfig。
struct BootstrapInfo: Codable {
    let serverAddr: String
    let serverPort: Int
    let authToken: String
    let subDomainHost: String
    let domains: [DomainEntry]
}

enum DomainDirectoryError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case endpointDisabled
    case unauthorized
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "未配置管理页地址或 token"
        case .invalidURL: return "管理页地址格式无效"
        case .invalidResponse: return "管理页响应无效"
        case .endpointDisabled: return "服务端未启用域名目录接口（未配 MEILINK_DOMAIN_API_TOKEN）"
        case .unauthorized: return "域名拉取 token 错误"
        case .httpError(let code): return "管理页返回错误（HTTP \(code)）"
        }
    }
}
