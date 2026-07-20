import SwiftUI

@main
struct MeilinkApp: App {
    @NSApplicationDelegateAdaptor(MeilinkAppDelegate.self) private var appDelegate
    @StateObject private var manager = AppRuntime.shared.manager

    init() {
        ProcessInfo.processInfo.disableAutomaticTermination("Meilink runs from the menu bar")
        ProcessInfo.processInfo.disableSuddenTermination()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            AppRuntime.shared.installStatusBar()
            AppRuntime.shared.windows.showMainWindow()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                manager: manager,
                openMainWindow: { AppRuntime.shared.windows.showMainWindow() },
                openSettingsWindow: { AppRuntime.shared.windows.showSettingsWindow() },
                openSetupWindow: { AppRuntime.shared.windows.showSetupWindow() },
                closePopover: {}
            )
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: AppIconProvider.image)
                Text("Meilink")
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class MeilinkAppDelegate: NSObject, NSApplicationDelegate {
    static var allowQuit = false

    private let runtime = AppRuntime.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("Meilink runs from the menu bar")
        ProcessInfo.processInfo.disableSuddenTermination()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.manager.stopImmediately()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        runtime.windows.showMainWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.allowQuit ? .terminateNow : .terminateCancel
    }
}
