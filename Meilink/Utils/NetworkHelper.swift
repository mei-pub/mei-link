import Foundation

struct NetworkHelper {
    static func testConnection(serverAddr: String, serverPort: Int) async throws -> Bool {
        let url = URL(string: "http://\(serverAddr):\(serverPort)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode != nil
        } catch {
            return false
        }
    }

    static func validateSubDomainHost(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty }
    }
}
