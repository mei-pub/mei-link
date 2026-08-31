import SwiftUI

struct MainWindow: View {
    @ObservedObject var manager: TunnelManager

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tunnelList
            Divider()
            footer
        }
        .frame(minWidth: 980, minHeight: 740)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            HStack(alignment: .center, spacing: 16) {
                appLogo

                VStack(alignment: .leading, spacing: 4) {
                    Text("Meilink")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(serverSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            HStack(spacing: 12) {
                statusIndicator
                headerButton(width: 104) {
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

                headerButton(width: 104) {
                    Task { await manager.restart() }
                } label: {
                    Label("重启", systemImage: "arrow.clockwise")
                }
                .disabled(!manager.isConfigured)

                headerButton(width: 104) {
                    AppRuntime.shared.windows.showSettingsWindow()
                } label: {
                    Label("设置", systemImage: "gear")
                }
            }
            .frame(minWidth: 560, alignment: .trailing)
            .layoutPriority(1)
        }
        .padding(20)
    }

    private var appLogo: some View {
        Image(nsImage: AppIconProvider.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
    }

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(manager.isConnected ? .green : manager.reconnectFailed ? .red : manager.isFrpcRunning || manager.isReconnecting ? .yellow : .gray)
                .frame(width: 10, height: 10)
            Text(statusText)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(width: 128, height: 46)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private func headerButton<LabelContent: View>(
        width: CGFloat,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> LabelContent
    ) -> some View {
        Button(action: action) {
            label()
                .lineLimit(1)
                .frame(width: width, height: 46)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
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
                    AppRuntime.shared.windows.showTunnelWindow()
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
                            AppRuntime.shared.windows.showTunnelWindow(tunnel: tunnel)
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
                AppRuntime.shared.windows.showTunnelWindow()
            } label: {
                Label("添加隧道", systemImage: "plus")
                    .frame(width: 124, height: 32)
            }
            .controlSize(.regular)
            .buttonStyle(.bordered)

            Spacer()

            Text("\(manager.tunnels.filter { $0.enabled }.count)/\(manager.tunnels.count) 个隧道启用")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                AppRuntime.shared.windows.showLogsWindow()
            } label: {
                Label("查看日志", systemImage: "doc.text.magnifyingglass")
                    .frame(width: 112, height: 32)
            }
            .controlSize(.regular)
            .buttonStyle(.bordered)

            Button {
                manager.clearEvents()
            } label: {
                Text("清空日志")
                    .frame(width: 104, height: 32)
            }
            .controlSize(.regular)
            .buttonStyle(.bordered)
            .disabled(manager.events.isEmpty)
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
        if manager.reconnectFailed { return "重连失败" }
        if manager.isReconnecting { return "重连中" }
        if manager.isFrpcRunning { return "连接中" }
        if manager.isConfigured { return "未连接" }
        return "未配置"
    }
}
