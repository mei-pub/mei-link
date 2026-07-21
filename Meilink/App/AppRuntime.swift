import SwiftUI
import AppKit
import Combine

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let manager: TunnelManager
    let windows: AppWindowController
    let statusBar: StatusBarController

    private init() {
        manager = TunnelManager()
        windows = AppWindowController(manager: manager)
        statusBar = StatusBarController(manager: manager, windows: windows)
    }

    func installStatusBar() {
        statusBar.install()
    }

    func rebuildStatusBar() {
        statusBar.rebuild()
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let manager: TunnelManager
    private let windows: AppWindowController
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []

    init(manager: TunnelManager, windows: AppWindowController) {
        self.manager = manager
        self.windows = windows
        super.init()
    }

    func install() {
        guard statusItem == nil else {
            updateButton()
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.isVisible = true
        configurePopover()
        configureButton()
        updateButton()

        manager.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateButton()
                }
            }
            .store(in: &cancellables)
    }

    func rebuild() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        cancellables.removeAll()
        install()
    }

    func refresh() {
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

    private func configureButton() {
        guard let button = statusItem?.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
        button.title = "Mei"
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
            statusItem?.length = 68
            button.imagePosition = .noImage
            button.image = nil
            applyMenuBarTitle(status.title, to: button)
        case .appIcon:
            statusItem?.length = 82
            button.imagePosition = .imageLeading
            button.image = resizedApplicationIcon()
            applyMenuBarTitle("Mei", to: button)
        case .link:
            statusItem?.length = 62
            button.imagePosition = .imageLeading
            button.image = makeLinkIcon(systemName: status.imageName)
            applyMenuBarTitle("Mei", to: button)
        }
        button.toolTip = "Meilink - \(status.title)"
    }

    private func applyMenuBarTitle(_ title: String, to button: NSStatusBarButton) {
        button.title = title
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    private func resizedApplicationIcon() -> NSImage {
        let icon = (AppIconProvider.image.copy() as? NSImage)
            ?? NSApp.applicationIconImage
            ?? NSImage(size: NSSize(width: 18, height: 18))
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }

    private func makeLinkIcon(systemName: String) -> NSImage {
        if let image = NSImage(systemSymbolName: systemName, accessibilityDescription: "Meilink") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor.black.setStroke()

        let path = NSBezierPath()
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: 4.2, y: 9))
        path.line(to: NSPoint(x: 4.2, y: 4.4))
        path.line(to: NSPoint(x: 6.3, y: 4.4))
        path.line(to: NSPoint(x: 9, y: 8.2))
        path.line(to: NSPoint(x: 11.7, y: 4.4))
        path.line(to: NSPoint(x: 13.8, y: 4.4))
        path.line(to: NSPoint(x: 13.8, y: 9))
        path.stroke()

        let linkPath = NSBezierPath()
        linkPath.lineWidth = 1.8
        linkPath.lineCapStyle = .round
        linkPath.move(to: NSPoint(x: 5, y: 12.2))
        linkPath.curve(
            to: NSPoint(x: 8.4, y: 12.2),
            controlPoint1: NSPoint(x: 5.8, y: 14.1),
            controlPoint2: NSPoint(x: 7.6, y: 14.1)
        )
        linkPath.move(to: NSPoint(x: 9.6, y: 12.2))
        linkPath.curve(
            to: NSPoint(x: 13, y: 12.2),
            controlPoint1: NSPoint(x: 10.4, y: 10.3),
            controlPoint2: NSPoint(x: 12.2, y: 10.3)
        )
        linkPath.stroke()

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "Meilink"
        return image
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
            size: NSSize(width: 1060, height: 820)
        ) {
            MainWindow(manager: manager)
        }
    }

    func showSettingsWindow() {
        settingsWindow = showWindow(
            existing: settingsWindow,
            title: "设置",
            size: NSSize(width: 760, height: 880)
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
            size: NSSize(width: 660, height: 840)
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
