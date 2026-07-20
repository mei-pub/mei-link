import SwiftUI
import AppKit

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let manager: TunnelManager
    let windows: AppWindowController

    private init() {
        manager = TunnelManager()
        windows = AppWindowController(manager: manager)
    }
}

@MainActor
final class AppWindowController {
    private let manager: TunnelManager
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?

    init(manager: TunnelManager) {
        self.manager = manager
    }

    func showMainWindow() {
        mainWindow = showWindow(
            existing: mainWindow,
            title: "Meilink",
            size: NSSize(width: 760, height: 520)
        ) {
            MainWindow(manager: manager)
        }
    }

    func showSettingsWindow() {
        settingsWindow = showWindow(
            existing: settingsWindow,
            title: "设置",
            size: NSSize(width: 900, height: 720)
        ) {
            SettingsView(manager: manager)
        }
    }

    func showSetupWindow() {
        setupWindow = showWindow(
            existing: setupWindow,
            title: "首次配置",
            size: NSSize(width: 500, height: 500)
        ) {
            SetupView(manager: manager)
        }
    }

    private func showWindow<Content: View>(
        existing: NSWindow?,
        title: String,
        size: NSSize,
        @ViewBuilder content: () -> Content
    ) -> NSWindow {
        if let existing {
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return existing
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content())
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        return window
    }
}
