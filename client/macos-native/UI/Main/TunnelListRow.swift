import SwiftUI

struct TunnelListRow: View {
    let tunnel: Tunnel
    let serverConfig: ServerConfig?
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tunnel.status.tintColor)
                    .frame(width: 8, height: 8)
                Text(tunnel.name)
                    .fontWeight(.medium)
            }
            .frame(width: 150, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(tunnel.type.rawValue.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Text(tunnel.localAddressText())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 120, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(tunnel.routeText(serverConfig: serverConfig))
                    .lineLimit(1)
                if let error = tunnel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                } else {
                    Text(tunnel.shortRouteText(serverConfig: serverConfig))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Text(tunnel.status.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(tunnel.status.tintColor)
                .frame(width: 80, alignment: .leading)

            Button {
                copy(tunnel.routeText(serverConfig: serverConfig))
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("复制访问地址")

            if let url = tunnel.openURL(serverConfig: serverConfig) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("打开访问地址")
            }

            Toggle("", isOn: Binding(
                get: { tunnel.enabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            Menu {
                Button("编辑") { onEdit() }
                Button("复制访问地址") {
                    copy(tunnel.routeText(serverConfig: serverConfig))
                }
                if let url = tunnel.openURL(serverConfig: serverConfig) {
                    Button("打开访问地址") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Divider()
                Button("删除", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 8)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
