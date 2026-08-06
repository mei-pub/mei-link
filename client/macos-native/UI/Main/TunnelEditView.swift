import SwiftUI

struct TunnelEditView: View {
    @ObservedObject var manager: TunnelManager
    @Environment(\.dismiss) private var dismiss: DismissAction

    var tunnel: Tunnel?
    var onClose: (() -> Void)? = nil

    @State private var name = ""
    @State private var type: TunnelType = .http
    @State private var localPort = "8080"
    @State private var localIP = "127.0.0.1"
    @State private var subdomain = ""
    @State private var customDomainsText = ""
    @State private var remotePort = ""
    @State private var enabled = true
    @State private var isSaving = false

    // 域名目录拉取（仅 HTTP/HTTPS）
    @State private var domains: [DomainEntry] = []
    @State private var selectedDomainID: String? = nil
    @State private var domainPrefix = ""
    @State private var domainFetchError: String? = nil
    @State private var isFetchingDomains = false
    /// 调试用：拉取成功时显示域名列表摘要
    @State private var domainFetchInfo: String? = nil

    /// 拉取成功且选了基域时为 true，走「选基域+前缀」交互；否则 fallback 到手填。
    private var useDomainDirectory: Bool { !domains.isEmpty && selectedDomainID != nil }

    var isEditing: Bool { tunnel != nil }

    private var selectedDomain: DomainEntry? { domains.first { $0.id == selectedDomainID } }

