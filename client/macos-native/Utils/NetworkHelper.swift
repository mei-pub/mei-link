import Foundation
import Network

private final class TCPProbeCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let continuation: CheckedContinuation<Bool, Never>
    var connection: NWConnection?

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func finish(_ success: Bool) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let connection = connection
        lock.unlock()

        connection?.stateUpdateHandler = nil
        connection?.cancel()
        continuation.resume(returning: success)
    }
}

struct NetworkHelper {
    static func testConnection(serverAddr: String, serverPort: Int) async throws -> Bool {
        guard let port = NWEndpoint.Port(rawValue: UInt16(serverPort)) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(serverAddr),
                port: port,
                using: .tcp
            )
            let queue = DispatchQueue(label: "pub.mei.meilink.network-test")
            let completion = TCPProbeCompletion(continuation: continuation)
            completion.connection = connection

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    completion.finish(true)
                case .failed, .cancelled:
                    completion.finish(false)
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + 5) {
                completion.finish(false)
            }
        }
    }

    static func validateSubDomainHost(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty }
    }
}
