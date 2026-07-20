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
        statusBar?.rebuild()
    }

    func rebuildStatusBar() {
        statusBar?.rebuild()
    }
}

@MainActor
final class StatusBarController {
    private static let autosaveName = "Meilink.StatusBarItem.v3"

    private let manager: TunnelManager
    private let windows: AppWindowController
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?

    init(manager: TunnelManager, windows: AppWindowController) {
        self.manager = manager
        self.windows = windows

        configurePopover()
        rebuild()

        cancellable = manager.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateButton()
            }
        }
    }

    func rebuild() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = Self.autosaveName
        item.isVisible = true
        statusItem = item

        forceStatusItemVisibility()

        configureButton()
        updateButton()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 330, height: 430)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                manager: manager,
                openMainWindow: { [weak self] in self?.windows.showMainWindow() },
                openSettingsWindow: { [weak self] in self?.windows.showSettingsWindow() },
                openSetupWindow: { [weak self] in self?.windows.showSetupWindow() },
                closePopover: { [weak popover] in popover?.performClose(nil) }
            )
        )
    }

    private func forceStatusItemVisibility() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "NSStatusItem Visible \(Self.autosaveName)")
        defaults.set(true, forKey: "NSStatusItem VisibleCC \(Self.autosaveName)")
        defaults.removeObject(forKey: "NSStatusItem Visible Item-0")
        defaults.removeObject(forKey: "NSStatusItem VisibleCC Item-0")
        defaults.synchronize()

        guard let bundleID = Bundle.main.bundleIdentifier as CFString? else { return }
        CFPreferencesSetAppValue("NSStatusItem Visible \(Self.autosaveName)" as CFString, kCFBooleanTrue, bundleID)
        CFPreferencesSetAppValue("NSStatusItem VisibleCC \(Self.autosaveName)" as CFString, kCFBooleanTrue, bundleID)
        CFPreferencesSetAppValue("NSStatusItem Visible Item-0" as CFString, nil, bundleID)
        CFPreferencesSetAppValue("NSStatusItem VisibleCC Item-0" as CFString, nil, bundleID)
        CFPreferencesAppSynchronize(bundleID)
    }

    private func configureButton() {
        guard let button = statusItem?.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.title = ""
        button.appearsDisabled = false
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }

        let status = MenuBarStatusItem(
            isConnected: manager.isConnected,
            isFrpcRunning: manager.isFrpcRunning,
            style: manager.appSettings.menuBarIconStyle
        )

        switch manager.appSettings.menuBarIconStyle {
        case .text:
            statusItem?.length = 78
            button.imagePosition = .noImage
            button.image = nil
            button.title = status.title
        case .appIcon:
            statusItem?.length = 92
            button.imagePosition = .imageLeading
            button.title = "Meilink"
            button.image = resizedApplicationIcon()
        case .link:
            statusItem?.length = NSStatusItem.squareLength
            button.imagePosition = .imageOnly
            button.title = ""
            if let image = NSImage(systemSymbolName: status.imageName, accessibilityDescription: "Meilink") {
                image.isTemplate = true
                button.image = image
            } else {
                button.image = nil
                button.title = "Meilink"
                statusItem?.length = NSStatusItem.variableLength
            }
        }

        button.toolTip = "Meilink - \(status.title)"
    }

    private func resizedApplicationIcon() -> NSImage {
        let icon = (AppIconProvider.image.copy() as? NSImage)
            ?? NSApp.applicationIconImage
            ?? NSImage(size: NSSize(width: 18, height: 18))
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@MainActor
final class AppWindowController {
    private let manager: TunnelManager
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var tunnelWindow: NSWindow?

    init(manager: TunnelManager) {
        self.manager = manager
    }

    func showMainWindow() {
        mainWindow = showWindow(
            existing: mainWindow,
            title: "Meilink",
            size: NSSize(width: 1060, height: 760)
        ) {
            MainWindow(manager: manager)
        }
    }

    func showSettingsWindow() {
        settingsWindow = showWindow(
            existing: settingsWindow,
            title: "设置",
            size: NSSize(width: 760, height: 820)
        ) {
            SettingsView(manager: manager) { [weak self] in
                self?.settingsWindow?.close()
            }
        }
    }

    func showSetupWindow() {
        setupWindow = showWindow(
            existing: setupWindow,
            title: "首次配置",
            size: NSSize(width: 560, height: 640)
        ) {
            SetupView(manager: manager)
        }
    }

    func showTunnelWindow(tunnel: Tunnel? = nil) {
        tunnelWindow = showWindow(
            existing: tunnelWindow,
            title: tunnel == nil ? "添加新隧道" : "编辑隧道",
            size: NSSize(width: 620, height: 680)
        ) {
            TunnelEditView(manager: manager, tunnel: tunnel) { [weak self] in
                self?.tunnelWindow?.close()
            }
        }
    }

    private func showWindow<Content: View>(
        existing: NSWindow?,
        title: String,
        size: NSSize,
        @ViewBuilder content: () -> Content
    ) -> NSWindow {
        if let existing, existing.isVisible {
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
        window.isMovableByWindowBackground = true
        window.contentViewController = NSHostingController(rootView: content())
        placeWindowOnVisibleScreen(window, size: size)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        return window
    }

    private func placeWindowOnVisibleScreen(_ window: NSWindow, size: NSSize) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }

        let width = min(size.width, visibleFrame.width - 40)
        let height = min(size.height, visibleFrame.height - 40)
        let origin = NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2
        )
        window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: false)
    }
}