    /// 实时预览的访问域名（选基域+前缀模式下）。
    private var domainPreview: String? {
        guard let entry = selectedDomain else { return nil }
        let prefix = domainPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty ? entry.hostPart : "\(prefix).\(entry.hostPart)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    formSection("基本信息") {
                        formRow("隧道名称") {
                            TextField("例如 admin", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }

                        formRow("类型") {
                            Picker("类型", selection: $type) {
                                ForEach(TunnelType.allCases, id: \.self) { type in
                                    Text(type.rawValue.uppercased()).tag(type)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                    }

                    formSection("本地配置") {
                        formRow("本地端口") {
                            TextField("8080", text: $localPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 128)
                        }

                        formRow("本地地址") {
                            TextField("127.0.0.1", text: $localIP)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    formSection("远程配置") {
                        if type == .http || type == .https {
                            domainSection
                        } else {
                            formRow("远程端口") {
                                TextField("留空自动分配", text: $remotePort)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                            }
                        }
                    }

                    formSection("状态") {
                        HStack {
                            Text("启用隧道")
                                .fontWeight(.medium)
                            Spacer()
                            Toggle("", isOn: $enabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                }
                .padding(20)
            }

            footer
        }
        .frame(width: 660)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if let tunnel = tunnel {
                name = tunnel.name
                type = tunnel.type
                localPort = String(tunnel.localPort)
                localIP = tunnel.localIP
                subdomain = tunnel.subdomain ?? ""
                customDomainsText = tunnel.customDomains.joined(separator: ",")
                remotePort = tunnel.remotePort.map { String($0) } ?? ""
                enabled = tunnel.enabled
            }
            fetchDomains()
        }
    }

    /// 拉取服务端域名目录。成功则进入「选基域+前缀」模式并尝试回填；
    /// 失败则保持 fallback 手填模式。非 HTTP/HTTPS 类型跳过（用不到）。
    private func fetchDomains() {
        guard type == .http || type == .https else { return }
        let config = manager.serverConfig
        guard let mgmtURL = config?.managementURL, !mgmtURL.isEmpty,
              let token = config?.domainAPIToken, !token.isEmpty else {
            domainFetchError = "未配置管理页地址或 token (config: " + (config == nil ? "nil" : "有值") + ", mgmtURL: " + (config?.managementURL ?? "nil") + ", token: " + (config?.domainAPIToken ?? "nil") + ")"
            return
        }
        isFetchingDomains = true
        Task {
            do {
                let fetched = try await DomainDirectory.fetch(managementURL: mgmtURL, token: token)
                await MainActor.run {
                    domains = fetched
                    isFetchingDomains = false
                    domainFetchError = nil
                    domainFetchInfo = "已拉取域名列表: " + fetched.map(\.domain).joined(separator: ", ")
                    prefillDomainSelection()
                }
            } catch {
                await MainActor.run {
                    domains = []
                    isFetchingDomains = false
                    domainFetchError = error.localizedDescription
                }
            }
        }
    }

    /// 编辑已有隧道时，根据其 subdomain/customDomains 反推应选中哪个基域 + 前缀。
    /// 匹配不上则不选（保持 fallback 单独展示，但 domains 已有，会走 fallback 提示）。
    private func prefillDomainSelection() {
        guard let tunnel = tunnel else {
            selectedDomainID = domains.first?.id
            return
        }
        // 主域名模式：subdomain + 主域名基域 = 完整域名
        if let sub = tunnel.subdomain, !sub.isEmpty {
            if let entry = domains.first(where: { !$0.isWildcard }) {
                selectedDomainID = entry.id
                domainPrefix = sub
                return
            }
        }
        // 泛域名模式：customDomains[0] 去掉前缀 = 泛域名基域 hostPart
        if let firstCustom = tunnel.customDomains.first {
            for entry in domains where entry.isWildcard {
                if firstCustom.hasSuffix(".\(entry.hostPart)") {
                    let prefix = String(firstCustom.dropLast(".\(entry.hostPart)".count))
                    selectedDomainID = entry.id
                    domainPrefix = prefix
                    return
                }
            }
        }
        // 都匹配不上：清空选择，走 fallback（domains 非空但未选中）
        selectedDomainID = nil
    }

    /// HTTP/HTTPS 隧道的域名配置区块。
    /// 拉取成功（有域名目录且选中基域）→ 「基域下拉 + 前缀 + 预览」；
    /// 否则 fallback 到手填（子域名 + 自定义域名）。
    private var domainSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 域名拉取状态（调试用，任何时候都可见）
            if let info = domainFetchInfo {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text(info)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(height: 32)
                .overlay(alignment: .bottom) { Divider().padding(.leading, 108).opacity(0.7) }
            }
            if let error = domainFetchError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("\(error)，改为手动填写")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(height: 40)
                .overlay(alignment: .bottom) { Divider().padding(.leading, 108).opacity(0.7) }
            }
            if useDomainDirectory {
                formRow("基域") {
                    Picker("基域", selection: $selectedDomainID) {
                        ForEach(domains) { d in
                            Text("\(d.domain)").tag(Optional(d.id))
                        }
                    }
                    .labelsHidden()
                }
                formRow("前缀") {
                    TextField("例如 admin", text: $domainPrefix)
                        .textFieldStyle(.roundedBorder)
                }
                if let preview = domainPreview {
                    HStack {
                        Spacer()
                        Text("访问地址：\(type == .https ? "https://" : "http://")\(preview)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(height: 32)
                    .overlay(alignment: .bottom) { Divider().padding(.leading, 108).opacity(0.7) }
                }
            } else {
                formRow("子域名") {
                    TextField("例如 admin（依赖服务端主域名）", text: $subdomain)
                        .textFieldStyle(.roundedBorder)
                }
                formRow("自定义域名") {
                    TextField("多个用逗号分隔，如 a.com,b.com", text: $customDomainsText)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("取消") {
                close()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(isEditing ? "保存" : "创建") {
                saveTunnel()
            }
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(.regularMaterial)
    }

    private func formSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func formRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .fontWeight(.medium)
                .frame(width: 92, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 46)
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 108)
                .opacity(0.7)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Int(localPort) != nil
            && !isSaving
    }

    private func saveTunnel() {
        guard let port = Int(localPort) else { return }

        let remoteP = Int(remotePort)

        // 根据域名配置模式算出最终的 subdomain / customDomains
        let resolved: (subdomain: String?, customDomains: [String])
        if type == .http || type == .https {
            resolved = resolveDomains()
        } else {
            resolved = (nil, [])
        }

        if var existing = tunnel {
            existing.name = name
            existing.type = type
            existing.localPort = port
            existing.localIP = localIP
            existing.subdomain = resolved.subdomain
            existing.customDomains = resolved.customDomains
            existing.remotePort = remoteP
            existing.enabled = enabled
            existing.updatedAt = Date()

            isSaving = true
            Task {
                try? await manager.updateTunnel(existing)
                isSaving = false
                close()
            }
        } else {
            let newTunnel = Tunnel(
                name: name,
                type: type,
                localPort: port,
                localIP: localIP,
                subdomain: resolved.subdomain,
                remotePort: remoteP,
                customDomains: resolved.customDomains,
                enabled: enabled
            )

            isSaving = true
            Task {
                try? await manager.addTunnel(newTunnel)
                isSaving = false
                close()
            }
        }
    }

    /// 把 UI 状态解析成 frp 要的 subdomain / customDomains。
    /// - 拉取模式（选中基域）：主域名 → subdomain=前缀；泛域名 → customDomains=[前缀.基域]
    /// - fallback 模式：subdomain 走 SubdomainNormalizer；customDomains 按逗号切分
    private func resolveDomains() -> (subdomain: String?, customDomains: [String]) {
        if useDomainDirectory, let entry = selectedDomain {
            let prefix = domainPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
            if entry.isWildcard {
                return (nil, [entry.combined(prefix: prefix)])
            } else {
                let normalized = SubdomainNormalizer.normalize(prefix, baseHost: manager.serverConfig?.subDomainHost)
                return (normalized, [])
            }
        }
        // fallback
        let subdomainVal = SubdomainNormalizer.normalize(
            subdomain,
            baseHost: manager.serverConfig?.subDomainHost
        )
        let customs = customDomainsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return (subdomainVal, customs)
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}
