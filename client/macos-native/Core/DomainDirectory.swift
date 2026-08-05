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
        let base = managementURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "") // 去掉尾部的 /
        guard !base.isEmpty, !token.isEmpty else {
            throw DomainDirectoryError.notConfigured
        }
        guard let url = URL(string: "\(base)/api/domains") else {
            throw DomainDirectoryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DomainDirectoryError.invalidResponse
        }
        if http.statusCode == 404 { throw DomainDirectoryError.endpointDisabled }
        if http.statusCode == 401 { throw DomainDirectoryError.unauthorized }
        guard http.statusCode == 200 else {
            throw DomainDirectoryError.httpError(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.domains
    }
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
