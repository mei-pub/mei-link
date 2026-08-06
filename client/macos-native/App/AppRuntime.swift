import SwiftUI
import AppKit
import Combine
import ObjectiveC

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
    private let panelSize = NSSize(width: 330, height: 440)
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var eventMonitors: [Any] = []

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
        closePanel()
        statusItem = nil
        cancellables.removeAll()
        install()
    }

    func refresh() {
        updateButton()
    }

    private func configureButton() {
        guard let button = statusItem?.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.appearsDisabled = false
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }

        let status = MenuBarStatusItem(
            isConnected: manager.isConnected,
            isFrpcRunning: manager.isFrpcRunning,
            style: manager.appSettings.menuBarIconStyle
        )

        statusItem?.length = NSStatusItem.squareLength
        button.imagePosition = .imageOnly
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.image = menuBarImage(for: status)
        button.toolTip = "Meilink - \(status.title)"
    }

    private func menuBarImage(for status: MenuBarStatusItem) -> NSImage {
        // Load the custom PNG icon from bundle resources (5 styles shared with GUI version).
        let name = status.imageName
        if let path = Bundle.main.path(forResource: name, ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }
        return resizedApplicationIcon()
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
        if panel?.isVisible == true {
            closePanel()
        } else {
            updateButton()
            showPanel(relativeTo: sender)
        }
    }

    private func showPanel(relativeTo sender: NSStatusBarButton) {
        guard let buttonWindow = sender.window else { return }
        let screen = buttonWindow.screen ?? NSScreen.main
        guard let screen else { return }

        let buttonFrame = buttonWindow.convertToScreen(sender.convert(sender.bounds, to: nil))
        let visibleFrame = screen.visibleFrame
        let horizontalPadding: CGFloat = 10
        let verticalGap: CGFloat = 8

        var originX = buttonFrame.midX - panelSize.width / 2
        originX = min(originX, visibleFrame.maxX - panelSize.width - horizontalPadding)
        originX = max(originX, visibleFrame.minX + horizontalPadding)

        var originY = buttonFrame.minY - panelSize.height - verticalGap
        if originY < visibleFrame.minY + horizontalPadding {
            originY = visibleFrame.maxY - panelSize.height - horizontalPadding
        }

        let arrowOffset = min(max(buttonFrame.midX - originX, 24), panelSize.width - 24)
        let content = MenuBarPanelChrome(arrowOffset: arrowOffset) {
            MenuBarView(
                manager: manager,
                openMainWindow: { [weak self] in
                    self?.closePanel()
                    self?.windows.showMainWindow()
                },
                openSettingsWindow: { [weak self] in
                    self?.closePanel()
                    self?.windows.showSettingsWindow()
                },
                openSetupWindow: { [weak self] in
                    self?.closePanel()
                    self?.windows.showSetupWindow()
                },
                openLogsWindow: { [weak self] in
                    self?.closePanel()
                    self?.windows.showLogsWindow()
                },
                closePopover: { [weak self] in self?.closePanel() }
            )
        }

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        hostingView.autoresizingMask = [.width, .height]

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.setFrame(NSRect(x: originX, y: originY, width: panelSize.width, height: panelSize.height), display: true)

        self.panel = panel
        installEventMonitors(for: panel)
        panel.orderFrontRegardless()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        panel = nil
        removeEventMonitors()
    }

    private func installEventMonitors(for panel: NSPanel) {
        removeEventMonitors()

        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            guard let panel else { return event }
            if event.window !== panel {
                self?.closePanel()
            }
            return event
        }

        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }

        [localMonitor, globalMonitor].compactMap { $0 }.forEach { eventMonitors.append($0) }
    }

    private func removeEventMonitors() {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors.removeAll()
    }
}

private struct MenuBarPanelChrome<Content: View>: View {
    let arrowOffset: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Spacer()
                    .frame(width: max(0, arrowOffset - 9))
                Triangle()
                    .fill(.regularMaterial)
                    .frame(width: 18, height: 12)
                Spacer(minLength: 0)
            }
            .frame(width: 330, height: 12, alignment: .leading)

            content
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8)
        }
        .frame(width: 330, height: 440, alignment: .top)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

@MainActor
final class AppWindowController {
    private let manager: TunnelManager
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var tunnelWindow: NSWindow?
    private var logsWindow: NSWindow?

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
            size: NSSize(width: 760, height: 460),
            escapable: true
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
            size: NSSize(width: 560, height: 640),
            escapable: true
        ) {
            SetupView(manager: manager) { [weak self] in
                self?.setupWindow?.close()
            }
        }
    }

    func showTunnelWindow(tunnel: Tunnel? = nil) {
        tunnelWindow = showWindow(
            existing: tunnelWindow,
            title: tunnel == nil ? "添加新隧道" : "编辑隧道",
            size: NSSize(width: 660, height: 440),
            escapable: true
        ) {
            TunnelEditView(manager: manager, tunnel: tunnel) { [weak self] in
                self?.tunnelWindow?.close()
            }
        }
    }

    func showLogsWindow() {
        logsWindow = showWindow(
            existing: logsWindow,
            title: "日志",
            size: NSSize(width: 820, height: 620)
        ) {
            LogWindowView(manager: manager)
        }
    }

    private func showWindow<Content: View>(
        existing: NSWindow?,
        title: String,
        size: NSSize,
        escapable: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> NSWindow {
        if let existing, existing.isVisible {
            // 窗口已存在时，重新设置 contentView 触发 onAppear（否则第二次打开不拉取域名）
            existing.contentViewController = NSHostingController(rootView: content())
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

        // 给设置/首次配置/隧道编辑窗口装 ESC 关闭监听。
        // 这些窗口是 NSWindow（非 sheet），.keyboardShortcut(.cancelAction) 不可靠，
        // 用本地事件监听器捕获 Escape 调 window.close()。
        if escapable {
            installEscapeCloseMonitor(for: window)
        }
        return window
    }

    /// 给窗口安装 ESC 键关闭监听。monitor 存在关联对象里，窗口关闭时自动移除。
    private func installEscapeCloseMonitor(for window: NSWindow) {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
            // keyCode 53 = Escape；仅当目标窗口是 key window 时响应
            if event.keyCode == 53, window?.isKeyWindow == true {
                window?.close()
                return nil // 吞掉事件
            }
            return event
        }
        EscapeCloseAssociation.setMonitor(monitor, for: window)
        // 窗口关闭时移除 monitor，避免泄漏
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            EscapeCloseAssociation.removeMonitor(for: window)
        }
        EscapeCloseAssociation.setObserver(observer, for: window)
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

/// 用 objc 关联对象把 ESC 监听器的 monitor token 和 willClose observer 存在 window 上，
/// 窗口关闭时移除，避免监听器泄漏（监听器持有闭包会 retain window）。
private enum EscapeCloseAssociation {
    private static var monitorKey: UInt8 = 0
    private static var observerKey: UInt8 = 0

    static func setMonitor(_ monitor: Any?, for window: NSWindow) {
        objc_setAssociatedObject(window, &monitorKey, monitor, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func setObserver(_ observer: NSObjectProtocol, for window: NSWindow) {
        objc_setAssociatedObject(window, &observerKey, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func removeMonitor(for window: NSWindow) {
        if let monitor = objc_getAssociatedObject(window, &monitorKey) {
            NSEvent.removeMonitor(monitor)
            objc_setAssociatedObject(window, &monitorKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        if let observer = objc_getAssociatedObject(window, &observerKey) as? NSObjectProtocol {
            NotificationCenter.default.removeObserver(observer)
            objc_setAssociatedObject(window, &observerKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
