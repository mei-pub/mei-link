import SwiftUI

@main
struct MeilinkApp: App {
    @NSApplicationDelegateAdaptor(MeilinkAppDelegate.self) private var appDelegate
    @StateObject private var manager = AppRuntime.shared.manager

    init() {
        ProcessInfo.processInfo.disableAutomaticTermination("Meilink runs from the menu bar")
        ProcessInfo.processInfo.disableSuddenTermination()
    }

    var body: some Scene {
        MenuBarExtra {
            Text(statusText)
            if let config = manager.serverConfig {
                Text("\(config.serverAddr):\(config.serverPort)")
                Text(config.subDomainHost)
            }

            Divider()

            Button("打开主窗口") {
                AppRuntime.shared.windows.showMainWindow()
            }

            Button(manager.isConfigured ? "服务器设置" : "首次配置") {
                if manager.isConfigured {
                    AppRuntime.shared.windows.showSettingsWindow()
                } else {
                    AppRuntime.shared.windows.showSetupWindow()
                }
            }

            Divider()

            Button(manager.isFrpcRunning ? "断开连接" : "连接") {
                Task {
                    if manager.isFrpcRunning {
                        await manager.stop()
                    } else {
                        await manager.start()
                    }
                }
            }
            .disabled(!manager.isConfigured)

            Button("重启隧道") {
                Task { await manager.restart() }
            }
            .disabled(!manager.isConfigured)

            Divider()

            Button("退出") {
                MeilinkAppDelegate.allowQuit = true
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Label("Meilink", systemImage: "link.circle.fill")
        }

        Window("Meilink", id: "main") {
            MainWindow(manager: manager)
        }
        .defaultSize(width: 760, height: 520)

        Window("首次配置", id: "setup") {
            SetupView(manager: manager)
        }
        .defaultSize(width: 500, height: 500)

        Window("设置", id: "settings") {
            SettingsView(manager: manager)
        }
        .defaultSize(width: 900, height: 720)

        Settings {
            SettingsView(manager: manager)
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
final class MeilinkAppDelegate: NSObject, NSApplicationDelegate {
    static var allowQuit = false

    private let runtime = AppRuntime.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("Meilink runs from the menu bar")
        ProcessInfo.processInfo.disableSuddenTermination()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [runtime] in
            runtime.windows.showMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.manager.stopImmediately()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.allowQuit ? .terminateNow : .terminateCancel
    }
}
