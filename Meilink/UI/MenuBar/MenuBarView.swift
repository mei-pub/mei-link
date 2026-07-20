import SwiftUI

struct MenuBarView: View {
    @ObservedObject var manager: TunnelManager
    @Binding var showMainWindow: Bool
    @Binding var showSetup: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            connectionStatus
            Divider()
            tunnelList
            Divider()
            actions
        }
        .frame(width: 280)
        .onAppear {
            if !manager.isConfigured {
                showSetup = true
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }

    private var connectionStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(manager.isConnected ? .green : .gray)
                .frame(width: 8, height: 8)
            if let config = manager.serverConfig {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已连接: \(config.serverAddr)")
                        .font(.caption)
                        .fontWeight(.medium)
                    if !config.subDomainHost.isEmpty {
                        Text("子域名基域: \(config.subDomainHost)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("未配置")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var tunnelList: some View {
        if manager.tunnels.isEmpty {
            Text("暂无隧道")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
        } else {
            ForEach(manager.tunnels.filter { $0.enabled }) { tunnel in
                TunnelRowView(tunnel: tunnel, compact: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                showMainWindow = true
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("打开设置窗口", systemImage: "gear")
            }
            .buttonStyle(.plain)

            if !manager.isConfigured {
                Button {
                    showSetup = true
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    Label("首次配置...", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
            }

            Divider()

            Button {
                Task { await manager.restart() }
            } label: {
                Label("重启隧道", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)

            if manager.isFrpcRunning {
                Button {
                    Task { await manager.stop() }
                } label: {
                    Label("断开连接", systemImage: "stop.circle")
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task { await manager.start() }
                } label: {
                    Label("连接", systemImage: "play.circle")
                }
                .buttonStyle(.plain)
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }
}
