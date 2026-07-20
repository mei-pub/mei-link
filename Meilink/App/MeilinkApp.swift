import SwiftUI

@main
struct MeilinkApp: App {
    @StateObject private var manager = TunnelManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(manager: manager)
        } label: {
            let statusItem = MenuBarStatusItem(
                isConnected: manager.isConnected,
                isFrpcRunning: manager.isFrpcRunning
            )
            Image(systemName: statusItem.imageName)
                .foregroundColor(statusItem.iconColor)
        }
        .menuBarExtraStyle(.window)

        Window("Meilink", id: "main") {
            MainWindow(manager: manager)
        }
        .defaultSize(width: 650, height: 450)

        Window("首次配置", id: "setup") {
            SetupView(manager: manager)
        }
        .defaultSize(width: 500, height: 500)
        .handlesExternalEvents(matching: ["setup"])

        Window("设置", id: "settings") {
            SettingsView(manager: manager)
        }
        .defaultSize(width: 460, height: 540)

        Settings {
            SettingsView(manager: manager)
        }
    }
}
