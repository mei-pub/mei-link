import AppKit

@main
enum MeilinkMain {
    @MainActor
    static func main() {
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
    private let runtime = AppRuntime.shared
    private var didStart = false

    func start() {
        guard !didStart else { return }
        didStart = true
        runtime.statusBar.install()
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
}
