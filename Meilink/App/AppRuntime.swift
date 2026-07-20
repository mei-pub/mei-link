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
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 330, height: 460)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                manager: manager,
                openMainWindow: { [weak self] in self?.windows.showMainWindow() },
                openSettingsWindow: { [weak self] in self?.windows.showSettingsWindow() },
                openSetupWindow: { [weak self] in self?.windows.showSetupWindow() },
                closePopover: { [weak self] in self?.popover.performClose(nil) }
            )
        )

        updateIcon()
        manager.$isConnected
            .combineLatest(manager.$isFrpcRunning)
            .sink { [weak self] _, _ in
                self?.updateIcon()
            }
            .store(in: &cancellables)

        if !manager.isConfigured {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.windows.showSetupWindow()
            }
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let statusItem = MenuBarStatusItem(
            isConnected: manager.isConnected,
            isFrpcRunning: manager.isFrpcRunning
        )
        let image = NSImage(systemSymbolName: statusItem.imageName, accessibilityDescription: "Meilink")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = "Mei"
        button.attributedTitle = NSAttributedString(
            string: "Mei",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        )
        button.toolTip = "Meilink - \(statusItem.accessibilityStatus)"
    }
}
