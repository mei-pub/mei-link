import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var manager: TunnelManager
    @Environment(\.dismiss) private var dismiss

    @State private var serverAddr = ""
    @State private var serverPort = ""
    @State private var authToken = ""
    @State private var subDomainHost = ""
    @State private var tlsEnabled = true
    @State private var adminPort = "7400"
    @State private var launchAtLogin = false
    @State private var isSaving = false
    @State private var isTesting = false
    @State private var showToken = false
    @State private var menuBarIconStyle: MenuBarIconStyle = .portal
    @State private var remoteReachabilityInterval: Double = 60
    @State private var saveError: String?
    @State private var testMessage: String?
    @State private var testSucceeded = false
    @State private var showQuitConfirmation = false
    @State private var showRestartConfirmation = false
    @State private var managementURL = ""
    @State private var domainAPIToken = ""

    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                serverCard
                appCard
            }
            .padding(16)

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
        .frame(width: 760)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            loadFields()
        }
        .confirmationDialog(
            "确定要完全退出 Meilink？",
            isPresented: $showQuitConfirmation,
            titleVisibility: .visible
        ) {
            Button("退出 Meilink", role: .destructive) {
                quitApplication()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后会停止当前 frpc 隧道，菜单栏入口也会消失。")
        }
        .confirmationDialog(
            "保存后是否立即重启 frpc 隧道？",
            isPresented: $showRestartConfirmation,
            titleVisibility: .visible
        ) {
            Button("保存并重启") {
                performRestartAfterSave()
            }
            Button("仅保存", role: .cancel) {
                finishSave()
            }
        } message: {
            Text("配置已写入。重启 frpc 让新配置立即生效；仅保存则下次启动时生效。")
        }
    }

    private var serverCard: some View {
        settingsSection(title: "服务器配置") {
            settingsRow("服务器地址") {
                HStack(spacing: 8) {
                    TextField("tunnel.example.com", text: $serverAddr)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)

                    Button {
                        testConnection()
                    } label: {
                        Label(isTesting ? "测试中" : "测试连接", systemImage: "network")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTesting || serverAddr.isEmpty || serverPort.isEmpty)

                    if let testMessage {
                        Label(testMessage, systemImage: testSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(testSucceeded ? .green : .red)
                    }
                }
            }

            settingsRow("客户端端口") {
                TextField("7000", text: $serverPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }

            settingsRow("管理端口") {
                TextField("7400", text: $adminPort)
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

            settingsRow("管理页地址") {
                TextField("如 http://vps:17500（可选）", text: $managementURL)
                    .textFieldStyle(.roundedBorder)
            }

            settingsRow("管理页 Token") {
                SecureField("客户端拉取配置用（可选）", text: $domainAPIToken)
                    .textFieldStyle(.roundedBorder)
            }
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

            settingsRow("菜单栏图标") {
                HStack(spacing: 8) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        Button {
                            updateMenuBarIconStyle(style)
                        } label: {
                            VStack(spacing: 4) {
                                if let path = Bundle.main.path(forResource: style.imageName, ofType: "png"),
                                   let img = NSImage(contentsOfFile: path) {
                                    Image(nsImage: img)
                                        .resizable()
                                        .frame(width: 22, height: 22)
                                }
                                Text(style.displayName)
                                    .font(.system(size: 9))
                                    .foregroundColor(style == menuBarIconStyle ? .accentColor : .secondary)
                            }
                            .frame(width: 52)
                            .padding(6)
                            .background(style == menuBarIconStyle ? Color.accentColor.opacity(0.12) : Color.clear)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    manager.rebuildMenuBarIcon()
                    AppRuntime.shared.rebuildStatusBar()
                } label: {
                    Label("重建图标", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
            }

            settingsRow("远程探测间隔") {
                Stepper(value: $remoteReachabilityInterval, in: 30...600, step: 15) {
                    Text("\(Int(remoteReachabilityInterval)) 秒")
                        .frame(width: 68, alignment: .leading)
                }
                .onChange(of: remoteReachabilityInterval) { newValue in
                    updateRemoteReachabilityInterval(newValue)
                }

                Text("降低外部端口探测频率，只影响远程可达性验证。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            // 左下角：退出（与跨平台端对齐）
            Button(role: .destructive) {
                showQuitConfirmation = true
            } label: {
                Label("退出", systemImage: "power")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("关闭") {
                close()
            }
            .keyboardShortcut(.cancelAction)

            Button {
                saveConfiguration()
            } label: {
                Label("保存", systemImage: "checkmark")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)

            Spacer()

            Button("关闭") {
                close()
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
            adminPort = String(config.adminPort)
            managementURL = config.managementURL
            domainAPIToken = config.domainAPIToken
        }
        launchAtLogin = AutoStartManager.isEnabled
        menuBarIconStyle = manager.appSettings.menuBarIconStyle
        remoteReachabilityInterval = min(max(manager.appSettings.remoteReachabilityInterval, 30), 600)
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

    private func updateMenuBarIconStyle(_ style: MenuBarIconStyle) {
        menuBarIconStyle = style  // 立即更新本地 state
        var settings = manager.appSettings
        settings.menuBarIconStyle = style
        do {
            try manager.saveAppSettings(settings)
            manager.rebuildMenuBarIcon()
            AppRuntime.shared.rebuildStatusBar()
        } catch {
            manager.addEvent("保存菜单栏图标设置失败: \(error.localizedDescription)", level: .error)
        }
    }

    private func updateRemoteReachabilityInterval(_ interval: Double) {
        var settings = manager.appSettings
        settings.remoteReachabilityInterval = min(max(interval, 30), 600)
        do {
            try manager.saveAppSettings(settings)
            manager.addEvent("远程探测间隔已更新为 \(Int(settings.remoteReachabilityInterval)) 秒")
        } catch {
            manager.addEvent("保存远程探测间隔失败: \(error.localizedDescription)", level: .error)
        }
    }

    private func saveConfiguration() {
        guard let port = Int(serverPort) else {
            saveError = "客户端端口必须是数字"
            return
        }
        guard let adminPortValue = Int(adminPort) else {
            saveError = "管理端口必须是数字"
            return
        }

        let config = ServerConfig(
            serverAddr: serverAddr,
            serverPort: port,
            authToken: authToken,
            subDomainHost: subDomainHost,
            tlsEnabled: tlsEnabled,
            adminPort: adminPortValue,
            managementURL: managementURL,
            domainAPIToken: domainAPIToken
        )

        isSaving = true
        saveError = nil

        do {
            try manager.saveConfiguration(config)
            manager.addEvent("服务器配置已保存")
            isSaving = false
            // 保存成功后弹框让用户选是否重启，与跨平台端交互一致
            showRestartConfirmation = true
        } catch {
            isSaving = false
            saveError = error.localizedDescription
            manager.addEvent("保存配置失败: \(error.localizedDescription)", level: .error)
        }
    }

    private func performRestartAfterSave() {
        isSaving = true
        Task {
            await manager.restart()
            isSaving = false
            close()
        }
    }

    private func finishSave() {
        close()
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func quitApplication() {
        MeilinkAppDelegate.performQuit()
    }
}
