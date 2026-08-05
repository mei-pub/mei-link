import SwiftUI

extension Tunnel {
    func localAddressText() -> String {
        "\(localIP):\(localPort)"
    }

    func routeText(serverConfig: ServerConfig?) -> String {
        switch type {
        case .http:
            if let remoteAddr, !remoteAddr.isEmpty { return "http://\(remoteAddr)" }
            guard let host = hostName(serverConfig: serverConfig) else { return "未设置子域名" }
            return "http://\(host)"
        case .https:
            if let remoteAddr, !remoteAddr.isEmpty { return "https://\(remoteAddr)" }
            guard let host = hostName(serverConfig: serverConfig) else { return "未设置子域名" }
            return "https://\(host)"
        case .tcp, .udp:
            if let remoteAddr, !remoteAddr.isEmpty { return remoteAddr }
            return remotePort.map { "\(serverConfig?.serverAddr ?? "服务器"):\($0)" } ?? "等待分配远程端口"
        }
    }

    func shortRouteText(serverConfig: ServerConfig?) -> String {
        switch type {
        case .http, .https:
            return hostName(serverConfig: serverConfig) ?? "未设置子域名"
        case .tcp, .udp:
            return remotePort.map { ":\($0)" } ?? "auto"
        }
    }

    func openURL(serverConfig: ServerConfig?) -> URL? {
        switch type {
        case .http, .https:
            return URL(string: routeText(serverConfig: serverConfig))
        case .tcp, .udp:
            return nil
        }
    }

    private func hostName(serverConfig: ServerConfig?) -> String? {
        // 自定义域名优先（用户主动填的完整域名更重要）
        if let first = customDomains.first, !first.isEmpty { return first }

        guard let normalized = SubdomainNormalizer.normalize(
            subdomain,
            baseHost: serverConfig?.subDomainHost
        ) else {
            return nil
        }

        guard let baseHost = serverConfig?.subDomainHost, !baseHost.isEmpty else {
            return normalized
        }

        return "\(normalized).\(baseHost)"
    }
}

extension TunnelStatus {
    var tintColor: Color {
        switch self {
        case .running: return .green
        case .waitStart: return .yellow
        case .startError, .checkFailed: return .red
        case .new, .closed: return .gray
        }
    }
}
