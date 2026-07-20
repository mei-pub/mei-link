import SwiftUI

struct TunnelEditView: View {
    @ObservedObject var manager: TunnelManager
    @Environment(\.dismiss) private var dismiss

    var tunnel: Tunnel?
    var onClose: (() -> Void)? = nil

    @State private var name = ""
    @State private var type: TunnelType = .http
    @State private var localPort = "8080"
    @State private var localIP = "127.0.0.1"
    @State private var subdomain = ""
    @State private var remotePort = ""
    @State private var enabled = true
    @State private var isSaving = false

    var isEditing: Bool { tunnel != nil }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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
                            formRow("子域名") {
                                TextField("例如 admin", text: $subdomain)
                                    .textFieldStyle(.roundedBorder)
                            }
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
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
            }

            footer
        }
        .frame(width: 620, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if let tunnel = tunnel {
                name = tunnel.name
                type = tunnel.type
                localPort = String(tunnel.localPort)
                localIP = tunnel.localIP
                subdomain = tunnel.subdomain ?? ""
                remotePort = tunnel.remotePort.map { String($0) } ?? ""
                enabled = tunnel.enabled
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(isEditing ? "编辑隧道" : "添加新隧道")
                .font(.title3)
                .fontWeight(.bold)

            Text(typeHint)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 18)
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

    private var typeHint: String {
        switch type {
        case .http, .https:
            return "通过子域名发布本机 HTTP 服务"
        case .tcp, .udp:
            return "通过远程端口转发本机 TCP/UDP 服务"
        }
    }

    private func saveTunnel() {
        guard let port = Int(localPort) else { return }

        let remoteP = Int(remotePort)
        let subdomainVal = SubdomainNormalizer.normalize(
            subdomain,
            baseHost: manager.serverConfig?.subDomainHost
        )

        if var existing = tunnel {
            existing.name = name
            existing.type = type
            existing.localPort = port
            existing.localIP = localIP
            existing.subdomain = subdomainVal
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
                subdomain: subdomainVal,
                remotePort: remoteP,
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

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}
