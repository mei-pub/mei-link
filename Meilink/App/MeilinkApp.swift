import SwiftUI

@main
struct MeilinkApp: App {
    @StateObject private var manager = TunnelManager()
    @State private var showMainWindow = false
    @State private var showSetup = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                manager: manager,
                showMainWindow: $showMainWindow,
                showSetup: $showSetup
            )
        } label: {
            let statusItem = MenuBarStatusItem(
                isConnected: manager.isConnected,
                isFrpcRunning: manager.isFrpcRunning
            )
            Image(systemName: statusItem.imageName)
                .foregroundColor(statusItem.iconColor)
        }
        .menuBarExtraStyle(.menu)

        Window("Meilink", id: "main") {
            MainWindow(manager: manager)
        }
        .defaultSize(width: 650, height: 450)

        Window("首次配置", id: "setup") {
            SetupView(manager: manager)
        }
        .defaultSize(width: 500, height: 500)
        .handlesExternalEvents(matching: ["setup"])

        Settings {
            SettingsView(manager: manager)
        }
    }
}
