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
        .frame(minWidth: 760, minHeight: 520)
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
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meilink")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(serverSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                statusIndicator
                Button {
                    Task {
                        if manager.isFrpcRunning {
                            await manager.stop()
                        } else {
                            await manager.start()
                        }
                    }
                } label: {
                    Label(manager.isFrpcRunning ? "断开" : "连接", systemImage: manager.isFrpcRunning ? "stop.fill" : "play.fill")
                }
                .disabled(!manager.isConfigured)

                Button {
                    Task { await manager.restart() }
                } label: {
                    Label("重启", systemImage: "arrow.clockwise")
                }
                .disabled(!manager.isConfigured)

                Button {
                    showSettings = true
                } label: {
                    Label("设置", systemImage: "gear")
                }
            }
        }
        .padding(20)
    }

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(manager.isConnected ? .green : manager.isFrpcRunning ? .yellow : .gray)
                .frame(width: 10, height: 10)
            Text(statusText)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var tunnelList: some View {
        if manager.tunnels.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 34))
                    .foregroundColor(.secondary)
                Text("还没有隧道")
                    .font(.headline)
                Text("添加一个 HTTP、HTTPS、TCP 或 UDP 隧道，把本机服务发布出去。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button {
                    showAddTunnel = true
                } label: {
                    Label("添加隧道", systemImage: "plus")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(manager.tunnels) { tunnel in
                        TunnelListRow(
                            tunnel: tunnel,
                            serverConfig: manager.serverConfig
                        ) {
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
                } header: {
                    HStack {
                        Text("名称")
                            .frame(width: 150, alignment: .leading)
                        Text("本地")
                            .frame(width: 120, alignment: .leading)
                        Text("外网访问")
                        Spacer()
                        Text("状态")
                            .frame(width: 80, alignment: .leading)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
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

            Text("\(manager.tunnels.filter { $0.enabled }.count)/\(manager.tunnels.count) 个隧道启用")
                .font(.caption)
                .foregroundColor(.secondary)

            if !manager.events.isEmpty {
                Button("清空日志") {
                    manager.clearEvents()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var serverSummary: String {
        guard let config = manager.serverConfig else { return "尚未配置服务器" }
        return "\(config.serverAddr):\(config.serverPort) · \(config.subDomainHost)"
    }

    private var statusText: String {
        if manager.isConnected { return "已连接" }
        if manager.isFrpcRunning { return "连接中" }
        if manager.isConfigured { return "未连接" }
        return "未配置"
    }
}
