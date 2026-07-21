import Foundation

class FrpcProcess {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private let logger = Logger(subsystem: "com.meilink", category: "FrpcProcess")

    var onOutput: ((String) -> Void)?
    var onTermination: ((Int32) -> Void)?

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
        if let resourcePath = Bundle.main.path(forResource: "frpc", ofType: nil) {
            return resourcePath
        }

        guard let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() else {
            return nil
        }

        let siblingPath = executableDirectory.appendingPathComponent("frpc").path
        return FileManager.default.isExecutableFile(atPath: siblingPath) ? siblingPath : nil
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

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        process.terminate()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        if process.isRunning {
            process.interrupt()
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
