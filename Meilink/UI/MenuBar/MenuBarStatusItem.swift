import SwiftUI

struct MenuBarStatusItem {
    let isConnected: Bool
    let isFrpcRunning: Bool

    var imageName: String {
        if isConnected { return "circle.fill" }
        if isFrpcRunning { return "circle.badge.questionmark" }
        return "circle"
    }

    var iconColor: Color {
        if isConnected { return .green }
        if isFrpcRunning { return .yellow }
        return .gray
    }
}
