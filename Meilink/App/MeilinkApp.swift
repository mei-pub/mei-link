import SwiftUI

@main
struct MeilinkApp: App {
    @NSApplicationDelegateAdaptor(MeilinkAppDelegate.self) private var appDelegate
    @StateObject private var manager = AppRuntime.shared.manager

    init() {
        ProcessInfo.processInfo.disableAutomaticTermination("Meilink runs from the menu bar")
        ProcessInfo.processInfo.disableSuddenTermination()
    }

    var body: some Scene {
        Window("Meilink", id: "main") {
            MainWindow(manager: manager)
        }
        .defaultSize(width: 980, height: 520)

        Window("首次配置", id: "setup") {
            SetupView(manager: manager)
        }
        .defaultSize(width: 500, height: 500)

        Window("设置", id: "settings") {
            SettingsView(manager: manager)
        }
        .defaultSize(width: 900, height: 720)

        Settings {
            SettingsView(manager: manager)
        }
    }

}

@MainActor
final class MeilinkAppDelegate: NSObject, NSApplicationDelegate {
    static var allowQuit = false

    private let runtime = AppRuntime.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        runtime.installStatusBar()
        ProcessInfo.processInfo.disableAutomaticTermination("Meilink runs from the menu bar")
        ProcessInfo.processInfo.disableSuddenTermination()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [runtime] in
            runtime.windows.showMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.manager.stopImmediately()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.allowQuit ? .terminateNow : .terminateCancel
    }
}
