import SwiftUI

struct MenuBarStatusItem {
    let isConnected: Bool
    let isFrpcRunning: Bool
    let style: MenuBarIconStyle

    var imageName: String {
        if style == .appIcon { return "app" }
        if isConnected { return "link" }
        if isFrpcRunning { return "link.badge.plus" }
        return "link"
    }

    var iconColor: Color {
        if isConnected { return .green }
        if isFrpcRunning { return .yellow }
        return .gray
    }

    var accessibilityStatus: String {
        if isConnected { return "已连接" }
        if isFrpcRunning { return "连接中" }
        return "未连接"
    }

    var title: String {
        if isConnected { return "Meilink" }
        if isFrpcRunning { return "Meilink..." }
        return "Meilink"
    }
}
