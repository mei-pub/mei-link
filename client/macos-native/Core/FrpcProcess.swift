import Foundation

class FrpcProcess {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private let logger = Logger(subsystem: "pub.mei.meilink", category: "FrpcProcess")

    var onOutput: ((String) -> Void)?
    /// frpc 进程退出回调。参数：(退出状态码, 是否由本进程主动停止触发)。
    /// 主动停止（stop/stopImmediately）产生的退出（终止信号会被记为非 0 状态码）
    /// 不应被上层当作崩溃来触发自动恢复。
    var onTermination: ((Int32, Bool) -> Void)?
    /// 在 frpc 进程成功启动后回调（异步，从 terminationHandler 的反向保证）
    var onStarted: (() -> Void)?

    /// 标记下一次 terminationHandler 触发是否由本进程主动停止（stop/stopImmediately）引起。
    /// 用 NSLock 保护，因 terminationHandler 在主线程派发，而 stop 可能从后台 Task 调用。
    private var pendingIntentionalStop = false
    private let intentionalStopLock = NSLock()

    var isRunning: Bool { process?.isRunning ?? false }
    var processID: Int32? { process?.processIdentifier }

    private func markIntentionalStop() {
        intentionalStopLock.lock()
        defer { intentionalStopLock.unlock() }
        pendingIntentionalStop = true
    }

    private func consumeIntentionalStop() -> Bool {
        intentionalStopLock.lock()
        defer { intentionalStopLock.unlock() }
        let value = pendingIntentionalStop
        pendingIntentionalStop = false
        return value
    }

    func start(configPath: String) throws {
        stopImmediately()

        guard let frpcPath = findFrpcPath() else {
            throw FrpcProcessError.binaryNotFound
        }

        // 新进程即将启动，清掉可能残留的旧 intentional 标志，
        // 避免上一个进程的退出状态误传给新进程的退出回调。
        _ = consumeIntentionalStop()

        process = Process()
        process?.executableURL = URL(fileURLWithPath: frpcPath)
        process?.arguments = ["-c", configPath]

        outputPipe = Pipe()
        errorPipe = Pipe()
        process?.standardOutput = outputPipe
        process?.standardError = errorPipe

        outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                self?.handleOutput(output, level: .info)
            }
        }

        errorPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                self?.handleOutput(output, level: .error)
            }
        }

        process?.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                let intentional = self?.consumeIntentionalStop() ?? false
                self?.logger.info("frpc 进程已退出，状态码: \(process.terminationStatus)，主动停止: \(intentional)")
                self?.onTermination?(process.terminationStatus, intentional)
            }
        }

        try process?.run()
        logger.info("frpc 进程已启动，PID: \(process?.processIdentifier ?? 0)")
        // 进程启动成功后立即回调（在主线程上）
        DispatchQueue.main.async { [weak self] in
            self?.onStarted?()
        }
    }

    private func handleOutput(_ output: String, level: EventLog.LogLevel) {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            switch level {
            case .info:
                logger.info("frpc: \(line)")
            case .warning:
                logger.warning("frpc: \(line)")
            case .error:
                logger.error("frpc stderr: \(line)")
            }
            DispatchQueue.main.async { [weak self] in
                self?.onOutput?(line)
            }
        }
    }

    private func findFrpcPath() -> String? {
        // 优先搜索同目录（Contents/MacOS/）
        guard let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() else {
            logger.error("无法获取 Bundle.main.executableURL")
            return nil
        }

        // meilink-tunnel 是嵌入 frp library 的独立二进制，替代 frpc 以规避杀软误报。
        let tunnelPath = executableDirectory.appendingPathComponent("meilink-tunnel").path
        if FileManager.default.isExecutableFile(atPath: tunnelPath) {
            logger.info("找到 meilink-tunnel: \(tunnelPath)")
            return tunnelPath
        }

        logger.warning("meilink-tunnel 不在同目录")

        // 回退到 Resources/ 目录
        if let resourcePath = Bundle.main.path(forResource: "meilink-tunnel", ofType: nil) {
            logger.info("在 Resources 中找到 meilink-tunnel: \(resourcePath)")
            return resourcePath
        }

        logger.error("meilink-tunnel 二进制未找到")
        return nil
    }

    func stop() {
        guard let process = process, process.isRunning else { return }

        markIntentionalStop()
        process.terminate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.process?.isRunning == true {
                self?.process?.interrupt()
            }
        }
    }

    func stopImmediately(timeout: TimeInterval = 2.0) {
        guard let process = process, process.isRunning else { return }
        let pid = process.processIdentifier

        markIntentionalStop()

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        process.terminate()
        // 等待进程退出，最多 timeout 秒
        let start = Date()
        while process.isRunning && Date().timeIntervalSince(start) < timeout {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            // interrupt 后 kill -9 兜底
            process.interrupt()
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning {
                process.interrupt()
                Thread.sleep(forTimeInterval: 0.5)
                if process.isRunning {
                    let exitPid = pid ?? 0
                    logger.warning("frpc 进程未能退出，使用 kill -9 强制终止")
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/kill")
                    task.arguments = ["-9", "\(exitPid)"]
                    try? task.run()
                    task.waitUntilExit()
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }
        }
    }
}

enum FrpcProcessError: Error, LocalizedError {
    case binaryNotFound

    var errorDescription: String? {
        switch self {
        case .binaryNotFound: return "未找到 meilink-tunnel 二进制文件"
        }
    }
}
