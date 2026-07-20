import SwiftUI
import AppKit
import Combine

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let manager: TunnelManager
    let windows: AppWindowController
    private var statusBar: StatusBarController?

    private init() {
        manager = TunnelManager()
        windows = AppWindowController(manager: manager)
    }

    func installStatusBar() {
        if statusBar == nil {
            statusBar = StatusBarController(manager: manager, windows: windows)
        }
    }
}

@MainActor
final class StatusBarController {
    private let manager: TunnelManager
    private let windows: AppWindowController
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?

    init(manager: TunnelManager, windows: AppWindowController) {
        self.manager = manager
        self.windows = windows
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem.autosaveName = "Meilink.StatusBarItem.v2"
        self.statusItem.isVisible = true

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 330, height: 420)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                manager: manager,
                openMainWindow: { windows.showMainWindow() },
                openSettingsWindow: { windows.showSettingsWindow() },
                openSetupWindow: { windows.showSetupWindow() },
                closePopover: { [weak popover] in popover?.performClose(nil) }
            )
        )

        configureButton()
        updateButton()

        cancellable = manager.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateButton()
            }
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let symbolName = manager.isConnected ? "link.circle.fill" : manager.isFrpcRunning ? "link.circle" : "link.circle"

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Meilink") {
            image.isTemplate = true
            button.image = image
            button.title = "Meilink"
        } else {
            button.image = nil
            button.title = "Meilink"
        }

        button.toolTip = "Meilink - \(statusText)"
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var statusText: String {
        if manager.isConnected { return "已连接" }
        if manager.isFrpcRunning { return "连接中" }
        if manager.isConfigured { return "未连接" }
        return "未配置"
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
