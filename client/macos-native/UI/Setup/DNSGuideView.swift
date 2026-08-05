import SwiftUI

struct DNSGuideView: View {
    let subDomainHost: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DNS 配置指引")
                .font(.title3)
                .fontWeight(.bold)

            Text("在你的域名管理处添加以下泛解析记录:")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("记录类型: A")
                Text("主机记录: *.\(subDomainHost)")
                Text("记录值: 你的 VPS IP 地址")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Text("配置完成后，所有形如 xxx.\(subDomainHost) 的子域名都会解析到你的 VPS。")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420, height: 280)
    }
}
