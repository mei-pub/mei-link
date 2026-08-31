import SwiftUI

struct MenuBarStatusItem {
    let isConnected: Bool
    let isFrpcRunning: Bool
    let isReconnecting: Bool
    let reconnectFailed: Bool
    let style: MenuBarIconStyle

    var imageName: String {
        style.imageName
    }

    var iconColor: Color {
        if isConnected { return .green }
        if reconnectFailed { return .red }
        if isFrpcRunning || isReconnecting { return .yellow }
        return .gray
    }

    var accessibilityStatus: String {
        if isConnected { return "已连接" }
        if reconnectFailed { return "重连失败" }
        if isReconnecting { return "重连中" }
        if isFrpcRunning { return "连接中" }
        return "未连接"
    }

    var title: String {
        if isConnected { return "Meilink" }
        if isFrpcRunning || isReconnecting { return "Meilink..." }
        return "Meilink"
    }
}
