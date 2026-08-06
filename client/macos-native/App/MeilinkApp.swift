import AppKit

@main
enum MeilinkMain {
    @MainActor
    static func main() {
        ProcessInfo.processInfo.disableAutomaticTermination("Meilink runs from the menu bar")
        ProcessInfo.processInfo.disableSuddenTermination()

        let app = NSApplication.shared
        let delegate = MeilinkAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // 菜单栏 app（.accessory）默认没有主菜单，导致 SwiftUI TextField 的
        // 复制/剪切/粘贴/全选不可用（这些命令依赖 Edit 菜单的 selector 沿响应链派发）。
        // 安装一个含标准 Edit 菜单的最小主菜单修复此问题。
        installMinimalMainMenu(app: app)
        app.finishLaunching()
        delegate.start()

        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    /// 构建含 App 菜单 + 标准 Edit 菜单的最小主菜单。
    /// Edit 菜单项用系统标准 selector，复用 AppKit 内置的文本编辑行为，
    /// 让 TextField 在 accessory policy（无 Dock、无默认菜单栏）下也能 Cmd+C/V/X/A 和右键粘贴。
    private static func installMinimalMainMenu(app: NSApplication) {
        let mainMenu = NSMenu()
        // App 菜单（必须存在，否则系统不认主菜单）。放一个"退出"项即可。
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "退出 Meilink", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu

        // Edit 菜单：Copy/Cut/Paste/Select All，用 nil target 让 AppKit 沿响应链派发到当前聚焦的 TextField。
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        app.mainMenu = mainMenu
    }
}

@MainActor
final class MeilinkAppDelegate: NSObject, NSApplicationDelegate {
    static var allowQuit = false

    private let runtime = AppRuntime.shared
    private var didStart = false
    /// 标记是否已发起 performQuit，避免重复清理（Cmd+Q + 按钮可能并发触发）。
    private static var isQuitting = false

    func start() {
        guard !didStart else { return }
        didStart = true
        runtime.installStatusBar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [runtime] in
            runtime.windows.showMainWindow()
        }
    }

    /// 统一退出路径：优雅停止 frpc → 允许终止 → terminate（触发 applicationWillTerminate 的 killFrpcOnExit 兜底）。
    /// MenuBar 退出、设置完全退出、Cmd+Q 都走这里，保证三条路径行为一致、frpc 必被清理。
    static func performQuit() {
        guard !isQuitting else { return }
        isQuitting = true
        let runtime = AppRuntime.shared
        Task {
            await runtime.manager.stop()        // 优雅停止：停 timer + frpc.stop
            allowQuit = true
            NSApplication.shared.terminate(nil) // 触发 applicationWillTerminate → killFrpcOnExit 兜底
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 兜底：即便 performQuit 的 manager.stop() 未完成，这里强杀 frpc
        runtime.manager.killFrpcOnExit()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        runtime.windows.showMainWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Cmd+Q：若用户未通过按钮显式退出（allowQuit=false），触发统一 performQuit 走完整清理，
        // 返回 .terminateCancel 让本次 terminate 不立即生效，等 performQuit 内部重新调 terminate。
        if !Self.allowQuit {
            Self.performQuit()
            return .terminateCancel
        }
        return .terminateNow
    }
}
