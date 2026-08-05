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
        app.finishLaunching()
        delegate.start()

        withExtendedLifetime(delegate) {
            app.run()
        }
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
