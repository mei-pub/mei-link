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
    @State private var isTesting = false
    @State private var showToken = false
    @State private var saveError: String?
    @State private var testMessage: String?
    @State private var testSucceeded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    serverCard
                    appCard
                    eventsCard
                }
                .padding(24)
            }

            if let saveError {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(saveError)
                        .foregroundColor(.red)
                }
                .font(.caption)
            }

            Divider()
            footer
        }
        .frame(width: 640, height: 680)
        .onAppear {
            loadFields()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("设置")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(manager.isConnected ? .green : manager.isFrpcRunning ? .yellow : .gray)
                    .frame(width: 10, height: 10)
                Text(manager.isConnected ? "已连接" : manager.isFrpcRunning ? "连接中" : "未连接")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
        .padding(24)
    }

    private var serverCard: some View {
        settingsSection(title: "服务器配置") {
            settingsRow("服务器地址") {
                TextField("tunnel.example.com", text: $serverAddr)
                    .textFieldStyle(.roundedBorder)
            }

            settingsRow("客户端端口") {
                TextField("7000", text: $serverPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }

            settingsRow("认证 Token") {
                HStack(spacing: 8) {
                    Group {
                        if showToken {
                            TextField("frps token", text: $authToken)
                        } else {
                            SecureField("frps token", text: $authToken)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button {
                        showToken.toggle()
                    } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.bordered)
                    .help(showToken ? "隐藏 Token" : "显示 Token")
                }
            }

            settingsRow("子域名基域") {
                TextField("tunnel.example.com", text: $subDomainHost)
                    .textFieldStyle(.roundedBorder)
            }

            settingsRow("TLS 连接") {
                Toggle("", isOn: $tlsEnabled)
                    .labelsHidden()
                Text("加密 frpc 到 frps 的控制连接，不等同于 HTTPS 隧道。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    testConnection()
                } label: {
                    Label(isTesting ? "测试中" : "测试连接", systemImage: "network")
                }
                .disabled(isTesting || serverAddr.isEmpty || serverPort.isEmpty)

                if let testMessage {
                    Label(testMessage, systemImage: testSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(testSucceeded ? .green : .red)
                }

                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private var appCard: some View {
        settingsSection(title: "应用设置") {
            settingsRow("开机自启动") {
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { newValue in
                        updateLaunchAtLogin(newValue)
                    }
                Text("登录 macOS 后自动启动 Meilink。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var eventsCard: some View {
        settingsSection(title: "最近事件") {
            if manager.events.isEmpty {
                Text("暂无事件")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(manager.events.prefix(8)) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Text(event.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 56, alignment: .leading)
                            Text(event.message)
                                .font(.caption)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                saveConfiguration(restartAfterSave: false)
            } label: {
                Label("保存", systemImage: "checkmark")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)

            Button {
                saveConfiguration(restartAfterSave: true)
            } label: {
                Label("保存并重启", systemImage: "arrow.clockwise")
            }
            .disabled(!canSave)

            Spacer()

            Button("关闭") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private var canSave: Bool {
        !isSaving &&
        !serverAddr.isEmpty &&
        !serverPort.isEmpty &&
        !authToken.isEmpty &&
        !subDomainHost.isEmpty
    }

    private var statusSubtitle: String {
        if let config = manager.serverConfig {
            return "\(config.serverAddr):\(config.serverPort) · \(config.subDomainHost)"
        }
        return "配置 frps 服务器和隧道基础域名"
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
        }
    }

    private func settingsRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
                .frame(width: 96, alignment: .leading)
            content()
        }
    }

    private func loadFields() {
        if let config = manager.serverConfig {
            serverAddr = config.serverAddr
            serverPort = String(config.serverPort)
            authToken = config.authToken
            subDomainHost = config.subDomainHost
            tlsEnabled = config.tlsEnabled
        }
        launchAtLogin = AutoStartManager.isEnabled
    }

    private func testConnection() {
        guard let port = Int(serverPort) else {
            testSucceeded = false
            testMessage = "端口必须是数字"
            return
        }

        isTesting = true
        testMessage = nil

        Task {
            let success = (try? await NetworkHelper.testConnection(
                serverAddr: serverAddr,
                serverPort: port
            )) ?? false

            testSucceeded = success
            testMessage = success ? "连接成功" : "连接失败"
            isTesting = false
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try AutoStartManager.enableAutoStart()
            } else {
                try AutoStartManager.disableAutoStart()
            }
        } catch {
            manager.addEvent("设置自启动失败: \(error.localizedDescription)", level: .error)
        }
    }

    private func saveConfiguration(restartAfterSave: Bool) {
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
            if restartAfterSave || manager.isFrpcRunning {
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
