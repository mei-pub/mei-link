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
    @State private var isFetching = false
    @State private var fetchMessage: String?
    @State private var fetchSucceeded = false
    @State private var showAdvanced = false

    var body: some View {
        VStack(spacing: 20) {
            Text("欢迎使用 Meilink")
                .font(.title2)
                .fontWeight(.bold)

            Text("请配置你的 VPS 服务器信息")
                .foregroundColor(.secondary)

            Form {
                Section("快速配置") {
                    TextField("管理页地址 (如 http://vps:17500)", text: $managementURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()

                    SecureField("管理页 Token", text: $domainAPIToken)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        fetchBootstrap()
                    } label: {
                        if isFetching { Text("拉取中...") } else { Text("拉取配置") }
                    }
                    .disabled(managementURL.isEmpty || domainAPIToken.isEmpty || isFetching)

                    if let msg = fetchMessage {
                        Label(msg, systemImage: fetchSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(fetchSucceeded ? .green : .red)
                    }

                    Text("填写管理页地址和 Token，自动拉取服务器连接信息。也可展开下方详细配置手动填写。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Toggle("启用 TLS 加密连接", isOn: $tlsEnabled)
                }

                DisclosureGroup("详细配置（自动填充，可手动修改）", isExpanded: $showAdvanced) {
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

                    TextField("子域名基域 (如 tunnel.example.com)", text: $subDomainHost)
                        .textFieldStyle(.roundedBorder)

                    Text("需在 DNS 添加泛解析: *.\(subDomainHost.isEmpty ? "tunnel.example.com" : subDomainHost) → VPS IP")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                // 填了管理页信息即可保存（会自动拉取）；或填了完整服务器信息也可
                .disabled(managementURL.isEmpty ? (serverAddr.isEmpty || authToken.isEmpty) : (serverAddr.isEmpty && authToken.isEmpty))
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

    /// 从管理页拉取启动信息，自动填充详细配置字段。
    private func fetchBootstrap() {
        isFetching = true
        fetchMessage = nil
        Task {
            do {
                let info = try await DomainDirectory.fetchBootstrap(managementURL: managementURL, token: domainAPIToken)
                await MainActor.run {
                    if !info.serverAddr.isEmpty { serverAddr = info.serverAddr }
                    if info.serverPort > 0 { serverPort = String(info.serverPort) }
                    if !info.authToken.isEmpty { authToken = info.authToken }
                    if !info.subDomainHost.isEmpty { subDomainHost = info.subDomainHost }
                    isFetching = false
                    fetchSucceeded = true
                    fetchMessage = "已拉取：\(info.serverAddr.isEmpty ? "未设置" : info.serverAddr):\(info.serverPort)"
                    // 拉取成功后展开详细配置让用户确认
                    showAdvanced = true
                }
            } catch {
                await MainActor.run {
                    isFetching = false
                    fetchSucceeded = false
                    fetchMessage = error.localizedDescription
                }
            }
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
        // 若填了管理页信息但没拉取（serverAddr 为空），先自动拉取再保存
        if serverAddr.isEmpty, !managementURL.isEmpty, !domainAPIToken.isEmpty {
            Task {
                isFetching = true
                let ok = await fetchBootstrapAndWait()
                isFetching = false
                if ok { performSave() }
            }
            return
        }
        performSave()
    }

    /// 同步拉取 bootstrap 并填充字段，返回是否成功。
    private func fetchBootstrapAndWait() async -> Bool {
        do {
            let info = try await DomainDirectory.fetchBootstrap(managementURL: managementURL, token: domainAPIToken)
            await MainActor.run {
                if !info.serverAddr.isEmpty { serverAddr = info.serverAddr }
                if info.serverPort > 0 { serverPort = String(info.serverPort) }
                if !info.authToken.isEmpty { authToken = info.authToken }
                if !info.subDomainHost.isEmpty { subDomainHost = info.subDomainHost }
            }
            return true
        } catch {
            await MainActor.run {
                fetchSucceeded = false
                fetchMessage = "拉取失败：\(error.localizedDescription)"
            }
            return false
        }
    }

    private func performSave() {
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
