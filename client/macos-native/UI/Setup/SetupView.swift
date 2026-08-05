import SwiftUI

struct SetupView: View {
    @ObservedObject var manager: TunnelManager
    @Environment(\.dismiss) private var dismiss

    /// 由 AppRuntime 注入的关闭回调。NSWindow 宿主下 @Environment(\.dismiss) 不会关窗，
    /// 必须用 onClose 调 window.close()。为 nil 时回退到 dismiss。
    var onClose: (() -> Void)? = nil

    @State private var serverAddr = ""
    @State private var serverPort = "7000"
    @State private var authToken = ""
    @State private var subDomainHost = ""
    @State private var tlsEnabled = true
    @State private var managementURL = ""
    @State private var domainAPIToken = ""
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSuccess = false

    var body: some View {
        VStack(spacing: 20) {
            Text("欢迎使用 Meilink")
                .font(.title2)
                .fontWeight(.bold)

            Text("请配置你的 VPS 服务器信息")
                .foregroundColor(.secondary)

            Form {
                Section("服务器信息") {
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
                }

                Section("子域名配置") {
                    TextField("子域名基域 (如 tunnel.example.com)", text: $subDomainHost)
                        .textFieldStyle(.roundedBorder)

                    Text("需在 DNS 添加泛解析: *.\(subDomainHost.isEmpty ? "tunnel.example.com" : subDomainHost) → VPS IP")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("管理页（可选）") {
                    TextField("管理页地址 (如 http://vps:17500)", text: $managementURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()

                    SecureField("域名拉取 Token", text: $domainAPIToken)
                        .textFieldStyle(.roundedBorder)

                    Text("配置后，编辑 HTTP/HTTPS 隧道时可从服务端拉取域名目录，自动适配子域名/泛域名。不填则隧道编辑走手填模式。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Toggle("启用 TLS 加密连接", isOn: $tlsEnabled)
                }
            }
            .formStyle(.grouped)

            if let result = testResult {
                HStack {
                    Image(systemName: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(testSuccess ? .green : .red)
                    Text(result)
                        .foregroundColor(testSuccess ? .green : .red)
                }
            }

            HStack {
                Button("取消") {
                    close()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("测试连接") {
                    testConnection()
                }
                .disabled(serverAddr.isEmpty || isTesting)

                Button("保存") {
                    saveConfiguration()
                }
                .disabled(serverAddr.isEmpty || authToken.isEmpty || subDomainHost.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            // 已有配置时回填，方便修改
            guard let config = manager.serverConfig, !config.serverAddr.isEmpty else { return }
            serverAddr = config.serverAddr
            serverPort = String(config.serverPort)
            authToken = config.authToken
            subDomainHost = config.subDomainHost
            tlsEnabled = config.tlsEnabled
            managementURL = config.managementURL
            domainAPIToken = config.domainAPIToken
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            let success = await withCheckedContinuation { continuation in
                Task {
                    do {
                        let result = try await NetworkHelper.testConnection(
                            serverAddr: serverAddr,
                            serverPort: Int(serverPort) ?? 7000
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(returning: false)
                    }
                }
            }

            isTesting = false
            testSuccess = success
            testResult = success ? "连接成功" : "连接失败，请检查服务器地址和端口"
        }
    }

    private func saveConfiguration() {
        let port = Int(serverPort) ?? 7000
        let config = ServerConfig(
            serverAddr: serverAddr,
            serverPort: port,
            authToken: authToken,
            subDomainHost: subDomainHost,
            tlsEnabled: tlsEnabled,
            managementURL: managementURL,
            domainAPIToken: domainAPIToken
        )

        do {
            try manager.saveConfiguration(config)
            close()
            Task { await manager.start() }
        } catch {
            manager.addEvent("保存配置失败: \(error.localizedDescription)", level: .error)
        }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}
