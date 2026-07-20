import SwiftUI

@main
struct MeilinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager = AppRuntime.shared.manager

    var body: some Scene {
        Settings {
            SettingsView(manager: manager)
        }
    }
}
