import SwiftUI

struct TunnelRowView: View {
    let tunnel: Tunnel
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(tunnel.name)
                    .font(compact ? .caption : .body)
                    .fontWeight(.medium)
                if !compact {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if compact {
                Text(tunnel.status.displayName)
                    .font(.caption2)
                    .foregroundColor(statusColor)
            }
        }
    }

    private var statusIcon: some View {
        Circle()
            .fill(statusColor)
            .frame(width: compact ? 6 : 8, height: compact ? 6 : 8)
    }

    private var description: String {
        switch tunnel.type {
        case .http, .https:
            let subdomain = tunnel.subdomain ?? "unnamed"
            return "\(tunnel.type.rawValue.uppercased()) :\(tunnel.localPort) → \(subdomain)"
        case .tcp, .udp:
            let remote = tunnel.remotePort.map { ":\($0)" } ?? "auto"
            return "\(tunnel.type.rawValue.uppercased()) :\(tunnel.localPort) → \(remote)"
        }
    }

    private var statusColor: Color {
        switch tunnel.status {
        case .running: return .green
        case .waitStart: return .yellow
        case .startError, .checkFailed: return .red
        case .new, .closed: return .gray
        }
    }
}
