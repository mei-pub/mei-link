import Foundation
import Network

enum TunnelReachabilityResult: Sendable {
    case reachable
    case unreachable(String)
    case skipped
}

final class TunnelReachabilityProbe {
    private let session: URLSession
    private let tcpTimeout: TimeInterval

    init(timeout: TimeInterval = 4.0) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
        self.tcpTimeout = timeout
    }

    func check(tunnel: Tunnel, serverConfig: ServerConfig?) async -> TunnelReachabilityResult {
        guard tunnel.enabled, tunnel.status == .running else {
            return .skipped
        }

        switch tunnel.type {
        case .http:
            guard let url = externalURL(for: tunnel) else { return .skipped }
            return await checkHTTP(url)
        case .https:
            guard let endpoint = endpoint(for: tunnel, defaultPort: 443) else { return .skipped }
            return await checkTCP(host: endpoint.host, port: endpoint.port)
        case .tcp:
            guard let endpoint = endpoint(for: tunnel, defaultPort: tunnel.remotePort) else { return .skipped }
            return await checkTCP(host: endpoint.host, port: endpoint.port)
        case .udp:
            return .skipped
        }
    }

    private func externalURL(for tunnel: Tunnel) -> URL? {
        guard let remoteAddr = tunnel.remoteAddr, !remoteAddr.isEmpty else { return nil }
        return URL(string: "http://\(remoteAddr)")
    }

    private func endpoint(for tunnel: Tunnel, defaultPort: Int?) -> (host: String, port: Int)? {
        guard let remoteAddr = tunnel.remoteAddr, !remoteAddr.isEmpty else { return nil }

        if let url = URL(string: "\(tunnel.type == .https ? "https" : "tcp")://\(remoteAddr)"),
           let host = url.host {
            let port = url.port ?? defaultPort
            if let port { return (host, port) }
        }

        let parts = remoteAddr.split(separator: ":", maxSplits: 1).map(String.init)
        guard let host = parts.first, !host.isEmpty else { return nil }

        if parts.count == 2, let port = Int(parts[1]) {
            return (host, port)
        }

        guard let defaultPort else { return nil }
        return (host, defaultPort)
    }

    private func checkHTTP(_ url: URL) async -> TunnelReachabilityResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-2048", forHTTPHeaderField: "Range")
        request.setValue("Meilink/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard response is HTTPURLResponse else {
                return .unreachable("外部 HTTP 无响应")
            }

            if let body = String(data: data.prefix(4096), encoding: .utf8),
               body.localizedCaseInsensitiveContains("powered by frp")
                || body.localizedCaseInsensitiveContains("faithfully yours, frp") {
                return .unreachable("frps 返回未找到代理")
            }

            return .reachable
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }

    private func checkTCP(host: String, port: Int) async -> TunnelReachabilityResult {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: UInt16(port)) ?? 0,
                using: .tcp
            )

            let didResume = LockedFlag()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.cancel()
                    didResume.resumeOnce {
                        continuation.resume(returning: .reachable)
                    }
                case .failed(let error):
                    connection.cancel()
                    didResume.resumeOnce {
                        continuation.resume(returning: .unreachable(error.localizedDescription))
                    }
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .utility))

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + tcpTimeout) {
                connection.cancel()
                didResume.resumeOnce {
                    continuation.resume(returning: .unreachable("TCP 探测超时"))
                }
            }
        }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func resumeOnce(_ block: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        block()
    }
}
