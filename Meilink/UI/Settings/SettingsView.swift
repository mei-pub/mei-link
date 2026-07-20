import SwiftUI

struct SettingsView: View {
    @ObservedObject var manager: TunnelManager
    @Environment(\.dismiss) private var dismiss

    @State private var serverAddr = ""
    @State private var serverPort = ""
    @State private var authToken = ""
    @State private var subDomainHost = ""
    @State private var tlsEnabled = true
    @State private var launchAtLogin = false
    @State private var isSaving = false
    @State private var saveError: String?

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

                    SecureField("认证 Token", text: $authToken)
                        .textFieldStyle(.roundedBorder)

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

            if let saveError {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(saveError)
                        .foregroundColor(.red)
                }
                .font(.caption)
            }

            HStack {
                Button("保存") {
                    saveConfiguration()
                }
                .disabled(
                    isSaving ||
                    serverAddr.isEmpty ||
                    serverPort.isEmpty ||
                    authToken.isEmpty ||
                    subDomainHost.isEmpty
                )
                .keyboardShortcut(.defaultAction)

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
                authToken = config.authToken
                subDomainHost = config.subDomainHost
                tlsEnabled = config.tlsEnabled
            }
            launchAtLogin = AutoStartManager.isEnabled
        }
    }

    private func saveConfiguration() {
        guard let port = Int(serverPort) else {
            saveError = "端口必须是数字"
            return
        }

        let config = ServerConfig(
            serverAddr: serverAddr,
            serverPort: port,
            authToken: authToken,
            subDomainHost: subDomainHost,
            tlsEnabled: tlsEnabled
        )

        isSaving = true
        saveError = nil

        do {
            try manager.saveConfiguration(config)
            manager.addEvent("服务器配置已保存")
            if manager.isFrpcRunning {
                Task {
                    await manager.restart()
                    isSaving = false
                    dismiss()
                }
            } else {
                isSaving = false
                dismiss()
            }
        } catch {
            isSaving = false
            saveError = error.localizedDescription
            manager.addEvent("保存配置失败: \(error.localizedDescription)", level: .error)
        }
    }
}
