import Foundation

enum FrpcError: Error, LocalizedError {
    case adminAPINotReady
    case createFailed(Int)
    case updateFailed
    case deleteFailed
    case stopFailed
    case reloadFailed
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .adminAPINotReady: return "Admin API 未就绪"
        case .createFailed(let code): return "创建代理失败 (HTTP \(code))"
        case .updateFailed: return "更新代理失败"
        case .deleteFailed: return "删除代理失败"
        case .stopFailed: return "停止 frpc 失败"
        case .reloadFailed: return "重载配置失败"
        case .networkError(let err): return "网络错误: \(err.localizedDescription)"
        }
    }
}

class FrpcAdminAPI {
    private let baseURL: URL
    private let session: URLSession
    private let authHeader: String
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(host: String = "127.0.0.1", port: Int = 7400,
         user: String = "admin", password: String = "admin") {
        self.baseURL = URL(string: "http://\(host):\(port)")!
        let credentials = "\(user):\(password)"
        self.authHeader = "Basic " + Data(credentials.utf8).base64EncodedString()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)

        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Health

    func healthCheck() async throws -> Bool {
        let url = baseURL.appendingPathComponent("/healthz")
        let (_, response) = try await session.data(from: url)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Status

    func getStatus() async throws -> StatusResponse {
        let url = baseURL.appendingPathComponent("/api/status")
        var request = URLRequest(url: url)
        request.addValue(authHeader, forHTTPHeaderField: "Authorization")

        let (data, _) = try await session.data(for: request)
        return try decoder.decode(StatusResponse.self, from: data)
    }

    // MARK: - Control

    func stop() async throws {
        let url = baseURL.appendingPathComponent("/api/stop")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(authHeader, forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FrpcError.stopFailed
        }
    }

    func reload() async throws {
        let url = baseURL.appendingPathComponent("/api/reload")
        var request = URLRequest(url: url)
        request.addValue(authHeader, forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FrpcError.reloadFailed
        }
    }

    // MARK: - Store API

    func listProxies() async throws -> [ProxyDefinition] {
        let url = baseURL.appendingPathComponent("/api/store/proxies")
        var request = URLRequest(url: url)
        request.addValue(authHeader, forHTTPHeaderField: "Authorization")

        let (data, _) = try await session.data(for: request)
        let resp = try decoder.decode(ProxyListResp.self, from: data)
        return resp.proxies
    }

    func createProxy(_ definition: ProxyDefinition) async throws {
        let url = baseURL.appendingPathComponent("/api/store/proxies")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(authHeader, forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(definition)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw FrpcError.createFailed(statusCode)
        }
    }

    func updateProxy(name: String, definition: ProxyDefinition) async throws {
        let url = baseURL.appendingPathComponent("/api/store/proxies/\(name)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(authHeader, forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(definition)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FrpcError.updateFailed
        }
    }

    func deleteProxy(name: String) async throws {
        let url = baseURL.appendingPathComponent("/api/store/proxies/\(name)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(authHeader, forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FrpcError.deleteFailed
        }
    }
}
