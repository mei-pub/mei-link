import SwiftUI

struct TunnelListRow: View {
    let tunnel: Tunnel
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(tunnel.name)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let remote = tunnel.remoteAddr, !remote.isEmpty {
                Text(remote)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let error = tunnel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }

            Toggle("", isOn: Binding(
                get: { tunnel.enabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            Menu {
                Button("编辑") { onEdit() }
                Button("删除", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .padding(.vertical, 4)
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
