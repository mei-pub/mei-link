import SwiftUI

struct TunnelEditView: View {
    @ObservedObject var manager: TunnelManager
    @Environment(\.dismiss) private var dismiss

    var tunnel: Tunnel?

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
        VStack(spacing: 16) {
            Text(isEditing ? "编辑隧道" : "添加新隧道")
                .font(.title3)
                .fontWeight(.bold)

            Form {
                Section("基本信息") {
                    TextField("隧道名称", text: $name)
                        .textFieldStyle(.roundedBorder)

                    Picker("类型", selection: $type) {
                        ForEach(TunnelType.allCases, id: \.self) { type in
                            Text(type.rawValue.uppercased()).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("本地配置") {
                    HStack {
                        Text("本地端口")
                        TextField("8080", text: $localPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }

                    TextField("本地地址", text: $localIP)
                        .textFieldStyle(.roundedBorder)
                }

                Section("远程配置") {
                    if type == .http || type == .https {
                        TextField("子域名", text: $subdomain)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        HStack {
                            Text("远程端口")
                            TextField("0 = 自动分配", text: $remotePort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                    }
                }

                Section {
                    Toggle("启用隧道", isOn: $enabled)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isEditing ? "保存" : "创建") {
                    saveTunnel()
                }
                .disabled(name.isEmpty || localPort.isEmpty || isSaving)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
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
                dismiss()
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
                dismiss()
            }
        }
    }
}
