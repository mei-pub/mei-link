import SwiftUI

struct MenuBarView: View {
    @ObservedObject var manager: TunnelManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader
            activeTunnels
            controlButtons
        }
        .padding(12)
        .frame(width: 340)
        .onAppear {
            if !manager.isConfigured {
                openAppWindow(id: "setup")
            }
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(manager.isConnected ? .green : manager.isFrpcRunning ? .yellow : .gray)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(serverSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    Task {
                        if manager.isFrpcRunning {
                            await manager.stop()
                        } else {
                            await manager.start()
                        }
                    }
                } label: {
                    Image(systemName: manager.isFrpcRunning ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
                .help(manager.isFrpcRunning ? "断开连接" : "连接")
            }
        }
    }

    @ViewBuilder
    private var activeTunnels: some View {
        let enabledTunnels = manager.tunnels.filter { $0.enabled }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("隧道")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(enabledTunnels.count) 个启用")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if enabledTunnels.isEmpty {
                emptyTunnelState
            } else {
                ForEach(enabledTunnels) { tunnel in
                    menuTunnelRow(tunnel)
                }
            }
        }
    }

    private var emptyTunnelState: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
                .foregroundColor(.secondary)
            Text("暂无启用隧道")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("添加") {
                openAppWindow(id: "main")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private func menuTunnelRow(_ tunnel: Tunnel) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tunnel.status.tintColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(tunnel.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(tunnel.routeText(serverConfig: manager.serverConfig))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                copy(tunnel.routeText(serverConfig: manager.serverConfig))
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("复制访问地址")

            if let url = tunnel.openURL(serverConfig: manager.serverConfig) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("打开访问地址")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private var controlButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    openAppWindow(id: "main")
                } label: {
                    Label("主窗口", systemImage: "rectangle.stack")
                }

                Button {
                    openAppWindow(id: manager.isConfigured ? "settings" : "setup")
                } label: {
                    Label("服务器", systemImage: "server.rack")
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await manager.restart() }
                } label: {
                    Label("重启", systemImage: "arrow.clockwise")
                }
                .disabled(!manager.isConfigured)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power")
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private var statusTitle: String {
        if manager.isConnected { return "已连接" }
        if manager.isFrpcRunning { return "连接中" }
        if manager.isConfigured { return "未连接" }
        return "未配置"
    }

    private var serverSubtitle: String {
        if let config = manager.serverConfig {
            return "\(config.serverAddr):\(config.serverPort) · \(config.subDomainHost)"
        } else {
            return "请先完成服务器配置"
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func openAppWindow(id: String) {
        openWindow(id: id)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
