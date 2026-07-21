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

    func start() {
        guard !didStart else { return }
        didStart = true
        runtime.installStatusBar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [runtime] in
            runtime.windows.showMainWindow()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        start()
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
