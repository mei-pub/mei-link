import SwiftUI

struct MenuBarStatusItem {
    let isConnected: Bool
    let isFrpcRunning: Bool

    var imageName: String {
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
}
