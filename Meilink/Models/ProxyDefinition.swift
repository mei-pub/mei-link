import Foundation

struct ProxyDefinition: Codable, Sendable {
    let name: String
    let type: String
    var tcp: TCPProxyConfig?
    var udp: UDPProxyConfig?
    var http: HTTPProxyConfig?
    var https: HTTPSProxyConfig?
}

struct TCPProxyConfig: Codable, Sendable {
    var localIP: String
    var localPort: Int
    var remotePort: Int
}

struct UDPProxyConfig: Codable, Sendable {
    var localIP: String
    var localPort: Int
    var remotePort: Int
}

struct HTTPProxyConfig: Codable, Sendable {
    var localIP: String
    var localPort: Int
    var subdomain: String?
    var customDomains: [String]?
    var locations: [String]?
    var httpUser: String?
    var httpPassword: String?
    var hostHeaderRewrite: String?
    var requestHeaders: HeaderOperations?
    var responseHeaders: HeaderOperations?
}

struct HTTPSProxyConfig: Codable, Sendable {
    var localIP: String
    var localPort: Int
    var subdomain: String?
    var customDomains: [String]?
}

struct HeaderOperations: Codable, Sendable {
    var set: [String: String]?
}

// MARK: - Status Response

typealias StatusResponse = [String: [ProxyStatusResp]]

struct ProxyStatusResp: Codable, Sendable {
    let name: String
    let type: String
    let status: String
    let err: String
    let localAddr: String
    let plugin: String
    let remoteAddr: String
    let source: String?
}

struct ProxyListResp: Codable, Sendable {
    let proxies: [ProxyDefinition]
}
