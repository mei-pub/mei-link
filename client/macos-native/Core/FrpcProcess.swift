import Foundation

class FrpcProcess {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private let logger = Logger(subsystem: "pub.mei.meilink", category: "FrpcProcess")

    var onOutput: ((String) -> Void)?
    var onTermination: ((Int32) -> Void)?
    /// 在 frpc 进程成功启动后回调（异步，从 terminationHandler 的反向保证）
    var onStarted: (() -> Void)?

    var isRunning: Bool { process?.isRunning ?? false }
    var processID: Int32? { process?.processIdentifier }

    func start(configPath: String) throws {
        stopImmediately()

        guard let frpcPath = findFrpcPath() else {
            throw FrpcProcessError.binaryNotFound
        }

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
                self?.logger.info("frpc 进程已退出，状态码: \(process.terminationStatus)")
                self?.onTermination?(process.terminationStatus)
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

        let siblingPath = executableDirectory.appendingPathComponent("frpc").path
        if FileManager.default.isExecutableFile(atPath: siblingPath) {
            logger.info("找到 frpc: \(siblingPath)")
            return siblingPath
        }

        logger.warning("frpc 不在同目录: \(siblingPath)")

        // 回退到 Resources/ 目录
        if let resourcePath = Bundle.main.path(forResource: "frpc", ofType: nil) {
            logger.info("在 Resources 中找到 frpc: \(resourcePath)")
            return resourcePath
        }

        logger.error("frpc 二进制未找到")
        return nil
    }

    func stop() {
        guard let process = process, process.isRunning else { return }

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
        case .binaryNotFound: return "未找到 frpc 二进制文件"
        }
    }
}
