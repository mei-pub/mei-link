import SwiftUI

struct MainWindow: View {
    @ObservedObject var manager: TunnelManager
    @State private var showAddTunnel = false
    @State private var editingTunnel: Tunnel?
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tunnelList
            Divider()
            footer
        }
        .frame(minWidth: 600, minHeight: 400)
        .sheet(isPresented: $showAddTunnel) {
            TunnelEditView(manager: manager)
        }
        .sheet(item: $editingTunnel) { tunnel in
            TunnelEditView(manager: manager, tunnel: tunnel)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(manager: manager)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meilink")
                    .font(.title3)
                    .fontWeight(.bold)
                if let config = manager.serverConfig {
                    Text("服务器: \(config.serverAddr):\(config.serverPort)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !config.subDomainHost.isEmpty {
                        Text("子域名基域: \(config.subDomainHost)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 12) {
                statusIndicator
                Button("设置") { showSettings = true }
            }
        }
        .padding()
    }

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(manager.isConnected ? .green : .gray)
                .frame(width: 10, height: 10)
            Text(manager.isConnected ? "已连接" : "未连接")
                .font(.caption)
        }
    }

    private var tunnelList: some View {
        List {
            ForEach(manager.tunnels) { tunnel in
                TunnelListRow(tunnel: tunnel) {
                    editingTunnel = tunnel
                } onDelete: {
                    Task {
                        try? await manager.deleteTunnel(id: tunnel.id)
                    }
                } onToggle: { enabled in
                    Task {
                        try? await manager.toggleTunnel(id: tunnel.id, enabled: enabled)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                showAddTunnel = true
            } label: {
                Label("添加隧道", systemImage: "plus")
            }

            Spacer()

            if !manager.events.isEmpty {
                Button("清空日志") {
                    manager.clearEvents()
                }
            }
        }
        .padding()
    }
}
