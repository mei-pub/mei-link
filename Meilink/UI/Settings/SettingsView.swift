import SwiftUI

struct SettingsView: View {
    @ObservedObject var manager: TunnelManager
    @Environment(\.dismiss) private var dismiss

    @State private var serverAddr = ""
    @State private var serverPort = ""
    @State private var subDomainHost = ""
    @State private var tlsEnabled = true
    @State private var launchAtLogin = false

    var body: some View {
        VStack(spacing: 16) {
            Text("设置")
                .font(.title3)
                .fontWeight(.bold)

            Form {
                Section("服务器配置") {
                    TextField("服务器地址", text: $serverAddr)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("端口")
                        TextField("7000", text: $serverPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }

                    TextField("子域名基域", text: $subDomainHost)
                        .textFieldStyle(.roundedBorder)

                    Toggle("启用 TLS", isOn: $tlsEnabled)
                }

                Section("应用设置") {
                    Toggle("开机自启动", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            do {
                                if newValue {
                                    try AutoStartManager.enableAutoStart()
                                } else {
                                    try AutoStartManager.disableAutoStart()
                                }
                            } catch {
                                manager.addEvent("设置自启动失败: \(error.localizedDescription)", level: .error)
                            }
                        }
                }

                Section("最近事件") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(manager.events.prefix(20)) { event in
                                HStack(alignment: .top) {
                                    Text(event.timestamp, style: .time)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .frame(width: 60, alignment: .leading)
                                    Text(event.message)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .frame(height: 150)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 420, height: 500)
        .onAppear {
            if let config = manager.serverConfig {
                serverAddr = config.serverAddr
                serverPort = String(config.serverPort)
                subDomainHost = config.subDomainHost
                tlsEnabled = config.tlsEnabled
            }
            launchAtLogin = AutoStartManager.isEnabled
        }
    }
}
