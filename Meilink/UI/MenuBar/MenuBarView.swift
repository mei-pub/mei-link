import SwiftUI

struct MenuBarView: View {
    @ObservedObject var manager: TunnelManager
    let openMainWindow: () -> Void
    let openSettingsWindow: () -> Void
    let openSetupWindow: () -> Void
    let closePopover: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusHeader
            activeTunnels
            controlButtons
        }
        .padding(14)
        .frame(width: 330)
        .background(.regularMaterial)
        .onAppear {
            if !manager.isConfigured {
                openSetupWindow()
            }
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(manager.isConnected ? .green : manager.isFrpcRunning ? .yellow : .gray)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(serverSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
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
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(manager.isFrpcRunning ? "断开连接" : "连接")
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }

    @ViewBuilder
    private var activeTunnels: some View {
        let enabledTunnels = manager.tunnels.filter { $0.enabled }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("隧道")
                    .font(.caption.weight(.medium))
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
                closePopover()
                openMainWindow()
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func menuTunnelRow(_ tunnel: Tunnel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tunnel.status.tintColor)
                    .frame(width: 8, height: 8)
                Text(tunnel.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                Text(tunnel.status.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(tunnel.status.tintColor)
            }

            HStack(spacing: 8) {
                Image(systemName: tunnel.type == .https ? "lock" : "network")
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                Text(tunnel.routeText(serverConfig: manager.serverConfig))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                actionButton("复制", systemImage: "doc.on.doc") {
                    copy(tunnel.routeText(serverConfig: manager.serverConfig))
                }

                if let url = tunnel.openURL(serverConfig: manager.serverConfig) {
                    actionButton("打开", systemImage: "arrow.up.right.square") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var controlButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                panelButton("主窗口", systemImage: "rectangle.stack") {
                    closePopover()
                    openMainWindow()
                }

                panelButton("服务器", systemImage: "server.rack") {
                    closePopover()
                    if manager.isConfigured {
                        openSettingsWindow()
                    } else {
                        openSetupWindow()
                    }
                }
            }

            HStack(spacing: 8) {
                panelButton("重启", systemImage: "arrow.clockwise") {
                    Task { await manager.restart() }
                }
                .disabled(!manager.isConfigured)

                panelButton("退出", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private func panelButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
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
}
